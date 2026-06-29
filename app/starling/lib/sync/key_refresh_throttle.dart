import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers/service_providers.dart';
import '../services/clock.dart';

part 'key_refresh_throttle.g.dart';

/// Per-peer cooldown gate for on-demand feed-key refreshes.
///
/// Both decrypt-failure recovery in `EncryptedImage` and the manual
/// "refresh" in `ConnectionSettingsScreen` may want to trigger a one-shot
/// per-peer sync to pull a pending rotation. Without throttling, a screen
/// scrolling through many media items from one peer would fire dozens of
/// redundant manifest calls in rapid succession; a peer whose identity
/// is genuinely gone would also burn requests forever.
///
/// The throttle keeps an in-memory map of `pubkey -> last attempt time`
/// and refuses re-entry within [cooldown]. Process-local — restart
/// resets the budget.
class KeyRefreshThrottle {
  KeyRefreshThrottle({
    required Clock clock,
    Duration cooldown = const Duration(seconds: 60),
  }) : _clock = clock,
       _cooldown = cooldown;

  final Clock _clock;
  final Duration _cooldown;
  final Map<String, int> _lastAttemptByPubkey = {};

  /// Returns true if this caller should proceed with a refresh attempt
  /// for [pubkey], and stamps the attempt time. Returns false if a
  /// previous attempt is still within the cooldown window.
  bool tryAcquire(String pubkey) {
    final now = _clock.nowUnixSeconds();
    final last = _lastAttemptByPubkey[pubkey];
    if (last != null && now - last < _cooldown.inSeconds) {
      return false;
    }
    _lastAttemptByPubkey[pubkey] = now;
    return true;
  }

  /// Forgets all attempts. Tests only.
  void resetForTesting() => _lastAttemptByPubkey.clear();
}

/// App-wide singleton. Shared by EncryptedImage and the connection
/// settings refresh so a tile-level button-mash doesn't bypass the
/// widget-level cooldown (or vice versa).
@Riverpod(keepAlive: true)
KeyRefreshThrottle keyRefreshThrottle(Ref ref) {
  return KeyRefreshThrottle(clock: ref.watch(clockProvider));
}
