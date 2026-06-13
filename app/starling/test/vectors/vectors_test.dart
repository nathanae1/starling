import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:starling/models/models.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/crypto/feed_key_ratchet.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/crypto_service.dart';
import 'package:starling/sync/manifest_ack.dart';
import 'package:starling/sync/manifest_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Uint8List fromHex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// Loads `test/vectors/index.json` from the package. Works regardless of
/// the cwd `flutter test` is run from.
Map<String, dynamic> _loadVectors() {
  // When running from the package root, the cwd is the package root.
  final candidates = [
    'test/vectors/index.json',
    p.join(Directory.current.path, 'test/vectors/index.json'),
  ];
  for (final path in candidates) {
    final f = File(path);
    if (f.existsSync()) {
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    }
  }
  throw StateError('could not find test/vectors/index.json');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService crypto;
  late Map<String, dynamic> vectors;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
    vectors = _loadVectors();
  });

  test('vector 1: keypair from fixed seed', () async {
    final v = vectors['keypair'] as Map<String, dynamic>;
    final seed = fromHex(v['seed_hex'] as String);
    final expectedPhrase = (v['recovery_phrase'] as List).cast<String>();
    final expectedPk = v['ed25519_public_key_hex'] as String;
    final expectedSk = v['ed25519_secret_key_hex'] as String;
    final expectedXpk = v['x25519_public_key_hex'] as String;
    final expectedXsk = v['x25519_secret_key_hex'] as String;

    final phrase = await crypto.deriveRecoveryPhrase(seed);
    expect(phrase, expectedPhrase);

    final kp = await crypto.recoverFromPhrase(phrase);
    expect(hex(kp.publicKey), expectedPk);
    expect(hex(kp.secretKey), expectedSk);

    expect(hex(crypto.ed25519ToX25519PublicKey(kp.publicKey)), expectedXpk);
    expect(hex(crypto.ed25519ToX25519SecretKey(kp.secretKey)), expectedXsk);
  });

  test('vector 2: event id from fixed fields', () async {
    final v = vectors['event_id'] as Map<String, dynamic>;
    final event = Event(
      version: v['version'] as String,
      id: '',
      pubkey: v['pubkey'] as String,
      createdAt: v['created_at'] as int,
      kind: EventKind.fromValue(v['kind'] as int),
      content: fromHex(v['content_hex'] as String),
      sig: Uint8List(0),
    );

    final idFieldsBytes = Uint8List.fromList(cbor.encode(event.toIdFields()));
    expect(hex(idFieldsBytes), v['id_fields_cbor_hex'] as String);

    final idHash = crypto.blake2b256(idFieldsBytes);
    expect(hex(idHash), v['id_bytes_hex'] as String);
    expect(crockfordBase32Encode(idHash), v['id_base32'] as String);
  });

  test('vector 3: event signature', () async {
    final v = vectors['event_sign'] as Map<String, dynamic>;
    final kpFixed = vectors['keypair'] as Map<String, dynamic>;
    final sk = fromHex(kpFixed['ed25519_secret_key_hex'] as String);
    final message = fromHex(v['signed_bytes_hex'] as String);
    final sig = crypto.sign(sk, message);
    expect(hex(sig), v['signature_hex'] as String);

    // And the signature must verify.
    final pk = fromHex(kpFixed['ed25519_public_key_hex'] as String);
    expect(crypto.verify(pk, message, sig), isTrue);
  });

  test('vector 4: feed key ratchet', () async {
    final v = vectors['ratchet'] as Map<String, dynamic>;
    final base = fromHex(v['base_key_hex'] as String);
    final epoch1 = ratchetFeedKey(base, crypto);
    final epoch2 = ratchetFeedKey(epoch1, crypto);
    expect(hex(epoch1), v['epoch_1_hex'] as String);
    expect(hex(epoch2), v['epoch_2_hex'] as String);
  });

  test('vector 5: event encryption with fixed nonce and key', () async {
    final v = vectors['event_encrypt'] as Map<String, dynamic>;
    final feedKey = fromHex(v['feed_key_hex'] as String);
    final nonce = fromHex(v['nonce_hex'] as String);
    final eventBytes = fromHex(v['event_bytes_hex'] as String);
    final expectedCt = v['ciphertext_hex'] as String;
    final ct = crypto.encrypt(eventBytes, nonce, feedKey);
    expect(hex(ct), expectedCt);

    // And the decryption round-trips.
    final pt = crypto.decrypt(ct, nonce, feedKey);
    expect(pt, eventBytes);
  });

  // --- relay_wire: the Dart↔Rust surfaces (Plan 15). The mirror test on
  // the Rust side is relay/crates/starling-wire/tests/wire_vectors.rs.

  group('relay_wire vectors', () {
    late Map<String, dynamic> rw;
    late Uint8List ownerPk;
    late Uint8List ownerSk;

    setUpAll(() {
      rw = vectors['relay_wire'] as Map<String, dynamic>;
      final kpFixed = vectors['keypair'] as Map<String, dynamic>;
      ownerPk = fromHex(kpFixed['ed25519_public_key_hex'] as String);
      ownerSk = fromHex(kpFixed['ed25519_secret_key_hex'] as String);
    });

    test('crockford base32 encode + look-alike decode', () {
      final v = rw['crockford_base32'] as Map<String, dynamic>;
      final bytes = fromHex(v['bytes_hex'] as String);
      expect(crockfordBase32Encode(bytes), v['encoded'] as String);
      expect(
        crockfordBase32Decode(v['lookalike_decode_input'] as String),
        crockfordBase32Decode(v['lookalike_decode_canonical'] as String),
      );
    });

    test('pair claim digest, signature, and claim CBOR', () {
      final v = rw['pair_claim'] as Map<String, dynamic>;
      final token = fromHex(v['pairing_token_hex'] as String);
      final claimBytes = Uint8List.fromList([
        ...utf8.encode('starling-relay-pair-v1'),
        ...ownerPk,
        ...utf8.encode(v['admin_onion'] as String),
        ...token,
      ]);
      expect(hex(claimBytes), v['claim_bytes_hex'] as String);
      final digest = crypto.blake2b256(claimBytes);
      expect(hex(digest), v['claim_digest_hex'] as String);
      final sig = crypto.sign(ownerSk, digest);
      expect(hex(sig), v['sig_hex'] as String);
      final claimCbor = Uint8List.fromList(cbor.encode(<String, dynamic>{
        'owner_pubkey': base64.encode(ownerPk),
        'pairing_token': token,
        'sig': sig,
      }));
      expect(hex(claimCbor), v['claim_cbor_hex'] as String);
    });

    test('relay_id derivation and PairResponse decode', () {
      final v = rw['relay_id'] as Map<String, dynamic>;
      final derived = hex(crypto.blake2b256(Uint8List.fromList([
        ...ownerPk,
        ...utf8.encode(v['owner_onion'] as String),
      ])));
      expect(derived, v['relay_id_hex'] as String);
      // Decode the pinned Rust-shaped response the way the initiator does.
      final decoded =
          cbor.decode(fromHex(v['pair_response_cbor_hex'] as String)) as Map;
      expect(decoded['relay_onion'], v['owner_onion'] as String);
      expect(decoded['relay_id'], v['relay_id_hex'] as String);
    });

    test('RelayQrCard decode', () {
      final v = rw['relay_qr_card'] as Map<String, dynamic>;
      final decoded = cbor.decode(fromHex(v['cbor_hex'] as String)) as Map;
      expect(
        decoded['relay_onion'],
        (rw['pair_claim'] as Map<String, dynamic>)['admin_onion'],
      );
      expect(
        hex(Uint8List.fromList((decoded['pairing_token'] as List).cast())),
        (rw['pair_claim'] as Map<String, dynamic>)['pairing_token_hex'],
      );
      expect(decoded['relay_version'], v['relay_version'] as String);
    });

    test('EncryptedEvent wire blob encodes to the pinned bytes', () {
      final v = rw['encrypted_event'] as Map<String, dynamic>;
      final ev = vectors['event_encrypt'] as Map<String, dynamic>;
      final encrypted = EncryptedEvent(
        pubkey: v['pubkey'] as String,
        createdAt: v['created_at'] as int,
        epoch: v['epoch'] as int,
        msgSeq: v['msg_seq'] as int,
        nonce: fromHex(ev['nonce_hex'] as String),
        payload: fromHex(ev['ciphertext_hex'] as String),
      );
      expect(hex(encrypted.toBytes()), v['cbor_hex'] as String);
      // And it round-trips through the Dart decoder.
      final back =
          EncryptedEvent.fromBytes(fromHex(v['cbor_hex'] as String));
      expect(back.pubkey, encrypted.pubkey);
      expect(back.msgSeq, encrypted.msgSeq);
    });

    test('PushBatch encodes to the pinned bytes; owner sig pins', () {
      final v = rw['push_batch'] as Map<String, dynamic>;
      final eventBytes = fromHex(
        (rw['encrypted_event'] as Map<String, dynamic>)['cbor_hex'] as String,
      );
      final batch = Uint8List.fromList(cbor.encode(<String, dynamic>{
        'items': [
          <String, dynamic>{
            'id': v['event_id'] as String,
            'payload': eventBytes,
          },
        ],
      }));
      expect(hex(batch), v['cbor_hex'] as String);
      final digest = crypto.blake2b256(batch);
      expect(hex(digest), v['owner_sig_digest_hex'] as String);
      expect(
        hex(crypto.sign(ownerSk, digest)),
        v['owner_sig_hex'] as String,
      );
    });

    test('PushReceipt decode', () {
      final v = rw['push_receipt'] as Map<String, dynamic>;
      final decoded = cbor.decode(fromHex(v['cbor_hex'] as String)) as Map;
      expect(decoded['accepted'], v['accepted'] as int);
      expect(decoded['rejected'], v['rejected'] as int);
    });

    test('manifest page decodes through parseManifestResponse', () {
      final v = rw['manifest_page'] as Map<String, dynamic>;
      final decoded =
          cbor.decode(fromHex(v['cbor_hex'] as String)) as Map<dynamic, dynamic>;
      final manifest = parseManifestResponse(
        decoded,
        toBytes: (b) => Uint8List.fromList((b as List).cast<int>()),
      );
      expect(
        manifest.pubkey,
        (vectors['event_id'] as Map<String, dynamic>)['pubkey'],
      );
      expect(manifest.events, hasLength(1));
      expect(
        manifest.events.single.id,
        (vectors['event_id'] as Map<String, dynamic>)['id_base32'],
      );
      expect(manifest.events.single.createdAt, 1700000000);
      expect(manifest.hasOlder, isTrue);
      expect(manifest.newFeedKey, isNull);
      expect(manifest.newConnectionCard, isNull);
    });

    test('media-manifest page decode', () {
      final v = rw['media_manifest_page'] as Map<String, dynamic>;
      final decoded = cbor.decode(fromHex(v['cbor_hex'] as String)) as Map;
      expect((decoded['hashes'] as List).cast<String>(), hasLength(2));
      expect(decoded['has_older'], isFalse);
    });

    test('events envelope decodes through Envelope.fromBytes', () {
      final v = rw['events_envelope'] as Map<String, dynamic>;
      final envelope = Envelope.fromBytes(fromHex(v['cbor_hex'] as String));
      expect(envelope.version, v['version'] as String);
      expect(envelope.items, hasLength(1));
      expect(envelope.items.single.type, 'event');
      expect(
        hex(envelope.items.single.payload),
        (rw['encrypted_event'] as Map<String, dynamic>)['cbor_hex'],
      );
    });

    test('manifest ack signature pins (Dart↔Dart)', () {
      final v = rw['manifest_ack'] as Map<String, dynamic>;
      final sig = signManifestAck(
        crypto,
        requesterSecretKey: ownerSk,
        ownerPubkey: ownerPk,
        ackRotationAt: v['ack_rotation_at'] as int,
        cardSeenAt: v['card_seen_at'] as int,
      );
      expect(hex(sig), v['sig_hex'] as String);
      expect(
        verifyManifestAck(
          crypto,
          requesterPubkey: ownerPk,
          ownerPubkey: ownerPk,
          ackRotationAt: v['ack_rotation_at'] as int,
          cardSeenAt: v['card_seen_at'] as int,
          sig: sig,
        ),
        isTrue,
      );
    });
  });
}
