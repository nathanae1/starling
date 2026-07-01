import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

import '../../models/encrypted_event.dart';
import '../../models/envelope.dart';
import '../../services/clock.dart';
import '../../services/content_key_service.dart';
import '../../services/crypto_service.dart';
import '../../services/storage_service.dart';
import '../../services/types.dart';
import 'room_ingest.dart';

/// `POST /events` — receives a CBOR-encoded `Envelope` of pushed items from a
/// peer, applies each by type, and stores the result locally.
///
/// - `event` (feed): authenticated by feed-key possession — accepted only if
///   we follow the author (so we hold their feed key) and decryption (which
///   verifies the inner Ed25519 signature) succeeds.
/// - `room-key` / `room-event` (Plan 17): membership-scoped chatroom items.
///   Requires the local [crypto]/identity/secret key to unseal + decrypt; see
///   `room_ingest.dart`. Absent those (e.g. a context without the secret
///   key), they are preserved as unknown items for later processing.
///
/// The response is always 202 so we don't leak which pubkeys/rooms we know.
Handler eventsPushHandler({
  required StorageService storage,
  required ContentKeyService contentKey,
  required Clock clock,
  CryptoService? crypto,
  Future<Identity?> Function()? identityLookup,
  Future<Uint8List?> Function()? ownSecretKeyLookup,
}) {
  return (Request request) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in request.read()) {
      builder.add(chunk);
    }
    final bodyBytes = builder.toBytes();
    if (bodyBytes.isEmpty) {
      return Response(400, body: 'empty body');
    }

    final Envelope envelope;
    try {
      envelope = Envelope.fromBytes(bodyBytes);
    } catch (e) {
      return Response(400, body: 'invalid envelope cbor');
    }

    Identity? identity;
    Uint8List? ownSecretKey;
    if (crypto != null &&
        identityLookup != null &&
        ownSecretKeyLookup != null) {
      identity = await identityLookup();
      ownSecretKey = await ownSecretKeyLookup();
    }

    await ingestPushedEnvelope(
      storage: storage,
      contentKey: contentKey,
      clock: clock,
      envelope: envelope,
      crypto: crypto,
      identity: identity,
      ownSecretKey: ownSecretKey,
    );
    return Response(202, body: '');
  };
}

/// Pure envelope ingestion. Reused by `Libp2pStreamServer` so the libp2p path
/// applies the exact same rules as the HTTP path. When [crypto]/[identity]/
/// [ownSecretKey] are supplied, `room-key`/`room-event` items are ingested
/// (`room-key` first, so the key is available to decrypt same-envelope
/// messages); otherwise they are preserved as unknown items.
Future<void> ingestPushedEnvelope({
  required StorageService storage,
  required ContentKeyService contentKey,
  required Clock clock,
  required Envelope envelope,
  CryptoService? crypto,
  Identity? identity,
  Uint8List? ownSecretKey,
}) async {
  final canIngestRooms =
      crypto != null && identity != null && ownSecretKey != null;

  // Pass 1: room keys before room events, so a key sealed in this envelope is
  // available to decrypt messages that ride alongside it.
  if (canIngestRooms) {
    for (final item in envelope.items) {
      if (item.type != 'room-key') continue;
      await ingestRoomKeyItem(
        storage: storage,
        crypto: crypto,
        clock: clock,
        identity: identity,
        ownSecretKey: ownSecretKey,
        payload: item.payload,
      );
    }
  }

  var accepted = 0;
  var rejected = 0;
  for (final item in envelope.items) {
    switch (item.type) {
      case 'event':
        try {
          final encrypted = EncryptedEvent.fromBytes(item.payload);
          final follow = await storage.getFollow(encrypted.pubkey);
          if (follow == null) {
            rejected++;
            continue;
          }
          final decrypted = contentKey.decryptEvent(encrypted, follow.feedKey);
          final plain = decrypted.copyWith(msgSeq: encrypted.msgSeq);
          await storage.saveEvent(plain);
          accepted++;
        } catch (e) {
          developer.log(
            'rejected pushed event: $e',
            name: 'events_push_handler',
          );
          rejected++;
        }
      case 'room-key':
        // Handled in pass 1 when we can ingest; otherwise preserve.
        if (!canIngestRooms) {
          await _preserveUnknown(storage, clock, envelope, item);
        }
      case 'room-event':
        if (canIngestRooms) {
          await ingestRoomEventItem(
            storage: storage,
            contentKey: contentKey,
            clock: clock,
            identity: identity,
            payload: item.payload,
          );
        } else {
          await _preserveUnknown(storage, clock, envelope, item);
        }
      default:
        await _preserveUnknown(storage, clock, envelope, item);
    }
  }

  developer.log(
    'envelope ingested accepted=$accepted rejected=$rejected',
    name: 'events_push_handler',
  );
}

/// Forward-compat: store an item with an unrecognized (or currently
/// un-ingestable) type so a later plan can consume it.
Future<void> _preserveUnknown(
  StorageService storage,
  Clock clock,
  Envelope envelope,
  EnvelopeItem item,
) => storage.saveUnknownEnvelopeItem(
  UnknownEnvelopeItem(
    sourcePubkey: '',
    envelopeVersion: envelope.version,
    type: item.type,
    payload: item.payload,
    receivedAt: clock.nowUnixSeconds(),
  ),
);
