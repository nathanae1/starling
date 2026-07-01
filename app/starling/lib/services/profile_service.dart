import 'dart:async';
import 'dart:typed_data';

import 'package:characters/characters.dart';

import '../models/models.dart';
import '../models/profile_content.dart';
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

/// Hard cap on profile bio length, in grapheme clusters. Enforced at input by
/// the editor's `StarlingTextarea` and defensively re-clamped in
/// [ProfileService.publishProfile] so the kind=2 event body honors it
/// regardless of entry point.
const kBioMaxLength = 280;

abstract class ProfileService {
  /// Publish a kind=2 profile event carrying [displayName], optional [bio],
  /// and an optional avatar image. When [avatarBytes] is supplied it is
  /// compressed to a square thumbnail, encrypted under the same per-message
  /// key as the event, and referenced both as `avatar_hash` in the JSON
  /// content and as a [MediaRef] on the event (so media fetch + retention
  /// pinning + key derivation all see it). Returns the new event id.
  ///
  /// Profiles are latest-created_at-wins: each call appends a fresh kind=2
  /// event rather than mutating a prior one.
  Future<String> publishProfile({
    required String displayName,
    String? bio,
    Uint8List? avatarBytes,
  });
}

/// Mirrors [DefaultPostService] for the kind=2 profile record. A profile is a
/// broadcast, feed-key-encrypted event just like a post, so it follows the
/// same publish discipline — allocate a monotonic `msg_seq` under the
/// [PublishLock], derive the per-message AEAD key once, sign+encrypt, persist
/// the author-time wire bytes, bump the counter — and the same fanout +
/// relay-mirror delivery (NOT the comment service's single-recipient
/// enqueue, since a profile is for every follower).
class DefaultProfileService implements ProfileService {
  DefaultProfileService({
    required ContentKeyService contentKey,
    required CryptoService crypto,
    required StorageService storage,
    required MediaService media,
    required Clock clock,
    required Future<Identity?> Function() identityLookup,
    PostFanoutService fanout = PostFanoutService.noop,
    Future<void> Function(Event signed, Uint8List encryptedBytes)? onPublished,
    PublishLock? publishLock,
  }) : _contentKey = contentKey,
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
  // Plan 15: fired after fanout so the relay push coordinator can mirror the
  // profile to the paired relay (if any). Best-effort.
  final Future<void> Function(Event signed, Uint8List encryptedBytes)?
  _onPublished;
  final PublishLock _publishLock;

  /// Avatars are small, square thumbnails — 256px is the spec target
  /// (plan 04). The compress isolate center-crops to a square first.
  static const int _avatarMaxDimension = 256;

  @override
  Future<String> publishProfile({
    required String displayName,
    String? bio,
    Uint8List? avatarBytes,
  }) => _publishLock.synchronized(() async {
    final identity = await _identityLookup();
    if (identity == null) {
      throw StateError('publishProfile called before identity is loaded');
    }

    // One msg_seq covers both the avatar blob and the event body, so a
    // receiver re-derives the avatar's AEAD key from the event's seq.
    final msgSeq = identity.msgSeqCounter;

    String? avatarHash;
    var media = const <MediaRef>[];
    if (avatarBytes != null) {
      final msgKey = deriveMsgKey(identity.feedKey, msgSeq, _crypto);
      final stored = await _media.processAndStoreOwnPhoto(
        photoBytes: avatarBytes,
        msgKey: msgKey,
        maxDimension: _avatarMaxDimension,
        square: true,
      );
      avatarHash = stored.compressedHash;
      media = [
        MediaRef(
          hash: stored.compressedHash,
          mimeType: stored.compressedMime,
          size: stored.compressedSize,
        ),
      ];
    }

    // Defensive re-clamp: the editor caps input at [kBioMaxLength] graphemes,
    // but this service is a public boundary (also reachable via onboarding), so
    // guarantee the invariant here rather than trusting the caller.
    final safeBio = bio != null && bio.characters.length > kBioMaxLength
        ? bio.characters.take(kBioMaxLength).toString()
        : bio;

    final unsigned = Event(
      version: kStarlingProtocolVersion,
      id: '',
      pubkey: identity.pubkey,
      createdAt: _clock.nowUnixSeconds(),
      kind: EventKind.profile,
      ref: null,
      content: encodeProfileContent(
        name: displayName,
        bio: safeBio,
        avatarHash: avatarHash,
      ),
      media: media,
      extensions: const {},
      sig: Uint8List(0),
    );

    final result = _contentKey.signAndEncryptForAudience(
      unsigned,
      Audience.broadcast,
      msgSeq: msgSeq,
    );
    final encryptedBytes = result.encrypted.toBytes();
    await _storage.saveOwnEventWithEncrypted(result.signed, encryptedBytes);
    // Persist the bumped counter so the next publish allocates a fresh
    // msg_seq. Reset to 0 by KeyRotationService when feedKey rotates.
    await _storage.saveIdentity(identity.copyWith(msgSeqCounter: msgSeq + 1));
    unawaited(_fanout.fanout(encryptedBytes));
    _notifyPublished(result.signed, encryptedBytes);
    return result.signed.id;
  });

  void _notifyPublished(Event signed, Uint8List encryptedBytes) {
    final cb = _onPublished;
    if (cb != null) unawaited(cb(signed, encryptedBytes));
  }
}
