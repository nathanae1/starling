import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:starling/services/storage/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.memory();
  });

  tearDown(() async {
    await db.close();
  });

  group('inbound requests', () {
    test('saves and retrieves pending requests', () async {
      await db.followRequestsDao.upsertInbound(
        InboundFollowRequestEntriesCompanion.insert(
          pubkey: 'requester-1',
          encryptedEndpoints: Uint8List.fromList([1, 2, 3]),
          createdAt: 1000,
        ),
      );

      final pending = await db.followRequestsDao.getInboundPending();
      expect(pending, hasLength(1));
      expect(pending.first.pubkey, equals('requester-1'));
    });

    test('updates status filters out of pending', () async {
      await db.followRequestsDao.upsertInbound(
        InboundFollowRequestEntriesCompanion.insert(
          pubkey: 'requester-1',
          encryptedEndpoints: Uint8List.fromList([1, 2, 3]),
          createdAt: 1000,
        ),
      );

      await db.followRequestsDao.updateInboundStatus('requester-1', 'accepted');

      final pending = await db.followRequestsDao.getInboundPending();
      expect(pending, isEmpty);
    });
  });

  group('outbound requests', () {
    test('saves and retrieves requests', () async {
      await db.followRequestsDao.upsertOutbound(
        OutboundFollowRequestEntriesCompanion.insert(
          pubkey: 'target-1',
          connectionCard: '{"pubkey":"target-1"}',
          createdAt: 2000,
        ),
      );

      final outbound = await db.followRequestsDao.getOutbound();
      expect(outbound, hasLength(1));
      expect(outbound.first.pubkey, equals('target-1'));
    });

    test('updates outbound status', () async {
      await db.followRequestsDao.upsertOutbound(
        OutboundFollowRequestEntriesCompanion.insert(
          pubkey: 'target-1',
          connectionCard: '{"pubkey":"target-1"}',
          createdAt: 2000,
        ),
      );

      await db.followRequestsDao.updateOutboundStatus('target-1', 'accepted');

      final outbound = await db.followRequestsDao.getOutbound();
      expect(outbound.first.status, equals('accepted'));
    });
  });
}
