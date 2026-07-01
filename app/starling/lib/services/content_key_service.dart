import 'dart:typed_data';

import '../models/models.dart';

/// Feed key management, epoch ratchet, and composed crypto operations.
///
/// Uses [CryptoService] for primitives. This is the layer that evolves
/// when MLS arrives — it gets a second implementation, not a rewrite.
///
/// v1 implementation: pairwise (encrypt once with feed key, key shared
/// pairwise with each follower via X25519 DH).
abstract class ContentKeyService {
  // --- Feed key lifecycle ---

  Future<Uint8List> generateFeedKey();

  /// Advance the feed key to the next epoch.
  /// `nextKey = BLAKE2b-256(currentKey || "starling-ratchet-v1")`
  Uint8List advanceEpoch(Uint8List currentKey);

  // --- Event encryption (sign-then-encrypt / decrypt-then-verify) ---

  /// Encrypts [event] under a per-message AEAD key derived from
  /// [chainRoot] (the publisher's `feedKey` for this epoch) and [msgSeq].
  /// The resulting [EncryptedEvent] carries both [epoch] and [msgSeq] on
  /// the wire so receivers can re-derive the same key.
  EncryptedEvent encryptEvent(
    Event event,
    Uint8List chainRoot,
    int epoch,
    int msgSeq,
  );

  /// Decrypts [encryptedEvent] using the supplied [chainRoot]. The per-
  /// message key is re-derived from `(chainRoot, encryptedEvent.msgSeq)`.
  /// Throws on AEAD failure or signature/id mismatch — caller handles.
  Event decryptEvent(EncryptedEvent encryptedEvent, Uint8List chainRoot);

  // --- Feed key wrapping (for follower key exchange) ---

  Uint8List encryptFeedKey(Uint8List feedKey, Uint8List sharedKey);

  Uint8List decryptFeedKey(Uint8List encryptedFeedKey, Uint8List sharedKey);

  // --- Event ID ---

  String computeEventId(Event event);

  // --- Publish pipeline ---

  /// Encrypt an event for the given audience under the supplied [msgSeq].
  /// For [Audience.broadcast], signs and encrypts with the current chain
  /// root. The caller (typically a publisher service holding the
  /// `PublishLock`) is responsible for allocating a monotonic [msgSeq]
  /// from `Identity.msgSeqCounter`.
  EncryptedEvent encryptForAudience(
    Event event,
    Audience audience, {
    required int msgSeq,
  });

  /// Sign and encrypt an event for the given audience, returning both the
  /// signed plaintext (for local storage) and the encrypted wire form (for
  /// the outbound queue / network). The signed `Event` carries the
  /// supplied [msgSeq] on its `msgSeq` field so callers can persist it
  /// alongside the row for later media decryption.
  ({Event signed, EncryptedEvent encrypted}) signAndEncryptForAudience(
    Event event,
    Audience audience, {
    required int msgSeq,
  });

  /// Plan 17: sign an event with the author's key but encrypt it under a
  /// membership-scoped [roomKey] (not the author's feed key), using a
  /// per-room MegOLM chain `([roomKey], [roomEpoch], [roomMsgSeq])`. Signing
  /// (author identity) and encryption (room key) stay cleanly separated;
  /// the returned `signed` event carries [roomMsgSeq] on its `msgSeq` field
  /// for local persistence. The caller (holding a room-scoped publish lock)
  /// allocates a monotonic [roomMsgSeq] from the room's `roomMsgSeqCounter`.
  ({Event signed, EncryptedEvent encrypted}) signAndEncryptForRoom(
    Event event, {
    required Uint8List roomKey,
    required int roomEpoch,
    required int roomMsgSeq,
  });
}
