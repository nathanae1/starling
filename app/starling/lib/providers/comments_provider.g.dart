// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'comments_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Comments (kind=4) on the post identified by [postId], ordered ASC by
/// `created_at`, filtered to authors the local viewer follows or is
/// themselves. Tombstoned comments (kind=6 referencing the comment id by
/// the same author) are excluded.
///
/// Storage holds every received comment regardless of follow status — the
/// filter is at the read layer so following someone retroactively reveals
/// their old comments without a backfill.
///
/// Plan 18 C1: reactive — an inbound comment (sync pull or push) re-emits
/// without any invalidation. Tombstone writes also re-fire the stream (the
/// storage watch is table-granular), so deletes disappear live too.

@ProviderFor(comments)
final commentsProvider = CommentsFamily._();

/// Comments (kind=4) on the post identified by [postId], ordered ASC by
/// `created_at`, filtered to authors the local viewer follows or is
/// themselves. Tombstoned comments (kind=6 referencing the comment id by
/// the same author) are excluded.
///
/// Storage holds every received comment regardless of follow status — the
/// filter is at the read layer so following someone retroactively reveals
/// their old comments without a backfill.
///
/// Plan 18 C1: reactive — an inbound comment (sync pull or push) re-emits
/// without any invalidation. Tombstone writes also re-fire the stream (the
/// storage watch is table-granular), so deletes disappear live too.

final class CommentsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<Event>>,
          List<Event>,
          Stream<List<Event>>
        >
    with $FutureModifier<List<Event>>, $StreamProvider<List<Event>> {
  /// Comments (kind=4) on the post identified by [postId], ordered ASC by
  /// `created_at`, filtered to authors the local viewer follows or is
  /// themselves. Tombstoned comments (kind=6 referencing the comment id by
  /// the same author) are excluded.
  ///
  /// Storage holds every received comment regardless of follow status — the
  /// filter is at the read layer so following someone retroactively reveals
  /// their old comments without a backfill.
  ///
  /// Plan 18 C1: reactive — an inbound comment (sync pull or push) re-emits
  /// without any invalidation. Tombstone writes also re-fire the stream (the
  /// storage watch is table-granular), so deletes disappear live too.
  CommentsProvider._({
    required CommentsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'commentsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$commentsHash();

  @override
  String toString() {
    return r'commentsProvider'
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
    return comments(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is CommentsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$commentsHash() => r'c1584c9e49f5c78179ec94d0d3ae123f49399fd3';

/// Comments (kind=4) on the post identified by [postId], ordered ASC by
/// `created_at`, filtered to authors the local viewer follows or is
/// themselves. Tombstoned comments (kind=6 referencing the comment id by
/// the same author) are excluded.
///
/// Storage holds every received comment regardless of follow status — the
/// filter is at the read layer so following someone retroactively reveals
/// their old comments without a backfill.
///
/// Plan 18 C1: reactive — an inbound comment (sync pull or push) re-emits
/// without any invalidation. Tombstone writes also re-fire the stream (the
/// storage watch is table-granular), so deletes disappear live too.

final class CommentsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<List<Event>>, String> {
  CommentsFamily._()
    : super(
        retry: null,
        name: r'commentsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Comments (kind=4) on the post identified by [postId], ordered ASC by
  /// `created_at`, filtered to authors the local viewer follows or is
  /// themselves. Tombstoned comments (kind=6 referencing the comment id by
  /// the same author) are excluded.
  ///
  /// Storage holds every received comment regardless of follow status — the
  /// filter is at the read layer so following someone retroactively reveals
  /// their old comments without a backfill.
  ///
  /// Plan 18 C1: reactive — an inbound comment (sync pull or push) re-emits
  /// without any invalidation. Tombstone writes also re-fire the stream (the
  /// storage watch is table-granular), so deletes disappear live too.

  CommentsProvider call(String postId) =>
      CommentsProvider._(argument: postId, from: this);

  @override
  String toString() => r'commentsProvider';
}

/// Create / delete a comment on [postId]. Invalidates [commentsProvider]
/// for the same post on every successful action so the post detail
/// screen rebuilds.

@ProviderFor(CommentController)
final commentControllerProvider = CommentControllerFamily._();

/// Create / delete a comment on [postId]. Invalidates [commentsProvider]
/// for the same post on every successful action so the post detail
/// screen rebuilds.
final class CommentControllerProvider
    extends $NotifierProvider<CommentController, void> {
  /// Create / delete a comment on [postId]. Invalidates [commentsProvider]
  /// for the same post on every successful action so the post detail
  /// screen rebuilds.
  CommentControllerProvider._({
    required CommentControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'commentControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$commentControllerHash();

  @override
  String toString() {
    return r'commentControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  CommentController create() => CommentController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is CommentControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$commentControllerHash() => r'59ed1fec8e92bef756f69fff3a37befa8d9bc03a';

/// Create / delete a comment on [postId]. Invalidates [commentsProvider]
/// for the same post on every successful action so the post detail
/// screen rebuilds.

final class CommentControllerFamily extends $Family
    with $ClassFamilyOverride<CommentController, void, void, void, String> {
  CommentControllerFamily._()
    : super(
        retry: null,
        name: r'commentControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Create / delete a comment on [postId]. Invalidates [commentsProvider]
  /// for the same post on every successful action so the post detail
  /// screen rebuilds.

  CommentControllerProvider call(String postId) =>
      CommentControllerProvider._(argument: postId, from: this);

  @override
  String toString() => r'commentControllerProvider';
}

/// Create / delete a comment on [postId]. Invalidates [commentsProvider]
/// for the same post on every successful action so the post detail
/// screen rebuilds.

abstract class _$CommentController extends $Notifier<void> {
  late final _$args = ref.$arg as String;
  String get postId => _$args;

  void build(String postId);
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
