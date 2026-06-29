import 'package:drift/drift.dart';

import '../database.dart';
import '../tables/inbound_follow_requests_table.dart';
import '../tables/outbound_follow_requests_table.dart';

part 'follow_requests_dao.g.dart';

@DriftAccessor(
  tables: [InboundFollowRequestEntries, OutboundFollowRequestEntries],
)
class FollowRequestsDao extends DatabaseAccessor<AppDatabase>
    with _$FollowRequestsDaoMixin {
  FollowRequestsDao(super.db);

  // --- Inbound ---

  Future<List<InboundFollowRequestEntry>> getInboundPending() => (select(
    inboundFollowRequestEntries,
  )..where((r) => r.status.equals('pending'))).get();

  Stream<List<InboundFollowRequestEntry>> watchInboundPending() => (select(
    inboundFollowRequestEntries,
  )..where((r) => r.status.equals('pending'))).watch();

  /// Inbound rows we've already actioned (accepted / pending-send /
  /// send-failed). Used to surface "Follows you" entries in the friends
  /// list — peers who scanned our QR but whom we haven't followed back.
  Stream<List<InboundFollowRequestEntry>> watchInboundActioned() => (select(
    inboundFollowRequestEntries,
  )..where((r) => r.status.isNotValue('pending'))).watch();

  Future<List<InboundFollowRequestEntry>> getInboundByStatus(String status) =>
      (select(
        inboundFollowRequestEntries,
      )..where((r) => r.status.equals(status))).get();

  Future<InboundFollowRequestEntry?> getInbound(String pubkey) => (select(
    inboundFollowRequestEntries,
  )..where((r) => r.pubkey.equals(pubkey))).getSingleOrNull();

  Future<void> upsertInbound(InboundFollowRequestEntriesCompanion entry) =>
      into(inboundFollowRequestEntries).insertOnConflictUpdate(entry);

  Future<void> updateInboundStatus(String pubkey, String status) =>
      (update(inboundFollowRequestEntries)
            ..where((r) => r.pubkey.equals(pubkey)))
          .write(InboundFollowRequestEntriesCompanion(status: Value(status)));

  Future<void> deleteInbound(String pubkey) => (delete(
    inboundFollowRequestEntries,
  )..where((r) => r.pubkey.equals(pubkey))).go();

  // --- Outbound ---

  Future<List<OutboundFollowRequestEntry>> getOutbound() =>
      select(outboundFollowRequestEntries).get();

  Stream<List<OutboundFollowRequestEntry>> watchOutbound() =>
      select(outboundFollowRequestEntries).watch();

  Future<OutboundFollowRequestEntry?> getOutboundFor(String pubkey) => (select(
    outboundFollowRequestEntries,
  )..where((r) => r.pubkey.equals(pubkey))).getSingleOrNull();

  Future<void> upsertOutbound(OutboundFollowRequestEntriesCompanion entry) =>
      into(outboundFollowRequestEntries).insertOnConflictUpdate(entry);

  Future<void> updateOutboundStatus(String pubkey, String status) =>
      (update(outboundFollowRequestEntries)
            ..where((r) => r.pubkey.equals(pubkey)))
          .write(OutboundFollowRequestEntriesCompanion(status: Value(status)));

  Future<void> deleteOutbound(String pubkey) => (delete(
    outboundFollowRequestEntries,
  )..where((r) => r.pubkey.equals(pubkey))).go();
}
