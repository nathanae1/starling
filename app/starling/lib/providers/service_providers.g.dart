// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(cryptoService)
final cryptoServiceProvider = CryptoServiceProvider._();

final class CryptoServiceProvider
    extends $FunctionalProvider<CryptoService, CryptoService, CryptoService>
    with $Provider<CryptoService> {
  CryptoServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'cryptoServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$cryptoServiceHash();

  @$internal
  @override
  $ProviderElement<CryptoService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CryptoService create(Ref ref) {
    return cryptoService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CryptoService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CryptoService>(value),
    );
  }
}

String _$cryptoServiceHash() => r'0d58462786084107e55cab9a337007c6d99a3d48';

@ProviderFor(contentKeyService)
final contentKeyServiceProvider = ContentKeyServiceProvider._();

final class ContentKeyServiceProvider
    extends
        $FunctionalProvider<
          ContentKeyService,
          ContentKeyService,
          ContentKeyService
        >
    with $Provider<ContentKeyService> {
  ContentKeyServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'contentKeyServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$contentKeyServiceHash();

  @$internal
  @override
  $ProviderElement<ContentKeyService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ContentKeyService create(Ref ref) {
    return contentKeyService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ContentKeyService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ContentKeyService>(value),
    );
  }
}

String _$contentKeyServiceHash() => r'e5a059e84dbf336859ec1cc80a195848b61f9cd3';

@ProviderFor(storageService)
final storageServiceProvider = StorageServiceProvider._();

final class StorageServiceProvider
    extends $FunctionalProvider<StorageService, StorageService, StorageService>
    with $Provider<StorageService> {
  StorageServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'storageServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$storageServiceHash();

  @$internal
  @override
  $ProviderElement<StorageService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  StorageService create(Ref ref) {
    return storageService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StorageService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StorageService>(value),
    );
  }
}

String _$storageServiceHash() => r'4180349da34ceeca8d362aecfdd8707bbb91d0a9';

@ProviderFor(torService)
final torServiceProvider = TorServiceProvider._();

final class TorServiceProvider
    extends $FunctionalProvider<TorService, TorService, TorService>
    with $Provider<TorService> {
  TorServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'torServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$torServiceHash();

  @$internal
  @override
  $ProviderElement<TorService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TorService create(Ref ref) {
    return torService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TorService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TorService>(value),
    );
  }
}

String _$torServiceHash() => r'6a60f20b0aef7d7e85eb959e970dc1e9f7eb6435';

/// Plan 11a — libp2p direct-connect tier. Selects the real FFI-backed
/// bridge on iOS and Android when `kLibp2pEnabled` is true; falls back to
/// the no-op stub on desktop, in tests, or when the feature flag is off.
/// `main.dart` may still override this in test setups.

@ProviderFor(libp2pService)
final libp2pServiceProvider = Libp2pServiceProvider._();

/// Plan 11a — libp2p direct-connect tier. Selects the real FFI-backed
/// bridge on iOS and Android when `kLibp2pEnabled` is true; falls back to
/// the no-op stub on desktop, in tests, or when the feature flag is off.
/// `main.dart` may still override this in test setups.

final class Libp2pServiceProvider
    extends $FunctionalProvider<Libp2pService, Libp2pService, Libp2pService>
    with $Provider<Libp2pService> {
  /// Plan 11a — libp2p direct-connect tier. Selects the real FFI-backed
  /// bridge on iOS and Android when `kLibp2pEnabled` is true; falls back to
  /// the no-op stub on desktop, in tests, or when the feature flag is off.
  /// `main.dart` may still override this in test setups.
  Libp2pServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'libp2pServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$libp2pServiceHash();

  @$internal
  @override
  $ProviderElement<Libp2pService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Libp2pService create(Ref ref) {
    return libp2pService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Libp2pService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Libp2pService>(value),
    );
  }
}

String _$libp2pServiceHash() => r'29d00ed368a142eb108b042cfb40ee584e83a5a8';

/// Reactive holder for the local `.onion` address. Updated by `main.dart`
/// after `TorService.createOnionService` returns; watched by
/// `ownEndpoints` so the published connection card picks up the onion
/// endpoint as soon as it's available.

@ProviderFor(OnionAddress)
final onionAddressProvider = OnionAddressProvider._();

/// Reactive holder for the local `.onion` address. Updated by `main.dart`
/// after `TorService.createOnionService` returns; watched by
/// `ownEndpoints` so the published connection card picks up the onion
/// endpoint as soon as it's available.
final class OnionAddressProvider
    extends $NotifierProvider<OnionAddress, String?> {
  /// Reactive holder for the local `.onion` address. Updated by `main.dart`
  /// after `TorService.createOnionService` returns; watched by
  /// `ownEndpoints` so the published connection card picks up the onion
  /// endpoint as soon as it's available.
  OnionAddressProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'onionAddressProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$onionAddressHash();

  @$internal
  @override
  OnionAddress create() => OnionAddress();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$onionAddressHash() => r'f1d213aee3b6e1dcde4a6b9f7b5b805d9ab4a40a';

/// Reactive holder for the local `.onion` address. Updated by `main.dart`
/// after `TorService.createOnionService` returns; watched by
/// `ownEndpoints` so the published connection card picks up the onion
/// endpoint as soon as it's available.

abstract class _$OnionAddress extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

@ProviderFor(networkService)
final networkServiceProvider = NetworkServiceProvider._();

final class NetworkServiceProvider
    extends $FunctionalProvider<NetworkService, NetworkService, NetworkService>
    with $Provider<NetworkService> {
  NetworkServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'networkServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$networkServiceHash();

  @$internal
  @override
  $ProviderElement<NetworkService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  NetworkService create(Ref ref) {
    return networkService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(NetworkService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<NetworkService>(value),
    );
  }
}

String _$networkServiceHash() => r'f6bf0f4d4e0db8fda9cf980e02b35c63da50c02b';

/// Default binding is the in-memory mock so tests don't trigger native
/// channel activity. Production code overrides this in `main.dart` with
/// the real `MethodChannelMdnsService`.

@ProviderFor(mdnsService)
final mdnsServiceProvider = MdnsServiceProvider._();

/// Default binding is the in-memory mock so tests don't trigger native
/// channel activity. Production code overrides this in `main.dart` with
/// the real `MethodChannelMdnsService`.

final class MdnsServiceProvider
    extends $FunctionalProvider<MdnsService, MdnsService, MdnsService>
    with $Provider<MdnsService> {
  /// Default binding is the in-memory mock so tests don't trigger native
  /// channel activity. Production code overrides this in `main.dart` with
  /// the real `MethodChannelMdnsService`.
  MdnsServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mdnsServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mdnsServiceHash();

  @$internal
  @override
  $ProviderElement<MdnsService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MdnsService create(Ref ref) {
    return mdnsService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MdnsService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MdnsService>(value),
    );
  }
}

String _$mdnsServiceHash() => r'4c871553ae885ba8c6083dd18390f67ff1075fe2';

/// Runtime-settable slot for the production [WsSignalingService].
///
/// Plan 11c: this replaces the previous pattern in `main.dart` that
/// constructed `WsSignalingService` with a closure over a `late
/// ProviderContainer`, then handed it back to the container via
/// `overrideWithValue`. That worked but was fragile — the closure was
/// captured *before* the container existed, surviving only because Dart
/// `late` captures by reference.
///
/// Now: `main.dart` builds the container, constructs the
/// `WsSignalingService` against the already-built container, and stores
/// it here via `set(svc)`. [signalingService] watches this slot and
/// returns whatever is current.

@ProviderFor(ProductionSignaling)
final productionSignalingProvider = ProductionSignalingProvider._();

/// Runtime-settable slot for the production [WsSignalingService].
///
/// Plan 11c: this replaces the previous pattern in `main.dart` that
/// constructed `WsSignalingService` with a closure over a `late
/// ProviderContainer`, then handed it back to the container via
/// `overrideWithValue`. That worked but was fragile — the closure was
/// captured *before* the container existed, surviving only because Dart
/// `late` captures by reference.
///
/// Now: `main.dart` builds the container, constructs the
/// `WsSignalingService` against the already-built container, and stores
/// it here via `set(svc)`. [signalingService] watches this slot and
/// returns whatever is current.
final class ProductionSignalingProvider
    extends $NotifierProvider<ProductionSignaling, SignalingService?> {
  /// Runtime-settable slot for the production [WsSignalingService].
  ///
  /// Plan 11c: this replaces the previous pattern in `main.dart` that
  /// constructed `WsSignalingService` with a closure over a `late
  /// ProviderContainer`, then handed it back to the container via
  /// `overrideWithValue`. That worked but was fragile — the closure was
  /// captured *before* the container existed, surviving only because Dart
  /// `late` captures by reference.
  ///
  /// Now: `main.dart` builds the container, constructs the
  /// `WsSignalingService` against the already-built container, and stores
  /// it here via `set(svc)`. [signalingService] watches this slot and
  /// returns whatever is current.
  ProductionSignalingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'productionSignalingProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$productionSignalingHash();

  @$internal
  @override
  ProductionSignaling create() => ProductionSignaling();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SignalingService? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SignalingService?>(value),
    );
  }
}

String _$productionSignalingHash() =>
    r'ea2055da3857eebfdccce1bc319cc5463b1535da';

/// Runtime-settable slot for the production [WsSignalingService].
///
/// Plan 11c: this replaces the previous pattern in `main.dart` that
/// constructed `WsSignalingService` with a closure over a `late
/// ProviderContainer`, then handed it back to the container via
/// `overrideWithValue`. That worked but was fragile — the closure was
/// captured *before* the container existed, surviving only because Dart
/// `late` captures by reference.
///
/// Now: `main.dart` builds the container, constructs the
/// `WsSignalingService` against the already-built container, and stores
/// it here via `set(svc)`. [signalingService] watches this slot and
/// returns whatever is current.

abstract class _$ProductionSignaling extends $Notifier<SignalingService?> {
  SignalingService? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<SignalingService?, SignalingService?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<SignalingService?, SignalingService?>,
              SignalingService?,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// The default fallback is [MockSignalingService] (so the dispatcher,
/// upgrader, and tests have a consistent backing) until `main.dart`
/// installs a real [WsSignalingService] via [ProductionSignaling].

@ProviderFor(signalingService)
final signalingServiceProvider = SignalingServiceProvider._();

/// The default fallback is [MockSignalingService] (so the dispatcher,
/// upgrader, and tests have a consistent backing) until `main.dart`
/// installs a real [WsSignalingService] via [ProductionSignaling].

final class SignalingServiceProvider
    extends
        $FunctionalProvider<
          SignalingService,
          SignalingService,
          SignalingService
        >
    with $Provider<SignalingService> {
  /// The default fallback is [MockSignalingService] (so the dispatcher,
  /// upgrader, and tests have a consistent backing) until `main.dart`
  /// installs a real [WsSignalingService] via [ProductionSignaling].
  SignalingServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'signalingServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$signalingServiceHash();

  @$internal
  @override
  $ProviderElement<SignalingService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SignalingService create(Ref ref) {
    return signalingService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SignalingService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SignalingService>(value),
    );
  }
}

String _$signalingServiceHash() => r'60d1ab507f1fb20eb944aecec0a488b4602866cc';

@ProviderFor(clock)
final clockProvider = ClockProvider._();

final class ClockProvider extends $FunctionalProvider<Clock, Clock, Clock>
    with $Provider<Clock> {
  ClockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'clockProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$clockHash();

  @$internal
  @override
  $ProviderElement<Clock> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  Clock create(Ref ref) {
    return clock(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(Clock value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<Clock>(value),
    );
  }
}

String _$clockHash() => r'51dfbf45b6f587fbcfbb074c52c85416118b4ff3';

/// Shared in-memory feed-key cache. Hydrated at launch (main.dart) with
/// the identity's current key + the keys we've received from each follow,
/// then mutated by KeyRotationService and the sync engine. Tests get a
/// fresh empty cache.

@ProviderFor(feedKeyCache)
final feedKeyCacheProvider = FeedKeyCacheProvider._();

/// Shared in-memory feed-key cache. Hydrated at launch (main.dart) with
/// the identity's current key + the keys we've received from each follow,
/// then mutated by KeyRotationService and the sync engine. Tests get a
/// fresh empty cache.

final class FeedKeyCacheProvider
    extends $FunctionalProvider<FeedKeyCache, FeedKeyCache, FeedKeyCache>
    with $Provider<FeedKeyCache> {
  /// Shared in-memory feed-key cache. Hydrated at launch (main.dart) with
  /// the identity's current key + the keys we've received from each follow,
  /// then mutated by KeyRotationService and the sync engine. Tests get a
  /// fresh empty cache.
  FeedKeyCacheProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'feedKeyCacheProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$feedKeyCacheHash();

  @$internal
  @override
  $ProviderElement<FeedKeyCache> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  FeedKeyCache create(Ref ref) {
    return feedKeyCache(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FeedKeyCache value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FeedKeyCache>(value),
    );
  }
}

String _$feedKeyCacheHash() => r'2e97e74cbc64b8a06b7dc0d767bb649815525c32';

/// Shared mutex serializing post publication against feed-key rotation
/// (Plan 13). All post-publish services and the rotation service must
/// pull from this single instance — without it, a post in flight could
/// be encrypted with a stale key mid-rotation.

@ProviderFor(publishLock)
final publishLockProvider = PublishLockProvider._();

/// Shared mutex serializing post publication against feed-key rotation
/// (Plan 13). All post-publish services and the rotation service must
/// pull from this single instance — without it, a post in flight could
/// be encrypted with a stale key mid-rotation.

final class PublishLockProvider
    extends $FunctionalProvider<PublishLock, PublishLock, PublishLock>
    with $Provider<PublishLock> {
  /// Shared mutex serializing post publication against feed-key rotation
  /// (Plan 13). All post-publish services and the rotation service must
  /// pull from this single instance — without it, a post in flight could
  /// be encrypted with a stale key mid-rotation.
  PublishLockProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'publishLockProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$publishLockHash();

  @$internal
  @override
  $ProviderElement<PublishLock> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PublishLock create(Ref ref) {
    return publishLock(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PublishLock value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PublishLock>(value),
    );
  }
}

String _$publishLockHash() => r'2e4b82c49bcb0fa8a4072951aa7ccb3c3b0cb9e2';

@ProviderFor(saveService)
final saveServiceProvider = SaveServiceProvider._();

final class SaveServiceProvider
    extends $FunctionalProvider<SaveService, SaveService, SaveService>
    with $Provider<SaveService> {
  SaveServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'saveServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$saveServiceHash();

  @$internal
  @override
  $ProviderElement<SaveService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SaveService create(Ref ref) {
    return saveService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SaveService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SaveService>(value),
    );
  }
}

String _$saveServiceHash() => r'9d95bea13731c72442485145daa07bab5f97fe31';

@ProviderFor(commentService)
final commentServiceProvider = CommentServiceProvider._();

final class CommentServiceProvider
    extends $FunctionalProvider<CommentService, CommentService, CommentService>
    with $Provider<CommentService> {
  CommentServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'commentServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$commentServiceHash();

  @$internal
  @override
  $ProviderElement<CommentService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CommentService create(Ref ref) {
    return commentService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CommentService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CommentService>(value),
    );
  }
}

String _$commentServiceHash() => r'd3cc2c7daf83634d841cda24bbe124f77a122d89';

@ProviderFor(reactionService)
final reactionServiceProvider = ReactionServiceProvider._();

final class ReactionServiceProvider
    extends
        $FunctionalProvider<ReactionService, ReactionService, ReactionService>
    with $Provider<ReactionService> {
  ReactionServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'reactionServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$reactionServiceHash();

  @$internal
  @override
  $ProviderElement<ReactionService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ReactionService create(Ref ref) {
    return reactionService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ReactionService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ReactionService>(value),
    );
  }
}

String _$reactionServiceHash() => r'd1f0c6141b6ec35b0a8bc17e16f45a292712375a';

@ProviderFor(roomKeyRotationService)
final roomKeyRotationServiceProvider = RoomKeyRotationServiceProvider._();

final class RoomKeyRotationServiceProvider
    extends
        $FunctionalProvider<
          RoomKeyRotationService,
          RoomKeyRotationService,
          RoomKeyRotationService
        >
    with $Provider<RoomKeyRotationService> {
  RoomKeyRotationServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roomKeyRotationServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roomKeyRotationServiceHash();

  @$internal
  @override
  $ProviderElement<RoomKeyRotationService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RoomKeyRotationService create(Ref ref) {
    return roomKeyRotationService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RoomKeyRotationService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RoomKeyRotationService>(value),
    );
  }
}

String _$roomKeyRotationServiceHash() =>
    r'a3bfcaf2cd4a5020fc6f76faee34a90dd8a7ad4c';

@ProviderFor(roomService)
final roomServiceProvider = RoomServiceProvider._();

final class RoomServiceProvider
    extends $FunctionalProvider<RoomService, RoomService, RoomService>
    with $Provider<RoomService> {
  RoomServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roomServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roomServiceHash();

  @$internal
  @override
  $ProviderElement<RoomService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RoomService create(Ref ref) {
    return roomService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RoomService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RoomService>(value),
    );
  }
}

String _$roomServiceHash() => r'21768899a99daf1ef1728a063492f7df7d22d72e';

@ProviderFor(roomMessageService)
final roomMessageServiceProvider = RoomMessageServiceProvider._();

final class RoomMessageServiceProvider
    extends
        $FunctionalProvider<
          RoomMessageService,
          RoomMessageService,
          RoomMessageService
        >
    with $Provider<RoomMessageService> {
  RoomMessageServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roomMessageServiceProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roomMessageServiceHash();

  @$internal
  @override
  $ProviderElement<RoomMessageService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RoomMessageService create(Ref ref) {
    return roomMessageService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RoomMessageService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RoomMessageService>(value),
    );
  }
}

String _$roomMessageServiceHash() =>
    r'3f0ab8db7c02b4224910c6182be3b8c5241ebc94';
