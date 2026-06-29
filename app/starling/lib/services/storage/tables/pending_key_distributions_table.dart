import 'package:drift/drift.dart';

/// Encrypted feed-key payloads waiting to be delivered to a follower (Plan 13).
///
/// On rotation we wrap the new feed key with each remaining follower's
/// X25519 DH shared key and write a row here. The row is consumed lazily on
/// the next sync from that follower: the manifest handler attaches the
/// latest undelivered row to the response, and a follow-up `ack_rotation_at`
/// query parameter on subsequent manifest calls flips `distributed=1`.
///
/// `(targetPubkey, createdAt)` is the primary key — repeated rotations
/// against the same follower stack as multiple rows. Lookup picks the row
/// with the highest `createdAt` and `distributed=0`.
class PendingKeyDistributionEntries extends Table {
  TextColumn get targetPubkey => text()();
  BlobColumn get encryptedFeedKey => blob()();
  BlobColumn get nonce => blob()();
  IntColumn get createdAt => integer()();
  IntColumn get distributed => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {targetPubkey, createdAt};
}
