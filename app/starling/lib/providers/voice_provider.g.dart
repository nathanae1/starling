// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'voice_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Voice-room coordination layer over the existing signaling plane.

@ProviderFor(roomSignaling)
final roomSignalingProvider = RoomSignalingProvider._();

/// Voice-room coordination layer over the existing signaling plane.

final class RoomSignalingProvider
    extends $FunctionalProvider<RoomSignaling, RoomSignaling, RoomSignaling>
    with $Provider<RoomSignaling> {
  /// Voice-room coordination layer over the existing signaling plane.
  RoomSignalingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roomSignalingProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roomSignalingHash();

  @$internal
  @override
  $ProviderElement<RoomSignaling> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RoomSignaling create(Ref ref) {
    return roomSignaling(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RoomSignaling value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RoomSignaling>(value),
    );
  }
}

String _$roomSignalingHash() => r'd28cfdc0304acfadf389b9f2675508fd12b382b8';

/// The WebRTC media engine. Overridden with a mock in tests.

@ProviderFor(voiceService)
final voiceServiceProvider = VoiceServiceProvider._();

/// The WebRTC media engine. Overridden with a mock in tests.

final class VoiceServiceProvider
    extends $FunctionalProvider<VoiceService, VoiceService, VoiceService>
    with $Provider<VoiceService> {
  /// The WebRTC media engine. Overridden with a mock in tests.
  VoiceServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'voiceServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$voiceServiceHash();

  @$internal
  @override
  $ProviderElement<VoiceService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  VoiceService create(Ref ref) {
    return voiceService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(VoiceService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<VoiceService>(value),
    );
  }
}

String _$voiceServiceHash() => r'dfa58d3c35ecb1a65ca7bc8d89b73d1f06ad8a26';

/// Orchestrates room lifecycle + the WebRTC mesh. `start()` is called from
/// [LifecycleManager] so inbound invites are received whenever the app is
/// foregrounded (not only while the voice UI is open).

@ProviderFor(roomManager)
final roomManagerProvider = RoomManagerProvider._();

/// Orchestrates room lifecycle + the WebRTC mesh. `start()` is called from
/// [LifecycleManager] so inbound invites are received whenever the app is
/// foregrounded (not only while the voice UI is open).

final class RoomManagerProvider
    extends $FunctionalProvider<RoomManager, RoomManager, RoomManager>
    with $Provider<RoomManager> {
  /// Orchestrates room lifecycle + the WebRTC mesh. `start()` is called from
  /// [LifecycleManager] so inbound invites are received whenever the app is
  /// foregrounded (not only while the voice UI is open).
  RoomManagerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'roomManagerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$roomManagerHash();

  @$internal
  @override
  $ProviderElement<RoomManager> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  RoomManager create(Ref ref) {
    return roomManager(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RoomManager value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RoomManager>(value),
    );
  }
}

String _$roomManagerHash() => r'332d26319fdd80e255a6cb4117fc2fac17e14384';

/// Live voice-room state for the UI; null when idle. Replays the manager's
/// current state to each subscriber before streaming updates, so a screen
/// mounted after the call started (active room, overlay) renders immediately
/// instead of waiting for the next change.

@ProviderFor(voiceRoomState)
final voiceRoomStateProvider = VoiceRoomStateProvider._();

/// Live voice-room state for the UI; null when idle. Replays the manager's
/// current state to each subscriber before streaming updates, so a screen
/// mounted after the call started (active room, overlay) renders immediately
/// instead of waiting for the next change.

final class VoiceRoomStateProvider
    extends
        $FunctionalProvider<
          AsyncValue<VoiceRoomState?>,
          VoiceRoomState?,
          Stream<VoiceRoomState?>
        >
    with $FutureModifier<VoiceRoomState?>, $StreamProvider<VoiceRoomState?> {
  /// Live voice-room state for the UI; null when idle. Replays the manager's
  /// current state to each subscriber before streaming updates, so a screen
  /// mounted after the call started (active room, overlay) renders immediately
  /// instead of waiting for the next change.
  VoiceRoomStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'voiceRoomStateProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$voiceRoomStateHash();

  @$internal
  @override
  $StreamProviderElement<VoiceRoomState?> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<VoiceRoomState?> create(Ref ref) {
    return voiceRoomState(ref);
  }
}

String _$voiceRoomStateHash() => r'24681ce7bed51d45e594ccfc1fdafdfb0d045e91';

/// Inbound room invites awaiting the user's accept/decline.

@ProviderFor(incomingVoiceInvites)
final incomingVoiceInvitesProvider = IncomingVoiceInvitesProvider._();

/// Inbound room invites awaiting the user's accept/decline.

final class IncomingVoiceInvitesProvider
    extends
        $FunctionalProvider<AsyncValue<VoiceRoom>, VoiceRoom, Stream<VoiceRoom>>
    with $FutureModifier<VoiceRoom>, $StreamProvider<VoiceRoom> {
  /// Inbound room invites awaiting the user's accept/decline.
  IncomingVoiceInvitesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'incomingVoiceInvitesProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$incomingVoiceInvitesHash();

  @$internal
  @override
  $StreamProviderElement<VoiceRoom> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<VoiceRoom> create(Ref ref) {
    return incomingVoiceInvites(ref);
  }
}

String _$incomingVoiceInvitesHash() =>
    r'1169122fae7cc06dd15c8526912f92111c117572';

/// Recent local call history for the room list.

@ProviderFor(recentVoiceRooms)
final recentVoiceRoomsProvider = RecentVoiceRoomsProvider._();

/// Recent local call history for the room list.

final class RecentVoiceRoomsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<VoiceRoom>>,
          List<VoiceRoom>,
          FutureOr<List<VoiceRoom>>
        >
    with $FutureModifier<List<VoiceRoom>>, $FutureProvider<List<VoiceRoom>> {
  /// Recent local call history for the room list.
  RecentVoiceRoomsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'recentVoiceRoomsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$recentVoiceRoomsHash();

  @$internal
  @override
  $FutureProviderElement<List<VoiceRoom>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<VoiceRoom>> create(Ref ref) {
    return recentVoiceRooms(ref);
  }
}

String _$recentVoiceRoomsHash() => r'6fb687aa75159345eeaa84f2708b3b68e526148a';

/// Active follows who also follow us — the only contacts invitable to a room
/// (Plan 16 §Room access model).

@ProviderFor(mutualFollows)
final mutualFollowsProvider = MutualFollowsProvider._();

/// Active follows who also follow us — the only contacts invitable to a room
/// (Plan 16 §Room access model).

final class MutualFollowsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Follow>>,
          List<Follow>,
          FutureOr<List<Follow>>
        >
    with $FutureModifier<List<Follow>>, $FutureProvider<List<Follow>> {
  /// Active follows who also follow us — the only contacts invitable to a room
  /// (Plan 16 §Room access model).
  MutualFollowsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mutualFollowsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mutualFollowsHash();

  @$internal
  @override
  $FutureProviderElement<List<Follow>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<Follow>> create(Ref ref) {
    return mutualFollows(ref);
  }
}

String _$mutualFollowsHash() => r'007b6ab69732cc6f2a53f9e6d9a0f4ae177dbc0f';
