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
      default:
        return EventKind(value);
    }
  }

  bool get isKnown => value >= 1 && value <= 6;

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
      default:
        return 'EventKind($value)';
    }
  }
}
