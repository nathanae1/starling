import 'dart:io';

import 'package:path/path.dart' as p;

import '../media/encrypted_media_paths.dart';
import '../storage_service.dart';

/// Default retention bounds. Tunable via constructor for tests.
class RetentionPolicy {
  const RetentionPolicy({
    this.maxAgeSeconds = 30 * 24 * 60 * 60,
    this.graceLastViewedSeconds = 7 * 24 * 60 * 60,
    this.maxMediaBytes = 2 * 1024 * 1024 * 1024,
    this.maxVoiceRoomAgeSeconds = 7 * 24 * 60 * 60,
  });

  /// Events older than this and not pinned/own/saved/recently-viewed are
  /// evicted. Default: 30 days.
  final int maxAgeSeconds;

  /// `last_viewed` within this many seconds of now keeps the event alive
  /// past [maxAgeSeconds]. Default: 7 days.
  final int graceLastViewedSeconds;

  /// Total non-pinned media-cache size cap. Default: 2 GB.
  final int maxMediaBytes;

  /// Voice-room history rows older than this are pruned. Default: 7 days.
  final int maxVoiceRoomAgeSeconds;
}

class RetentionResult {
  const RetentionResult({
    required this.eventsEvicted,
    required this.mediaEvicted,
    this.voiceRoomsEvicted = 0,
  });

  final int eventsEvicted;
  final int mediaEvicted;
  final int voiceRoomsEvicted;
}

/// Run-once-per-launch retention pass.
///
/// Composes the three pieces:
///   1. Events older than the policy window with no recent `last_viewed`
///      get deleted (own + saved are immune).
///   2. The pin set — media hashes referenced by `is_saved=1` or `is_own=1`
///      events — is computed against the survivors.
///   3. Non-pinned media cache is evicted oldest-first by `lastAccessed`
///      until under the size cap. Underlying files on disk are removed.
///
/// Order matters: events are evicted first so any media that was *only*
/// referenced by an evicted (foreign, unsaved, expired) event becomes
/// eligible for eviction in the same pass.
class RetentionService {
  RetentionService({
    required StorageService storage,
    required Directory mediaRoot,
    RetentionPolicy policy = const RetentionPolicy(),
  })  : _storage = storage,
        _mediaRoot = mediaRoot,
        _policy = policy;

  final StorageService _storage;
  final Directory _mediaRoot;
  final RetentionPolicy _policy;

  Future<RetentionResult> run() async {
    final events = await _storage.evictOldEvents(
      _policy.maxAgeSeconds,
      _policy.graceLastViewedSeconds,
    );

    final pinned = await _storage.getPinnedMediaHashes();
    final removed = await _storage.evictMediaExcluding(
      _policy.maxMediaBytes,
      pinned,
    );

    for (final entry in removed) {
      await _deleteMediaFile(entry.hash);
    }

    final voiceRooms =
        await _storage.evictOldVoiceRooms(_policy.maxVoiceRoomAgeSeconds);

    return RetentionResult(
      eventsEvicted: events,
      mediaEvicted: removed.length,
      voiceRoomsEvicted: voiceRooms,
    );
  }

  Future<void> _deleteMediaFile(String hexHash) async {
    try {
      final file = File(p.join(_mediaRoot.path, mediaRelativePath(hexHash)));
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (_) {
      // Best-effort cleanup; a missing or in-use file shouldn't block the
      // rest of the eviction pass.
    }
  }
}
