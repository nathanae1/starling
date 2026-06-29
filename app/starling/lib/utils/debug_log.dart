import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Centralized, debug-only diagnostic logging.
///
/// In release builds the [kDebugMode] guard lets the tree-shaker drop the
/// body, so the verbose identity/crypto diagnostics that are useful during
/// development never reach production logs (Xcode console / `adb logcat`).
/// Every ad-hoc `print` / `developer.log` debug site routes through here so
/// the gating lives in exactly one place and can't be reintroduced piecemeal.
///
/// [tag] is the subsystem name (e.g. `starling.keys`, `starling.media`); it is
/// used as the `developer.log` name and as a `[tag]` prefix on stdout.
///
/// Callers should not log raw key material — use [shortFingerprint] for keys.
void debugLog(String tag, String msg) {
  if (!kDebugMode) return;
  developer.log(msg, name: tag);
  // ignore: avoid_print
  print('[$tag] $msg');
}

/// A safe-to-log fingerprint of [bytes]: the first 8 hex chars followed by an
/// ellipsis (e.g. `a1b2c3d4…`). Enough to correlate keys across log lines and
/// devices without ever putting full key material on screen.
String shortFingerprint(Uint8List bytes) {
  final hex = bytes
      .take(4)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '$hex…';
}
