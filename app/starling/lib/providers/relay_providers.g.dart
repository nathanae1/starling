// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'relay_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The Relay this Owner has paired with (Plan 15), loaded from storage and
/// reloaded on pair/unpair. Watched by `ownEndpoints` so the published
/// Connection card grows (or loses) its relay endpoint the moment pairing
/// state changes.

@ProviderFor(PairedRelayController)
final pairedRelayControllerProvider = PairedRelayControllerProvider._();

/// The Relay this Owner has paired with (Plan 15), loaded from storage and
/// reloaded on pair/unpair. Watched by `ownEndpoints` so the published
/// Connection card grows (or loses) its relay endpoint the moment pairing
/// state changes.
final class PairedRelayControllerProvider
    extends $AsyncNotifierProvider<PairedRelayController, PairedRelay?> {
  /// The Relay this Owner has paired with (Plan 15), loaded from storage and
  /// reloaded on pair/unpair. Watched by `ownEndpoints` so the published
  /// Connection card grows (or loses) its relay endpoint the moment pairing
  /// state changes.
  PairedRelayControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'pairedRelayControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$pairedRelayControllerHash();

  @$internal
  @override
  PairedRelayController create() => PairedRelayController();
}

String _$pairedRelayControllerHash() =>
    r'b58025a5878a51cb3f903d69c74ec188c0373df2';

/// The Relay this Owner has paired with (Plan 15), loaded from storage and
/// reloaded on pair/unpair. Watched by `ownEndpoints` so the published
/// Connection card grows (or loses) its relay endpoint the moment pairing
/// state changes.

abstract class _$PairedRelayController extends $AsyncNotifier<PairedRelay?> {
  FutureOr<PairedRelay?> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<PairedRelay?>, PairedRelay?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<PairedRelay?>, PairedRelay?>,
              AsyncValue<PairedRelay?>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// Shared Tor-backed HTTP client for all relay traffic (pairing + push).
/// Every relay endpoint is a `.onion`, so relay HTTP always rides Arti's
/// SOCKS5 proxy. Returns null until the onion address is published — the
/// same "Tor is ready for outbound" gate used by `torNetworkService`.
///
/// `keepAlive: true` because the wrapped [TorHttpClient] is a long-lived
/// resource that shouldn't be torn down on a transient drop in watchers.

@ProviderFor(relayTorClient)
final relayTorClientProvider = RelayTorClientProvider._();

/// Shared Tor-backed HTTP client for all relay traffic (pairing + push).
/// Every relay endpoint is a `.onion`, so relay HTTP always rides Arti's
/// SOCKS5 proxy. Returns null until the onion address is published — the
/// same "Tor is ready for outbound" gate used by `torNetworkService`.
///
/// `keepAlive: true` because the wrapped [TorHttpClient] is a long-lived
/// resource that shouldn't be torn down on a transient drop in watchers.

final class RelayTorClientProvider
    extends $FunctionalProvider<http.Client?, http.Client?, http.Client?>
    with $Provider<http.Client?> {
  /// Shared Tor-backed HTTP client for all relay traffic (pairing + push).
  /// Every relay endpoint is a `.onion`, so relay HTTP always rides Arti's
  /// SOCKS5 proxy. Returns null until the onion address is published — the
  /// same "Tor is ready for outbound" gate used by `torNetworkService`.
  ///
  /// `keepAlive: true` because the wrapped [TorHttpClient] is a long-lived
  /// resource that shouldn't be torn down on a transient drop in watchers.
  RelayTorClientProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'relayTorClientProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$relayTorClientHash();

  @$internal
  @override
  $ProviderElement<http.Client?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  http.Client? create(Ref ref) {
    return relayTorClient(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(http.Client? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<http.Client?>(value),
    );
  }
}

String _$relayTorClientHash() => r'f3007c53d53d3713e887d151f1cf932a6031db31';

/// Owner-signed push of EncryptedEvents + media to the paired relay
/// (Plan 15). Null until Tor is ready (see [relayTorClient]).

@ProviderFor(relayPushService)
final relayPushServiceProvider = RelayPushServiceProvider._();

/// Owner-signed push of EncryptedEvents + media to the paired relay
/// (Plan 15). Null until Tor is ready (see [relayTorClient]).

final class RelayPushServiceProvider
    extends
        $FunctionalProvider<
          RelayPushService?,
          RelayPushService?,
          RelayPushService?
        >
    with $Provider<RelayPushService?> {
  /// Owner-signed push of EncryptedEvents + media to the paired relay
  /// (Plan 15). Null until Tor is ready (see [relayTorClient]).
  RelayPushServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'relayPushServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$relayPushServiceHash();

  @$internal
  @override
  $ProviderElement<RelayPushService?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RelayPushService? create(Ref ref) {
    return relayPushService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RelayPushService? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RelayPushService?>(value),
    );
  }
}

String _$relayPushServiceHash() => r'476e2f02b506f69e8c2ba99db70e726e1e562996';

/// Drives the `/pair` handshake against a relay's admin onion (Plan 15).
/// Null until Tor is ready (see [relayTorClient]).

@ProviderFor(relayPairingInitiator)
final relayPairingInitiatorProvider = RelayPairingInitiatorProvider._();

/// Drives the `/pair` handshake against a relay's admin onion (Plan 15).
/// Null until Tor is ready (see [relayTorClient]).

final class RelayPairingInitiatorProvider
    extends
        $FunctionalProvider<
          RelayPairingInitiator?,
          RelayPairingInitiator?,
          RelayPairingInitiator?
        >
    with $Provider<RelayPairingInitiator?> {
  /// Drives the `/pair` handshake against a relay's admin onion (Plan 15).
  /// Null until Tor is ready (see [relayTorClient]).
  RelayPairingInitiatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'relayPairingInitiatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$relayPairingInitiatorHash();

  @$internal
  @override
  $ProviderElement<RelayPairingInitiator?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RelayPairingInitiator? create(Ref ref) {
    return relayPairingInitiator(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RelayPairingInitiator? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RelayPairingInitiator?>(value),
    );
  }
}

String _$relayPairingInitiatorHash() =>
    r'721fbf108cb697e6efcce44579a70d5513b5b654';

/// Best-effort owner→relay push coordinator (Plan 15). Async because it
/// needs the app-support directory to read encrypted media blobs from
/// disk. Null until Tor is ready (see [relayTorClient]).

@ProviderFor(relayPushCoordinator)
final relayPushCoordinatorProvider = RelayPushCoordinatorProvider._();

/// Best-effort owner→relay push coordinator (Plan 15). Async because it
/// needs the app-support directory to read encrypted media blobs from
/// disk. Null until Tor is ready (see [relayTorClient]).

final class RelayPushCoordinatorProvider
    extends
        $FunctionalProvider<
          AsyncValue<RelayPushCoordinator?>,
          RelayPushCoordinator?,
          FutureOr<RelayPushCoordinator?>
        >
    with
        $FutureModifier<RelayPushCoordinator?>,
        $FutureProvider<RelayPushCoordinator?> {
  /// Best-effort owner→relay push coordinator (Plan 15). Async because it
  /// needs the app-support directory to read encrypted media blobs from
  /// disk. Null until Tor is ready (see [relayTorClient]).
  RelayPushCoordinatorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'relayPushCoordinatorProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$relayPushCoordinatorHash();

  @$internal
  @override
  $FutureProviderElement<RelayPushCoordinator?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RelayPushCoordinator?> create(Ref ref) {
    return relayPushCoordinator(ref);
  }
}

String _$relayPushCoordinatorHash() =>
    r'e73c764f3b58bcdc30705c7c5b0a60ab56f1419c';

/// Phone-side relay pairing orchestrator (Plan 15). Async because it
/// depends on [relayPushCoordinator]. Null until Tor is ready.

@ProviderFor(relayPairingService)
final relayPairingServiceProvider = RelayPairingServiceProvider._();

/// Phone-side relay pairing orchestrator (Plan 15). Async because it
/// depends on [relayPushCoordinator]. Null until Tor is ready.

final class RelayPairingServiceProvider
    extends
        $FunctionalProvider<
          AsyncValue<RelayPairingService?>,
          RelayPairingService?,
          FutureOr<RelayPairingService?>
        >
    with
        $FutureModifier<RelayPairingService?>,
        $FutureProvider<RelayPairingService?> {
  /// Phone-side relay pairing orchestrator (Plan 15). Async because it
  /// depends on [relayPushCoordinator]. Null until Tor is ready.
  RelayPairingServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'relayPairingServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$relayPairingServiceHash();

  @$internal
  @override
  $FutureProviderElement<RelayPairingService?> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RelayPairingService?> create(Ref ref) {
    return relayPairingService(ref);
  }
}

String _$relayPairingServiceHash() =>
    r'd6413732f232026ef3635273796693d3b32ff136';
