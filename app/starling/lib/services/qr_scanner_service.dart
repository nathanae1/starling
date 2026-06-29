import 'package:flutter/services.dart';

/// Bespoke QR scanner backed by AVFoundation on iOS and CameraX + ZXing
/// on Android. See Plan 08 for the rationale behind avoiding mobile_scanner
/// (Google ML Kit / Play Services dependency + arm64-sim gap).
abstract class QrScannerService {
  /// Requests camera permission and starts the capture session. Throws a
  /// [QrScannerException] with `code = 'permission-denied'` if the user
  /// rejects the prompt.
  Future<void> start();

  /// Stops capture and releases the camera. Safe to call when not running.
  Future<void> stop();

  /// Stream of decoded QR payload strings. The native side de-duplicates
  /// rapid repeated scans so consumers get one event per "fresh" code.
  Stream<String> get scans;

  /// PlatformView type registered by the native plugin. Hosted via
  /// `UiKitView` / `AndroidView`.
  String get platformViewType;
}

class QrScannerException implements Exception {
  const QrScannerException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'QrScannerException($code): $message';
}

/// Method-channel-backed default. Channel name + EventChannel name are kept
/// in sync with the iOS Swift plugin and the Android Kotlin plugin.
class MethodChannelQrScannerService implements QrScannerService {
  MethodChannelQrScannerService();

  static const _methodChannel = MethodChannel('dev.starling.qr_scanner');
  static const _eventChannel = EventChannel('dev.starling.qr_scanner/scans');

  Stream<String>? _scans;

  @override
  Future<void> start() async {
    try {
      await _methodChannel.invokeMethod<void>('start');
    } on PlatformException catch (e) {
      throw QrScannerException(e.code, e.message ?? 'scanner start failed');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _methodChannel.invokeMethod<void>('stop');
    } on PlatformException catch (e) {
      throw QrScannerException(e.code, e.message ?? 'scanner stop failed');
    }
  }

  @override
  Stream<String> get scans =>
      _scans ??= _eventChannel.receiveBroadcastStream().cast<String>();

  @override
  String get platformViewType => 'dev.starling.qr_scanner_view';
}
