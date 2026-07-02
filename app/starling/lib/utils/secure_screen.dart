import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Toggles Android's FLAG_SECURE for the current window — blocks
/// screenshots/screen recording and hides the app in the recents switcher.
/// No-op off Android: iOS has no equivalent flag (packages fake it with
/// unreliable obscuring hacks), so the phrase screens keep the copy-based
/// warning there.
class SecureScreen {
  static const _channel = MethodChannel('starling/secure_screen');

  static bool get _supported => !kIsWeb && Platform.isAndroid;

  /// Enable while a secret (the recovery phrase) is on screen.
  static Future<void> enable() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('enable');
    } catch (_) {
      // Best effort — the screen still renders its warning copy.
    }
  }

  /// Disable when the secret leaves the screen.
  static Future<void> disable() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('disable');
    } catch (_) {}
  }
}
