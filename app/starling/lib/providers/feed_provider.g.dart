// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'feed_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Single-instance LastViewedTracker for the running app. Lives at the
/// provider scope so the dedupe set survives across feed rebuilds but
/// dies with the app process.

@ProviderFor(lastViewedTracker)
final lastViewedTrackerProvider = LastViewedTrackerProvider._();

/// Single-instance LastViewedTracker for the running app. Lives at the
/// provider scope so the dedupe set survives across feed rebuilds but
/// dies with the app process.

final class LastViewedTrackerProvider
    extends
        $FunctionalProvider<
          LastViewedTracker,
          LastViewedTracker,
          LastViewedTracker
        >
    with $Provider<LastViewedTracker> {
  /// Single-instance LastViewedTracker for the running app. Lives at the
  /// provider scope so the dedupe set survives across feed rebuilds but
  /// dies with the app process.
  LastViewedTrackerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'lastViewedTrackerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$lastViewedTrackerHash();

  @$internal
  @override
  $ProviderElement<LastViewedTracker> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  LastViewedTracker create(Ref ref) {
    return lastViewedTracker(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LastViewedTracker value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LastViewedTracker>(value),
    );
  }
}

String _$lastViewedTrackerHash() => r'96e1cb52d02aab043d964b7b9131a8bdafaf6b87';

/// Reverse-chronological feed of kind=1 posts from own identity + active
/// follows. Posts with a kind=6 tombstone from the same author are excluded
/// at the storage layer.
///
/// Plan 18 C1: a reactive stream over the storage layer, not a one-shot
/// future — content appears live regardless of which path stored it (sync
/// pull, inbound push, background sync, own publish).

@ProviderFor(feed)
final feedProvider = FeedProvider._();

/// Reverse-chronological feed of kind=1 posts from own identity + active
/// follows. Posts with a kind=6 tombstone from the same author are excluded
/// at the storage layer.
///
/// Plan 18 C1: a reactive stream over the storage layer, not a one-shot
/// future — content appears live regardless of which path stored it (sync
/// pull, inbound push, background sync, own publish).

final class FeedProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Event>>,
          List<Event>,
          Stream<List<Event>>
        >
    with $FutureModifier<List<Event>>, $StreamProvider<List<Event>> {
  /// Reverse-chronological feed of kind=1 posts from own identity + active
  /// follows. Posts with a kind=6 tombstone from the same author are excluded
  /// at the storage layer.
  ///
  /// Plan 18 C1: a reactive stream over the storage layer, not a one-shot
  /// future — content appears live regardless of which path stored it (sync
  /// pull, inbound push, background sync, own publish).
  FeedProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'feedProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$feedHash();

  @$internal
  @override
  $StreamProviderElement<List<Event>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Event>> create(Ref ref) {
    return feed(ref);
  }
}

String _$feedHash() => r'8b0eb9a5d69fa0d3d3e94f6c2e2618ec0497985c';

/// Single event by id, used by the post-detail screen so it doesn't have
/// to re-query the whole feed.

@ProviderFor(eventById)
final eventByIdProvider = EventByIdFamily._();

/// Single event by id, used by the post-detail screen so it doesn't have
/// to re-query the whole feed.

final class EventByIdProvider
    extends $FunctionalProvider<AsyncValue<Event?>, Event?, FutureOr<Event?>>
    with $FutureModifier<Event?>, $FutureProvider<Event?> {
  /// Single event by id, used by the post-detail screen so it doesn't have
  /// to re-query the whole feed.
  EventByIdProvider._({
    required EventByIdFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'eventByIdProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$eventByIdHash();

  @override
  String toString() {
    return r'eventByIdProvider'
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
    return eventById(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is EventByIdProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$eventByIdHash() => r'1c419a1fe059310f471dc7ebe37dee164123713c';

/// Single event by id, used by the post-detail screen so it doesn't have
/// to re-query the whole feed.

final class EventByIdFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<Event?>, String> {
  EventByIdFamily._()
    : super(
        retry: null,
        name: r'eventByIdProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Single event by id, used by the post-detail screen so it doesn't have
  /// to re-query the whole feed.

  EventByIdProvider call(String id) =>
      EventByIdProvider._(argument: id, from: this);

  @override
  String toString() => r'eventByIdProvider';
}

/// Own posts (kind=1, deletes excluded) for the "You"-tab grid. Reactive.

@ProviderFor(ownPosts)
final ownPostsProvider = OwnPostsProvider._();

/// Own posts (kind=1, deletes excluded) for the "You"-tab grid. Reactive.

final class OwnPostsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Event>>,
          List<Event>,
          Stream<List<Event>>
        >
    with $FutureModifier<List<Event>>, $StreamProvider<List<Event>> {
  /// Own posts (kind=1, deletes excluded) for the "You"-tab grid. Reactive.
  OwnPostsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ownPostsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ownPostsHash();

  @$internal
  @override
  $StreamProviderElement<List<Event>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Event>> create(Ref ref) {
    return ownPosts(ref);
  }
}

String _$ownPostsHash() => r'7a42b0943dddb938f79c32501c497b087bf463b7';

/// Posts authored by a given pubkey, for other-profile grid. Reactive.

@ProviderFor(profilePosts)
final profilePostsProvider = ProfilePostsFamily._();

/// Posts authored by a given pubkey, for other-profile grid. Reactive.

final class ProfilePostsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Event>>,
          List<Event>,
          Stream<List<Event>>
        >
    with $FutureModifier<List<Event>>, $StreamProvider<List<Event>> {
  /// Posts authored by a given pubkey, for other-profile grid. Reactive.
  ProfilePostsProvider._({
    required ProfilePostsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'profilePostsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$profilePostsHash();

  @override
  String toString() {
    return r'profilePostsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<List<Event>> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<List<Event>> create(Ref ref) {
    final argument = this.argument as String;
    return profilePosts(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ProfilePostsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$profilePostsHash() => r'f8f15d7a962fc05f43d7e0fb49d7efe76ef3dae5';

/// Posts authored by a given pubkey, for other-profile grid. Reactive.

final class ProfilePostsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<Event>>, String> {
  ProfilePostsFamily._()
    : super(
        retry: null,
        name: r'profilePostsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Posts authored by a given pubkey, for other-profile grid. Reactive.

  ProfilePostsProvider call(String pubkey) =>
      ProfilePostsProvider._(argument: pubkey, from: this);

  @override
  String toString() => r'profilePostsProvider';
}
