import 'dart:developer' as developer;

import '../models/envelope.dart';
import '../models/protocol_version.dart';
import '../services/follow_service.dart' show isFollowAcceptQueueEntry;
import '../services/lan_network_service.dart' show NetworkException;
import '../services/storage_service.dart';
import '../services/types.dart';
import 'sync_engine.dart';

/// Per-peer drop threshold for deliveries the peer actively REJECTED
/// (HTTP 4xx). After 3 rejections, remove the entry — the peer has likely
/// unfollowed. Transport-level failures (no response: socket errors,
/// timeouts) and 5xx do NOT count toward this; queued comments/likes wait
/// for connectivity instead of being burned by three Tor flaps (D9).
const int kOutboundMaxRetries = 3;

/// Drain queued events targeting [follow], pushing them in a single
/// envelope to [peer] via [transport.pushEvents]. Called by `SyncEngine`
/// at the tail of each peer's sync slot, after manifest+envelope pull.
///
/// On success: every queue row removed. On failure: each row's
/// `retry_count` is incremented; rows that reach `kOutboundMaxRetries`
/// are dropped. Counts as a single batch — partial-success is not modeled
/// because the receiver's POST /events is all-or-nothing per request.
Future<OutboundDrainResult> drainOutboundQueueForPeer({
  required StorageService storage,
  required SyncTransport transport,
  required Follow follow,
  required PeerConnection peer,
}) async {
  // The outbound queue is shared with follow-accept wrappers keyed by the
  // same pubkey (the follow retry pump owns those). Never ship them as
  // 'event' payloads — leave them queued untouched for the retry pump.
  final queued = (await storage.dequeue(follow.pubkey))
      .where((q) => !isFollowAcceptQueueEntry(q.eventBlob))
      .toList(growable: false);
  if (queued.isEmpty) {
    return const OutboundDrainResult(pushed: 0, dropped: 0, retried: 0);
  }

  final envelope = Envelope(
    version: kStarlingProtocolVersion,
    items: queued
        // Plan 17: rows carry an explicit `itemType` ('room-key'/'room-event');
        // null means a plain feed 'event' (all pre-Plan-17 rows). Ship each
        // row under its own type so chatroom fan-out rides this same queue.
        .map((q) => EnvelopeItem(type: q.itemType ?? 'event', payload: q.eventBlob))
        .toList(growable: false),
  );

  try {
    await transport.pushEnvelope(peer, envelope);
    for (final entry in queued) {
      await storage.removeFromQueue(entry.id);
    }
    return OutboundDrainResult(pushed: queued.length, dropped: 0, retried: 0);
  } catch (e) {
    developer.log(
      'pushEvents failed for ${follow.pubkey}: $e',
      name: 'outbound_drain',
    );
    final status = e is NetworkException ? e.statusCode : null;
    final rejected = status != null && status >= 400 && status < 500;
    if (!rejected) {
      // Transport-level failure or server error: the envelope may simply
      // not have arrived. Leave retry counts alone — these entries retry
      // on every future pass until a delivery is actually answered.
      return OutboundDrainResult(pushed: 0, dropped: 0, retried: queued.length);
    }
    var dropped = 0;
    var retried = 0;
    for (final entry in queued) {
      if (entry.retryCount + 1 >= kOutboundMaxRetries) {
        await storage.removeFromQueue(entry.id);
        dropped++;
        developer.log(
          'dropped after $kOutboundMaxRetries rejections: '
          'queue id=${entry.id} target=${entry.targetPubkey}',
          name: 'outbound_drain',
        );
      } else {
        await storage.incrementRetry(entry.id);
        retried++;
      }
    }
    return OutboundDrainResult(pushed: 0, dropped: dropped, retried: retried);
  }
}

class OutboundDrainResult {
  const OutboundDrainResult({
    required this.pushed,
    required this.dropped,
    required this.retried,
  });
  final int pushed;
  final int dropped;
  final int retried;
}
