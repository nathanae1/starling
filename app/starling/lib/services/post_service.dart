import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../models/models.dart';
import '../models/protocol_version.dart';
import 'clock.dart';
import 'content_key_service.dart';
import 'crypto/feed_key_ratchet.dart';
import 'crypto/publish_lock.dart';
import 'crypto_service.dart';
import 'media_service.dart';
import 'post_fanout_service.dart';
import 'storage_service.dart';
import 'types.dart';

abstract class PostService {
  /// Create a kind=1 post with optional caption + one compressed photo.
  /// Returns the new event id.
  Future<String> createPost({
    required Uint8List photoBytes,
    required String caption,
  });

  /// Create a kind=6 delete event pointing at [targetEventId]. Returns the
  /// new delete event's id. Does not remove the target row from storage —
  /// feed queries filter by kind=6 refs at read time.
  Future<String> deletePost(String targetEventId);
}

/// Builds signed events, encrypts media, and persists both locally. Does NOT
/// touch the outbound queue — that lands in Plan 07/11.
///
/// Ordering: media file writes happen before DB writes. A crash between a
/// successful file write and the event row insert leaves orphan files (Plan
/// 14's retention sweep), never a ghost event without backing media.
class DefaultPostService implements PostService {
  DefaultPostService({
    required ContentKeyService contentKey,
    required CryptoService crypto,
    required StorageService storage,
    required MediaService media,
    required Clock clock,
    required Future<Identity?> Function() identityLookup,
    PostFanoutService fanout = PostFanoutService.noop,
    Future<void> Function(Event signed, Uint8List encryptedBytes)? onPublished,
    PublishLock? publishLock,
  })  : _contentKey = contentKey,
        _crypto = crypto,
        _storage = storage,
        _media = media,
        _clock = clock,
        _identityLookup = identityLookup,
        _fanout = fanout,
        _onPublished = onPublished,
        _publishLock = publishLock ?? PublishLock();

  final ContentKeyService _contentKey;
  final CryptoService _crypto;
  final StorageService _storage;
  final MediaService _media;
  final Clock _clock;
  final Future<Identity?> Function() _identityLookup;
  final PostFanoutService _fanout;
  // Plan 15: fired after fanout with the freshly-published event so the
  // relay push coordinator can mirror it to the paired relay (if any).
  final Future<void> Function(Event signed, Uint8List encryptedBytes)?
      _onPublished;
  final PublishLock _publishLock;

  @override
  Future<String> createPost({
    required Uint8List photoBytes,
    required String caption,
  }) =>
      _publishLock.synchronized(() async {
        final identity = await _identityLookup();
        if (identity == null) {
          throw StateError('createPost called before identity is loaded');
        }

        // Allocate the next per-message sequence under the publish lock,
        // derive the AEAD key once, and use it for both the post body
        // (via signAndEncryptForAudience) and every media blob.
        final msgSeq = identity.msgSeqCounter;
        final msgKey = deriveMsgKey(identity.feedKey, msgSeq, _crypto);
        // ignore: avoid_print
        print(
          '[starling.media] pub createPost msgSeq=$msgSeq '
          'feedKeyFp=${_fpPostSvc(identity.feedKey)} '
          'msgKeyFp=${_fpPostSvc(msgKey)}',
        );

        final media = await _media.processAndStoreOwnPhoto(
          photoBytes: photoBytes,
          msgKey: msgKey,
        );

        final unsigned = Event(
          version: kStarlingProtocolVersion,
          id: '',
          pubkey: identity.pubkey,
          createdAt: _clock.nowUnixSeconds(),
          kind: EventKind.post,
          ref: null,
          content: Uint8List.fromList(utf8.encode(caption)),
          media: [
            MediaRef(
              hash: media.compressedHash,
              mimeType: media.compressedMime,
              size: media.compressedSize,
            ),
          ],
          extensions: const {},
          sig: Uint8List(0),
        );

        final result = _contentKey.signAndEncryptForAudience(
          unsigned,
          Audience.broadcast,
          msgSeq: msgSeq,
        );
        final encryptedBytes = result.encrypted.toBytes();
        await _storage.saveOwnEventWithEncrypted(
          result.signed,
          encryptedBytes,
        );
        // Persist the bumped counter so the next publish allocates a
        // fresh msg_seq. Cleared/reset to 0 in KeyRotationService when
        // feedKey rotates.
        await _storage.saveIdentity(
          identity.copyWith(msgSeqCounter: msgSeq + 1),
        );
        unawaited(_fanout.fanout(encryptedBytes));
        _notifyPublished(result.signed, encryptedBytes);
        return result.signed.id;
      });

  @override
  Future<String> deletePost(String targetEventId) =>
      _publishLock.synchronized(() async {
        final identity = await _identityLookup();
        if (identity == null) {
          throw StateError('deletePost called before identity is loaded');
        }

        final msgSeq = identity.msgSeqCounter;

        final unsigned = Event(
          version: kStarlingProtocolVersion,
          id: '',
          pubkey: identity.pubkey,
          createdAt: _clock.nowUnixSeconds(),
          kind: EventKind.delete,
          ref: targetEventId,
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
        final encryptedBytes = result.encrypted.toBytes();
        await _storage.saveOwnEventWithEncrypted(
          result.signed,
          encryptedBytes,
        );
        await _storage.saveIdentity(
          identity.copyWith(msgSeqCounter: msgSeq + 1),
        );
        unawaited(_fanout.fanout(encryptedBytes));
        _notifyPublished(result.signed, encryptedBytes);
        return result.signed.id;
      });

  void _notifyPublished(Event signed, Uint8List encryptedBytes) {
    final cb = _onPublished;
    if (cb != null) unawaited(cb(signed, encryptedBytes));
  }
}

String _fpPostSvc(Uint8List bytes) {
  final hex = bytes
      .take(4)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '$hex…';
}
