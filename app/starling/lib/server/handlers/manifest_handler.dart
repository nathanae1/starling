import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:shelf/shelf.dart';

import '../../services/crypto_service.dart';
import '../../services/storage_service.dart';
import '../../services/types.dart';
import '../../sync/manifest_ack.dart' show hexDecodeAckSig;
import '../../sync/sealed_delivery.dart';

/// `GET /manifest?since={ts}&until={ts}&requester_pubkey={pk}&ack_rotation_at={ts}`
///
/// Returns a CBOR map:
/// - `pubkey`: owner's pubkey
/// - `events`: list of `{id, created_at}` for the requested window
///   (newest-first by the underlying DAO's order)
/// - `has_older`: more events exist beyond the returned window
/// - `new_feed_key` *(optional, Plan 13)*: when `requester_pubkey` is an
///   accepted follower with an undelivered key rotation pending, the
///   latest wrapped payload is included as `{encrypted_feed_key, nonce,
///   created_at}`. The follower decrypts it with the X25519 DH shared key
///   derived against this device's pubkey, persists it as their
///   `follow.feedKey`, and acks via `ack_rotation_at` on the next request.
/// - `new_connection_card` *(optional, Plan 15)*: same flow for an updated
///   Connection card, sealed like `new_feed_key` (`{encrypted_card, nonce,
///   created_at}`) and acked via `card_seen_at`.
///
/// `has_older` paging: clients set `until = oldest.createdAt, until_id =
/// oldest.id` on the next call — the pair is a strict keyset cursor, so
/// same-second events truncated by the page limit are never skipped. Bare
/// `until` keeps the old inclusive semantics.
///
/// `requester_pubkey` is unauthenticated on LAN by design (Plan 09 makes
/// no auth claim for `/manifest`). A LAN attacker can request someone
/// else's pending payload but can't decrypt it without the follower's
/// secret key — the X25519 DH shared key derivation is what gates access.
/// Delivery acks are different: they *write* (mark distributions
/// delivered), so they require the `ack_sig` possession proof (S3a, see
/// `sync/manifest_ack.dart`) and are ignored without a valid one.
///
/// Plan 11a: the request-parsing/response-building split lets the libp2p
/// inbound stream handler (`Libp2pStreamServer`) reuse
/// [buildManifestResponseBytes] with CBOR-derived inputs.
Handler manifestHandler({
  required StorageService storage,
  required CryptoService crypto,
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
    final untilId = params['until_id'];
    final requesterPubkey = params['requester_pubkey'];
    final ackRotationAt = _parseInt(params['ack_rotation_at']);
    if (params.containsKey('ack_rotation_at') && ackRotationAt == null) {
      return Response(400, body: 'invalid ack_rotation_at');
    }
    final cardSeenAt = _parseInt(params['card_seen_at']);
    if (params.containsKey('card_seen_at') && cardSeenAt == null) {
      return Response(400, body: 'invalid card_seen_at');
    }
    Uint8List? ackSig;
    if (params.containsKey('ack_sig')) {
      ackSig = hexDecodeAckSig(params['ack_sig']!);
      if (ackSig == null) {
        return Response(400, body: 'invalid ack_sig');
      }
    }

    final body = await buildManifestResponseBytes(
      storage: storage,
      crypto: crypto,
      identity: identity,
      since: since,
      until: until,
      untilId: untilId,
      requesterPubkey: requesterPubkey,
      ackRotationAt: ackRotationAt,
      cardSeenAt: cardSeenAt,
      ackSig: ackSig,
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
  required CryptoService crypto,
  required Identity identity,
  int? since,
  int? until,
  String? untilId,
  String? requesterPubkey,
  int? ackRotationAt,
  int? cardSeenAt,
  Uint8List? ackSig,
  int pageLimit = 1000,
}) async {
  // Apply acks first so freshly-acked rows aren't re-attached below.
  // Requires the S3a possession proof — see applyDeliveryAcks.
  if (requesterPubkey != null) {
    await applyDeliveryAcks(
      crypto: crypto,
      storage: storage,
      identity: identity,
      requesterPubkey: requesterPubkey,
      ackRotationAt: ackRotationAt,
      cardSeenAt: cardSeenAt,
      ackSig: ackSig,
    );
  }

  final fetched = await storage.getEvents(
    pubkey: identity.pubkey,
    since: since,
    until: until,
    untilId: untilId,
    limit: pageLimit + 1,
  );
  final hasOlder = fetched.length > pageLimit;
  final events = hasOlder ? fetched.sublist(0, pageLimit) : fetched;

  final response = <String, dynamic>{
    'pubkey': identity.pubkey,
    'events': events
        .map((e) => <String, dynamic>{'id': e.id, 'created_at': e.createdAt})
        .toList(),
    'has_older': hasOlder,
  };

  // S4: pending payloads are only attached for *current* accepted
  // followers — the gate lives inside attachPendingDeliveries.
  if (requesterPubkey != null) {
    await attachPendingDeliveries(storage, requesterPubkey, response);
  }

  return Uint8List.fromList(cbor.encode(response));
}

int? _parseInt(String? raw) {
  if (raw == null) return null;
  return int.tryParse(raw);
}
