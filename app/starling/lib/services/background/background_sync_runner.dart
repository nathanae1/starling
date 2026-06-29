import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:http/http.dart' as http;

import '../../sync/peer_connection_factory.dart';
import '../../sync/peer_reachability_monitor.dart';
import '../../sync/sync_engine.dart';
import '../../sync/transport_router.dart';
import '../clock.dart';
import '../crypto/key_cache.dart';
import '../crypto/pairwise_content_key_service.dart';
import '../crypto/sodium_crypto_service.dart';
import '../lan_network_service.dart';
import '../lifecycle/lifecycle_manager.dart' show torDataDirectory;
import '../mdns_service.dart';
import '../mocks/mock_tor_service.dart';
import '../storage/database.dart';
import '../storage/drift_storage_service.dart';
import '../storage/keychain_manager.dart';
import '../tor/arti_tor_service.dart';
import '../tor/tor_http_client.dart';
import '../tor_service.dart';

/// Result enum so the platform dispatcher knows what to report back to
/// the OS scheduler (WorkManager `Future<bool>` / iOS `setTaskCompleted`).
enum BackgroundSyncOutcome {
  /// Sync ran end-to-end without throwing. Events may or may not have
  /// been fetched (no follows reachable counts as success).
  ok,

  /// No identity in the DB — the user hasn't onboarded yet. There is
  /// nothing to sync. WorkManager should keep retrying since onboarding
  /// can happen later.
  noIdentity,

  /// Sync threw. The platform dispatcher will ask the OS to retry.
  failed,
}

/// One-shot background sync entry point. Builds the SyncEngine dependency
/// graph from scratch — this runs inside a Flutter isolate (WorkManager on
/// Android, BGTaskScheduler on iOS) where no Riverpod scope exists.
///
/// With `allowTor: true` (Plan 14 Phase D — iOS BGProcessingTask, Android
/// WorkManager when conditions allow), the runner stands up a real
/// [ArtiTorService] in [TorBootstrapMode.onDemand] and bounds the bootstrap
/// wait by [torWarmBootstrapBudget]. On timeout, the run continues
/// LAN-only — circuits weren't ready in the budget, and a BGTask handler
/// has no slack to keep waiting.
class BackgroundSyncRunner {
  const BackgroundSyncRunner._();

  static Future<BackgroundSyncOutcome> run({
    bool allowTor = false,
    Duration torWarmBootstrapBudget = const Duration(seconds: 7),
  }) async {
    _log('background sync begin allowTor=$allowTor');
    // Required so plugins (keychain, mDNS) have a binding to dispatch
    // method-channel calls through. Cheap and idempotent.
    WidgetsFlutterBinding.ensureInitialized();

    DriftStorageService? storage;
    PeerReachabilityMonitor? monitor;
    TorService? tor;
    final lanHttp = http.Client();
    try {
      // --- Boot stack: same primitives as `main()` in main.dart, minus the
      // Flutter app shell. Riverpod isn't loaded here — every dependency is
      // constructed directly so the isolate can run without a ProviderScope.
      final keychain = KeychainManager();
      storage = await _openStorage(keychain);

      final identity = await storage.getIdentity();
      if (identity == null) {
        _log('background sync: no identity, skipping');
        return BackgroundSyncOutcome.noIdentity;
      }

      final secretKey = await keychain.loadIdentitySecretKey();
      if (secretKey == null) {
        _log('background sync: identity present but no secret key, skipping');
        return BackgroundSyncOutcome.noIdentity;
      }

      final crypto = await SodiumCryptoService.init();

      final follows = await storage.getFollows();
      final cache = FeedKeyCache()
        ..put(identity.pubkey, identity.feedKey, identity.feedKeyEpoch);
      for (final f in follows) {
        cache.put(f.pubkey, f.feedKey, f.feedKeyEpoch);
      }

      final contentKey = PairwiseContentKeyService(
        crypto: crypto,
        cache: cache,
        ownPubkey: identity.pubkey,
        ownSecretKey: secretKey,
      );

      final mdns = MethodChannelMdnsService();
      final lan = LanNetworkService(mdns: mdns, httpClient: lanHttp);

      const clock = SystemClock();

      // Opportunistic Tor: stand up Arti in on-demand mode, warm-bootstrap
      // it with a budget. On timeout we drop back to LAN-only — circuits
      // weren't ready in time, and a BGTask handler can't keep waiting.
      LanNetworkService? torLan;
      http.Client? torHttp;
      if (allowTor) {
        try {
          final arti = ArtiTorService();
          final dir = await torDataDirectory();
          await arti.init(dir.path, bootstrapMode: TorBootstrapMode.onDemand);
          tor = arti;
          await arti.bootstrap(timeout: torWarmBootstrapBudget);
          final socks = arti.socksPort;
          if (socks != 0 && arti.isReady) {
            torHttp = TorHttpClient(socksHost: '127.0.0.1', socksPort: socks);
            torLan = LanNetworkService(mdns: mdns, httpClient: torHttp);
            _log('Tor ready for background sync (socks=$socks)');
          } else {
            _log('Tor init succeeded but not ready in budget — LAN-only');
          }
        } catch (e) {
          _log('Tor warm-bootstrap failed (continuing LAN-only): $e');
        }
      }

      monitor = PeerReachabilityMonitor(
        mdns: mdns,
        // MockTorService when allowTor is off or Tor failed to warm — the
        // monitor reads `isReady` and skips Tor probes when false.
        tor: tor ?? MockTorService(),
        storage: storage,
        lanProbeClient: lanHttp,
        torProbeClient: () => torHttp,
        clock: clock,
      );
      await monitor.start();

      // Give the monitor's first probe round a chance to land. LAN probes
      // have a ~5s individual timeout; bound the wait so we don't burn the
      // whole WorkManager budget here. Plan 14 verification step 4 — confirm
      // background sync completes inside the OS budget.
      await Future<void>.delayed(const Duration(seconds: 4));

      // SyncTransport: LAN-only when Tor isn't ready; otherwise route per
      // PeerConnection.transport. `PeerConnectionFactory` only resolves
      // transports the monitor has validated, so the Tor backing is only
      // dialed when its probe came back reachable.
      final SyncTransport transport = torLan != null
          ? TransportRouter(lan: lan, tor: torLan)
          : lan;

      final engine = SyncEngine(
        storage: storage,
        contentKey: contentKey,
        crypto: crypto,
        transport: transport,
        peerFactory: PeerConnectionFactory(monitor: monitor),
        reachabilityMonitor: monitor,
        clock: clock,
        ownSecretKeyLookup: () async => secretKey,
        feedKeyCache: cache,
      );

      final report = await engine.syncNow();
      _log(
        'background sync ok peers=${report.peers.length} '
        'fetched=${report.totalEventsFetched} '
        'duration=${report.finishedAt - report.startedAt}s',
      );
      return BackgroundSyncOutcome.ok;
    } catch (e, st) {
      _log('background sync failed: $e\n$st');
      return BackgroundSyncOutcome.failed;
    } finally {
      try {
        await monitor?.stop();
      } catch (_) {}
      try {
        lanHttp.close();
      } catch (_) {}
      try {
        await tor?.shutdown();
      } catch (_) {}
      // `torHttp` (TorHttpClient) closes when its underlying sockets are
      // dropped — no explicit close API. DriftStorageService likewise has
      // no public close; the isolate exit handles both.
    }
  }

  static Future<DriftStorageService> _openStorage(
    KeychainManager keychain,
  ) async {
    final dbKey = await keychain.read(KeychainManager.dbKeyName);
    if (dbKey == null) {
      throw StateError(
        'background sync: no DB key in keychain — main app never ran',
      );
    }
    final db = AppDatabase.encrypted(dbKey);
    return DriftStorageService(db, const SystemClock());
  }

  static void _log(String msg) {
    developer.log(msg, name: 'starling.bgsync');
    // ignore: avoid_print
    print('[starling.bgsync] $msg');
  }
}
