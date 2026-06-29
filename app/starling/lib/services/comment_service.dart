import 'dart:convert';
import 'dart:typed_data';

import '../models/models.dart';
import '../models/protocol_version.dart';
import 'clock.dart';
import 'content_key_service.dart';
import 'crypto/publish_lock.dart';
import 'storage_service.dart';
import 'types.dart';

abstract class CommentService {
  /// Create a kind=4 comment referencing [targetPostId] with the given body.
  /// Returns the new comment's id. If the target post is on someone else's
  /// device, the encrypted comment is enqueued for delivery to that author.
  Future<String> create({required String targetPostId, required String text});

  /// Create a kind=6 delete event referencing [commentId]. Returns the
  /// new delete event's id. Same delivery rules: if the comment was on
  /// someone else's post, the delete is enqueued for that author.
  Future<String> delete(String commentId);
}

/// Mirrors `DefaultPostService` minus the media pipeline. Comments live on
/// top of the same publish primitive — sign+encrypt with the local feed
/// key, write the plaintext to local storage, and (if the target's author
/// is someone else) hand the encrypted blob to the outbound queue so the
/// author's device gets it on next sync.
class DefaultCommentService implements CommentService {
  DefaultCommentService({
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
  Future<String> create({required String targetPostId, required String text}) =>
      _publishLock.synchronized(() async {
        final identity = await _identityLookup();
        if (identity == null) {
          throw StateError('createComment called before identity is loaded');
        }

        final msgSeq = identity.msgSeqCounter;

        final unsigned = Event(
          version: kStarlingProtocolVersion,
          id: '',
          pubkey: identity.pubkey,
          createdAt: _clock.nowUnixSeconds(),
          kind: EventKind.comment,
          ref: targetPostId,
          content: Uint8List.fromList(utf8.encode(text)),
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
        await _storage.saveIdentity(
          identity.copyWith(msgSeqCounter: msgSeq + 1),
        );
        await _maybeEnqueueForAuthor(targetPostId, identity, result.encrypted);
        return result.signed.id;
      });

  @override
  Future<String> delete(String commentId) => _publishLock.synchronized(
    () async {
      final identity = await _identityLookup();
      if (identity == null) {
        throw StateError('deleteComment called before identity is loaded');
      }

      final msgSeq = identity.msgSeqCounter;

      final unsigned = Event(
        version: kStarlingProtocolVersion,
        id: '',
        pubkey: identity.pubkey,
        createdAt: _clock.nowUnixSeconds(),
        kind: EventKind.delete,
        ref: commentId,
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

      // Walk one ref up: if the deleted comment was on someone else's
      // post, the post author wants the tombstone too.
      final original = await _storage.getEvent(commentId);
      if (original != null && original.ref != null) {
        await _maybeEnqueueForAuthor(original.ref!, identity, result.encrypted);
      }
      return result.signed.id;
    },
  );

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
