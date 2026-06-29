import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/unknown_envelope_items_table.dart';

part 'unknown_items_dao.g.dart';

@DriftAccessor(tables: [UnknownEnvelopeItemEntries])
class UnknownItemsDao extends DatabaseAccessor<AppDatabase>
    with _$UnknownItemsDaoMixin {
  UnknownItemsDao(super.db);

  Future<int> insert(UnknownEnvelopeItemEntriesCompanion entry) =>
      into(unknownEnvelopeItemEntries).insert(entry);

  Future<List<UnknownEnvelopeItemEntry>> getByType(String type) => (select(
    unknownEnvelopeItemEntries,
  )..where((e) => e.type.equals(type))).get();

  Future<int> deleteOlderThan(int cutoffSeconds) => (delete(
    unknownEnvelopeItemEntries,
  )..where((e) => e.receivedAt.isSmallerThanValue(cutoffSeconds))).go();
}
