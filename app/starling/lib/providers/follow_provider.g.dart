// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'follow_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Endpoints we currently advertise to peers. Tor-only: friend-add and
/// the connection cards that ride inside follow-request payloads must
/// not carry LAN hints, both to avoid leaking the local address and
/// because LAN-direct addresses are unreliable across NATs (e.g. Android
/// emulator's 10.0.2.0/24). Returns an empty list until Arti has
/// published our onion service — callers (QR sheet, follow request) gate
/// their UX on that.
///
/// Plan 15: once the Owner pairs a relay, its `.onion` is appended as a
/// `type:'relay'` endpoint. Followers rank it last (phone-onion first),
/// so it only carries traffic when the phone is unreachable.

@ProviderFor(ownEndpoints)
final ownEndpointsProvider = OwnEndpointsProvider._();

/// Endpoints we currently advertise to peers. Tor-only: friend-add and
/// the connection cards that ride inside follow-request payloads must
/// not carry LAN hints, both to avoid leaking the local address and
/// because LAN-direct addresses are unreliable across NATs (e.g. Android
/// emulator's 10.0.2.0/24). Returns an empty list until Arti has
/// published our onion service — callers (QR sheet, follow request) gate
/// their UX on that.
///
/// Plan 15: once the Owner pairs a relay, its `.onion` is appended as a
/// `type:'relay'` endpoint. Followers rank it last (phone-onion first),
/// so it only carries traffic when the phone is unreachable.

final class OwnEndpointsProvider
    extends $FunctionalProvider<List<Endpoint>, List<Endpoint>, List<Endpoint>>
    with $Provider<List<Endpoint>> {
  /// Endpoints we currently advertise to peers. Tor-only: friend-add and
  /// the connection cards that ride inside follow-request payloads must
  /// not carry LAN hints, both to avoid leaking the local address and
  /// because LAN-direct addresses are unreliable across NATs (e.g. Android
  /// emulator's 10.0.2.0/24). Returns an empty list until Arti has
  /// published our onion service — callers (QR sheet, follow request) gate
  /// their UX on that.
  ///
  /// Plan 15: once the Owner pairs a relay, its `.onion` is appended as a
  /// `type:'relay'` endpoint. Followers rank it last (phone-onion first),
  /// so it only carries traffic when the phone is unreachable.
  OwnEndpointsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ownEndpointsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ownEndpointsHash();

  @$internal
  @override
  $ProviderElement<List<Endpoint>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<Endpoint> create(Ref ref) {
    return ownEndpoints(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<Endpoint> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<Endpoint>>(value),
    );
  }
}

String _$ownEndpointsHash() => r'5407d1282bde2f5e53e58a8cfcfb749e4ec9995a';

/// Singleton [KeyRotationService] (Plan 13) — generates a new feed key on
/// follower removal and queues per-follower wrapped distributions.

@ProviderFor(keyRotationService)
final keyRotationServiceProvider = KeyRotationServiceProvider._();

/// Singleton [KeyRotationService] (Plan 13) — generates a new feed key on
/// follower removal and queues per-follower wrapped distributions.

final class KeyRotationServiceProvider
    extends
        $FunctionalProvider<
          KeyRotationService,
          KeyRotationService,
          KeyRotationService
        >
    with $Provider<KeyRotationService> {
  /// Singleton [KeyRotationService] (Plan 13) — generates a new feed key on
  /// follower removal and queues per-follower wrapped distributions.
  KeyRotationServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'keyRotationServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$keyRotationServiceHash();

  @$internal
  @override
  $ProviderElement<KeyRotationService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  KeyRotationService create(Ref ref) {
    return keyRotationService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(KeyRotationService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<KeyRotationService>(value),
    );
  }
}

String _$keyRotationServiceHash() =>
    r'6b8f050176a968d69e9ae71d74334bc3cc704423';

/// Singleton [FollowService] for the running app. Constructs the real
/// HTTP transport, wires identity / secret-key lookups, and points the
/// service at the live storage + crypto. Handshake requests to `.onion`
/// endpoints route through Arti's SOCKS5 proxy via [TorHttpClient]; LAN
/// endpoints continue to use the default `http.Client`.

@ProviderFor(followService)
final followServiceProvider = FollowServiceProvider._();

/// Singleton [FollowService] for the running app. Constructs the real
/// HTTP transport, wires identity / secret-key lookups, and points the
/// service at the live storage + crypto. Handshake requests to `.onion`
/// endpoints route through Arti's SOCKS5 proxy via [TorHttpClient]; LAN
/// endpoints continue to use the default `http.Client`.

final class FollowServiceProvider
    extends $FunctionalProvider<FollowService, FollowService, FollowService>
    with $Provider<FollowService> {
  /// Singleton [FollowService] for the running app. Constructs the real
  /// HTTP transport, wires identity / secret-key lookups, and points the
  /// service at the live storage + crypto. Handshake requests to `.onion`
  /// endpoints route through Arti's SOCKS5 proxy via [TorHttpClient]; LAN
  /// endpoints continue to use the default `http.Client`.
  FollowServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'followServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$followServiceHash();

  @$internal
  @override
  $ProviderElement<FollowService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  FollowService create(Ref ref) {
    return followService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FollowService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FollowService>(value),
    );
  }
}

String _$followServiceHash() => r'4a56f98f8d001ff745d210800a4b26a71c6fc391';

/// Convenience: assemble the connection card we share via QR. Returns
/// `null` until the onion endpoint is available so the QR sheet can show
/// a loading state instead of publishing a card with no reachable
/// transport.

@ProviderFor(ownConnectionCard)
final ownConnectionCardProvider = OwnConnectionCardProvider._();

/// Convenience: assemble the connection card we share via QR. Returns
/// `null` until the onion endpoint is available so the QR sheet can show
/// a loading state instead of publishing a card with no reachable
/// transport.

final class OwnConnectionCardProvider
    extends
        $FunctionalProvider<ConnectionCard?, ConnectionCard?, ConnectionCard?>
    with $Provider<ConnectionCard?> {
  /// Convenience: assemble the connection card we share via QR. Returns
  /// `null` until the onion endpoint is available so the QR sheet can show
  /// a loading state instead of publishing a card with no reachable
  /// transport.
  OwnConnectionCardProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ownConnectionCardProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ownConnectionCardHash();

  @$internal
  @override
  $ProviderElement<ConnectionCard?> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ConnectionCard? create(Ref ref) {
    return ownConnectionCard(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConnectionCard? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConnectionCard?>(value),
    );
  }
}

String _$ownConnectionCardHash() => r'9af2ad5601bacb4f90a4fc9c1fb22e7b27e0d3e4';
