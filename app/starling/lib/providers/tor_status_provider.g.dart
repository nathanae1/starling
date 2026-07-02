// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tor_status_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Live Tor status for the UI. `TorService.getStatus()` is a cheap
/// synchronous FFI read, but every consumer so far called it once per
/// build — a frozen snapshot. This polls it: fast (1 s) while
/// bootstrapping so "Connecting to network… N%" tracks progress, then a
/// slow tick (10 s) once ready because circuit count still changes.
/// Emits only when the status actually changes to avoid rebuild churn.
///
/// Deliberately auto-dispose, with the timer torn down on `onCancel`:
/// polling runs only while something displays the status, and widget
/// tests never end with a pending periodic timer.

@ProviderFor(TorStatusPoller)
final torStatusPollerProvider = TorStatusPollerProvider._();

/// Live Tor status for the UI. `TorService.getStatus()` is a cheap
/// synchronous FFI read, but every consumer so far called it once per
/// build — a frozen snapshot. This polls it: fast (1 s) while
/// bootstrapping so "Connecting to network… N%" tracks progress, then a
/// slow tick (10 s) once ready because circuit count still changes.
/// Emits only when the status actually changes to avoid rebuild churn.
///
/// Deliberately auto-dispose, with the timer torn down on `onCancel`:
/// polling runs only while something displays the status, and widget
/// tests never end with a pending periodic timer.
final class TorStatusPollerProvider
    extends $NotifierProvider<TorStatusPoller, TorStatus> {
  /// Live Tor status for the UI. `TorService.getStatus()` is a cheap
  /// synchronous FFI read, but every consumer so far called it once per
  /// build — a frozen snapshot. This polls it: fast (1 s) while
  /// bootstrapping so "Connecting to network… N%" tracks progress, then a
  /// slow tick (10 s) once ready because circuit count still changes.
  /// Emits only when the status actually changes to avoid rebuild churn.
  ///
  /// Deliberately auto-dispose, with the timer torn down on `onCancel`:
  /// polling runs only while something displays the status, and widget
  /// tests never end with a pending periodic timer.
  TorStatusPollerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'torStatusPollerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$torStatusPollerHash();

  @$internal
  @override
  TorStatusPoller create() => TorStatusPoller();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TorStatus value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TorStatus>(value),
    );
  }
}

String _$torStatusPollerHash() => r'76fd53933a6f5d6f8f06bb20c3841b41f4fd5be5';

/// Live Tor status for the UI. `TorService.getStatus()` is a cheap
/// synchronous FFI read, but every consumer so far called it once per
/// build — a frozen snapshot. This polls it: fast (1 s) while
/// bootstrapping so "Connecting to network… N%" tracks progress, then a
/// slow tick (10 s) once ready because circuit count still changes.
/// Emits only when the status actually changes to avoid rebuild churn.
///
/// Deliberately auto-dispose, with the timer torn down on `onCancel`:
/// polling runs only while something displays the status, and widget
/// tests never end with a pending periodic timer.

abstract class _$TorStatusPoller extends $Notifier<TorStatus> {
  TorStatus build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<TorStatus, TorStatus>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<TorStatus, TorStatus>,
              TorStatus,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}
