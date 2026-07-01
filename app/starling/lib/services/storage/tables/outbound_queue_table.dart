import 'package:drift/drift.dart';

class OutboundQueueEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get targetPubkey => text()();
  BlobColumn get eventBlob => blob()();
  IntColumn get createdAt => integer()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  /// Plan 17: the EnvelopeItem `type` this row ships as when drained. Null ⇒
  /// `'event'` (back-compat with all pre-Plan-17 rows). Chatroom fan-out sets
  /// `'room-key'` / `'room-event'`.
  TextColumn get itemType => text().nullable()();
}
