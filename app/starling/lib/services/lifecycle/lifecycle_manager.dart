import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../storage/keychain_manager.dart';

import '../../providers/discovery_provider.dart';
import '../../providers/follow_provider.dart';
import '../../providers/identity_provider.dart';
import '../../providers/server_provider.dart';
import '../../providers/service_providers.dart';
import '../../providers/sync_provider.dart';
import '../../providers/voice_provider.dart';
import '../../sync/concurrency.dart';
import '../../sync/peer_reachability_provider.dart';
import '../../utils/feature_flags.dart';
import '../background/foreground_service_controller.dart';
import '../background/ios_background_handler.dart';
import '../background/workmanager_dispatcher.dart';
import '../follow_retry_pump.dart';
import 'onion_publisher.dart';
import '../signaling/ws_signaling_service.dart';
import '../types.dart';
import '../sync_pump.dart';

/// Foreground lifecycle orchestration. Owns the long-lived pumps, the
/// memoized Tor init future, and the onion-publish state that used to live
/// inline on `_StarlingAppState` in `main.dart`.
///
/// Three entry points map to the Flutter app lifecycle:
/// - [start] — once, from `initState`. Eager-reads HTTP server + mDNS
///   providers, kicks off Tor init, starts the pumps.
/// - [onResume]/[onPause] — from `WidgetsBindingObserver`. Restart or stop
///   the same services on foreground/background.
/// - [stop] — once, from `dispose`. Stops pumps and tears down subscriptions.
///
/// Background sync (WorkManager, BGTaskScheduler) does NOT use this class —
/// it has no Riverpod scope. See `runBackgroundSync` for that entry point.
class LifecycleManager {
  LifecycleManager({required this.ref});

  final WidgetRef ref;


  FollowRetryPump? _retryPump;
  SyncPump? _syncPump;
  ProviderSubscription<AsyncValue<int?>>? _torPortSub;
  ProviderSubscription<AsyncValue<Identity?>>? _identitySub;

  /// Debounce window before [onPause] actually tears down Tor + the
  /// HTTP server + pumps. System overlays (camera permission, sheets,
  /// scanner) trigger hidden/paused on iOS too — without this window
  /// the onion descriptor gets re-published every time the user opens
  /// a sheet, and never settles in the Tor network. iOS suspends the
  /// process within ~10s of true background, so this almost always
  /// falls back to the "elapsed > debounce on resume" path for real
  /// backgrounding.
  static const Duration _pauseDebounce = Duration(seconds: 30);
  Timer? _shutdownTimer;
  DateTime? _pausedAt;

  /// Memoized Tor init future. Any caller — initState, lifecycle resume,
  /// the port listener — gets back the same in-flight Future, so concurrent
  /// triggers (e.g. resume right after launch) don't double-init Arti.
  Future<void>? _torInitFuture;

  /// Plan 11a — memoized libp2p listen future. Same dedup pattern as
  /// [_torInitFuture]. Reset to null on [onPause] so the next resume
  /// re-binds listeners.
  Future<void>? _libp2pListenFuture;

  /// Onion-service publish lifecycle. Tracks the published address/port,
  /// re-targets in place when the HTTP server rebinds on a new ephemeral
  /// port, and retries with backoff on failure (so a transient Tor error
  /// no longer leaves the device dark over Tor for the session). Provider
  /// writes go through the `onAddress` callback below so a late retry timer
  /// never touches `ref` after teardown.
  late final OnionPublisher _onionPublisher = OnionPublisher(
    ensureTorInit: _ensureTorInit,
    tor: () => ref.read(torServiceProvider),
    onAddress: (addr) => ref.read(onionAddressProvider.notifier).set(addr),
  );

  /// Call from `initState`. Wires the pumps and the port-change listener that
  /// publishes a Tor onion service whenever the HTTP server binds.
  void start() {
    // Eagerly start the embedded HTTP server. The provider waits for
    // identity to be loaded before it actually binds a port.
    ref.read(httpServerControllerProvider);
    // Eagerly bring up mDNS discovery; the controller no-ops until both
    // identity and the server port are ready.
    ref.read(discoveryControllerProvider);
    // Bring up the peer reachability monitor (Plan 11c). Probes run in the
    // background; consumers ask `bestConnectionFor(pubkey)` for a
    // pre-validated transport instead of doing their own cascade.
    //
    // Plan 11d: bind the libp2p passive-ping callback BEFORE starting the
    // monitor so the first periodic tick can demote a stale libp2p path
    // without waiting for the next sync request to fail. The binding is
    // a closure over `ref.read` so a stub-→-real bridge swap is picked up
    // automatically (the closure resolves at call time).
    final monitor = ref.read(peerReachabilityMonitorProvider);
    monitor.bindLibp2pProbe(
      (conn) => ref.read(libp2pNetworkServiceProvider).ping(conn),
    );
    unawaited(monitor.start());

    _retryPump = FollowRetryPump(
      followService: ref.read(followServiceProvider),
      reachability: monitor,
      clock: ref.read(clockProvider),
    )..start();
    _syncPump = SyncPump(
      runSync: () =>
          ref.read(syncControllerProvider.notifier).syncNow().then((_) {}),
    )..start();
    ref.read(reconnectPusherProvider).start();

    // Plan 11a: bring up Tor in parallel with everything else. Bootstrap
    // can take 10–30s on cold start; LAN sync stays available throughout.
    unawaited(_ensureTorInit());

    // Plan 11a: bring up the libp2p direct-connect tier. Cheap with the
    // stub bridge (no-op); with the FFI-backed bridge it binds a UDP/QUIC
    // listener and starts the swarm event loop. Background sync (Plan 14)
    // skips this entirely — the swarm only runs while foregrounded.
    unawaited(_ensureLibp2pListen());

    // Plan 11d: pre-warm libp2p paths for libp2p-capable follows so the
    // first sync (and Plan 16 voice) doesn't pay upgrade-dance latency
    // on cold start. No-op when signaling isn't bound yet (first launch
    // without identity); retried on every resume to cover onboarding-
    // mid-session.
    unawaited(_prewarmLibp2pUpgrades());

    // Plan 11a #17a: own the SignalingService.onInboundConnection callback
    // so the responder side of libp2p DCUtR upgrades can be dispatched.
    //
    // Plan 11c: bind the production `WsSignalingService` into the
    // runtime-settable slot the moment identity + secret are available,
    // then start the dispatcher. `main.dart` already does this at boot if
    // identity exists; this path handles the mid-session onboarding case
    // (boot identity=null → onboarding completes → identity arrives) that
    // used to leave the slot empty forever, breaking signaling + libp2p
    // prewarm for the rest of the session.
    unawaited(_ensureSignalingAndDispatcher());
    _identitySub = ref.listenManual<AsyncValue<Identity?>>(
      identityControllerProvider,
      (_, next) {
        if (next is AsyncData && next.value != null) {
          unawaited(_ensureSignalingAndDispatcher());
        }
      },
    );

    // Plan 14 Phase B: register the Android WorkManager periodic sync.
    // No-op on iOS (BGTaskScheduler is registered natively in AppDelegate).
    // Idempotent — `ExistingWorkPolicy.keep` means re-registering on every
    // resume doesn't reset the schedule.
    unawaited(initializeBackgroundSync());

    // Plan 14 Phase C: prepare the foreground service (Android only). The
    // service isn't started here — the user enables it from the Network
    // settings screen. Init is idempotent and cheap.
    ForegroundServiceController.instance.init();

    // Plan 14 Phase D: register the iOS BGTask Dart-side method channel
    // so when AppDelegate fires `BGAppRefreshTask` / `BGProcessingTask`,
    // the Swift handler can invoke `runBackgroundSync`. No-op on Android.
    IosBackgroundHandler.instance.install();

    // Re-publish the onion service whenever the HTTP server's bound port
    // changes (initial start, post-restart rebind). Arti reuses the persisted
    // keypair so the .onion address is stable across rebinds.
    _torPortSub = ref.listenManual<AsyncValue<int?>>(
      httpServerControllerProvider,
      (_, next) {
        final port = next.value;
        if (port != null) {
          _onionPublisher.requestPublish(port);
        }
      },
      fireImmediately: true,
    );
  }

  /// Call from `dispose`.
  Future<void> stop() async {
    unawaited(_retryPump?.stop());
    unawaited(_syncPump?.stop());
    unawaited(ref.read(reconnectPusherProvider).stop());
    _torPortSub?.close();
    _torPortSub = null;
    _identitySub?.close();
    _identitySub = null;
    _shutdownTimer?.cancel();
    _shutdownTimer = null;
    _pausedAt = null;
    // Cancel any pending publish-retry timer so it can't fire after dispose.
    _onionPublisher.reset();
  }

  /// Handle a foreground transition. If we were only briefly hidden
  /// (system sheet, camera permission, app switcher peek), the debounced
  /// shutdown is still pending and we cancel it — services stay live and
  /// the onion descriptor isn't disturbed. If we were paused long enough
  /// that iOS likely suspended the process, the timer would not have
  /// fired during suspension; in that case we force the shutdown now so
  /// the normal re-init starts from a clean slate.
  Future<void> onResume() async {
    final timer = _shutdownTimer;
    final pausedAt = _pausedAt;
    // _torInitFuture is nulled by _performShutdown; if it's null here the
    // previous shutdown already fired and a fresh pause-resume race set a
    // phantom timer. Re-init unconditionally instead of taking the "kept
    // live" branch.
    final servicesUp = _torInitFuture != null;
    // Clear state up front so a racing timer callback bails on the guard
    // in _performShutdown instead of tearing down what we're about to
    // re-init.
    _shutdownTimer = null;
    _pausedAt = null;
    timer?.cancel();

    if (servicesUp && timer != null && pausedAt != null) {
      final elapsed = DateTime.now().difference(pausedAt);
      if (elapsed < _pauseDebounce) {
        _log(
          'lifecycle=resumed (services kept live — paused ${elapsed.inSeconds}s, under ${_pauseDebounce.inSeconds}s)',
        );
        return;
      }
      _log(
        'lifecycle=resumed (suspended ${elapsed.inSeconds}s — forcing shutdown before re-init)',
      );
      _performShutdown(reason: 'suspended');
    } else if (!servicesUp) {
      _log('lifecycle=resumed (services were torn down — re-initing)');
    } else {
      _log('lifecycle=resumed');
    }

    final notifier = ref.read(httpServerControllerProvider.notifier);
    unawaited(notifier.restart());
    unawaited(_ensureTorInit());
    unawaited(_ensureLibp2pListen());
    // Plan 11c: bind production signaling before firing prewarm — the
    // prewarm bails on `signalingService is! WsSignalingService`, so
    // ordering matters when identity loaded mid-session and the start()
    // call ran without it. Awaited so the prewarm below sees the bound
    // service.
    await _ensureSignalingAndDispatcher();
    unawaited(_prewarmLibp2pUpgrades());
    _syncPump?.start();
    ref.read(reconnectPusherProvider).start();
  }

  /// Handle paused / detached / hidden. Defers the actual teardown via
  /// a debounced timer — see [_pauseDebounce]. The foreground-service
  /// branch (Android Plan 14 Phase C) still keeps services live with no
  /// timer at all, since the OS won't suspend us in that mode.
  Future<void> onPause() async {
    if (await ForegroundServiceController.instance.isRunning()) {
      _log('lifecycle=paused (fgservice on — keeping services live)');
      return;
    }
    // Already torn down — don't arm a phantom timer. A later resume that
    // sees a fresh timer + _pausedAt incorrectly takes the "services kept
    // live" branch and skips re-init, leaving Tor offline indefinitely.
    if (_torInitFuture == null && _onionPublisher.onionAddress == null) {
      _log('lifecycle=paused (services already down)');
      return;
    }
    _pausedAt ??= DateTime.now();
    if (_shutdownTimer != null) {
      _log('lifecycle=paused (shutdown already scheduled)');
      return;
    }
    _log(
      'lifecycle=paused (shutdown scheduled in ${_pauseDebounce.inSeconds}s)',
    );
    _shutdownTimer = Timer(_pauseDebounce, () {
      _performShutdown(reason: 'debounce elapsed');
    });
  }

  /// Tear down the HTTP server, Tor, libp2p, and the pumps. Invoked
  /// either by the debounced timer (true background past the window) or
  /// directly from [onResume] when wall-clock time says iOS already
  /// suspended us. Idempotent — re-entry via timer-vs-resume race is
  /// guarded by the `_pausedAt == null` check that [onResume] sets
  /// before calling.
  void _performShutdown({required String reason}) {
    // Guard against the timer firing concurrent with onResume's cancel —
    // onResume nulls _pausedAt before invoking us explicitly, so an
    // explicit call passes through, but a stale timer callback bails.
    if (_shutdownTimer == null && _pausedAt == null && reason != 'suspended') {
      return;
    }
    _shutdownTimer = null;
    _pausedAt = null;
    _log('lifecycle=shutdown ($reason)');
    final notifier = ref.read(httpServerControllerProvider.notifier);
    final tor = ref.read(torServiceProvider);
    final libp2p = ref.read(libp2pServiceProvider);
    unawaited(notifier.stop());
    // Cancel any pending publish-retry and clear the publisher's address
    // state; keep the provider write here (out of the publisher) so a late
    // timer never touches `ref` after teardown. The null gates the UI's
    // "Tor starting…" state and sendFollowRequest's noEndpoints check.
    _onionPublisher.reset();
    ref.read(onionAddressProvider.notifier).set(null);
    _torInitFuture = null;
    _libp2pListenFuture = null;
    unawaited(tor.shutdown());
    // Plan 11a: drop the libp2p swarm + UDP listeners on background to
    // avoid burning battery on QUIC keepalives + Identify pings.
    unawaited(libp2p.shutdown());
    unawaited(_syncPump?.stop());
    unawaited(ref.read(reconnectPusherProvider).stop());
  }

  Future<void> _ensureLibp2pListen() {
    return _libp2pListenFuture ??= () async {
      try {
        final libp2p = ref.read(libp2pServiceProvider);
        final dir = await libp2pDataDirectory();
        final seed = await _loadEd25519Seed();
        if (seed == null) {
          _log('libp2p.init skipped (no identity yet)');
          _libp2pListenFuture = null;
          return;
        }
        // init() is cheap with the stub (no-op); with the real bridge it
        // constructs the swarm. listen() actually binds UDP/QUIC. Zeroize
        // the seed buffer right after — the bridge owns its own copy.
        try {
          await libp2p.init(dir.path, seed);
          await libp2p.listen();
          _log('libp2p.listen complete peer_id=${libp2p.localPeerId}');
          // Bring up the inbound stream server so peers can reach us
          // over /starling/sync/*/1 protocols. Cheap with the stub
          // (no-op registrations); with the real bridge it activates
          // libp2p_stream::Behaviour acceptors per protocol.
          final server = await ref.read(libp2pStreamServerProvider.future);
          server.start();
        } finally {
          seed.fillRange(0, seed.length, 0);
        }
      } catch (e, st) {
        _log('libp2p.init failed: $e\n$st');
        _libp2pListenFuture = null;
        rethrow;
      }
    }();
  }

  /// Plan 11d — proactively run [Libp2pUpgrader.tryUpgrade] for every
  /// libp2p-capable follow on foreground, so the first sync request (and
  /// Plan 16 voice call) doesn't pay the upgrade-dance latency.
  ///
  /// Bails fast when prerequisites aren't met (signaling not bound,
  /// libp2p stub on this platform, listen still pending). The upgrader's
  /// internal `_inflight` set dedupes against a sync-engine-driven
  /// attempt firing in the same window, so calling this concurrently
  /// with the regular sync pump is safe.
  ///
  /// Skips peers reachable on LAN (already cheaper than libp2p) and peers
  /// already promoted to libp2pDirect (nothing to do). For Tor-resolved
  /// peers, signaling rides Tor and the upgrade dance can run.
  Future<void> _prewarmLibp2pUpgrades() async {
    // Wait for an in-flight listen so libp2p.isReady is meaningful.
    final pending = _libp2pListenFuture;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        return;
      }
    }

    final libp2p = ref.read(libp2pServiceProvider);
    if (!libp2p.isReady) return;

    final signaling = ref.read(signalingServiceProvider);
    if (signaling is! WsSignalingService) {
      _log('libp2p prewarm skipped: signaling not bound yet');
      return;
    }

    final storage = ref.read(storageServiceProvider);
    final upgrader = ref.read(libp2pUpgraderProvider);
    final factory = ref.read(peerConnectionFactoryProvider);

    final List<Follow> follows;
    try {
      follows = await storage.getFollows();
    } catch (e) {
      _log('libp2p prewarm: getFollows failed: $e');
      return;
    }

    // Cheap heuristic — same one the upgrader uses internally to decide
    // whether to bother. False positives are benign (tryUpgrade just
    // bails). The connectionCard is JSON, so a substring match is fine.
    bool capable(Follow f) => f.connectionCard.contains('libp2p-direct-v1');

    final candidates = follows.where(capable).toList();
    if (candidates.isEmpty) return;
    _log('libp2p prewarm: ${candidates.length} candidate follow(s)');

    final pool = Pool(3);
    await Future.wait(candidates.map((f) => pool.run(() async {
          final conn = await factory.resolve(f.pubkey);
          if (conn == null) return;
          // LAN beats libp2p; libp2p already promoted means nothing to do.
          if (conn.transport == PeerTransport.lan) return;
          if (conn.transport == PeerTransport.libp2pDirect) return;
          // conn is Tor (or future relay) — signaling rides it. Fire and
          // forget; tryUpgrade handles its own dedupe + backoff.
          try {
            await upgrader.tryUpgrade(conn, f);
          } catch (_) {
            // Upgrader logs internally; prewarm failures stay on Tor
            // until the next sync re-tries.
          }
        })));
  }

  /// Pull the 32-byte Ed25519 seed from the keychain-stored expanded secret.
  /// libsodium stores the secret as `seed || pubkey` (64 bytes); the first
  /// 32 are the seed the libp2p bridge needs to derive its PeerId. Returns
  /// null before onboarding has completed.
  Future<Uint8List?> _loadEd25519Seed() async {
    final secret = await _loadFullSecretKey();
    if (secret == null || secret.length < 32) return null;
    return Uint8List.fromList(secret.sublist(0, 32));
  }

  /// Full 64-byte Ed25519 secret (seed || pubkey) from the keychain.
  /// [WsSignalingService.localSecretKey] needs the expanded form to sign
  /// the WebSocket auth header.
  Future<Uint8List?> _loadFullSecretKey() async {
    final keychain = KeychainManager();
    final encoded = await keychain.read(KeychainManager.identitySecretKeyName);
    if (encoded == null) return null;
    return Uint8List.fromList(base64Decode(encoded));
  }

  /// Plan 11c: install [WsSignalingService] into the production slot
  /// (idempotent — set-once-then-keep), then start the dispatcher.
  /// Replaces the previous "bind only at boot if identity exists" pattern
  /// in `main.dart`: that left the slot empty when the user onboarded in
  /// the same session, after which `libp2p prewarm skipped: signaling not
  /// bound yet` kept firing for the rest of the session.
  Future<void> _ensureSignalingAndDispatcher() async {
    if (ref.read(productionSignalingProvider) == null) {
      final storage = ref.read(storageServiceProvider);
      final identity = await storage.getIdentity();
      if (identity == null) return;
      final secretKey = await _loadFullSecretKey();
      if (secretKey == null || secretKey.length != 64) return;
      final svc = WsSignalingService(
        crypto: ref.read(cryptoServiceProvider),
        peerFactory: (pubkey) =>
            ref.read(peerConnectionFactoryProvider).resolve(pubkey),
        localPubkey: identity.pubkey,
        localSecretKey: secretKey,
      );
      ref.read(productionSignalingProvider.notifier).set(svc);
      _log('signaling: bound production WsSignalingService');
    }
    final signaling = ref.read(signalingServiceProvider);
    if (signaling is WsSignalingService) {
      ref.read(signalingDispatcherProvider).start();
      if (kVoiceEnabled) {
        // Plan 16: listen for inbound room invites whenever foregrounded.
        ref.read(roomManagerProvider).start();
      }
    }
  }

  Future<void> _ensureTorInit() {
    return _torInitFuture ??= () async {
      try {
        _log('tor.init begin');
        final tor = ref.read(torServiceProvider);
        _log('tor.init service=${tor.runtimeType}');
        final dir = await torDataDirectory();
        _log('tor.init dataDir=${dir.path}');
        await tor.init(dir.path);
        _log('tor.init complete socksPort=${tor.socksPort}');
      } catch (e, st) {
        _log('tor.init failed: $e\n$st');
        // Drop the cached future on failure so a future port event can
        // retry from a clean slate.
        _torInitFuture = null;
        rethrow;
      }
    }();
  }

  void _log(String msg) {
    developer.log(msg, name: 'starling.tor');
    // ignore: avoid_print
    print('[starling.tor] $msg');
  }
}

/// Resolves Arti's data directory. Always under
/// `getApplicationSupportDirectory()` so iOS doesn't purge it under storage
/// pressure (Plan 14 Phase D: keeps the on-disk consensus + guards intact
/// across suspensions so warm bootstrap stays fast).
Future<Directory> torDataDirectory() async {
  final supportDir = await getApplicationSupportDirectory();
  final torDir = Directory('${supportDir.path}/tor');
  await torDir.create(recursive: true);
  return torDir;
}

/// Plan 11a — libp2p PeerStore cache directory. No secrets; the Ed25519
/// seed lives in the keychain. Under `getApplicationSupportDirectory()` so
/// iOS doesn't purge it under storage pressure.
Future<Directory> libp2pDataDirectory() async {
  final supportDir = await getApplicationSupportDirectory();
  final libp2pDir = Directory('${supportDir.path}/libp2p');
  await libp2pDir.create(recursive: true);
  return libp2pDir;
}
