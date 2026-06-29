import 'dart:typed_data';

import '../utils/debug_log.dart';
import '../services/media_service.dart';
import '../services/storage_service.dart';
import 'peer_connection_factory.dart';
import 'peer_reachability_monitor.dart';
import 'sync_engine.dart' show SyncTransport;

/// On-demand media pull. Used by `EncryptedImage` when the local cache
/// misses: ask the reachability monitor for the best transport to the
/// author's peer, fetch `/media/{hash}`, persist to disk, then let the
/// widget read it back via `MediaService`.
///
/// Returns the raw encrypted bytes on success, `null` if the author has no
/// reachable peer right now (caller decides whether to show a placeholder
/// or retry on the next sync). On HTTP failure, marks the chosen transport
/// unreachable so the next call routes around it.
class RemoteMediaFetcher {
  RemoteMediaFetcher({
    required SyncTransport transport,
    required MediaService mediaService,
    required StorageService storage,
    required PeerConnectionFactory peerFactory,
    required PeerReachabilityMonitor reachabilityMonitor,
  }) : _transport = transport,
       _mediaService = mediaService,
       _storage = storage,
       _peerFactory = peerFactory,
       _reachability = reachabilityMonitor;

  final SyncTransport _transport;
  final MediaService _mediaService;
  final StorageService _storage;
  final PeerConnectionFactory _peerFactory;
  final PeerReachabilityMonitor _reachability;

  /// Fetches and persists the encrypted blob for [hash] from a peer that
  /// owns [authorPubkey]. Returns the encrypted bytes; the caller can
  /// then read the plaintext through `MediaService.readPlaintext`.
  Future<Uint8List?> fetch(String hash, String authorPubkey) async {
    // Cache hit short-circuit. Verify the file is actually on disk —
    // a `CachedMedia` row can outlive its file (OS-side app-cache
    // eviction, partial retention, fresh install over old DB) and the
    // older "row exists → return null" path turned that into a forever-
    // MISS loop in `EncryptedImage`.
    final cached = await _storage.getMedia(hash);
    if (cached != null && await _mediaService.hasBlobOnDisk(hash)) {
      return null;
    }
    if (cached != null) {
      debugLog(
        'starling.fetch',
        'stale CachedMedia row for $hash (no file on disk) — re-fetching',
      );
      await _storage.deleteMedia(hash);
    }

    final connection = await _peerFactory.resolve(authorPubkey);
    if (connection == null) {
      debugLog(
        'starling.fetch',
        'no transport for media $hash from $authorPubkey',
      );
      return null;
    }

    debugLog(
      'starling.fetch',
      'attempting media $hash from $authorPubkey via '
          '${connection.transport.name} url=${connection.baseUrl}',
    );

    final Uint8List bytes;
    try {
      bytes = await _transport.fetchMedia(connection, hash);
    } catch (e) {
      debugLog(
        'starling.fetch',
        'media fetch failed for $hash from $authorPubkey via '
            '${connection.transport.name}: $e',
      );
      _reachability.markUnreachable(authorPubkey, connection.transport, e);
      return null;
    }

    debugLog(
      'starling.fetch',
      'media fetch OK $hash via ${connection.transport.name} '
          'bytes=${bytes.length}',
    );

    try {
      await _mediaService.storeReceivedBlob(hash, bytes);
    } catch (e) {
      debugLog('starling.fetch', 'media store failed for $hash: $e');
      return null;
    }
    return bytes;
  }
}
