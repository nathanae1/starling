// ignore_for_file: avoid_print

// One-shot vector generator. Run this manually to regenerate the
// canonical test vectors that pin the protocol against accidental changes.
//
// Usage:
//   flutter test test/vectors/vectors_gen.dart
//
// This "test" prints a JSON index to stdout. Copy-paste the output into
// `test/vectors/index.json`, then run `vectors_test.dart` to assert the
// pinned values.

import 'dart:convert';
import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:starling/models/models.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/crypto/feed_key_ratchet.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/sync/manifest_ack.dart';
import 'package:flutter_test/flutter_test.dart';

String hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List fromHex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generate protocol test vectors', () async {
    final crypto = await SodiumCryptoService.init();

    // Vector 1: keypair from fixed seed.
    final seed = fromHex(
      '000102030405060708090a0b0c0d0e0f'
      '101112131415161718191a1b1c1d1e1f',
    );
    final phrase = await crypto.deriveRecoveryPhrase(seed);
    final kp = await crypto.recoverFromPhrase(phrase);
    final xpk = crypto.ed25519ToX25519PublicKey(kp.publicKey);
    final xsk = crypto.ed25519ToX25519SecretKey(kp.secretKey);

    // Vector 2: event id for a fixed event.
    final event = Event(
      version: '2026-03-24',
      id: '',
      pubkey: crockfordBase32Encode(kp.publicKey),
      createdAt: 1_700_000_000,
      kind: EventKind.fromValue(1),
      content: Uint8List.fromList('hello starling'.codeUnits),
      sig: Uint8List(0),
    );
    final idFieldsBytes = Uint8List.fromList(cbor.encode(event.toIdFields()));
    final idHash = crypto.blake2b256(idFieldsBytes);
    final eventId = crockfordBase32Encode(idHash);

    // Vector 3: event signature over id bytes.
    final sig = crypto.sign(kp.secretKey, idHash);

    // Vector 4: feed key ratchet, fixed base key.
    final baseKey = fromHex(
      'ff' * 32,
    );
    final epoch1 = ratchetFeedKey(baseKey, crypto);
    final epoch2 = ratchetFeedKey(epoch1, crypto);

    // Vector 5: event encryption with fixed key + nonce.
    final feedKey = fromHex('a1' * 32);
    final nonce = fromHex('b2' * 24);
    final signedEvent = event.copyWith(id: eventId, sig: sig);
    final ciphertext = crypto.encrypt(signedEvent.toBytes(), nonce, feedKey);

    // --- relay_wire: every CBOR/sig surface that crosses the Dart↔Rust
    // boundary (Plan 15). The Rust consumer test is
    // relay/crates/starling-wire/tests/wire_vectors.rs. For Dart-produced
    // surfaces the Rust test decodes the pinned bytes; for Rust-produced
    // surfaces it asserts its encoder emits them byte-for-byte (the maps
    // below mirror the Rust struct field order).

    // Crockford base32 of a fixed 32-byte buffer.
    final b32Bytes = Uint8List.fromList(List.generate(32, (i) => i));

    // Pairing claim: tag || owner_pk || utf8(admin_onion) || token, then
    // blake2b256 + Ed25519 (relay_pairing_initiator.dart ↔ pairing.rs).
    const adminOnion = 'exampleadminonionaddressexampleadminonionaddress.onion';
    final pairingToken = Uint8List.fromList(List.filled(32, 0x42));
    final claimBytes = Uint8List.fromList([
      ...utf8.encode('starling-relay-pair-v1'),
      ...kp.publicKey,
      ...utf8.encode(adminOnion),
      ...pairingToken,
    ]);
    final claimDigest = crypto.blake2b256(claimBytes);
    final claimSig = crypto.sign(kp.secretKey, claimDigest);
    final pairingClaimCbor = Uint8List.fromList(cbor.encode(<String, dynamic>{
      'owner_pubkey': base64.encode(kp.publicKey),
      'pairing_token': pairingToken,
      'sig': claimSig,
    }));

    // relay_id = hex(blake2b256(owner_pk || utf8(owner_onion))) and the
    // PairResponse CBOR carrying it (Rust-produced, Dart-decoded).
    const ownerOnion = 'ownerexampleonionaddressownerexampleonionaddress.onion';
    final relayIdHex = hex(crypto.blake2b256(
      Uint8List.fromList([...kp.publicKey, ...utf8.encode(ownerOnion)]),
    ));
    final pairResponseCbor = Uint8List.fromList(cbor.encode(<String, dynamic>{
      'relay_onion': ownerOnion,
      'relay_id': relayIdHex,
    }));

    // RelayQrCard (Rust-produced, scanned by the phone).
    final qrCardCbor = Uint8List.fromList(cbor.encode(<String, dynamic>{
      'relay_onion': adminOnion,
      'pairing_token': pairingToken,
      'relay_version': '0.1.0-test',
    }));

    // EncryptedEvent wire blob (Dart-produced; the relay reads only the
    // cleartext header fields).
    final encryptedEvent = EncryptedEvent(
      pubkey: crockfordBase32Encode(kp.publicKey),
      createdAt: 1_700_000_000,
      epoch: 0,
      msgSeq: 7,
      nonce: nonce,
      payload: ciphertext,
    );
    final encryptedEventBytes = encryptedEvent.toBytes();

    // POST /events PushBatch (Dart-produced, relay_push_service.dart).
    final pushBatchCbor = Uint8List.fromList(cbor.encode(<String, dynamic>{
      'items': [
        <String, dynamic>{'id': eventId, 'payload': encryptedEventBytes},
      ],
    }));

    // Owner write auth: Ed25519 over blake2b256(body) (X-Starling-Sig).
    final ownerSigDigest = crypto.blake2b256(pushBatchCbor);
    final ownerSig = crypto.sign(kp.secretKey, ownerSigDigest);

    // PushReceipt (Rust-produced).
    final pushReceiptCbor = Uint8List.fromList(cbor.encode(<String, dynamic>{
      'accepted': 1,
      'rejected': 0,
    }));

    // GET /manifest page (Rust-produced shape; Dart decodes it through
    // parseManifestResponse).
    final manifestPageCbor = Uint8List.fromList(cbor.encode(<String, dynamic>{
      'pubkey': crockfordBase32Encode(kp.publicKey),
      'events': [
        <String, dynamic>{'id': eventId, 'created_at': 1_700_000_000},
      ],
      'has_older': true,
    }));

    // GET /media-manifest page (Rust-produced).
    final mediaManifestCbor = Uint8List.fromList(cbor.encode(<String, dynamic>{
      'hashes': ['aa' * 32, 'bb' * 32],
      'has_older': false,
    }));

    // GET /events Envelope (Rust-produced via build_events_envelope).
    final envelopeCbor = Uint8List.fromList(cbor.encode(<String, dynamic>{
      'version': '2026-04-28',
      'items': [
        <String, dynamic>{
          'type': 'event',
          'payload': encryptedEventBytes,
          'extensions': <String, dynamic>{},
        },
      ],
      'extensions': <String, dynamic>{},
    }));

    // Manifest ack possession proof (S3a). Dart↔Dart only (phone owner ↔
    // phone follower); pinned here against Dart-side drift, skipped by the
    // Rust test.
    final ackSig = signManifestAck(
      crypto,
      requesterSecretKey: kp.secretKey,
      ownerPubkey: kp.publicKey,
      ackRotationAt: 111,
      cardSeenAt: 222,
    );

    final vectors = {
      'keypair': {
        'seed_hex': hex(seed),
        'recovery_phrase': phrase,
        'ed25519_public_key_hex': hex(kp.publicKey),
        'ed25519_secret_key_hex': hex(kp.secretKey),
        'x25519_public_key_hex': hex(xpk),
        'x25519_secret_key_hex': hex(xsk),
      },
      'event_id': {
        'version': event.version,
        'pubkey': event.pubkey,
        'created_at': event.createdAt,
        'kind': event.kind.value,
        'content_hex': hex(event.content),
        'id_fields_cbor_hex': hex(idFieldsBytes),
        'id_bytes_hex': hex(idHash),
        'id_base32': eventId,
      },
      'event_sign': {
        'signer_pubkey_hex': hex(kp.publicKey),
        'signed_bytes_hex': hex(idHash),
        'signature_hex': hex(sig),
      },
      'ratchet': {
        'base_key_hex': hex(baseKey),
        'epoch_1_hex': hex(epoch1),
        'epoch_2_hex': hex(epoch2),
      },
      'event_encrypt': {
        'feed_key_hex': hex(feedKey),
        'nonce_hex': hex(nonce),
        'event_bytes_hex': hex(signedEvent.toBytes()),
        'ciphertext_hex': hex(ciphertext),
      },
      'relay_wire': {
        '_comment': 'Dart↔Rust wire surfaces (Plan 15). Rust consumer: '
            'relay/crates/starling-wire/tests/wire_vectors.rs. '
            'manifest_ack is Dart↔Dart only and skipped by the Rust test.',
        'crockford_base32': {
          'bytes_hex': hex(b32Bytes),
          'encoded': crockfordBase32Encode(b32Bytes),
          'lookalike_decode_input': 'ILO1',
          'lookalike_decode_canonical': '1101',
        },
        'pair_claim': {
          'admin_onion': adminOnion,
          'pairing_token_hex': hex(pairingToken),
          'claim_bytes_hex': hex(claimBytes),
          'claim_digest_hex': hex(claimDigest),
          'sig_hex': hex(claimSig),
          'claim_cbor_hex': hex(pairingClaimCbor),
        },
        'relay_id': {
          'owner_onion': ownerOnion,
          'relay_id_hex': relayIdHex,
          'pair_response_cbor_hex': hex(pairResponseCbor),
        },
        'relay_qr_card': {
          'relay_version': '0.1.0-test',
          'cbor_hex': hex(qrCardCbor),
        },
        'encrypted_event': {
          'pubkey': encryptedEvent.pubkey,
          'created_at': encryptedEvent.createdAt,
          'epoch': encryptedEvent.epoch,
          'msg_seq': encryptedEvent.msgSeq,
          'cbor_hex': hex(encryptedEventBytes),
        },
        'push_batch': {
          'event_id': eventId,
          'cbor_hex': hex(pushBatchCbor),
          'owner_sig_digest_hex': hex(ownerSigDigest),
          'owner_sig_hex': hex(ownerSig),
        },
        'push_receipt': {
          'accepted': 1,
          'rejected': 0,
          'cbor_hex': hex(pushReceiptCbor),
        },
        'manifest_page': {
          'cbor_hex': hex(manifestPageCbor),
        },
        'media_manifest_page': {
          'cbor_hex': hex(mediaManifestCbor),
        },
        'events_envelope': {
          'version': '2026-04-28',
          'cbor_hex': hex(envelopeCbor),
        },
        'manifest_ack': {
          '_dart_only': true,
          'ack_rotation_at': 111,
          'card_seen_at': 222,
          'sig_hex': hex(ackSig),
        },
      },
    };

    print('\n===== BEGIN VECTOR JSON =====');
    print(const JsonEncoder.withIndent('  ').convert(vectors));
    print('===== END VECTOR JSON =====\n');
  });
}
