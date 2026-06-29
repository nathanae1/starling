import 'package:drift/drift.dart';

class OutboundFollowRequestEntries extends Table {
  TextColumn get pubkey => text()();
  TextColumn get connectionCard => text()();
  IntColumn get createdAt => integer()();
  TextColumn get status => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {pubkey};
}
