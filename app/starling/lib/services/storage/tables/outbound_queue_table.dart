import 'package:drift/drift.dart';

class OutboundQueueEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get targetPubkey => text()();
  BlobColumn get eventBlob => blob()();
  IntColumn get createdAt => integer()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
}
