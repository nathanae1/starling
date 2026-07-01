import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/models.dart';
import '../services/types.dart';
import 'identity_provider.dart';
import 'service_providers.dart';

part 'room_provider.g.dart';

/// Chatrooms the local user is a member of, newest-activity first.
@riverpod
Future<List<Room>> rooms(Ref ref) async {
  final storage = ref.watch(storageServiceProvider);
  final all = await storage.getRooms();
  return all.where((r) => r.isMember).toList();
}

/// A single room by id (room screen header + call affordance).
@riverpod
Future<Room?> roomById(Ref ref, String roomId) =>
    ref.watch(storageServiceProvider).getRoom(roomId);

/// Active members of [roomId].
@riverpod
Future<List<RoomMember>> roomMembersList(Ref ref, String roomId) async {
  final members = await ref
      .watch(storageServiceProvider)
      .getRoomMembers(roomId);
  return members.where((m) => m.isActive).toList();
}

/// Text messages (kind=102) in [roomId], ordered ASC by `created_at`,
/// filtered to current members (mirrors the comments allow-list). Room text
/// has no tombstones in v1.
@riverpod
Future<List<Event>> roomMessages(Ref ref, String roomId) async {
  final storage = ref.watch(storageServiceProvider);
  final members = await storage.getRoomMembers(roomId);
  final allowed = members
      .where((m) => m.isActive)
      .map((m) => m.pubkey)
      .toSet();
  final identity = await ref.watch(identityControllerProvider.future);
  if (identity != null) allowed.add(identity.pubkey);
  final raw = await storage.getEventsByRef(roomId, kind: EventKind.roomMessage);
  return raw.where((e) => allowed.contains(e.pubkey)).toList();
}

/// The most recent "call started" record (kind=103) for [roomId], or null.
@riverpod
Future<Event?> latestRoomCall(Ref ref, String roomId) async {
  final calls = await ref
      .watch(storageServiceProvider)
      .getEventsByRef(roomId, kind: EventKind.roomCallStarted);
  return calls.isEmpty ? null : calls.last;
}

/// Count of member rooms with unread activity (`lastActivityAt > lastReadAt`).
@riverpod
Future<int> unreadRoomsCount(Ref ref) async {
  final all = await ref.watch(storageServiceProvider).getRooms();
  return all.where((r) => r.isMember && r.lastActivityAt > r.lastReadAt).length;
}

/// Send messages in [roomId] and manage the local read cursor.
@riverpod
class RoomMessageController extends _$RoomMessageController {
  @override
  void build(String roomId) {}

  Future<String> submit(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('room message must not be empty');
    }
    final id = await ref
        .read(roomMessageServiceProvider)
        .send(roomId: roomId, text: trimmed);
    ref.invalidate(roomMessagesProvider(roomId));
    ref.invalidate(roomsProvider);
    return id;
  }

  /// Stamp the room read up to now; refreshes the unread badge + list.
  Future<void> markRead() async {
    final now = ref.read(clockProvider).nowUnixSeconds();
    await ref.read(storageServiceProvider).setRoomLastRead(roomId, now);
    ref.invalidate(unreadRoomsCountProvider);
    ref.invalidate(roomsProvider);
  }
}
