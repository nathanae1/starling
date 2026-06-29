import 'dart:async';
import 'dart:developer' as developer;

/// Foreground-only periodic pump that calls [runSync] every [interval].
/// Mirrors `FollowRetryPump`: a single in-flight tick is enforced via the
/// `_running` guard so sync runs that overflow the interval don't stack.
class SyncPump {
  SyncPump({required this.runSync, this.interval = const Duration(minutes: 1)});

  final Future<void> Function() runSync;
  final Duration interval;

  Timer? _timer;
  bool _running = false;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => _tick());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_running) return;
    _running = true;
    try {
      await runSync();
    } catch (e) {
      developer.log('sync tick failed: $e', name: 'sync_pump');
    } finally {
      _running = false;
    }
  }
}
