// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'compose_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Compose-screen scratch state. Lives across Compose → Preview → back-to-edit
/// so the photo and caption survive the sub-route push. Invalidate on modal
/// close (either ✕ or successful publish).
///
/// `keepAlive: true` so the state survives the transient gap between the ✕
/// icon popping Compose and any listener re-subscribing — and so that tests
/// that seed state via [ComposeController.debugSeedState] before the
/// widget tree mounts don't lose it to auto-dispose.

@ProviderFor(ComposeController)
final composeControllerProvider = ComposeControllerProvider._();

/// Compose-screen scratch state. Lives across Compose → Preview → back-to-edit
/// so the photo and caption survive the sub-route push. Invalidate on modal
/// close (either ✕ or successful publish).
///
/// `keepAlive: true` so the state survives the transient gap between the ✕
/// icon popping Compose and any listener re-subscribing — and so that tests
/// that seed state via [ComposeController.debugSeedState] before the
/// widget tree mounts don't lose it to auto-dispose.
final class ComposeControllerProvider
    extends $NotifierProvider<ComposeController, ComposeState> {
  /// Compose-screen scratch state. Lives across Compose → Preview → back-to-edit
  /// so the photo and caption survive the sub-route push. Invalidate on modal
  /// close (either ✕ or successful publish).
  ///
  /// `keepAlive: true` so the state survives the transient gap between the ✕
  /// icon popping Compose and any listener re-subscribing — and so that tests
  /// that seed state via [ComposeController.debugSeedState] before the
  /// widget tree mounts don't lose it to auto-dispose.
  ComposeControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'composeControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$composeControllerHash();

  @$internal
  @override
  ComposeController create() => ComposeController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ComposeState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ComposeState>(value),
    );
  }
}

String _$composeControllerHash() => r'b594e47439616fa902d304716adee424f2fda37d';

/// Compose-screen scratch state. Lives across Compose → Preview → back-to-edit
/// so the photo and caption survive the sub-route push. Invalidate on modal
/// close (either ✕ or successful publish).
///
/// `keepAlive: true` so the state survives the transient gap between the ✕
/// icon popping Compose and any listener re-subscribing — and so that tests
/// that seed state via [ComposeController.debugSeedState] before the
/// widget tree mounts don't lose it to auto-dispose.

abstract class _$ComposeController extends $Notifier<ComposeState> {
  ComposeState build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<ComposeState, ComposeState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ComposeState, ComposeState>,
              ComposeState,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
