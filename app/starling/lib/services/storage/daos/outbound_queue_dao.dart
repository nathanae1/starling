import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/outbound_queue_table.dart';

part 'outbound_queue_dao.g.dart';

@DriftAccessor(tables: [OutboundQueueEntries])
class OutboundQueueDao extends DatabaseAccessor<AppDatabase>
    with _$OutboundQueueDaoMixin {
  OutboundQueueDao(super.db);

  Future<void> enqueue(OutboundQueueEntriesCompanion entry) =>
      into(outboundQueueEntries).insert(entry);

  Future<List<OutboundQueueEntry>> dequeue(String targetPubkey) => (select(
    outboundQueueEntries,
  )..where((q) => q.targetPubkey.equals(targetPubkey))).get();

  Future<void> incrementRetry(int id) async {
    final entry = await (select(
      outboundQueueEntries,
    )..where((q) => q.id.equals(id))).getSingleOrNull();
    if (entry != null) {
      await (update(outboundQueueEntries)..where((q) => q.id.equals(id))).write(
        OutboundQueueEntriesCompanion(retryCount: Value(entry.retryCount + 1)),
      );
    }
  }

  Future<void> removeFromQueue(int id) =>
      (delete(outboundQueueEntries)..where((q) => q.id.equals(id))).go();
}
