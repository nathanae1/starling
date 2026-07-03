import 'dart:developer' as developer;
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/events_dao.dart';
import 'daos/follow_requests_dao.dart';
import 'daos/follows_dao.dart';
import 'daos/identity_dao.dart';
import 'daos/key_rotation_dao.dart';
import 'daos/media_cache_dao.dart';
import 'daos/outbound_queue_dao.dart';
import 'daos/paired_relay_dao.dart';
import 'daos/rooms_dao.dart';
import 'daos/unknown_items_dao.dart';
import 'daos/voice_rooms_dao.dart';
import 'tables/events_table.dart';
import 'tables/feed_key_history_table.dart';
import 'tables/follow_feed_key_history_table.dart';
import 'tables/follows_table.dart';
import 'tables/identity_table.dart';
import 'tables/inbound_follow_requests_table.dart';
import 'tables/media_cache_table.dart';
import 'tables/outbound_follow_requests_table.dart';
import 'tables/outbound_queue_table.dart';
import 'tables/paired_relay_table.dart';
import 'tables/pending_card_distributions_table.dart';
import 'tables/pending_key_distributions_table.dart';
import 'tables/relay_fanout_state_table.dart';
import 'tables/room_key_history_table.dart';
import 'tables/room_members_table.dart';
import 'tables/rooms_table.dart';
import 'tables/unknown_envelope_items_table.dart';
import 'tables/voice_room_participants_table.dart';
import 'tables/voice_rooms_table.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    IdentityEntries,
    FollowEntries,
    EventEntries,
    MediaCacheEntries,
    InboundFollowRequestEntries,
    OutboundFollowRequestEntries,
    OutboundQueueEntries,
    UnknownEnvelopeItemEntries,
    FeedKeyHistoryEntries,
    FollowFeedKeyHistoryEntries,
    PendingKeyDistributionEntries,
    PairedRelayEntries,
    PendingCardDistributionEntries,
    RelayFanoutStateEntries,
    VoiceRoomEntries,
    VoiceRoomParticipantEntries,
    RoomEntries,
    RoomMemberEntries,
    RoomKeyHistoryEntries,
  ],
  daos: [
    IdentityDao,
    FollowsDao,
    EventsDao,
    MediaCacheDao,
    FollowRequestsDao,
    OutboundQueueDao,
    UnknownItemsDao,
    KeyRotationDao,
    PairedRelayDao,
    VoiceRoomsDao,
    RoomsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Production: encrypted file-based DB.
  factory AppDatabase.encrypted(String dbKey) {
    return AppDatabase(_openEncryptedConnection(dbKey));
  }

  /// Tests: in-memory, unencrypted.
  factory AppDatabase.memory() {
    return AppDatabase(NativeDatabase.memory());
  }

  @override
  int get schemaVersion => 13;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await customStatement(
        'CREATE INDEX idx_events_feed '
        'ON event_entries (created_at DESC)',
      );
      await customStatement(
        'CREATE INDEX idx_events_pubkey '
        'ON event_entries (pubkey, created_at DESC)',
      );
      await customStatement(
        'CREATE INDEX idx_events_ref '
        'ON event_entries (ref_id)',
      );
      await customStatement(
        'CREATE INDEX idx_events_saved '
        'ON event_entries (is_saved) WHERE is_saved = 1',
      );
      await customStatement(
        'CREATE INDEX idx_pending_distributions_undelivered '
        'ON pending_key_distribution_entries (target_pubkey) '
        'WHERE distributed = 0',
      );
      await customStatement(
        'CREATE INDEX idx_pending_card_distributions_undelivered '
        'ON pending_card_distribution_entries (target_pubkey) '
        'WHERE distributed = 0',
      );
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(eventEntries, eventEntries.encryptedPayload);
      }
      if (from < 3) {
        await m.createTable(pairedRelayEntries);
        await m.createTable(pendingCardDistributionEntries);
        await customStatement(
          'CREATE INDEX idx_pending_card_distributions_undelivered '
          'ON pending_card_distribution_entries (target_pubkey) '
          'WHERE distributed = 0',
        );
      }
      if (from < 4) {
        // Plan 15 R3 cleanup: phone is no longer a relay. Drop the
        // tables that backed the abandoned phone-as-relay code. The
        // index lived on a dropped table; DROP TABLE removes it, but
        // be explicit in case a dev manually created it without the
        // table.
        await customStatement(
          'DROP TABLE IF EXISTS relay_paired_owner_entries',
        );
        await customStatement('DROP TABLE IF EXISTS relay_pairing_entries');
        await customStatement('DROP TABLE IF EXISTS served_event_entries');
        await customStatement('DROP TABLE IF EXISTS served_media_entries');
        await customStatement(
          'DROP TABLE IF EXISTS served_follow_request_entries',
        );
        await customStatement(
          'DROP INDEX IF EXISTS idx_served_events_pubkey_created',
        );
      }
      if (from < 5) {
        // Plan 15: track the most recent Connection card update accepted
        // from each peer, so the follower can ack card distributions the
        // same way it acks key rotations.
        await m.addColumn(followEntries, followEntries.lastReceivedCardAt);
      }
      if (from < 6) {
        // S2/S3b: card deliveries are now sealed per follower
        // (encrypted_card + nonce replace card_cbor + sig). Old
        // cleartext rows are a transient outbox — drop and recreate;
        // they're re-queued on the next pair/unpair.
        await customStatement(
          'DROP TABLE IF EXISTS pending_card_distribution_entries',
        );
        await m.createTable(pendingCardDistributionEntries);
        await customStatement(
          'CREATE INDEX idx_pending_card_distributions_undelivered '
          'ON pending_card_distribution_entries (target_pubkey) '
          'WHERE distributed = 0',
        );
      }
      if (from < 7) {
        // D1: per-follow timestamp of the last FULL (un-windowed)
        // manifest diff; the periodic full pass catches events that
        // arrived at a store out of author-time order.
        await m.addColumn(followEntries, followEntries.lastFullSyncAt);
      }
      if (from < 8) {
        // Plan 16: local-only voice-room call history (signaling-plane
        // rooms, never feed events). Pruned after 7 days.
        await m.createTable(voiceRoomEntries);
        await m.createTable(voiceRoomParticipantEntries);
      }
      if (from < 9) {
        // Plan 17: durable chatrooms. Room identity/keys/roster tables plus
        // a typed outbound-queue column so room-key/room-event items fan out
        // over the existing directed-delivery queue.
        await m.createTable(roomEntries);
        await m.createTable(roomMemberEntries);
        await m.createTable(roomKeyHistoryEntries);
        await m.addColumn(outboundQueueEntries, outboundQueueEntries.itemType);
      }
      if (from < 10) {
        // Drop the vestigial follow name/avatar columns (always null; a
        // friend's name + avatar come from their kind=2 profile, resolved via
        // followProfileProvider). Data-preserving: TableMigration recreates
        // follow_entries from the new schema, copying every remaining column
        // and row — NEVER a DROP TABLE, which would wipe the friend list.
        await m.alterTable(TableMigration(followEntries));
      }
      if (from < 11) {
        // Plan 19: invitee-side missed-call flag on voice-room history.
        await m.addColumn(voiceRoomEntries, voiceRoomEntries.missed);
      }
      if (from < 12) {
        // Phase 3 deletion/retention: persisted per-relay prune horizon.
        // Own posts older than this were deliberately aged off the relay
        // and must not be re-pushed by the reconciler.
        await m.addColumn(
          pairedRelayEntries,
          pairedRelayEntries.relayPruneBefore,
        );
      }
      if (from < 13) {
        // Relay review Phase 2: per-relay health (A7) + crash-safe
        // pair/unpair side-effect markers (A2/A3 heal pass).
        await m.addColumn(pairedRelayEntries, pairedRelayEntries.lastPushAt);
        await m.addColumn(pairedRelayEntries, pairedRelayEntries.lastError);
        await m.createTable(relayFanoutStateEntries);
      }
    },
  );
}

LazyDatabase _openEncryptedConnection(String dbKey) {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'starling.db'));
    final exists = await file.exists();
    final size = exists ? await file.length() : 0;
    final keyFp = _shortHex(dbKey);
    _dbLog('open path=${file.path} exists=$exists size=$size keyFp=$keyFp');

    return NativeDatabase.createInBackground(
      file,
      setup: (rawDb) {
        try {
          rawDb.execute("PRAGMA key = \"x'$dbKey'\";");
          // Fail fast if key is wrong.
          rawDb.execute('SELECT count(*) FROM sqlite_master');
          _dbLog('open ok keyFp=$keyFp');
        } catch (e) {
          _dbLog('open FAILED keyFp=$keyFp err=$e');
          rethrow;
        }
      },
    );
  });
}

/// First 8 hex chars of a hex-encoded string, for safe logging.
String _shortHex(String hex) {
  if (hex.length <= 8) return hex;
  return '${hex.substring(0, 8)}…';
}

void _dbLog(String msg) {
  developer.log(msg, name: 'starling.db');
  // ignore: avoid_print
  print('[starling.db] $msg');
}
