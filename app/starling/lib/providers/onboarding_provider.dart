import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/crypto/crockford_base32.dart';
import '../services/storage/keychain_manager.dart';
import '../services/types.dart';
import 'identity_provider.dart';
import 'own_profile_provider.dart';
import 'profile_provider.dart';
import 'profile_service_provider.dart';
import 'service_providers.dart';

part 'onboarding_provider.g.dart';

/// Re-exported for callers (mainly tests) that still reference the
/// pre-Plan-12 constant. New code should use
/// `KeychainManager.identitySecretKeyName`.
const kSecretKeyStorageName = KeychainManager.identitySecretKeyName;

/// Transient session-level state built up during onboarding — the generated
/// recovery phrase that the user hasn't yet confirmed they've written down.
/// Cleared once they tap "I wrote it down" on the recovery screen.
class OnboardingSession {
  const OnboardingSession({this.recoveryPhrase});
  final List<String>? recoveryPhrase;

  OnboardingSession copyWith({List<String>? recoveryPhrase}) =>
      OnboardingSession(recoveryPhrase: recoveryPhrase ?? this.recoveryPhrase);
}

// keepAlive: the onboarding flow spans multiple screens (Setup → Recovery).
// Under Riverpod 3, autoDispose providers get torn down across async gaps
// in their notifier methods, which would invalidate `ref` mid-`createIdentity()`
// and lose the recovery phrase before the Recovery screen can read it.
@Riverpod(keepAlive: true)
class OnboardingController extends _$OnboardingController {
  @override
  OnboardingSession build() => const OnboardingSession();

  /// Generates keypair + feed key, derives recovery phrase, writes the identity
  /// row and stashes the secret key in secure storage. Returns the generated
  /// recovery phrase (also cached in session state so the Recovery screen can
  /// read it without re-deriving).
  Future<List<String>> createIdentity() async {
    final crypto = ref.read(cryptoServiceProvider);
    final storage = ref.read(storageServiceProvider);
    final clock = ref.read(clockProvider);

    // Read the name + avatar the user entered on Setup synchronously, before
    // any await — OnboardingProfileController is autoDispose and could be torn
    // down across the async gaps below.
    final onboardingProfile = ref.read(onboardingProfileControllerProvider);

    // Seed → keypair → phrase. Round-tripping through recoverFromPhrase keeps
    // the pubkey matched to what a future restore would derive.
    final seed = crypto.randomBytes(32);
    final phrase = await crypto.deriveRecoveryPhrase(seed);
    final keypair = await crypto.recoverFromPhrase(phrase);

    final feedKey = crypto.randomBytes(32);

    await _writeSecretKey(keypair.secretKey);

    final identity = Identity(
      pubkey: crockfordBase32Encode(keypair.publicKey),
      feedKey: feedKey,
      feedKeyEpoch: 0,
      createdAt: clock.nowUnixSeconds(),
    );
    await storage.saveIdentity(identity);

    // Persist the collected name + optional avatar as the first kind=2
    // profile event so the owner's profile isn't empty. publishProfile reads
    // the just-saved identity via storage. (On first run the content-key
    // service is still the mock binding — see main.dart — so this populates
    // the local "You" tab immediately; it's re-published with real crypto
    // from the edit screen after the next launch.)
    final displayName = onboardingProfile.displayName.trim();
    if (displayName.isNotEmpty) {
      try {
        await ref
            .read(profileServiceProvider)
            .publishProfile(
              displayName: displayName,
              bio: onboardingProfile.bio,
              avatarBytes: onboardingProfile.avatarBytes,
            );
      } catch (_) {
        // Non-fatal: the identity already exists; the profile can be set
        // later from the edit screen.
      }
      ref.read(onboardingProfileControllerProvider.notifier).reset();
    }

    state = state.copyWith(recoveryPhrase: phrase);
    ref.read(identityControllerProvider.notifier).refresh();
    ref.invalidate(ownProfileProvider);
    return phrase;
  }

  /// Restores an identity from a user-supplied 24-word recovery phrase. Writes
  /// the identity row + secret key. Throws if the phrase is invalid.
  Future<void> restoreIdentity(List<String> phrase) async {
    final crypto = ref.read(cryptoServiceProvider);
    final storage = ref.read(storageServiceProvider);
    final clock = ref.read(clockProvider);

    final keypair = await crypto.recoverFromPhrase(phrase);
    // No feed key survives the recovery phrase; start a fresh one.
    final feedKey = crypto.randomBytes(32);

    await _writeSecretKey(keypair.secretKey);

    final identity = Identity(
      pubkey: crockfordBase32Encode(keypair.publicKey),
      feedKey: feedKey,
      feedKeyEpoch: 0,
      createdAt: clock.nowUnixSeconds(),
    );
    await storage.saveIdentity(identity);
    ref.read(identityControllerProvider.notifier).refresh();
  }

  /// Clears the in-memory recovery phrase once the user has acknowledged it.
  void clearRecoveryPhrase() {
    state = const OnboardingSession();
  }

  /// Test-only: seeds the session with a phrase without running the full
  /// [createIdentity] flow (which needs real crypto + keychain).
  @visibleForTesting
  void debugSeedPhrase(List<String> phrase) {
    state = OnboardingSession(recoveryPhrase: phrase);
  }

  Future<void> _writeSecretKey(Uint8List secretKey) async {
    final keychain = KeychainManager();
    // Delete before write: on iOS the Keychain survives app uninstalls, and
    // SecItemUpdate matches on full attribute set — a leftover entry written
    // with different accessibility flags can cause the new write to silently
    // collide instead of overwrite, leaving a stale sk paired with a fresh
    // identity pubkey. An explicit delete + add side-steps the ambiguity.
    await keychain.delete(KeychainManager.identitySecretKeyName);
    await keychain.write(
      KeychainManager.identitySecretKeyName,
      base64Encode(secretKey),
    );
  }
}
