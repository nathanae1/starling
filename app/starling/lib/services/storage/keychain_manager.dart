import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../utils/debug_log.dart';

/// Centralized OS keychain access for secrets that must persist across app
/// launches but never leave the device. Two values live here:
///
///   * `starling_db_key` — 32-byte hex key passed to `PRAGMA key` for SQLCipher.
///   * `starling_secret_key` — base64 Ed25519 secret key for the local identity.
///
/// Both are read once at app launch (DB key in `main.dart`, identity key
/// when hydrating `PairwiseContentKeyService`). The chosen access control
/// allows the app to reach them after the device's first unlock following
/// a reboot — i.e. without prompting the user for biometrics on every
/// resume — while still keeping the values out of an iCloud/Google backup.
///
/// iOS: `IOSAccessibility.first_unlock_this_device` ⇒
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Available after
/// unlock, persists across reboots, never migrates to a new device.
///
/// Android: keystore-backed; no `setUserAuthenticationRequired(true)` so the
/// app can read at process launch without a biometric prompt. The data still
/// rides on the AES key minted in the Android Keystore.
class KeychainManager {
  KeychainManager({FlutterSecureStorage? storage})
    : _storage = storage ?? _defaultStorage();

  final FlutterSecureStorage _storage;

  static const String dbKeyName = 'starling_db_key';
  static const String identitySecretKeyName = 'starling_secret_key';

  static FlutterSecureStorage _defaultStorage() => const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      synchronizable: false,
    ),
    aOptions: AndroidOptions(),
  );

  Future<String?> read(String key) async {
    final value = await _storage.read(key: key);
    _log('read', key, present: value != null, len: value?.length);
    return value;
  }

  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
    _log('write', key, present: true, len: value.length);
  }

  Future<void> delete(String key) async {
    await _storage.delete(key: key);
    _log('delete', key, present: false);
  }

  Future<bool> contains(String key) => _storage.containsKey(key: key);

  /// The local identity's Ed25519 secret key, or null if none is stored.
  /// The canonical decode of [identitySecretKeyName] — every secret-key
  /// lookup (providers, boot, background sync) goes through here.
  Future<Uint8List?> loadIdentitySecretKey() async {
    final encoded = await read(identitySecretKeyName);
    if (encoded == null) return null;
    return Uint8List.fromList(base64Decode(encoded));
  }

  void _log(String op, String key, {required bool present, int? len}) {
    final lenPart = len == null ? '' : ' len=$len';
    debugLog('starling.keychain', 'op=$op name=$key present=$present$lenPart');
  }
}
