import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:shelf/shelf.dart';

import '../../services/storage_service.dart';
import '../../services/types.dart';

/// `GET /manifest?since={ts}&until={ts}&requester_pubkey={pk}&ack_rotation_at={ts}`
///
/// Returns a CBOR map:
/// - `pubkey`: owner's pubkey
/// - `events`: list of `{id, created_at}` for the requested window
///   (newest-first by the underlying DAO's order)
/// - `has_older`: more events exist beyond the returned window
/// - `new_feed_key` *(optional, Plan 13)*: when `requester_pubkey` is set
///   and there's an undelivered key rotation pending for that follower,
///   the latest wrapped payload is included as `{encrypted_feed_key,
///   nonce, created_at}`. The follower decrypts it with the X25519 DH
///   shared key derived against this device's pubkey, persists it as
///   their `follow.feedKey`, and acks via `ack_rotation_at` on the next
///   request.
///
/// `has_older` paging works as before: clients set `until = oldest.createdAt
/// - 1` on the next call.
///
/// `requester_pubkey` is unauthenticated on LAN by design (Plan 09 makes
/// no auth claim for `/manifest`). A LAN attacker can request someone
/// else's pending payload but can't decrypt it without the follower's
/// secret key — the X25519 DH shared key derivation is what gates access.
///
/// Plan 11a: the request-parsing/response-building split lets the libp2p
/// inbound stream handler (`Libp2pStreamServer`) reuse
/// [buildManifestResponseBytes] with CBOR-derived inputs.
Handler manifestHandler({
  required StorageService storage,
  required Future<Identity?> Function() identityLookup,
  int pageLimit = 1000,
}) {
  return (Request request) async {
    final identity = await identityLookup();
    if (identity == null) {
      return Response(503, body: 'not ready');
    }
    final params = request.url.queryParameters;
    final since = _parseInt(params['since']);
    final until = _parseInt(params['until']);
    if (params.containsKey('since') && since == null) {
      return Response(400, body: 'invalid since');
    }
    if (params.containsKey('until') && until == null) {
      return Response(400, body: 'invalid until');
    }
    final requesterPubkey = params['requester_pubkey'];
    final ackRotationAt = _parseInt(params['ack_rotation_at']);
    if (params.containsKey('ack_rotation_at') && ackRotationAt == null) {
      return Response(400, body: 'invalid ack_rotation_at');
    }
    final cardSeenAt = _parseInt(params['card_seen_at']);
    if (params.containsKey('card_seen_at') && cardSeenAt == null) {
      return Response(400, body: 'invalid card_seen_at');
    }

    final body = await buildManifestResponseBytes(
      storage: storage,
      identity: identity,
      since: since,
      until: until,
      requesterPubkey: requesterPubkey,
      ackRotationAt: ackRotationAt,
      cardSeenAt: cardSeenAt,
      pageLimit: pageLimit,
    );
    return Response.ok(
      body,
      headers: const {'content-type': 'application/cbor'},
    );
  };
}

/// Pure manifest computation. Reused by the libp2p stream server so the
/// CBOR wire format stays byte-identical to the HTTP path.
Future<Uint8List> buildManifestResponseBytes({
  required StorageService storage,
  required Identity identity,
  int? since,
  int? until,
  String? requesterPubkey,
  int? ackRotationAt,
  int? cardSeenAt,
  int pageLimit = 1000,
}) async {
  // Apply acks first so freshly-acked rows aren't re-attached below.
  if (requesterPubkey != null && ackRotationAt != null) {
    await storage.markDistributionsDelivered(
      requesterPubkey,
      ackRotationAt,
    );
  }
  if (requesterPubkey != null && cardSeenAt != null) {
    await storage.markCardDistributionsDelivered(
      requesterPubkey,
      cardSeenAt,
    );
  }

  final fetched = await storage.getEvents(
    pubkey: identity.pubkey,
    since: since,
    until: until,
    limit: pageLimit + 1,
  );
  final hasOlder = fetched.length > pageLimit;
  final events = hasOlder ? fetched.sublist(0, pageLimit) : fetched;

  final response = <String, dynamic>{
    'pubkey': identity.pubkey,
    'events': events
        .map((e) => <String, dynamic>{
              'id': e.id,
              'created_at': e.createdAt,
            })
        .toList(),
    'has_older': hasOlder,
  };

  if (requesterPubkey != null) {
    final pending =
        await storage.latestPendingDistributionFor(requesterPubkey);
    if (pending != null) {
      response['new_feed_key'] = <String, dynamic>{
        'encrypted_feed_key': pending.encryptedFeedKey,
        'nonce': pending.nonce,
        'created_at': pending.createdAt,
      };
    }
    final pendingCard = await storage.latestPendingCardFor(requesterPubkey);
    if (pendingCard != null) {
      response['new_connection_card'] = <String, dynamic>{
        'card_cbor': pendingCard.cardCbor,
        'sig': pendingCard.sig,
        'created_at': pendingCard.createdAt,
      };
    }
  }

  return Uint8List.fromList(cbor.encode(response));
}

int? _parseInt(String? raw) {
  if (raw == null) return null;
  return int.tryParse(raw);
}
