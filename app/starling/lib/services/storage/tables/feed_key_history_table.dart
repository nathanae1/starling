import 'package:drift/drift.dart';

/// Retired feed keys (Plan 13).
///
/// A row is appended whenever the owner rotates their feed key — typically on
/// removeFollower. The row records the key bytes, the ratchet epoch in effect
/// at the moment of rotation, and the half-open `[validFrom, validUntil)`
/// time window during which this key was the current key. The current
/// (in-use) key lives on `identity_entries.feedKey` with a corresponding
/// `feedKeyValidFrom`; only retired keys live here.
///
/// Used by historical-key lookups when decrypting own media that was
/// encrypted before a rotation (`MediaService` encrypts with the feed key).
/// Plaintext events on disk don't need this lookup.
class FeedKeyHistoryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  BlobColumn get feedKey => blob()();
  IntColumn get feedKeyEpoch => integer().withDefault(const Constant(0))();
  IntColumn get validFrom => integer()();
  IntColumn get validUntil => integer()();
}
