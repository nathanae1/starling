import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/services.dart';

import 'background_sync_runner.dart';

/// Plan 14 Phase D — Dart side of the iOS background-sync method channel.
///
/// `AppDelegate.swift` registers `BGAppRefreshTask` (LAN-only, ~30s budget)
/// and `BGProcessingTask` (Tor-allowed, plugged-in-and-idle window) handlers
/// with `BGTaskScheduler`. When iOS fires one, the Swift side invokes
/// `runBackgroundSync` on this channel with an `allowTor` flag. The
/// `applicationWillResignActive` lifecycle callback also invokes
/// `refreshTorDirectory` so the next BGProcessingTask wake finds fresh
/// consensus on disk.
///
/// Initialize from the main isolate's startup (e.g.
/// [LifecycleManager.start]). The channel handler stays installed for the
/// lifetime of the process.
class IosBackgroundHandler {
  IosBackgroundHandler._();

  static final IosBackgroundHandler instance = IosBackgroundHandler._();

  static const MethodChannel _channel = MethodChannel(
    'dev.starling.app/background_sync',
  );

  bool _installed = false;

  void install() {
    if (!Platform.isIOS) return;
    if (_installed) return;
    _installed = true;
    _channel.setMethodCallHandler(_onMethodCall);
    developer.log('iOS background channel installed', name: 'starling.bgsync');
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'runBackgroundSync':
        final allowTor =
            (call.arguments as Map?)?['allowTor'] as bool? ?? false;
        developer.log(
          'iOS BGTask invoked allowTor=$allowTor',
          name: 'starling.bgsync',
        );
        final outcome = await BackgroundSyncRunner.run(allowTor: allowTor);
        switch (outcome) {
          case BackgroundSyncOutcome.ok:
          case BackgroundSyncOutcome.noIdentity:
            return true;
          case BackgroundSyncOutcome.failed:
            return false;
        }
      case 'refreshTorDirectory':
        // Hook for "pre-refresh Arti's consensus before iOS suspends us."
        // No-op by design with arti-client 0.34 — its `tor-dirmgr` already
        // refreshes the consensus on a background schedule while the
        // client is alive, and the on-disk cache is persisted as it goes.
        // There is no public "flush state to disk now" API to invoke.
        // The hook stays so a future Arti release with an explicit
        // refresh/flush primitive can fill it in without touching the
        // Swift side.
        developer.log(
          'refreshTorDirectory: dirmgr handles refresh automatically — no-op',
          name: 'starling.bgsync',
        );
        return null;
      default:
        throw MissingPluginException(
          'unknown iOS background channel method: ${call.method}',
        );
    }
  }
}
