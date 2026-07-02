import 'dart:typed_data';

import 'package:starling/models/models.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/crypto/feed_key_ratchet.dart';
import 'package:starling/services/crypto/key_cache.dart';
import 'package:starling/services/crypto/pairwise_content_key_service.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService crypto;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  Future<_Fixture> buildFixture() async {
    final kp = await crypto.generateKeyPair();
    final ownPubkey = crockfordBase32Encode(kp.publicKey);
    final feedKey = crypto.randomBytes(32);
    final cache = FeedKeyCache()..put(ownPubkey, feedKey, 0);
    final service = PairwiseContentKeyService(
      crypto: crypto,
      cache: cache,
      ownPubkey: ownPubkey,
      ownSecretKey: kp.secretKey,
    );
    return _Fixture(
      service: service,
      cache: cache,
      ownPubkey: ownPubkey,
      ownSecretKey: kp.secretKey,
      ownPublicKey: kp.publicKey,
      feedKey: feedKey,
    );
  }

  Event unsignedEvent({
    required String pubkey,
    String content = 'hello world',
    int kind = 1,
    Map<String, Uint8List> extensions = const {},
  }) {
    return Event(
      version: '2026-03-24',
      id: '', // placeholder, encryptForAudience computes real id
      pubkey: pubkey,
      createdAt: 1_712_500_000,
      kind: EventKind.fromValue(kind),
      content: Uint8List.fromList(content.codeUnits),
      sig: Uint8List(0),
      extensions: extensions,
    );
  }

  group('encryptForAudience + decryptEvent', () {
    test(
      'round-trip recovers the original event with valid signature',
      () async {
        final f = await buildFixture();
        final event = unsignedEvent(pubkey: f.ownPubkey);

        final enc = f.service.encryptForAudience(
          event,
          Audience.broadcast,
          msgSeq: 0,
        );
        expect(enc.pubkey, f.ownPubkey);
        expect(enc.createdAt, event.createdAt);
        expect(enc.epoch, 0);
        expect(enc.nonce.length, 24);
        expect(enc.payload, isNotEmpty);

        final decrypted = f.service.decryptEvent(enc, f.feedKey);
        expect(decrypted.version, event.version);
        expect(decrypted.pubkey, event.pubkey);
        expect(decrypted.createdAt, event.createdAt);
        expect(decrypted.content, event.content);
        expect(decrypted.id, isNotEmpty);
        expect(decrypted.sig.length, 64);
      },
    );

    test('decrypt with wrong key throws', () async {
      final f = await buildFixture();
      final event = unsignedEvent(pubkey: f.ownPubkey);
      final enc = f.service.encryptForAudience(
        event,
        Audience.broadcast,
        msgSeq: 0,
      );
      final wrongKey = crypto.randomBytes(32);
      expect(() => f.service.decryptEvent(enc, wrongKey), throwsA(anything));
    });

    test('uses current cache epoch, not a hardcoded zero', () async {
      final f = await buildFixture();
      final epoch3Key = deriveEpochKey(f.feedKey, 3, crypto);
      f.cache.put(f.ownPubkey, epoch3Key, 3);

      final event = unsignedEvent(pubkey: f.ownPubkey);
      final enc = f.service.encryptForAudience(
        event,
        Audience.broadcast,
        msgSeq: 0,
      );
      expect(enc.epoch, 3);

      final decrypted = f.service.decryptEvent(enc, epoch3Key);
      expect(decrypted.content, event.content);
    });

    test(
      'encryptForAudience throws when cache is missing own pubkey',
      () async {
        final f = await buildFixture();
        f.cache.remove(f.ownPubkey);
        final event = unsignedEvent(pubkey: f.ownPubkey);
        expect(
          () => f.service.encryptForAudience(
            event,
            Audience.broadcast,
            msgSeq: 0,
          ),
          throwsStateError,
        );
      },
    );
  });

  group('computeEventId', () {
    test('is deterministic for equivalent events', () async {
      final f = await buildFixture();
      final e1 = unsignedEvent(pubkey: f.ownPubkey);
      final e2 = unsignedEvent(pubkey: f.ownPubkey);
      expect(f.service.computeEventId(e1), f.service.computeEventId(e2));
    });

    test('depends on version (downgrade protection)', () async {
      final f = await buildFixture();
      final e1 = unsignedEvent(pubkey: f.ownPubkey);
      final e2 = e1.copyWith(version: '2099-01-01');
      expect(f.service.computeEventId(e1), isNot(f.service.computeEventId(e2)));
    });

    test('depends on extensions (trust-model coverage)', () async {
      final f = await buildFixture();
      final e1 = unsignedEvent(pubkey: f.ownPubkey);
      final e2 = unsignedEvent(
        pubkey: f.ownPubkey,
        extensions: {
          'x': Uint8List.fromList([1, 2, 3]),
        },
      );
      expect(f.service.computeEventId(e1), isNot(f.service.computeEventId(e2)));
    });

    test('empty-extensions event produces stable id', () async {
      final f = await buildFixture();
      final e = unsignedEvent(pubkey: f.ownPubkey);
      final id1 = f.service.computeEventId(e);
      final id2 = f.service.computeEventId(e);
      expect(id1, id2);
      // And the id is a valid base32 string.
      expect(id1.length, 52);
    });
  });

  group('feed key wrapping', () {
    test('encryptFeedKey + decryptFeedKey round trip', () async {
      final f = await buildFixture();
      final sharedKey = crypto.randomBytes(32);
      final feedKey = crypto.randomBytes(32);
      final wrapped = f.service.encryptFeedKey(feedKey, sharedKey);
      expect(wrapped.length, greaterThan(24));
      final unwrapped = f.service.decryptFeedKey(wrapped, sharedKey);
      expect(unwrapped, feedKey);
    });

    test('wrong shared key throws on decrypt', () async {
      final f = await buildFixture();
      final wrapped = f.service.encryptFeedKey(
        crypto.randomBytes(32),
        crypto.randomBytes(32),
      );
      expect(
        () => f.service.decryptFeedKey(wrapped, crypto.randomBytes(32)),
        throwsA(anything),
      );
    });
  });

  group('epoch advancement', () {
    test('advanceEpoch matches the standalone ratchet function', () async {
      final f = await buildFixture();
      expect(
        f.service.advanceEpoch(f.feedKey),
        ratchetFeedKey(f.feedKey, crypto),
      );
    });

    test('advanced key differs from original', () async {
      final f = await buildFixture();
      expect(f.service.advanceEpoch(f.feedKey), isNot(f.feedKey));
    });
  });

  group('signAndEncryptForAudience', () {
    test(
      'returns the signed plaintext alongside the encrypted wire form',
      () async {
        final f = await buildFixture();
        final unsigned = unsignedEvent(pubkey: f.ownPubkey);

        final result = f.service.signAndEncryptForAudience(
          unsigned,
          Audience.broadcast,
          msgSeq: 0,
        );

        expect(result.signed.id, isNotEmpty);
        expect(result.signed.sig.length, equals(64));
        expect(result.signed.pubkey, equals(f.ownPubkey));
        expect(result.signed.content, equals(unsigned.content));
        // Signature must verify against the owner's public key over the decoded
        // id bytes (same contract as decryptEvent).
        final idBytes = crockfordBase32Decode(result.signed.id);
        expect(
          crypto.verify(f.ownPublicKey, idBytes, result.signed.sig),
          isTrue,
        );
        // Encrypted wire form decrypts back to the same signed event.
        final decrypted = f.service.decryptEvent(result.encrypted, f.feedKey);
        expect(decrypted.id, equals(result.signed.id));
        expect(decrypted.sig, equals(result.signed.sig));
      },
    );

    test('encryptForAudience returns the same encrypted event', () async {
      final f = await buildFixture();
      final unsigned = unsignedEvent(pubkey: f.ownPubkey);
      // Two independent calls produce different ciphertexts (nonces differ)
      // but identical ids/signatures — compare via decryption instead.
      final pair = f.service.signAndEncryptForAudience(
        unsigned,
        Audience.broadcast,
        msgSeq: 0,
      );
      final viaEncryptOnly = f.service.encryptForAudience(
        unsigned,
        Audience.broadcast,
        msgSeq: 0,
      );
      final a = f.service.decryptEvent(pair.encrypted, f.feedKey);
      final b = f.service.decryptEvent(viaEncryptOnly, f.feedKey);
      expect(a.id, equals(b.id));
    });
  });
}

class _Fixture {
  _Fixture({
    required this.service,
    required this.cache,
    required this.ownPubkey,
    required this.ownSecretKey,
    required this.ownPublicKey,
    required this.feedKey,
  });

  final PairwiseContentKeyService service;
  final FeedKeyCache cache;
  final String ownPubkey;
  final Uint8List ownSecretKey;
  final Uint8List ownPublicKey;
  final Uint8List feedKey;
}
