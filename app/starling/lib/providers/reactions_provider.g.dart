// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reactions_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Plan 18 C1: reactive — an inbound like (or unlike tombstone) from any
/// storage path re-emits without invalidation.

@ProviderFor(reactions)
final reactionsProvider = ReactionsFamily._();

/// Plan 18 C1: reactive — an inbound like (or unlike tombstone) from any
/// storage path re-emits without invalidation.

final class ReactionsProvider
    extends
        $FunctionalProvider<
          AsyncValue<ReactionSummary>,
          ReactionSummary,
          Stream<ReactionSummary>
        >
    with $FutureModifier<ReactionSummary>, $StreamProvider<ReactionSummary> {
  /// Plan 18 C1: reactive — an inbound like (or unlike tombstone) from any
  /// storage path re-emits without invalidation.
  ReactionsProvider._({
    required ReactionsFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'reactionsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$reactionsHash();

  @override
  String toString() {
    return r'reactionsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $StreamProviderElement<ReactionSummary> $createElement(
    $ProviderPointer pointer,
  ) => $StreamProviderElement(pointer);

  @override
  Stream<ReactionSummary> create(Ref ref) {
    final argument = this.argument as String;
    return reactions(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is ReactionsProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$reactionsHash() => r'3f0c6a09ad2c9d9f3565784608bca94c38427a39';

/// Plan 18 C1: reactive — an inbound like (or unlike tombstone) from any
/// storage path re-emits without invalidation.

final class ReactionsFamily extends $Family
    with $FunctionalFamilyOverride<Stream<ReactionSummary>, String> {
  ReactionsFamily._()
    : super(
        retry: null,
        name: r'reactionsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Plan 18 C1: reactive — an inbound like (or unlike tombstone) from any
  /// storage path re-emits without invalidation.

  ReactionsProvider call(String postId) =>
      ReactionsProvider._(argument: postId, from: this);

  @override
  String toString() => r'reactionsProvider';
}

@ProviderFor(ReactionController)
final reactionControllerProvider = ReactionControllerFamily._();

final class ReactionControllerProvider
    extends $NotifierProvider<ReactionController, void> {
  ReactionControllerProvider._({
    required ReactionControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'reactionControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$reactionControllerHash();

  @override
  String toString() {
    return r'reactionControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ReactionController create() => ReactionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReactionControllerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$reactionControllerHash() =>
    r'e62f573743ae5870ca12a68033def4b67a5627dd';

final class ReactionControllerFamily extends $Family
    with $ClassFamilyOverride<ReactionController, void, void, void, String> {
  ReactionControllerFamily._()
    : super(
        retry: null,
        name: r'reactionControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ReactionControllerProvider call(String postId) =>
      ReactionControllerProvider._(argument: postId, from: this);

  @override
  String toString() => r'reactionControllerProvider';
}

abstract class _$ReactionController extends $Notifier<void> {
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
