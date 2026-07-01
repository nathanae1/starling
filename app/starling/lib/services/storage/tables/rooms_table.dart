import 'package:drift/drift.dart';

/// A durable chatroom (Plan 17). The per-room analogue of the identity's
/// feed-key columns: its own membership-scoped key/epoch/message-seq counter,
/// plus membership + local UI state. Messages themselves reuse
/// `event_entries` (kinds 102/103, `ref = roomId`) — no separate table.
class RoomEntries extends Table {
  /// roomId = the id of the genesis `roomCreate` event.
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get creatorPubkey => text()();
  IntColumn get createdAt => integer()();

  /// Retention key: last time a message/membership/call event touched the
  /// room. NOT createdAt — a long-lived room stays alive on activity.
  IntColumn get lastActivityAt => integer()();

  /// Current room key (chain root), its epoch, and the time it took effect.
  BlobColumn get roomKey => blob()();
  IntColumn get roomKeyEpoch => integer().withDefault(const Constant(0))();
  IntColumn get roomKeyValidFrom => integer().withDefault(const Constant(0))();

  /// Next msg_seq to allocate under the current room key.
  IntColumn get roomMsgSeqCounter => integer().withDefault(const Constant(0))();

  /// Monotonic membership version — a `roomMembership` is applied only if
  /// its epoch is newer than this.
  IntColumn get membershipEpoch => integer().withDefault(const Constant(0))();

  /// 1 while the local user is a member; 0 after leaving/removal. Drives
  /// retention (left rooms are evictable) and the room list.
  IntColumn get isMember => integer().withDefault(const Constant(1))();

  /// Local-only read cursor (unix seconds) for the unread badge.
  IntColumn get lastReadAt => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}
