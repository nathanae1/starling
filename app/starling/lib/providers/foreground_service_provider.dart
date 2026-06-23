import 'dart:async';
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/background/foreground_service_controller.dart';

part 'foreground_service_provider.g.dart';

/// Plan 14 Phase C — UI-facing state for the Android foreground service.
/// Polls [FlutterForegroundTask.isRunningService] on a slow interval; the
/// settings toggle reads `.running` and calls `.toggle` to flip it.
@Riverpod(keepAlive: true)
class ForegroundServiceState extends _$ForegroundServiceState {
  Timer? _pollTimer;

  @override
  Future<bool> build() async {
    if (!Platform.isAndroid) return false;
    _pollTimer ??= Timer.periodic(const Duration(seconds: 5), (_) async {
      final running = await ForegroundServiceController.instance.isRunning();
      if (state.value != running) state = AsyncData(running);
    });
    ref.onDispose(() {
      _pollTimer?.cancel();
      _pollTimer = null;
    });
    return ForegroundServiceController.instance.isRunning();
  }

  /// Returns true when the service is now running, false otherwise. The
  /// caller (settings toggle) can surface a permission-denied message if
  /// this returns false after a request to enable.
  Future<bool> setEnabled(bool enabled) async {
    if (!Platform.isAndroid) return false;
    if (enabled) {
      final ok = await ForegroundServiceController.instance
          .setPersistentEnabled(true);
      state = AsyncData(ok);
      return ok;
    } else {
      // Reconciles to stopped only if no call is keeping the service alive.
      final running = await ForegroundServiceController.instance
          .setPersistentEnabled(false);
      state = AsyncData(running);
      return false;
    }
  }
}
