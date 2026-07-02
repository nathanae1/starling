import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/types.dart';
import 'service_providers.dart';

part 'tor_status_provider.g.dart';

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
@riverpod
class TorStatusPoller extends _$TorStatusPoller {
  Timer? _timer;

  // Mirrors `state.isReady`; lifecycle callbacks (onResume) may not touch
  // `state`/`ref`, so the reschedule path reads this field instead.
  bool _lastReady = false;

  @override
  TorStatus build() {
    ref.onCancel(_stop);
    ref.onResume(() => _schedule(ready: _lastReady));
    ref.onDispose(_stop);
    final status = ref.watch(torServiceProvider).getStatus();
    _lastReady = status.isReady;
    _schedule(ready: status.isReady);
    return status;
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _schedule({required bool ready}) {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: ready ? 10 : 1), (_) => _poll());
  }

  void _poll() {
    final next = ref.read(torServiceProvider).getStatus();
    final readinessFlipped = next.isReady != _lastReady;
    _lastReady = next.isReady;
    if (next != state) state = next;
    if (readinessFlipped) _schedule(ready: next.isReady);
  }
}
