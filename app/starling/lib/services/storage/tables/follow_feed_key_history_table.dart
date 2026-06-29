import 'package:drift/drift.dart';

/// Per-follow archive of retired feed keys (chain roots).
///
/// Mirrors [FeedKeyHistoryEntries] but keyed by follower pubkey, so we
/// can decrypt cached content from a peer that has since rotated their
/// `feedKey`. A row is appended in `SyncEngine._applyRotatedFeedKey`
/// when a rotation arrives via `/manifest`, *before* the new key
/// overwrites `Follow.feedKey`.
///
/// Lookup contract: when decrypting an EncryptedEvent or media blob from
/// pubkey `P`, candidate chain roots are `Follow.feedKey` (current) plus
/// every row in this table where `followPubkey == P`. Each candidate is
/// fed through `deriveMsgKey(root, msgSeq)` to derive the AEAD key.
class FollowFeedKeyHistoryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get followPubkey => text()();
  BlobColumn get feedKey => blob()();
  IntColumn get feedKeyEpoch => integer().withDefault(const Constant(0))();
  IntColumn get validFrom => integer()();
  IntColumn get validUntil => integer()();
}
