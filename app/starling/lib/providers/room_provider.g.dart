// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'room_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Chatrooms the local user is a member of, newest-activity first.

@ProviderFor(rooms)
final roomsProvider = RoomsProvider._();

/// Chatrooms the local user is a member of, newest-activity first.

final class RoomsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Room>>,
          List<Room>,
          FutureOr<List<Room>>
        >
    with $FutureModifier<List<Room>>, $FutureProvider<List<Room>> {
  /// Chatrooms the local user is a member of, newest-activity first.
  RoomsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roomsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roomsHash();

  @$internal
  @override
  $FutureProviderElement<List<Room>> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<List<Room>> create(Ref ref) {
    return rooms(ref);
  }
}

String _$roomsHash() => r'42be4e09d3f6341bdb5eb400bd29f96db06c8155';

/// A single room by id (room screen header + call affordance).

@ProviderFor(roomById)
final roomByIdProvider = RoomByIdFamily._();

/// A single room by id (room screen header + call affordance).

final class RoomByIdProvider
    extends $FunctionalProvider<AsyncValue<Room?>, Room?, FutureOr<Room?>>
    with $FutureModifier<Room?>, $FutureProvider<Room?> {
  /// A single room by id (room screen header + call affordance).
  RoomByIdProvider._({
    required RoomByIdFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'roomByIdProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$roomByIdHash();

  @override
  String toString() {
    return r'roomByIdProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Room?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Room?> create(Ref ref) {
    final argument = this.argument as String;
    return roomById(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RoomByIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$roomByIdHash() => r'0d4f24ccbfc24f602d086d7d470cac4a30a3c787';

/// A single room by id (room screen header + call affordance).

final class RoomByIdFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Room?>, String> {
  RoomByIdFamily._()
    : super(
        retry: null,
        name: r'roomByIdProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A single room by id (room screen header + call affordance).

  RoomByIdProvider call(String roomId) =>
      RoomByIdProvider._(argument: roomId, from: this);

  @override
  String toString() => r'roomByIdProvider';
}

/// Active members of [roomId].

@ProviderFor(roomMembersList)
final roomMembersListProvider = RoomMembersListFamily._();

/// Active members of [roomId].

final class RoomMembersListProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<RoomMember>>,
          List<RoomMember>,
          FutureOr<List<RoomMember>>
        >
    with $FutureModifier<List<RoomMember>>, $FutureProvider<List<RoomMember>> {
  /// Active members of [roomId].
  RoomMembersListProvider._({
    required RoomMembersListFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'roomMembersListProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$roomMembersListHash();

  @override
  String toString() {
    return r'roomMembersListProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<RoomMember>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<RoomMember>> create(Ref ref) {
    final argument = this.argument as String;
    return roomMembersList(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RoomMembersListProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$roomMembersListHash() => r'0051a2f1aaf451372ca78d02eab48825268480c3';

/// Active members of [roomId].

final class RoomMembersListFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<RoomMember>>, String> {
  RoomMembersListFamily._()
    : super(
        retry: null,
        name: r'roomMembersListProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Active members of [roomId].

  RoomMembersListProvider call(String roomId) =>
      RoomMembersListProvider._(argument: roomId, from: this);

  @override
  String toString() => r'roomMembersListProvider';
}

/// Text messages (kind=102) in [roomId], ordered ASC by `created_at`,
/// filtered to current members (mirrors the comments allow-list). Room text
/// has no tombstones in v1.

@ProviderFor(roomMessages)
final roomMessagesProvider = RoomMessagesFamily._();

/// Text messages (kind=102) in [roomId], ordered ASC by `created_at`,
/// filtered to current members (mirrors the comments allow-list). Room text
/// has no tombstones in v1.

final class RoomMessagesProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Event>>,
          List<Event>,
          FutureOr<List<Event>>
        >
    with $FutureModifier<List<Event>>, $FutureProvider<List<Event>> {
  /// Text messages (kind=102) in [roomId], ordered ASC by `created_at`,
  /// filtered to current members (mirrors the comments allow-list). Room text
  /// has no tombstones in v1.
  RoomMessagesProvider._({
    required RoomMessagesFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'roomMessagesProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$roomMessagesHash();

  @override
  String toString() {
    return r'roomMessagesProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<List<Event>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Event>> create(Ref ref) {
    final argument = this.argument as String;
    return roomMessages(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is RoomMessagesProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$roomMessagesHash() => r'bef23efdce80bbc14f147735f1dfee5dcee1d383';

/// Text messages (kind=102) in [roomId], ordered ASC by `created_at`,
/// filtered to current members (mirrors the comments allow-list). Room text
/// has no tombstones in v1.

final class RoomMessagesFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<List<Event>>, String> {
  RoomMessagesFamily._()
    : super(
        retry: null,
        name: r'roomMessagesProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Text messages (kind=102) in [roomId], ordered ASC by `created_at`,
  /// filtered to current members (mirrors the comments allow-list). Room text
  /// has no tombstones in v1.

  RoomMessagesProvider call(String roomId) =>
      RoomMessagesProvider._(argument: roomId, from: this);

  @override
  String toString() => r'roomMessagesProvider';
}

/// The most recent "call started" record (kind=103) for [roomId], or null.

@ProviderFor(latestRoomCall)
final latestRoomCallProvider = LatestRoomCallFamily._();

/// The most recent "call started" record (kind=103) for [roomId], or null.

final class LatestRoomCallProvider
    extends $FunctionalProvider<AsyncValue<Event?>, Event?, FutureOr<Event?>>
    with $FutureModifier<Event?>, $FutureProvider<Event?> {
  /// The most recent "call started" record (kind=103) for [roomId], or null.
  LatestRoomCallProvider._({
    required LatestRoomCallFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'latestRoomCallProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$latestRoomCallHash();

  @override
  String toString() {
    return r'latestRoomCallProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<Event?> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<Event?> create(Ref ref) {
    final argument = this.argument as String;
    return latestRoomCall(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is LatestRoomCallProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$latestRoomCallHash() => r'5e8d0f7bf5cfdc59e2dd30b855a6ec043c0f2479';

/// The most recent "call started" record (kind=103) for [roomId], or null.

final class LatestRoomCallFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Event?>, String> {
  LatestRoomCallFamily._()
    : super(
        retry: null,
        name: r'latestRoomCallProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// The most recent "call started" record (kind=103) for [roomId], or null.

  LatestRoomCallProvider call(String roomId) =>
      LatestRoomCallProvider._(argument: roomId, from: this);

  @override
  String toString() => r'latestRoomCallProvider';
}

/// Count of member rooms with unread activity (`lastActivityAt > lastReadAt`).

@ProviderFor(unreadRoomsCount)
final unreadRoomsCountProvider = UnreadRoomsCountProvider._();

/// Count of member rooms with unread activity (`lastActivityAt > lastReadAt`).

final class UnreadRoomsCountProvider
    extends $FunctionalProvider<AsyncValue<int>, int, FutureOr<int>>
    with $FutureModifier<int>, $FutureProvider<int> {
  /// Count of member rooms with unread activity (`lastActivityAt > lastReadAt`).
  UnreadRoomsCountProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'unreadRoomsCountProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$unreadRoomsCountHash();

  @$internal
  @override
  $FutureProviderElement<int> $createElement($ProviderPointer pointer) =>
      $FutureProviderElement(pointer);

  @override
  FutureOr<int> create(Ref ref) {
    return unreadRoomsCount(ref);
  }
}

String _$unreadRoomsCountHash() => r'f6fea443c422893ef6d9293955907ebd33d6593c';

/// Send messages in [roomId] and manage the local read cursor.

@ProviderFor(RoomMessageController)
final roomMessageControllerProvider = RoomMessageControllerFamily._();

/// Send messages in [roomId] and manage the local read cursor.
final class RoomMessageControllerProvider
    extends $NotifierProvider<RoomMessageController, void> {
  /// Send messages in [roomId] and manage the local read cursor.
  RoomMessageControllerProvider._({
    required RoomMessageControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'roomMessageControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$roomMessageControllerHash();

  @override
  String toString() {
    return r'roomMessageControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  RoomMessageController create() => RoomMessageController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is RoomMessageControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$roomMessageControllerHash() =>
    r'40e779e109b9ebe0ad06fd047ab8cc4a31a8d8a5';

/// Send messages in [roomId] and manage the local read cursor.

final class RoomMessageControllerFamily extends $Family
    with $ClassFamilyOverride<RoomMessageController, void, void, void, String> {
  RoomMessageControllerFamily._()
    : super(
        retry: null,
        name: r'roomMessageControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Send messages in [roomId] and manage the local read cursor.

  RoomMessageControllerProvider call(String roomId) =>
      RoomMessageControllerProvider._(argument: roomId, from: this);

  @override
  String toString() => r'roomMessageControllerProvider';
}

/// Send messages in [roomId] and manage the local read cursor.

abstract class _$RoomMessageController extends $Notifier<void> {
  late final _$args = ref.$arg as String;
  String get roomId => _$args;

  void build(String roomId);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}
