import 'dart:io' show Platform;

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/clock.dart';
import '../services/comment_service.dart';
import '../services/content_key_service.dart';
import '../services/crypto/key_cache.dart';
import '../services/crypto/publish_lock.dart';
import '../services/crypto_service.dart';
import '../services/libp2p/libp2p_bridge.dart';
import '../services/libp2p/libp2p_bridge_stub.dart';
import '../services/libp2p/libp2p_service.dart';
import '../utils/feature_flags.dart';
import '../services/mdns_service.dart';
import '../services/mocks/mock_content_key_service.dart';
import '../services/mocks/mock_crypto_service.dart';
import '../services/mocks/mock_mdns_service.dart';
import '../services/mocks/mock_network_service.dart';
import '../services/mocks/mock_signaling_service.dart';
import '../services/mocks/mock_storage_service.dart';
import '../services/mocks/mock_tor_service.dart';
import '../services/network_service.dart';
import '../services/reaction_service.dart';
import '../services/room_key_rotation_service.dart';
import '../services/room_message_service.dart';
import '../services/room_service.dart';
import '../services/save_service.dart';
import '../services/signaling_service.dart';
import '../services/storage/keychain_manager.dart';
import '../services/storage_service.dart';
import '../services/tor_service.dart';

part 'service_providers.g.dart';

@riverpod
CryptoService cryptoService(Ref ref) => MockCryptoService();

@riverpod
ContentKeyService contentKeyService(Ref ref) => MockContentKeyService();

@riverpod
StorageService storageService(Ref ref) => MockStorageService();

@riverpod
TorService torService(Ref ref) => MockTorService();

/// Plan 11a — libp2p direct-connect tier. Selects the real FFI-backed
/// bridge on iOS and Android when `kLibp2pEnabled` is true; falls back to
/// the no-op stub on desktop, in tests, or when the feature flag is off.
/// `main.dart` may still override this in test setups.
@Riverpod(keepAlive: true)
Libp2pService libp2pService(Ref ref) {
  final canUseNative = kLibp2pEnabled && (Platform.isIOS || Platform.isAndroid);
  final Libp2pService bridge = canUseNative
      ? Libp2pBridge()
      : Libp2pBridgeStub();
  ref.onDispose(bridge.shutdown);
  return bridge;
}

/// Reactive holder for the local `.onion` address. Updated by `main.dart`
/// after `TorService.createOnionService` returns; watched by
/// `ownEndpoints` so the published connection card picks up the onion
/// endpoint as soon as it's available.
@Riverpod(keepAlive: true)
class OnionAddress extends _$OnionAddress {
  @override
  String? build() => null;
  void set(String? address) => state = address;
}

@riverpod
NetworkService networkService(Ref ref) => MockNetworkService();

/// Default binding is the in-memory mock so tests don't trigger native
/// channel activity. Production code overrides this in `main.dart` with
/// the real `MethodChannelMdnsService`.
@riverpod
MdnsService mdnsService(Ref ref) => MockMdnsService();

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
@Riverpod(keepAlive: true)
class ProductionSignaling extends _$ProductionSignaling {
  @override
  SignalingService? build() => null;
  void set(SignalingService svc) => state = svc;
}

/// The default fallback is [MockSignalingService] (so the dispatcher,
/// upgrader, and tests have a consistent backing) until `main.dart`
/// installs a real [WsSignalingService] via [ProductionSignaling].
@riverpod
SignalingService signalingService(Ref ref) {
  return ref.watch(productionSignalingProvider) ?? MockSignalingService();
}

@riverpod
Clock clock(Ref ref) => const SystemClock();

/// Shared in-memory feed-key cache. Hydrated at launch (main.dart) with
/// the identity's current key + the keys we've received from each follow,
/// then mutated by KeyRotationService and the sync engine. Tests get a
/// fresh empty cache.
@Riverpod(keepAlive: true)
FeedKeyCache feedKeyCache(Ref ref) => FeedKeyCache();

/// Shared mutex serializing post publication against feed-key rotation
/// (Plan 13). All post-publish services and the rotation service must
/// pull from this single instance — without it, a post in flight could
/// be encrypted with a stale key mid-rotation.
@Riverpod(keepAlive: true)
PublishLock publishLock(Ref ref) => PublishLock();

@riverpod
SaveService saveService(Ref ref) =>
    DefaultSaveService(ref.watch(storageServiceProvider));

@riverpod
CommentService commentService(Ref ref) => DefaultCommentService(
  contentKey: ref.watch(contentKeyServiceProvider),
  storage: ref.watch(storageServiceProvider),
  clock: ref.watch(clockProvider),
  identityLookup: () => ref.read(storageServiceProvider).getIdentity(),
  publishLock: ref.watch(publishLockProvider),
);

@riverpod
ReactionService reactionService(Ref ref) => DefaultReactionService(
  contentKey: ref.watch(contentKeyServiceProvider),
  storage: ref.watch(storageServiceProvider),
  clock: ref.watch(clockProvider),
  identityLookup: () => ref.read(storageServiceProvider).getIdentity(),
  publishLock: ref.watch(publishLockProvider),
);

// --- Chatrooms (Plan 17) ---

@riverpod
RoomKeyRotationService roomKeyRotationService(Ref ref) =>
    DefaultRoomKeyRotationService(
      crypto: ref.watch(cryptoServiceProvider),
      contentKey: ref.watch(contentKeyServiceProvider),
      storage: ref.watch(storageServiceProvider),
      clock: ref.watch(clockProvider),
      identityLookup: () => ref.read(storageServiceProvider).getIdentity(),
      ownSecretKeyLookup: () => KeychainManager().loadIdentitySecretKey(),
      publishLock: ref.watch(publishLockProvider),
    );

@riverpod
RoomService roomService(Ref ref) => DefaultRoomService(
  crypto: ref.watch(cryptoServiceProvider),
  contentKey: ref.watch(contentKeyServiceProvider),
  storage: ref.watch(storageServiceProvider),
  clock: ref.watch(clockProvider),
  identityLookup: () => ref.read(storageServiceProvider).getIdentity(),
  ownSecretKeyLookup: () => KeychainManager().loadIdentitySecretKey(),
  rotationService: ref.watch(roomKeyRotationServiceProvider),
  publishLock: ref.watch(publishLockProvider),
);

@riverpod
RoomMessageService roomMessageService(Ref ref) => DefaultRoomMessageService(
  contentKey: ref.watch(contentKeyServiceProvider),
  storage: ref.watch(storageServiceProvider),
  clock: ref.watch(clockProvider),
  identityLookup: () => ref.read(storageServiceProvider).getIdentity(),
  publishLock: ref.watch(publishLockProvider),
);
