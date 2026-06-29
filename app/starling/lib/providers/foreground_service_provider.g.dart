// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'foreground_service_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Plan 14 Phase C — UI-facing state for the Android foreground service.
/// Polls [FlutterForegroundTask.isRunningService] on a slow interval; the
/// settings toggle reads `.running` and calls `.toggle` to flip it.

@ProviderFor(ForegroundServiceState)
final foregroundServiceStateProvider = ForegroundServiceStateProvider._();

/// Plan 14 Phase C — UI-facing state for the Android foreground service.
/// Polls [FlutterForegroundTask.isRunningService] on a slow interval; the
/// settings toggle reads `.running` and calls `.toggle` to flip it.
final class ForegroundServiceStateProvider
    extends $AsyncNotifierProvider<ForegroundServiceState, bool> {
  /// Plan 14 Phase C — UI-facing state for the Android foreground service.
  /// Polls [FlutterForegroundTask.isRunningService] on a slow interval; the
  /// settings toggle reads `.running` and calls `.toggle` to flip it.
  ForegroundServiceStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'foregroundServiceStateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$foregroundServiceStateHash();

  @$internal
  @override
  ForegroundServiceState create() => ForegroundServiceState();
}

String _$foregroundServiceStateHash() =>
    r'b76b41ba0c2843f35f055874b9d39e34bc8d2d76';

/// Plan 14 Phase C — UI-facing state for the Android foreground service.
/// Polls [FlutterForegroundTask.isRunningService] on a slow interval; the
/// settings toggle reads `.running` and calls `.toggle` to flip it.

abstract class _$ForegroundServiceState extends $AsyncNotifier<bool> {
  FutureOr<bool> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<bool>, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<bool>, bool>,
              AsyncValue<bool>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
