import 'package:shelf/shelf.dart';

import '../../models/envelope.dart';
import '../../models/protocol_version.dart';
import '../../services/content_key_service.dart';
import '../../services/storage_service.dart';
import '../../services/types.dart';

/// `GET /events?since={ts}` — CBOR `Envelope` of `EnvelopeItem(type:'event')`.
///
/// Returns:
///   1. The owner's own events (kind=1 posts, kind=4 outgoing comments,
///      kind=5 likes, kind=6 deletes/unlikes).
///   2. Events from others whose `ref` points to one of the owner's events
///      (received comments / likes / tombstones on own posts, pushed via
///      `POST /events` from followers — see Plan 10 re-distribution).
///
/// Own events authored after the schema-v2 migration ship as the original
/// wire-format `EncryptedEvent` bytes captured at author time — the only
/// way to keep the per-message AEAD key aligned with the media blobs that
/// were encrypted under that same author-time `msgSeq`. Re-distributed
/// third-party events (and own events from before the migration) are
/// re-encrypted on the fly under the owner's current chain root with a
/// fresh `msgSeq`. The receiver derives the event id from the inner
/// signed `Event` and verifies the inner Ed25519 signature.
Handler eventsHandler({
  required StorageService storage,
  required ContentKeyService contentKey,
  required Future<Identity?> Function() identityLookup,
  int pageLimit = 500,
}) {
  return (Request request) async {
    final identity = await identityLookup();
    if (identity == null) {
      return Response(503, body: 'not ready');
    }
    final params = request.url.queryParameters;
    int? since;
    if (params.containsKey('since')) {
      since = int.tryParse(params['since']!);
      if (since == null) {
        return Response(400, body: 'invalid since');
      }
    }
    final envelope = await buildEventsEnvelope(
      storage: storage,
      contentKey: contentKey,
      identity: identity,
      since: since,
      pageLimit: pageLimit,
    );
    return Response.ok(
      envelope.toBytes(),
      headers: const {'content-type': 'application/cbor'},
    );
  };
}

/// Pure envelope build for `/events` / `/starling/sync/events/1`. Persists
/// the bumped `msgSeqCounter` if any fallback re-encryptions ran.
Future<Envelope> buildEventsEnvelope({
  required StorageService storage,
  required ContentKeyService contentKey,
  required Identity identity,
  int? since,
  int pageLimit = 500,
}) async {
  final events =
      (await storage.getOwnAndIncomingRefs(
            identity.pubkey,
            since: since,
            limit: pageLimit,
          ))
          // Defense-in-depth: the DAO already excludes chatroom kinds (100-103)
          // from this seam; never re-encrypt a room event under the feed key and
          // serve it to followers.
          .where((e) => !e.kind.isRoomScoped)
          .toList();
  // For each event row, prefer the persisted wire-EncryptedEvent
  // captured at author time — that's the only encryption whose msgSeq
  // matches the media blobs on disk. Fall back to on-the-fly re-encrypt
  // for re-distributed third-party events (no media) and for own events
  // from before the v2 migration (no stored payload). The fresh-msgSeq
  // counter only advances when the fallback fires.
  var nextSeq = identity.msgSeqCounter;
  final items = <EnvelopeItem>[];
  for (final event in events) {
    if (event.pubkey == identity.pubkey) {
      final stored = await storage.getEncryptedPayload(event.id);
      if (stored != null) {
        items.add(EnvelopeItem(type: 'event', payload: stored));
        continue;
      }
    }
    final msgSeq = nextSeq++;
    final encrypted = contentKey.encryptEvent(
      event,
      identity.feedKey,
      identity.feedKeyEpoch,
      msgSeq,
    );
    items.add(EnvelopeItem(type: 'event', payload: encrypted.toBytes()));
  }
  if (nextSeq != identity.msgSeqCounter) {
    await storage.saveIdentity(identity.copyWith(msgSeqCounter: nextSeq));
  }
  return Envelope(version: kStarlingProtocolVersion, items: items);
}
