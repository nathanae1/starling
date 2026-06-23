import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// The desired foreground-service shape given the two independent intents that
/// drive it. Pure (no plugin/platform access) so it is unit-testable.
///
/// - `persistent` — the user enabled "background mode" in Settings → Network
///   (Plan 14): keep the process alive as a near-relay.
/// - `callActive` — a voice call is in progress (Plan 16): the mic must stay
///   captured even if the app is backgrounded, which on Android 14+ requires
///   the running service to advertise the `microphone` foreground type.
///
/// The service runs if either intent wants it; it advertises the microphone
/// type only while a call is active.
({bool running, bool mic}) desiredFgState({
  required bool persistent,
  required bool callActive,
}) =>
    (running: persistent || callActive, mic: callActive);

/// Plan 14 Phase C — opt-in Android foreground service.
///
/// The Starling foreground service exists to keep the Android process alive in
/// the background. A foreground notification prevents Android from suspending
/// the process, which means the main UI isolate's HTTP server, Tor onion
/// service, and mDNS registration all keep serving content to peers while
/// the app is in the background. This turns any phone into a near-relay
/// (Plan 14 design intent → Plan 15 builds on this).
///
/// Plan 16 layers a second reason to run on top: an active voice call needs
/// the `microphone` foreground type so call audio survives backgrounding on
/// Android 14+. Two intents — [setPersistentEnabled] (the Settings toggle) and
/// [setCallActive] (a live call) — feed a single [_reconcile] that owns the
/// start/stop/upgrade/downgrade decision (see [desiredFgState]), so the two
/// callers never race over the service's type set.
///
/// The [_NoopTaskHandler] does no work itself — the service notification
/// alone is what gates the OS lifecycle. The main isolate's
/// [LifecycleManager.onPause] checks [FlutterForegroundTask.isRunningService]
/// and short-circuits the teardown when the service is running.
///
/// iOS is a no-op for the whole feature: there is no equivalent persistent
/// foreground concept (Plan 14 Phase D explains the iOS warm-start path), and
/// backgrounded call audio is covered by `UIBackgroundModes: audio` instead.
class ForegroundServiceController {
  ForegroundServiceController._();

  static final ForegroundServiceController instance =
      ForegroundServiceController._();

  /// Has [init] been called this process. Safe to call multiple times.
  bool _initialized = false;

  /// Intent: the user enabled the always-on background service in Settings.
  bool _persistentEnabled = false;

  /// Intent: a voice call is currently active.
  bool _callActive = false;

  /// Whether the running FG service currently advertises the `microphone`
  /// service type. Tracks the live service shape so [_reconcile] knows when a
  /// stop-then-restart is needed (Android cannot change the type set in place).
  bool _microphoneActive = false;

  /// Serializes reconciles so two near-simultaneous intent changes (e.g. the
  /// Settings toggle and a call starting) can't interleave their
  /// stop/start plugin calls.
  Future<void> _reconcileChain = Future.value();

  /// Idempotent. Caller can invoke at app startup; no service is started
  /// until an intent ([setPersistentEnabled]/[setCallActive]) asks for one.
  void init() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'starling_foreground',
        channelName: 'Starling background mode',
        channelDescription:
            'Keeps Starling reachable to your friends while the app is in '
            'the background.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        // No sound or vibration — this is a status notification, not an alert.
        playSound: false,
        enableVibration: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Returns whether the FG service is currently running.
  Future<bool> isRunning() async {
    if (!Platform.isAndroid) return false;
    return FlutterForegroundTask.isRunningService;
  }

  /// Requests the runtime POST_NOTIFICATIONS permission needed on Android
  /// 13+. Returns true if the user grants it, false otherwise.
  Future<bool> ensureNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    final status = await FlutterForegroundTask.checkNotificationPermission();
    if (status == NotificationPermission.granted) return true;
    final result = await FlutterForegroundTask.requestNotificationPermission();
    return result == NotificationPermission.granted;
  }

  /// Settings → Network toggle (Plan 14). Returns whether the service is now
  /// running, so the toggle can surface a permission-denied message.
  Future<bool> setPersistentEnabled(bool enabled) {
    _persistentEnabled = enabled;
    return _reconcile();
  }

  /// Voice call lifecycle (Plan 16). Pass true when a call becomes active and
  /// false when it ends. While true the running service advertises the
  /// `microphone` type; when it ends the service downgrades to `dataSync`-only
  /// if the user enabled background mode, otherwise it stops.
  Future<void> setCallActive(bool active) async {
    _callActive = active;
    await _reconcile();
  }

  /// Drives the live service toward [desiredFgState] for the current intents.
  /// Reconciles are serialized via [_reconcileChain]; returns whether the
  /// service is running once this reconcile settles.
  Future<bool> _reconcile() {
    final next = _reconcileChain.then((_) => _applyDesired());
    // Don't let one failed reconcile poison the chain for the next caller.
    _reconcileChain = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<bool> _applyDesired() async {
    if (!Platform.isAndroid) return false;
    final desired =
        desiredFgState(persistent: _persistentEnabled, callActive: _callActive);
    final running = await FlutterForegroundTask.isRunningService;

    if (!desired.running) {
      if (running) {
        final result = await FlutterForegroundTask.stopService();
        developer.log(
          'foreground service stop result=$result',
          name: 'starling.fgservice',
        );
      }
      _microphoneActive = false;
      return false;
    }

    // We want the service running. If it already is and the type set matches,
    // there's nothing to do.
    if (running && _microphoneActive == desired.mic) return true;

    // Android can't change a running service's type set in place, so stop
    // first when the mic type needs to be added (upgrade) or removed
    // (downgrade after a call ends).
    if (running) {
      await FlutterForegroundTask.stopService();
    }

    if (!await ensureNotificationPermission()) {
      developer.log(
        'foreground service: POST_NOTIFICATIONS denied — cannot start',
        name: 'starling.fgservice',
      );
      _microphoneActive = false;
      return false;
    }

    init();
    final types = <ForegroundServiceTypes>[
      ForegroundServiceTypes.dataSync,
      if (desired.mic) ForegroundServiceTypes.microphone,
    ];
    final (title, text) = _notificationCopy(callActive: _callActive);
    final result = await FlutterForegroundTask.startService(
      serviceTypes: types,
      notificationTitle: title,
      notificationText: text,
      callback: startForegroundCallback,
    );

    if (result is ServiceRequestSuccess) {
      _microphoneActive = desired.mic;
      developer.log(
        'foreground service running (mic=${desired.mic})',
        name: 'starling.fgservice',
      );
      return true;
    }
    developer.log(
      'foreground service start failed: $result',
      name: 'starling.fgservice',
    );
    _microphoneActive = false;
    return false;
  }

  (String, String) _notificationCopy({required bool callActive}) {
    if (callActive) {
      return (
        'Starling — voice call',
        'Voice call in progress.',
      );
    }
    return (
      'Starling is running',
      'Your phone is reachable to your friends in the '
          'background. Disable in Settings → Network.',
    );
  }
}

/// Top-level entry point for the foreground service isolate. Must stay
/// top-level and `@pragma('vm:entry-point')` so it survives AOT
/// tree-shaking. The handler does nothing — its sole purpose is to satisfy
/// the package's requirement that a service have a registered handler.
@pragma('vm:entry-point')
void startForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_NoopTaskHandler());
}

class _NoopTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
