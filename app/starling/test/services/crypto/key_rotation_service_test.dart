import 'dart:typed_data';

import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/crypto/key_cache.dart';
import 'package:starling/services/crypto/key_rotation_service.dart';
import 'package:starling/services/crypto/publish_lock.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/crypto_service.dart';
import 'package:starling/services/mocks/mock_clock.dart';
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService crypto;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  group('KeyRotationService.rotate', () {
    late _RotatorFixture fixture;

    setUp(() async {
      fixture = await _RotatorFixture.build(crypto);
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test(
      'with no followers: identity rotates, history grows, no distributions',
      () async {
        final originalKey = Uint8List.fromList(fixture.identity.feedKey);
        final originalValidFrom = fixture.identity.feedKeyValidFrom == 0
            ? fixture.identity.createdAt
            : fixture.identity.feedKeyValidFrom;

        fixture.clock.advance(60);
        await fixture.rotation.rotate(
          removedPubkey: 'someone-not-in-followers',
        );

        final newIdentity = await fixture.storage.getIdentity();
        expect(newIdentity!.feedKey, isNot(equals(originalKey)));
        expect(newIdentity.feedKeyEpoch, equals(0));
        expect(
          newIdentity.feedKeyValidFrom,
          equals(fixture.clock.nowUnixSeconds()),
        );

        final history = await fixture.storage.getFeedKeyHistory();
        expect(history, hasLength(1));
        expect(history.single.feedKey, equals(originalKey));
        expect(history.single.validFrom, equals(originalValidFrom));
        expect(
          history.single.validUntil,
          equals(fixture.clock.nowUnixSeconds()),
        );

        // No followers, no distributions.
        final cacheEntry = fixture.cache.get(fixture.identity.pubkey);
        expect(cacheEntry, isNotNull);
        expect(cacheEntry!.key, equals(newIdentity.feedKey));
      },
    );

    test(
      'with 3 followers, removing one: 2 distributions, none for the removed pubkey',
      () async {
        final carol = await _Peer.build(crypto);
        final dave = await _Peer.build(crypto);
        final evan = await _Peer.build(crypto);
        try {
          await fixture.acceptFollower(carol.pubkey);
          await fixture.acceptFollower(dave.pubkey);
          await fixture.acceptFollower(evan.pubkey);

          fixture.clock.advance(60);
          final rotateAt = fixture.clock.nowUnixSeconds();
          await fixture.rotation.rotate(removedPubkey: dave.pubkey);

          // Removed follower has no row.
          expect(
            await fixture.storage.latestPendingDistributionFor(dave.pubkey),
            isNull,
          );
          // Remaining followers each have a row.
          final carolPending = await fixture.storage
              .latestPendingDistributionFor(carol.pubkey);
          final evanPending = await fixture.storage
              .latestPendingDistributionFor(evan.pubkey);
          expect(carolPending, isNotNull);
          expect(evanPending, isNotNull);
          expect(carolPending!.createdAt, equals(rotateAt));
          expect(evanPending!.createdAt, equals(rotateAt));

          // Each follower can decrypt their own row to recover the new key.
          final newKey = (await fixture.storage.getIdentity())!.feedKey;
          for (final follower in [carol, evan]) {
            final pending = (await fixture.storage.latestPendingDistributionFor(
              follower.pubkey,
            ))!;
            final shared = follower.deriveSharedFromRotator(
              crypto: crypto,
              rotatorEdPk: crockfordBase32Decode(fixture.identity.pubkey),
              timestamp: rotateAt,
            );
            final decrypted = crypto.decrypt(
              pending.encryptedFeedKey,
              pending.nonce,
              shared,
            );
            expect(decrypted, equals(newKey));
          }

          // Carol can't decrypt evan's row (wrong shared key).
          final evanRow = (await fixture.storage.latestPendingDistributionFor(
            evan.pubkey,
          ))!;
          final carolWrongShared = carol.deriveSharedFromRotator(
            crypto: crypto,
            rotatorEdPk: crockfordBase32Decode(fixture.identity.pubkey),
            timestamp: rotateAt,
          );
          expect(
            () => crypto.decrypt(
              evanRow.encryptedFeedKey,
              evanRow.nonce,
              carolWrongShared,
            ),
            throwsA(anything),
          );
        } finally {
          // peers are pure data fixtures with no resources to release
        }
      },
    );

    test(
      'removing a follower clears any prior pending distribution for them',
      () async {
        final carol = await _Peer.build(crypto);
        await fixture.acceptFollower(carol.pubkey);

        // Pretend a stale distribution row already exists for carol.
        await fixture.storage.addPendingKeyDistribution(
          targetPubkey: carol.pubkey,
          encryptedFeedKey: Uint8List.fromList(List.filled(32, 0x11)),
          nonce: Uint8List.fromList(List.filled(24, 0x22)),
          createdAt: 5,
        );

        // Now remove carol — rotation should sweep her existing row even though
        // she's the one being removed.
        fixture.clock.advance(60);
        await fixture.rotation.rotate(removedPubkey: carol.pubkey);

        expect(
          await fixture.storage.latestPendingDistributionFor(carol.pubkey),
          isNull,
        );
      },
    );

    test(
      'two concurrent rotations serialize and both run to completion',
      () async {
        final carol = await _Peer.build(crypto);
        final dave = await _Peer.build(crypto);
        await fixture.acceptFollower(carol.pubkey);
        await fixture.acceptFollower(dave.pubkey);

        fixture.clock.advance(60);
        // Kick off two rotations from the same now() — they must serialize so
        // each appends one history row. (Without the lock, the second could
        // observe the first's mid-rotation cache state.)
        final fut1 = fixture.rotation.rotate(removedPubkey: carol.pubkey);
        final fut2 = fixture.rotation.rotate(removedPubkey: dave.pubkey);
        await Future.wait([fut1, fut2]);

        final history = await fixture.storage.getFeedKeyHistory();
        expect(history, hasLength(2));

        // Final identity feedKey is in the cache for our pubkey.
        final identity = await fixture.storage.getIdentity();
        expect(
          fixture.cache.get(fixture.identity.pubkey)?.key,
          equals(identity!.feedKey),
        );
      },
    );
  });
}

class _RotatorFixture {
  _RotatorFixture._({
    required this.identity,
    required this.secretKey,
    required this.storage,
    required this.cache,
    required this.rotation,
    required this.clock,
  });

  final Identity identity;
  final Uint8List secretKey;
  final MockStorageService storage;
  final FeedKeyCache cache;
  final KeyRotationService rotation;
  final MockClock clock;

  static Future<_RotatorFixture> build(CryptoService crypto) async {
    final kp = await crypto.generateKeyPair();
    final identity = Identity(
      pubkey: crockfordBase32Encode(kp.publicKey),
      feedKey: crypto.randomBytes(32),
      feedKeyEpoch: 0,
      feedKeyValidFrom: 1_000_000,
      createdAt: 1_000_000,
    );
    final storage = MockStorageService();
    await storage.saveIdentity(identity);
    final cache = FeedKeyCache()
      ..put(identity.pubkey, identity.feedKey, identity.feedKeyEpoch);
    final clock = MockClock(2_000_000);
    final rotation = KeyRotationService(
      crypto: crypto,
      storage: storage,
      clock: clock,
      feedKeyCache: cache,
      publishLock: PublishLock(),
      ownSecretKeyLookup: () async => kp.secretKey,
    );
    return _RotatorFixture._(
      identity: identity,
      secretKey: kp.secretKey,
      storage: storage,
      cache: cache,
      rotation: rotation,
      clock: clock,
    );
  }

  Future<void> acceptFollower(String followerPubkey) async {
    await storage.saveInboundRequest(
      FollowRequest(
        pubkey: followerPubkey,
        payload: Uint8List(0),
        createdAt: clock.nowUnixSeconds(),
        requestTimestamp: clock.nowUnixSeconds(),
        status: 'accepted',
      ),
    );
  }

  Future<void> dispose() => storage.dispose();
}

class _Peer {
  _Peer._({required this.pubkey, required this.secretKey});

  final String pubkey;
  final Uint8List secretKey;

  static Future<_Peer> build(CryptoService crypto) async {
    final kp = await crypto.generateKeyPair();
    return _Peer._(
      pubkey: crockfordBase32Encode(kp.publicKey),
      secretKey: kp.secretKey,
    );
  }

  /// Derive the shared key this follower would compute when receiving a
  /// rotation from [rotatorEdPk] at [timestamp]. Mirror the rotator's
  /// argument order so info bytes hash to the same value.
  Uint8List deriveSharedFromRotator({
    required CryptoService crypto,
    required Uint8List rotatorEdPk,
    required int timestamp,
  }) {
    final myEdPk = crockfordBase32Decode(pubkey);
    final myXSk = crypto.ed25519ToX25519SecretKey(secretKey);
    final theirXPk = crypto.ed25519ToX25519PublicKey(rotatorEdPk);
    return crypto.deriveSharedKey(
      myXSk,
      theirXPk,
      rotatorEdPk, // requester (the rotator)
      myEdPk, // responder (us, the follower)
      timestamp,
    );
  }
}
