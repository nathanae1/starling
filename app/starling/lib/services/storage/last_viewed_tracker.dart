import 'dart:async';

import '../clock.dart';
import '../storage_service.dart';

/// Debounced "this event entered the feed viewport" recorder.
///
/// `last_viewed` feeds the retention grace period — recently viewed events
/// survive past the 30-day age cutoff. The exact timestamp doesn't matter
/// to the second, only that the event was viewed during this session.
/// We dedupe per-id within the session so repeated scroll passes don't
/// flood the DB with writes.
class LastViewedTracker {
  LastViewedTracker({required StorageService storage, required Clock clock})
    : _storage = storage,
      _clock = clock;

  final StorageService _storage;
  final Clock _clock;
  final Set<String> _sessionMarked = <String>{};

  /// Idempotent within a session. Safe to call from a widget's build —
  /// the storage write is fire-and-forget; failure to update is silent
  /// (worst case: the event ages out one cycle earlier).
  void markViewed(String eventId) {
    if (_sessionMarked.contains(eventId)) return;
    _sessionMarked.add(eventId);
    unawaited(_storage.setEventLastViewed(eventId, _clock.nowUnixSeconds()));
  }

  /// Test hook — drops the per-session memoization.
  void resetForTesting() {
    _sessionMarked.clear();
  }
}
