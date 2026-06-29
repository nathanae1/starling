import 'dart:typed_data';

import '../models/models.dart';
import '../models/protocol_version.dart';
import 'clock.dart';
import 'content_key_service.dart';
import 'crypto/publish_lock.dart';
import 'storage_service.dart';
import 'types.dart';

abstract class ReactionService {
  /// Create a kind=5 like referencing [targetPostId]. Idempotent: if the
  /// viewer already likes the post (an active kind=5 not tombstoned by a
  /// kind=6), this returns the existing like's id without creating a new
  /// event. Returns the (possibly-existing) like's id.
  Future<String> like(String targetPostId);

  /// Toggle off a previously-created like by emitting a kind=6 referencing
  /// it. Returns the new tombstone's id, or null if there was no active
  /// like to tombstone.
  Future<String?> unlike(String targetPostId);

  /// Whether the local viewer currently has an active like on [targetPostId].
  Future<bool> isLikedByMe(String targetPostId);
}

class DefaultReactionService implements ReactionService {
  DefaultReactionService({
    required ContentKeyService contentKey,
    required StorageService storage,
    required Clock clock,
    required Future<Identity?> Function() identityLookup,
    PublishLock? publishLock,
  }) : _contentKey = contentKey,
       _storage = storage,
       _clock = clock,
       _identityLookup = identityLookup,
       _publishLock = publishLock ?? PublishLock();

  final ContentKeyService _contentKey;
  final StorageService _storage;
  final Clock _clock;
  final Future<Identity?> Function() _identityLookup;
  final PublishLock _publishLock;

  @override
  Future<String> like(String targetPostId) => _publishLock.synchronized(
    () async {
      final identity = await _identityLookup();
      if (identity == null) {
        throw StateError('like called before identity is loaded');
      }

      final existing = await _findActiveLike(targetPostId, identity.pubkey);
      if (existing != null) {
        return existing.id;
      }

      final msgSeq = identity.msgSeqCounter;

      final unsigned = Event(
        version: kStarlingProtocolVersion,
        id: '',
        pubkey: identity.pubkey,
        createdAt: _clock.nowUnixSeconds(),
        kind: EventKind.like,
        ref: targetPostId,
        content: Uint8List(0),
        media: const [],
        extensions: const {},
        sig: Uint8List(0),
      );

      final result = _contentKey.signAndEncryptForAudience(
        unsigned,
        Audience.broadcast,
        msgSeq: msgSeq,
      );
      await _storage.saveOwnEventWithEncrypted(
        result.signed,
        result.encrypted.toBytes(),
      );
      await _storage.saveIdentity(identity.copyWith(msgSeqCounter: msgSeq + 1));
      await _maybeEnqueueForAuthor(targetPostId, identity, result.encrypted);
      return result.signed.id;
    },
  );

  @override
  Future<String?> unlike(String targetPostId) => _publishLock.synchronized(
    () async {
      final identity = await _identityLookup();
      if (identity == null) {
        throw StateError('unlike called before identity is loaded');
      }

      final like = await _findActiveLike(targetPostId, identity.pubkey);
      if (like == null) return null;

      final msgSeq = identity.msgSeqCounter;

      final unsigned = Event(
        version: kStarlingProtocolVersion,
        id: '',
        pubkey: identity.pubkey,
        createdAt: _clock.nowUnixSeconds(),
        kind: EventKind.delete,
        ref: like.id,
        content: Uint8List(0),
        media: const [],
        extensions: const {},
        sig: Uint8List(0),
      );

      final result = _contentKey.signAndEncryptForAudience(
        unsigned,
        Audience.broadcast,
        msgSeq: msgSeq,
      );
      await _storage.saveOwnEventWithEncrypted(
        result.signed,
        result.encrypted.toBytes(),
      );
      await _storage.saveIdentity(identity.copyWith(msgSeqCounter: msgSeq + 1));
      await _maybeEnqueueForAuthor(targetPostId, identity, result.encrypted);
      return result.signed.id;
    },
  );

  @override
  Future<bool> isLikedByMe(String targetPostId) async {
    final identity = await _identityLookup();
    if (identity == null) return false;
    final active = await _findActiveLike(targetPostId, identity.pubkey);
    return active != null;
  }

  /// The viewer's own kind=5 against [targetPostId] that is not tombstoned
  /// by any kind=6. Returns null if the viewer has never liked, or has
  /// liked-then-unliked.
  Future<Event?> _findActiveLike(String targetPostId, String myPubkey) async {
    final refs = await _storage.getEventsByRef(
      targetPostId,
      kind: EventKind.like,
    );
    final myLikes = refs.where((e) => e.pubkey == myPubkey).toList();
    if (myLikes.isEmpty) return null;

    for (final like in myLikes) {
      final tombstones = await _storage.getEventsByRef(
        like.id,
        kind: EventKind.delete,
      );
      final activeTombstone = tombstones.any((t) => t.pubkey == myPubkey);
      if (!activeTombstone) {
        return like;
      }
    }
    return null;
  }

  Future<void> _maybeEnqueueForAuthor(
    String postId,
    Identity self,
    EncryptedEvent encrypted,
  ) async {
    final post = await _storage.getEvent(postId);
    if (post == null) return;
    if (post.pubkey == self.pubkey) return;
    await _storage.enqueue(post.pubkey, encrypted.toBytes());
  }
}
