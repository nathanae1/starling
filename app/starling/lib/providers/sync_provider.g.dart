// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Provides the singleton [PeerConnectionFactory] used by the sync engine
/// and `RemoteMediaFetcher`. Thin façade over [peerReachabilityMonitor]
/// — actual probing and state-tracking lives there.

@ProviderFor(peerConnectionFactory)
final peerConnectionFactoryProvider = PeerConnectionFactoryProvider._();

/// Provides the singleton [PeerConnectionFactory] used by the sync engine
/// and `RemoteMediaFetcher`. Thin façade over [peerReachabilityMonitor]
/// — actual probing and state-tracking lives there.

final class PeerConnectionFactoryProvider
    extends
        $FunctionalProvider<
          PeerConnectionFactory,
          PeerConnectionFactory,
          PeerConnectionFactory
        >
    with $Provider<PeerConnectionFactory> {
  /// Provides the singleton [PeerConnectionFactory] used by the sync engine
  /// and `RemoteMediaFetcher`. Thin façade over [peerReachabilityMonitor]
  /// — actual probing and state-tracking lives there.
  PeerConnectionFactoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'peerConnectionFactoryProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$peerConnectionFactoryHash();

  @$internal
  @override
  $ProviderElement<PeerConnectionFactory> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PeerConnectionFactory create(Ref ref) {
    return peerConnectionFactory(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PeerConnectionFactory value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PeerConnectionFactory>(value),
    );
  }
}

String _$peerConnectionFactoryHash() =>
    r'1ec5d4af777fc9e9ed1306bbfdaa1e0646bab2f2';

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

@ProviderFor(lanNetworkService)
final lanNetworkServiceProvider = LanNetworkServiceProvider._();

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

final class LanNetworkServiceProvider
    extends
        $FunctionalProvider<
          LanNetworkService,
          LanNetworkService,
          LanNetworkService
        >
    with $Provider<LanNetworkService> {
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
  LanNetworkServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lanNetworkServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lanNetworkServiceHash();

  @$internal
  @override
  $ProviderElement<LanNetworkService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LanNetworkService create(Ref ref) {
    return lanNetworkService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LanNetworkService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LanNetworkService>(value),
    );
  }
}

String _$lanNetworkServiceHash() => r'de7cdb89630d19386b31862d1c6224113dfd5cfd';

/// Sibling of [lanNetworkServiceProvider] backed by [TorHttpClient]. Same
/// `LanNetworkService` class, but every HTTP call goes through Arti's
/// SOCKS5 proxy. Returns `null` until our onion address is published —
/// that signal implies the SOCKS port is bound and `tor.init()` has
/// completed, so it doubles as the "Tor is ready for outbound" gate.
///
/// `keepAlive: true` for the same reason as [lanNetworkServiceProvider]:
/// the wrapped `TorHttpClient` is a long-lived resource that should not
/// be torn down on a transient drop in watcher count.

@ProviderFor(torNetworkService)
final torNetworkServiceProvider = TorNetworkServiceProvider._();

/// Sibling of [lanNetworkServiceProvider] backed by [TorHttpClient]. Same
/// `LanNetworkService` class, but every HTTP call goes through Arti's
/// SOCKS5 proxy. Returns `null` until our onion address is published —
/// that signal implies the SOCKS port is bound and `tor.init()` has
/// completed, so it doubles as the "Tor is ready for outbound" gate.
///
/// `keepAlive: true` for the same reason as [lanNetworkServiceProvider]:
/// the wrapped `TorHttpClient` is a long-lived resource that should not
/// be torn down on a transient drop in watcher count.

final class TorNetworkServiceProvider
    extends
        $FunctionalProvider<
          LanNetworkService?,
          LanNetworkService?,
          LanNetworkService?
        >
    with $Provider<LanNetworkService?> {
  /// Sibling of [lanNetworkServiceProvider] backed by [TorHttpClient]. Same
  /// `LanNetworkService` class, but every HTTP call goes through Arti's
  /// SOCKS5 proxy. Returns `null` until our onion address is published —
  /// that signal implies the SOCKS port is bound and `tor.init()` has
  /// completed, so it doubles as the "Tor is ready for outbound" gate.
  ///
  /// `keepAlive: true` for the same reason as [lanNetworkServiceProvider]:
  /// the wrapped `TorHttpClient` is a long-lived resource that should not
  /// be torn down on a transient drop in watcher count.
  TorNetworkServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'torNetworkServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$torNetworkServiceHash();

  @$internal
  @override
  $ProviderElement<LanNetworkService?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LanNetworkService? create(Ref ref) {
    return torNetworkService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LanNetworkService? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LanNetworkService?>(value),
    );
  }
}

String _$torNetworkServiceHash() => r'cc9fca4ce22ce78cfe308c8546f9f1f91ccc5290';

/// Plan 11a — Libp2pNetworkService bound to the global [libp2pServiceProvider]
/// (currently a stub; production override binds the FFI-backed bridge). Used
/// by [syncTransportProvider] as the dispatch target for `libp2pDirect`.

@ProviderFor(libp2pNetworkService)
final libp2pNetworkServiceProvider = Libp2pNetworkServiceProvider._();

/// Plan 11a — Libp2pNetworkService bound to the global [libp2pServiceProvider]
/// (currently a stub; production override binds the FFI-backed bridge). Used
/// by [syncTransportProvider] as the dispatch target for `libp2pDirect`.

final class Libp2pNetworkServiceProvider
    extends
        $FunctionalProvider<
          Libp2pNetworkService,
          Libp2pNetworkService,
          Libp2pNetworkService
        >
    with $Provider<Libp2pNetworkService> {
  /// Plan 11a — Libp2pNetworkService bound to the global [libp2pServiceProvider]
  /// (currently a stub; production override binds the FFI-backed bridge). Used
  /// by [syncTransportProvider] as the dispatch target for `libp2pDirect`.
  Libp2pNetworkServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libp2pNetworkServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libp2pNetworkServiceHash();

  @$internal
  @override
  $ProviderElement<Libp2pNetworkService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  Libp2pNetworkService create(Ref ref) {
    return libp2pNetworkService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Libp2pNetworkService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Libp2pNetworkService>(value),
    );
  }
}

String _$libp2pNetworkServiceHash() =>
    r'530655e0bfe9fa186ee99b64294f1fccb55e786c';

/// Plan 11a — inbound side of the libp2p direct tier. Wires the seven
/// `/starling/sync/*/1` protocol handlers to the same pure handler
/// functions the shelf HTTP server uses. `LifecycleManager` reads this
/// provider after `libp2p.listen()` completes and calls `start()`.

@ProviderFor(libp2pStreamServer)
final libp2pStreamServerProvider = Libp2pStreamServerProvider._();

/// Plan 11a — inbound side of the libp2p direct tier. Wires the seven
/// `/starling/sync/*/1` protocol handlers to the same pure handler
/// functions the shelf HTTP server uses. `LifecycleManager` reads this
/// provider after `libp2p.listen()` completes and calls `start()`.

final class Libp2pStreamServerProvider
    extends
        $FunctionalProvider<
          AsyncValue<Libp2pStreamServer>,
          Libp2pStreamServer,
          FutureOr<Libp2pStreamServer>
        >
    with
        $FutureModifier<Libp2pStreamServer>,
        $FutureProvider<Libp2pStreamServer> {
  /// Plan 11a — inbound side of the libp2p direct tier. Wires the seven
  /// `/starling/sync/*/1` protocol handlers to the same pure handler
  /// functions the shelf HTTP server uses. `LifecycleManager` reads this
  /// provider after `libp2p.listen()` completes and calls `start()`.
  Libp2pStreamServerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libp2pStreamServerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libp2pStreamServerHash();

  @$internal
  @override
  $FutureProviderElement<Libp2pStreamServer> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<Libp2pStreamServer> create(Ref ref) {
    return libp2pStreamServer(ref);
  }
}

String _$libp2pStreamServerHash() =>
    r'376a7dacd99c74a767ddf8b94650171f05309c84';

/// Singleton [SyncTransport] that routes each `PeerConnection` to the
/// HTTP client matching its transport (LAN direct vs SOCKS5-over-Tor vs
/// libp2p stream). Shared by [syncEngineProvider] and the on-demand media
/// fetcher so they all dial through the same routing logic.

@ProviderFor(syncTransport)
final syncTransportProvider = SyncTransportProvider._();

/// Singleton [SyncTransport] that routes each `PeerConnection` to the
/// HTTP client matching its transport (LAN direct vs SOCKS5-over-Tor vs
/// libp2p stream). Shared by [syncEngineProvider] and the on-demand media
/// fetcher so they all dial through the same routing logic.

final class SyncTransportProvider
    extends $FunctionalProvider<SyncTransport, SyncTransport, SyncTransport>
    with $Provider<SyncTransport> {
  /// Singleton [SyncTransport] that routes each `PeerConnection` to the
  /// HTTP client matching its transport (LAN direct vs SOCKS5-over-Tor vs
  /// libp2p stream). Shared by [syncEngineProvider] and the on-demand media
  /// fetcher so they all dial through the same routing logic.
  SyncTransportProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncTransportProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncTransportHash();

  @$internal
  @override
  $ProviderElement<SyncTransport> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SyncTransport create(Ref ref) {
    return syncTransport(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SyncTransport value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SyncTransport>(value),
    );
  }
}

String _$syncTransportHash() => r'104948cfa481b6ec813ff734cf0f3d87e75014f8';

/// Best-effort fan-out from the local poster to every accepted follower
/// whose connection is reachable. Used by `DefaultPostService` after a
/// post or delete event is persisted.

@ProviderFor(postFanoutService)
final postFanoutServiceProvider = PostFanoutServiceProvider._();

/// Best-effort fan-out from the local poster to every accepted follower
/// whose connection is reachable. Used by `DefaultPostService` after a
/// post or delete event is persisted.

final class PostFanoutServiceProvider
    extends
        $FunctionalProvider<
          PostFanoutService,
          PostFanoutService,
          PostFanoutService
        >
    with $Provider<PostFanoutService> {
  /// Best-effort fan-out from the local poster to every accepted follower
  /// whose connection is reachable. Used by `DefaultPostService` after a
  /// post or delete event is persisted.
  PostFanoutServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'postFanoutServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$postFanoutServiceHash();

  @$internal
  @override
  $ProviderElement<PostFanoutService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  PostFanoutService create(Ref ref) {
    return postFanoutService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PostFanoutService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PostFanoutService>(value),
    );
  }
}

String _$postFanoutServiceHash() => r'd4dc8b8e8d49a3ebc13f050766055b8536295f40';

/// Catches followers transitioning into a reachable state and pushes
/// recent own events to them. `keepAlive: true` so the in-memory
/// reachable-set + cooldown map survive transient watcher gaps.

@ProviderFor(reconnectPusher)
final reconnectPusherProvider = ReconnectPusherProvider._();

/// Catches followers transitioning into a reachable state and pushes
/// recent own events to them. `keepAlive: true` so the in-memory
/// reachable-set + cooldown map survive transient watcher gaps.

final class ReconnectPusherProvider
    extends
        $FunctionalProvider<ReconnectPusher, ReconnectPusher, ReconnectPusher>
    with $Provider<ReconnectPusher> {
  /// Catches followers transitioning into a reachable state and pushes
  /// recent own events to them. `keepAlive: true` so the in-memory
  /// reachable-set + cooldown map survive transient watcher gaps.
  ReconnectPusherProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reconnectPusherProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reconnectPusherHash();

  @$internal
  @override
  $ProviderElement<ReconnectPusher> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ReconnectPusher create(Ref ref) {
    return reconnectPusher(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReconnectPusher value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReconnectPusher>(value),
    );
  }
}

String _$reconnectPusherHash() => r'8f4825632466468ecb56e669b6a7ca723ff50597';

/// Plan 11a — DCUtR upgrade orchestrator. Wired into [syncEngineProvider]
/// so each Tor-resolved peer fire-and-forget tries to upgrade. Gated
/// internally on [Libp2pService.isReady]; with the stub bridge in place
/// every attempt is a no-op until the FFI-backed bridge ships.

@ProviderFor(libp2pUpgrader)
final libp2pUpgraderProvider = Libp2pUpgraderProvider._();

/// Plan 11a — DCUtR upgrade orchestrator. Wired into [syncEngineProvider]
/// so each Tor-resolved peer fire-and-forget tries to upgrade. Gated
/// internally on [Libp2pService.isReady]; with the stub bridge in place
/// every attempt is a no-op until the FFI-backed bridge ships.

final class Libp2pUpgraderProvider
    extends $FunctionalProvider<Libp2pUpgrader, Libp2pUpgrader, Libp2pUpgrader>
    with $Provider<Libp2pUpgrader> {
  /// Plan 11a — DCUtR upgrade orchestrator. Wired into [syncEngineProvider]
  /// so each Tor-resolved peer fire-and-forget tries to upgrade. Gated
  /// internally on [Libp2pService.isReady]; with the stub bridge in place
  /// every attempt is a no-op until the FFI-backed bridge ships.
  Libp2pUpgraderProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libp2pUpgraderProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libp2pUpgraderHash();

  @$internal
  @override
  $ProviderElement<Libp2pUpgrader> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Libp2pUpgrader create(Ref ref) {
    return libp2pUpgrader(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Libp2pUpgrader value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Libp2pUpgrader>(value),
    );
  }
}

String _$libp2pUpgraderHash() => r'9c6c1a68589a304fd07f3314d6a58d5777a4b8a9';

/// Plan 11a #17a — single owner of `SignalingService.onInboundConnection`.
/// Routes inbound libp2pConnect messages to [Libp2pUpgrader]; other
/// message types fall through for Plan 16. `LifecycleManager` calls
/// `start()`.

@ProviderFor(signalingDispatcher)
final signalingDispatcherProvider = SignalingDispatcherProvider._();

/// Plan 11a #17a — single owner of `SignalingService.onInboundConnection`.
/// Routes inbound libp2pConnect messages to [Libp2pUpgrader]; other
/// message types fall through for Plan 16. `LifecycleManager` calls
/// `start()`.

final class SignalingDispatcherProvider
    extends
        $FunctionalProvider<
          SignalingDispatcher,
          SignalingDispatcher,
          SignalingDispatcher
        >
    with $Provider<SignalingDispatcher> {
  /// Plan 11a #17a — single owner of `SignalingService.onInboundConnection`.
  /// Routes inbound libp2pConnect messages to [Libp2pUpgrader]; other
  /// message types fall through for Plan 16. `LifecycleManager` calls
  /// `start()`.
  SignalingDispatcherProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'signalingDispatcherProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$signalingDispatcherHash();

  @$internal
  @override
  $ProviderElement<SignalingDispatcher> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  SignalingDispatcher create(Ref ref) {
    return signalingDispatcher(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SignalingDispatcher value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SignalingDispatcher>(value),
    );
  }
}

String _$signalingDispatcherHash() =>
    r'75ba52ab326c62a2f06db77aa3c3b777cb315c9d';

/// Routes each peer's HTTP calls to either [lanNetworkServiceProvider]
/// or [torNetworkServiceProvider] based on `connection.transport`.

@ProviderFor(syncEngine)
final syncEngineProvider = SyncEngineProvider._();

/// Routes each peer's HTTP calls to either [lanNetworkServiceProvider]
/// or [torNetworkServiceProvider] based on `connection.transport`.

final class SyncEngineProvider
    extends $FunctionalProvider<SyncEngine, SyncEngine, SyncEngine>
    with $Provider<SyncEngine> {
  /// Routes each peer's HTTP calls to either [lanNetworkServiceProvider]
  /// or [torNetworkServiceProvider] based on `connection.transport`.
  SyncEngineProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncEngineProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncEngineHash();

  @$internal
  @override
  $ProviderElement<SyncEngine> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SyncEngine create(Ref ref) {
    return syncEngine(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SyncEngine value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SyncEngine>(value),
    );
  }
}

String _$syncEngineHash() => r'e32bd88c9bf29cc8faa0331b299d394a220a52c7';

/// Surfaces sync state to the UI and exposes [syncNow] for pull-to-refresh.

@ProviderFor(SyncController)
final syncControllerProvider = SyncControllerProvider._();

/// Surfaces sync state to the UI and exposes [syncNow] for pull-to-refresh.
final class SyncControllerProvider
    extends $NotifierProvider<SyncController, SyncEngineState> {
  /// Surfaces sync state to the UI and exposes [syncNow] for pull-to-refresh.
  SyncControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'syncControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$syncControllerHash();

  @$internal
  @override
  SyncController create() => SyncController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SyncEngineState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SyncEngineState>(value),
    );
  }
}

String _$syncControllerHash() => r'98ce29548449bf63bd53e695080e69b9a39b66f8';

/// Surfaces sync state to the UI and exposes [syncNow] for pull-to-refresh.

abstract class _$SyncController extends $Notifier<SyncEngineState> {
  SyncEngineState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<SyncEngineState, SyncEngineState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SyncEngineState, SyncEngineState>,
              SyncEngineState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
