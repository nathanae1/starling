import 'dart:typed_data';

import 'package:cbor/simple.dart';

import '../../models/models.dart';
import '../content_key_service.dart';
import '../crypto_service.dart';
import 'crockford_base32.dart';
import 'feed_key_ratchet.dart';
import 'key_cache.dart';

/// v1 (pairwise) implementation of [ContentKeyService].
///
/// - Events are encrypted once with the owner's current feed key.
/// - The feed key is shared with each follower individually via X25519 DH
///   (see [CryptoService.deriveSharedKey] + [encryptFeedKey]).
/// - Epoch advancement uses a MegOLM-style one-way hash ratchet.
///
/// This implementation depends only on [CryptoService] primitives and a
/// [FeedKeyCache]. When MLS arrives it gets a second implementation; this
/// one does not get rewritten.
class PairwiseContentKeyService implements ContentKeyService {
  PairwiseContentKeyService({
    required CryptoService crypto,
    required FeedKeyCache cache,
    required String ownPubkey,
    required Uint8List ownSecretKey,
  }) : _crypto = crypto,
       _cache = cache,
       _ownPubkey = ownPubkey,
       _ownSecretKey = ownSecretKey;

  final CryptoService _crypto;
  final FeedKeyCache _cache;
  final String _ownPubkey;
  final Uint8List _ownSecretKey;

  // --- Feed key lifecycle ---

  @override
  Future<Uint8List> generateFeedKey() async => _crypto.randomBytes(32);

  @override
  Uint8List advanceEpoch(Uint8List currentKey) =>
      ratchetFeedKey(currentKey, _crypto);

  // --- Event encryption (sign-then-encrypt / decrypt-then-verify) ---

  @override
  EncryptedEvent encryptEvent(
    Event event,
    Uint8List chainRoot,
    int epoch,
    int msgSeq,
  ) {
    final msgKey = deriveMsgKey(chainRoot, msgSeq, _crypto);
    final serialized = event.toBytes();
    final nonce = _crypto.randomBytes(24);
    final payload = _crypto.encrypt(serialized, nonce, msgKey);
    return EncryptedEvent(
      pubkey: event.pubkey,
      createdAt: event.createdAt,
      epoch: epoch,
      msgSeq: msgSeq,
      nonce: nonce,
      payload: payload,
    );
  }

  @override
  Event decryptEvent(EncryptedEvent encryptedEvent, Uint8List chainRoot) {
    final msgKey = deriveMsgKey(chainRoot, encryptedEvent.msgSeq, _crypto);
    final serialized = _crypto.decrypt(
      encryptedEvent.payload,
      encryptedEvent.nonce,
      msgKey,
    );
    final event = Event.fromBytes(serialized);

    // Verify: (1) id re-derivation, (2) signature over id bytes.
    final expectedId = computeEventId(event);
    if (event.id != expectedId) {
      throw StateError(
        'event id mismatch: computed $expectedId, got ${event.id}',
      );
    }
    final idBytes = crockfordBase32Decode(event.id);
    final pubkeyBytes = crockfordBase32Decode(event.pubkey);
    if (!_crypto.verify(pubkeyBytes, idBytes, event.sig)) {
      throw StateError('event signature verification failed for ${event.id}');
    }

    return event;
  }

  // --- Feed key wrapping (for follower key exchange) ---

  @override
  Uint8List encryptFeedKey(Uint8List feedKey, Uint8List sharedKey) {
    final nonce = _crypto.randomBytes(24);
    final ct = _crypto.encrypt(feedKey, nonce, sharedKey);
    final result = Uint8List(nonce.length + ct.length);
    result.setRange(0, nonce.length, nonce);
    result.setRange(nonce.length, result.length, ct);
    return result;
  }

  @override
  Uint8List decryptFeedKey(Uint8List encryptedFeedKey, Uint8List sharedKey) {
    if (encryptedFeedKey.length < 24) {
      throw ArgumentError(
        'encrypted feed key too short (< 24 bytes for nonce)',
      );
    }
    final nonce = Uint8List.fromList(encryptedFeedKey.sublist(0, 24));
    final ct = Uint8List.fromList(encryptedFeedKey.sublist(24));
    return _crypto.decrypt(ct, nonce, sharedKey);
  }

  // --- Event ID ---

  @override
  String computeEventId(Event event) {
    final idFieldsBytes = Uint8List.fromList(cbor.encode(event.toIdFields()));
    final hash = _crypto.blake2b256(idFieldsBytes);
    return crockfordBase32Encode(hash);
  }

  // --- Publish pipeline ---

  @override
  EncryptedEvent encryptForAudience(
    Event event,
    Audience audience, {
    required int msgSeq,
  }) => signAndEncryptForAudience(event, audience, msgSeq: msgSeq).encrypted;

  @override
  ({Event signed, EncryptedEvent encrypted}) signAndEncryptForAudience(
    Event event,
    Audience audience, {
    required int msgSeq,
  }) {
    // v1 supports only broadcast audience; future audiences will branch here.
    switch (audience) {
      case Audience.broadcast:
        break;
    }

    final entry = _cache.get(_ownPubkey);
    if (entry == null) {
      throw StateError(
        'own feed key not loaded in cache for pubkey $_ownPubkey',
      );
    }

    // Step 1: compute event id (base32 string) from the *unsigned* event.
    // toIdFields() deliberately excludes id and sig, so this is safe even
    // though the event currently has placeholder values for those fields.
    final id = computeEventId(event);

    // Step 2: sign the raw 32-byte hash bytes (not the base32 string).
    final idBytes = crockfordBase32Decode(id);
    final sig = _crypto.sign(_ownSecretKey, idBytes);

    // Step 3: attach id + sig + msgSeq (msgSeq is local-only metadata,
    // excluded from `toMap`/`toIdFields`/wire serialization — but kept on
    // the in-memory model so the caller persists it to event_entries).
    final signed = event.copyWith(id: id, sig: sig, msgSeq: msgSeq);

    // Step 4: encrypt with a per-message key derived from the chain root
    // for this epoch + msgSeq.
    final encrypted = encryptEvent(signed, entry.key, entry.epoch, msgSeq);

    return (signed: signed, encrypted: encrypted);
  }

  @override
  ({Event signed, EncryptedEvent encrypted}) signAndEncryptForRoom(
    Event event, {
    required Uint8List roomKey,
    required int roomEpoch,
    required int roomMsgSeq,
  }) {
    // Identical to the broadcast path, except the chain root is the caller-
    // supplied room key rather than our own feed key from the cache. The
    // author still signs with their own Ed25519 secret key — membership
    // scoping comes from the encryption key, authorship from the signature.
    final id = computeEventId(event);
    final idBytes = crockfordBase32Decode(id);
    final sig = _crypto.sign(_ownSecretKey, idBytes);
    final signed = event.copyWith(id: id, sig: sig, msgSeq: roomMsgSeq);
    final encrypted = encryptEvent(signed, roomKey, roomEpoch, roomMsgSeq);
    return (signed: signed, encrypted: encrypted);
  }
}
