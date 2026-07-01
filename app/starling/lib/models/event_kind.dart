/// Event kinds are an open integer enum. Clients MUST store and sync events
/// with unknown kinds without crashing or dropping them.
///
/// Reserved ranges:
///   1-9    Core social feed (post, profile, follows, comments, likes, deletes)
///   10-19  Real-time / ephemeral (voice rooms, typing indicators, presence)
///   20-99  Reserved for future core protocol extensions
///   100-199  Messaging (DMs, group chat, read receipts)
///   200-299  Media (video, audio, file sharing)
///   300+     Application-defined (third-party extensions)
class EventKind {
  const EventKind(this.value);
  final int value;

  // --- Defined kinds (v1) ---
  static const post = EventKind(1);
  static const profile = EventKind(2);
  static const followList = EventKind(3);
  static const comment = EventKind(4);
  static const like = EventKind(5);
  static const delete = EventKind(6);

  // --- Messaging kinds (Plan 17 chatrooms, 100-199 range) ---
  /// Genesis of a durable chatroom. The event id IS the roomId.
  static const roomCreate = EventKind(100);

  /// Signed membership roster (creator-authored). `ref = roomId`.
  static const roomMembership = EventKind(101);

  /// A chatroom text message. `ref = roomId` (mirrors a comment).
  static const roomMessage = EventKind(102);

  /// Durable "a call started" record. `ref = roomId`.
  static const roomCallStarted = EventKind(103);

  /// Known kinds for iteration. Does not include unknown kinds.
  static List<EventKind> get values => const [
    post,
    profile,
    followList,
    comment,
    like,
    delete,
  ];

  /// Returns the matching known kind, or a new EventKind for unknown values.
  /// Never throws — unknown kinds are valid and must be preserved.
  static EventKind fromValue(int value) {
    switch (value) {
      case 1:
        return post;
      case 2:
        return profile;
      case 3:
        return followList;
      case 4:
        return comment;
      case 5:
        return like;
      case 6:
        return delete;
      case 100:
        return roomCreate;
      case 101:
        return roomMembership;
      case 102:
        return roomMessage;
      case 103:
        return roomCallStarted;
      default:
        return EventKind(value);
    }
  }

  /// Core feed kinds only. Chatroom kinds (100-103) deliberately stay
  /// "unknown" so they flow through storage/sync ungated and are never
  /// treated as feed content by any consumer that gates on [isKnown].
  bool get isKnown => value >= 1 && value <= 6;

  /// True for chatroom-scoped kinds (Plan 17, 100-103). These are encrypted
  /// under a membership room key and delivered only to members — they MUST be
  /// excluded from every feed-broadcast / re-serve seam, or they'd be
  /// re-encrypted under the owner's feed key and served to all followers.
  bool get isRoomScoped => value >= 100 && value <= 103;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is EventKind && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() {
    switch (value) {
      case 1:
        return 'EventKind.post';
      case 2:
        return 'EventKind.profile';
      case 3:
        return 'EventKind.followList';
      case 4:
        return 'EventKind.comment';
      case 5:
        return 'EventKind.like';
      case 6:
        return 'EventKind.delete';
      case 100:
        return 'EventKind.roomCreate';
      case 101:
        return 'EventKind.roomMembership';
      case 102:
        return 'EventKind.roomMessage';
      case 103:
        return 'EventKind.roomCallStarted';
      default:
        return 'EventKind($value)';
    }
  }
}
