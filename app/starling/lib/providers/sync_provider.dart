import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/lan_network_service.dart';
import '../services/libp2p_network_service.dart';
import '../services/libp2p_stream_server.dart';
import '../services/post_fanout_service.dart';
import '../services/reconnect_pusher.dart';
import '../services/signaling/signaling_dispatcher.dart';
import '../services/storage/keychain_manager.dart';
import '../services/tor/tor_http_client.dart';
import '../sync/libp2p_upgrader.dart';
import '../sync/peer_connection_factory.dart';
import '../sync/peer_reachability_provider.dart';
import '../sync/sync_engine.dart';
import '../sync/transport_router.dart';
import '../utils/debug_log.dart';
import 'app_paths_provider.dart';
import 'follow_provider.dart';
import 'relay_providers.dart';
import 'service_providers.dart';

part 'sync_provider.g.dart';

/// Provides the singleton [PeerConnectionFactory] used by the sync engine
/// and `RemoteMediaFetcher`. Thin façade over [peerReachabilityMonitor]
/// — actual probing and state-tracking lives there.
@riverpod
PeerConnectionFactory peerConnectionFactory(Ref ref) {
  return PeerConnectionFactory(
    monitor: ref.watch(peerReachabilityMonitorProvider),
  );
}

/// LanNetworkService singleton. The default `networkServiceProvider` is
/// the abstract interface (mock by default); the concrete LAN client is
/// kept separate so the sync engine can call `fetchEnvelope`, which is a
/// LAN-specific method not yet on the cross-tier interface.
///
/// `keepAlive: true` because the wrapped `http.Client` is a connection-
/// pooling singleton — auto-disposing closes it, and a brief watcher gap
/// during a rebuild cascade (e.g. when `onionAddressProvider` flips
/// non-null and `torNetworkServiceProvider` rebuilds → `syncTransport`
/// rebuilds) used to leave captured references holding a closed client.
@Riverpod(keepAlive: true)
LanNetworkService lanNetworkService(Ref ref) {
  final mdns = ref.watch(mdnsServiceProvider);
  final svc = LanNetworkService(mdns: mdns);
  ref.onDispose(svc.close);
  return svc;
}

/// Sibling of [lanNetworkServiceProvider] backed by [TorHttpClient]. Same
/// `LanNetworkService` class, but every HTTP call goes through Arti's
/// SOCKS5 proxy. Returns `null` until our onion address is published —
/// that signal implies the SOCKS port is bound and `tor.init()` has
/// completed, so it doubles as the "Tor is ready for outbound" gate.
///
/// `keepAlive: true` for the same reason as [lanNetworkServiceProvider]:
/// the wrapped `TorHttpClient` is a long-lived resource that should not
/// be torn down on a transient drop in watcher count.
@Riverpod(keepAlive: true)
LanNetworkService? torNetworkService(Ref ref) {
  // Watch the onion address as a reactive ready-signal. Until it lands,
  // sync stays on the LAN tier; once it lands, this provider rebuilds and
  // the sync engine picks up Tor as a fallback.
  final onion = ref.watch(onionAddressProvider);
  if (onion == null) return null;
  final tor = ref.watch(torServiceProvider);
  final port = tor.socksPort;
  if (port == 0) return null;
  final mdns = ref.watch(mdnsServiceProvider);
  final svc = LanNetworkService(
    mdns: mdns,
    httpClient: TorHttpClient(socksHost: '127.0.0.1', socksPort: port),
  );
  ref.onDispose(svc.close);
  return svc;
}

/// Plan 11a — Libp2pNetworkService bound to the global [libp2pServiceProvider]
/// (currently a stub; production override binds the FFI-backed bridge). Used
/// by [syncTransportProvider] as the dispatch target for `libp2pDirect`.
@Riverpod(keepAlive: true)
Libp2pNetworkService libp2pNetworkService(Ref ref) {
  return Libp2pNetworkService(libp2p: ref.watch(libp2pServiceProvider));
}

/// Plan 11a — inbound side of the libp2p direct tier. Wires the seven
/// `/starling/sync/*/1` protocol handlers to the same pure handler
/// functions the shelf HTTP server uses. `LifecycleManager` reads this
/// provider after `libp2p.listen()` completes and calls `start()`.
@Riverpod(keepAlive: true)
Future<Libp2pStreamServer> libp2pStreamServer(Ref ref) async {
  final storage = ref.watch(storageServiceProvider);
  final contentKey = ref.watch(contentKeyServiceProvider);
  final clock = ref.watch(clockProvider);
  final appSupportDir = await ref.watch(appSupportDirectoryProvider.future);
  final libp2p = ref.watch(libp2pServiceProvider);
  return Libp2pStreamServer(
    libp2p: libp2p,
    storage: storage,
    contentKey: contentKey,
    crypto: ref.watch(cryptoServiceProvider),
    clock: clock,
    appSupportDir: appSupportDir,
    identityLookup: storage.getIdentity,
    followServiceLookup: () => ref.read(followServiceProvider),
    ownSecretKeyLookup: () => KeychainManager().loadIdentitySecretKey(),
  );
}

/// Singleton [SyncTransport] that routes each `PeerConnection` to the
/// HTTP client matching its transport (LAN direct vs SOCKS5-over-Tor vs
/// libp2p stream). Shared by [syncEngineProvider] and the on-demand media
/// fetcher so they all dial through the same routing logic.
@riverpod
SyncTransport syncTransport(Ref ref) {
  final lan = ref.watch(lanNetworkServiceProvider);
  final tor = ref.watch(torNetworkServiceProvider);
  final libp2p = ref.watch(libp2pNetworkServiceProvider);
  if (tor == null) return lan as SyncTransport;
  return TransportRouter(lan: lan, tor: tor, libp2p: libp2p);
}

/// Best-effort fan-out from the local poster to every accepted follower
/// whose connection is reachable. Used by `DefaultPostService` after a
/// post or delete event is persisted.
@riverpod
PostFanoutService postFanoutService(Ref ref) {
  return DefaultPostFanoutService(
    storage: ref.watch(storageServiceProvider),
    transport: ref.watch(syncTransportProvider),
    reachability: ref.watch(peerReachabilityMonitorProvider),
  );
}

/// Catches followers transitioning into a reachable state and pushes
/// recent own events to them. `keepAlive: true` so the in-memory
/// reachable-set + cooldown map survive transient watcher gaps.
@Riverpod(keepAlive: true)
ReconnectPusher reconnectPusher(Ref ref) {
  return ReconnectPusher(
    storage: ref.watch(storageServiceProvider),
    transport: ref.watch(syncTransportProvider),
    reachability: ref.watch(peerReachabilityMonitorProvider),
    clock: ref.watch(clockProvider),
  );
}

/// Plan 11a — DCUtR upgrade orchestrator. Wired into [syncEngineProvider]
/// so each Tor-resolved peer fire-and-forget tries to upgrade. Gated
/// internally on [Libp2pService.isReady]; with the stub bridge in place
/// every attempt is a no-op until the FFI-backed bridge ships.
@Riverpod(keepAlive: true)
Libp2pUpgrader libp2pUpgrader(Ref ref) {
  return Libp2pUpgrader(
    libp2p: ref.watch(libp2pServiceProvider),
    signaling: ref.watch(signalingServiceProvider),
    reachability: ref.watch(peerReachabilityMonitorProvider),
    clock: ref.watch(clockProvider),
    crypto: ref.watch(cryptoServiceProvider),
    localPubkeyLookup: () async {
      final identity = await ref.read(storageServiceProvider).getIdentity();
      return identity?.pubkey;
    },
    localSecretKeyLookup: () => KeychainManager().loadIdentitySecretKey(),
  );
}

/// Plan 11a #17a — single owner of `SignalingService.onInboundConnection`.
/// Routes inbound libp2pConnect messages to [Libp2pUpgrader]; other
/// message types fall through for Plan 16. `LifecycleManager` calls
/// `start()`.
@Riverpod(keepAlive: true)
SignalingDispatcher signalingDispatcher(Ref ref) {
  return SignalingDispatcher(
    signaling: ref.watch(signalingServiceProvider),
    upgrader: ref.watch(libp2pUpgraderProvider),
    crypto: ref.watch(cryptoServiceProvider),
    localPubkeyLookup: () async {
      final identity = await ref.read(storageServiceProvider).getIdentity();
      return identity?.pubkey;
    },
    localSecretKeyLookup: () => KeychainManager().loadIdentitySecretKey(),
  );
}

/// Routes each peer's HTTP calls to either [lanNetworkServiceProvider]
/// or [torNetworkServiceProvider] based on `connection.transport`.
@riverpod
SyncEngine syncEngine(Ref ref) {
  final transport = ref.watch(syncTransportProvider);
  return SyncEngine(
    storage: ref.watch(storageServiceProvider),
    contentKey: ref.watch(contentKeyServiceProvider),
    crypto: ref.watch(cryptoServiceProvider),
    transport: transport,
    peerFactory: ref.watch(peerConnectionFactoryProvider),
    reachabilityMonitor: ref.watch(peerReachabilityMonitorProvider),
    clock: ref.watch(clockProvider),
    ownSecretKeyLookup: () => KeychainManager().loadIdentitySecretKey(),
    libp2pUpgrader: ref.watch(libp2pUpgraderProvider),
  );
}

enum SyncRunPhase { idle, syncing }

class SyncEngineState {
  const SyncEngineState({
    required this.phase,
    this.lastReport,
    this.lastSyncAt,
    this.lastError,
  });
  final SyncRunPhase phase;
  final SyncReport? lastReport;
  final int? lastSyncAt;
  final String? lastError;

  SyncEngineState copyWith({
    SyncRunPhase? phase,
    SyncReport? lastReport,
    int? lastSyncAt,
    String? lastError,
    bool clearError = false,
  }) => SyncEngineState(
    phase: phase ?? this.phase,
    lastReport: lastReport ?? this.lastReport,
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    lastError: clearError ? null : (lastError ?? this.lastError),
  );

  static const idle = SyncEngineState(phase: SyncRunPhase.idle);
}

/// Surfaces sync state to the UI and exposes [syncNow] for pull-to-refresh.
@riverpod
class SyncController extends _$SyncController {
  @override
  SyncEngineState build() => SyncEngineState.idle;

  Future<SyncReport> syncNow() async {
    if (state.phase == SyncRunPhase.syncing) {
      // Coalesce concurrent triggers — the in-flight sync's report is
      // what callers will see when it lands.
      return state.lastReport ??
          const SyncReport(startedAt: 0, finishedAt: 0, peers: []);
    }
    state = state.copyWith(phase: SyncRunPhase.syncing, clearError: true);
    final engine = ref.read(syncEngineProvider);
    try {
      final report = await engine.syncNow();
      state = SyncEngineState(
        phase: SyncRunPhase.idle,
        lastReport: report,
        lastSyncAt: report.finishedAt,
      );
      // Plan 15: best-effort self-heal — re-push any own events the paired
      // relay is missing (e.g. published while it was unreachable). No-ops
      // when no relay is paired.
      unawaited(_reconcileRelay());
      return report;
    } catch (e) {
      // Users see the fixed "Sync problem" copy; the raw detail lives here.
      debugLog('sync', 'sync run failed: $e');
      state = state.copyWith(phase: SyncRunPhase.idle, lastError: e.toString());
      rethrow;
    }
  }

  Future<void> _reconcileRelay() async {
    try {
      // A2/A3: retry any pending card fan-out / wire unpair notify a
      // crash or Tor outage left behind, before the content pass.
      await ref.read(relayPairingServiceProvider).heal();
      final coord = await ref.read(relayPushCoordinatorProvider.future);
      await coord?.reconcile();
      // A7: freshen the paired-relay row (lastPushAt/lastError) the
      // connection-settings screen renders.
      await ref.read(pairedRelayControllerProvider.notifier).reload();
    } catch (_) {
      // Best-effort; the next sync pass retries.
    }
  }
}
