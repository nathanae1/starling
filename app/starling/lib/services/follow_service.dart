import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:http/http.dart' as http;

import '../models/connection_card.dart';
import '../sync/peer_reachability_monitor.dart';
import '../sync/sealed_delivery.dart';
import 'clock.dart';
import 'crypto/crockford_base32.dart';
import 'crypto/key_cache.dart';
import 'crypto/key_rotation_service.dart';
import 'crypto_service.dart';
import 'storage_service.dart';
import 'types.dart';

/// Why we couldn't fulfill the request — surfaces to the UI for inline error
/// display and to the retry pump for status transitions.
enum FollowFailureKind { noEndpoints, network, unknownRequester, decryptFailed }

class FollowFailure implements Exception {
  const FollowFailure(this.kind, this.message);
  final FollowFailureKind kind;
  final String message;

  @override
  String toString() => 'FollowFailure($kind): $message';
}

/// Outcome of the synchronous send leg of [FollowService.acceptFollowRequest].
/// `delivered` means the responder POSTed and got 202; `queued` means delivery
/// failed and the encoded body was enqueued for the retry pump.
enum AcceptDelivery { delivered, queued, failed }

/// Result type for the round-trip ingest of an inbound `/follow-accept`.
/// Used by the server handler to choose its response code.
class IngestAcceptResult {
  const IngestAcceptResult({required this.follow});
  final Follow follow;
}

/// True iff [blob] is a queued follow-accept wrapper (`{ url, body }`), as
/// written by [FollowService]'s retry queue — distinct from the encrypted
/// comment/reaction events that share the same outbound-queue table (those
/// are `EncryptedEvent` CBOR: `pubkey/created_at/epoch/msg_seq/nonce/
/// payload`, no `url` key). Used by both the accept-retry pump and the sync
/// drain so neither clobbers the other's entries for a shared pubkey.
bool isFollowAcceptQueueEntry(Uint8List blob) {
  try {
    final decoded = cbor.decode(blob);
    if (decoded is! Map) return false;
    final url = decoded['url'];
    final body = decoded['body'];
    return url is String && (body is Uint8List || body is List<int>);
  } catch (_) {
    return false;
  }
}

/// Hand-off transport for the follow handshake. Routes `.onion` URLs
/// through [torClient] (Arti's SOCKS5 proxy) and everything else through
/// [defaultClient] (direct HTTP). [torClient] is supplied lazily so the
/// transport works during the bootstrap window before Tor is ready —
/// callers will get a `FollowFailureKind.network` if they try to dial an
/// onion endpoint while Tor is still bootstrapping.
///
/// All four follow-handshake calls (`/follow-request`, `/follow-accept`,
/// outbound + retry pump) flow through here, so wiring Tor in one place
/// covers the entire admin path.
class HandshakeTransport {
  HandshakeTransport(this._defaultClient, {http.Client? Function()? torClient})
    : _torClientLookup = torClient;

  final http.Client _defaultClient;
  final http.Client? Function()? _torClientLookup;

  http.Client _pick(Uri uri) {
    if (uri.host.endsWith('.onion')) {
      final tor = _torClientLookup?.call();
      if (tor == null) {
        throw const HandshakeTransportException(
          'onion endpoint requested but Tor is not ready yet',
        );
      }
      return tor;
    }
    return _defaultClient;
  }

  Future<int> postFollowRequest(String baseUrl, Uint8List body) async {
    final uri = Uri.parse('$baseUrl/follow-request');
    final res = await _pick(uri).post(
      uri,
      headers: const {'content-type': 'application/cbor'},
      body: body,
    );
    return res.statusCode;
  }

  Future<int> postFollowAccept(String baseUrl, Uint8List body) async {
    final uri = Uri.parse('$baseUrl/follow-accept');
    final res = await _pick(uri).post(
      uri,
      headers: const {'content-type': 'application/cbor'},
      body: body,
    );
    return res.statusCode;
  }
}

class HandshakeTransportException implements Exception {
  const HandshakeTransportException(this.message);
  final String message;
  @override
  String toString() => 'HandshakeTransportException: $message';
}

/// Coordinates the follow-request handshake (Plan 08).
///
/// Wire shapes:
/// - `POST /follow-request` body (CBOR):
///   `{ requester_pubkey, encrypted_return_endpoints, nonce, timestamp }`
///   Plaintext of `encrypted_return_endpoints` (CBOR):
///   `{ connection_card, feed_key_epoch }` — connection card is the
///   requester's contact info, feed_key_epoch is informational.
/// - `POST /follow-accept` body (CBOR):
///   `{ owner_pubkey, encrypted_feed_key, nonce, epoch, timestamp }`
///   Plaintext of `encrypted_feed_key` is the raw 32-byte feed key.
///
/// Shared key derivation uses `crypto.deriveSharedKey(myXSk, theirXPk,
/// requesterEdPk, responderEdPk, timestamp)` with `timestamp` echoed
/// verbatim through the handshake so both sides agree on it.
///
/// Semantics: a single QR-scan handshake is one-directional. Alice scans
/// Bob's QR → Alice gets Bob's feed key. Bob does NOT automatically gain
/// Alice's feed key; Bob would need to scan Alice's QR for that.
class FollowService {
  FollowService({
    required CryptoService crypto,
    required StorageService storage,
    required Clock clock,
    required HandshakeTransport transport,
    required PeerReachabilityMonitor reachabilityMonitor,
    required Future<Identity?> Function() identityLookup,
    required Future<Uint8List?> Function() ownSecretKeyLookup,
    required Future<List<Endpoint>> Function() ownEndpointsLookup,
    FeedKeyCache? feedKeyCache,
    KeyRotationService? keyRotationService,
  }) : _crypto = crypto,
       _storage = storage,
       _clock = clock,
       _transport = transport,
       _reachability = reachabilityMonitor,
       _identityLookup = identityLookup,
       _ownSecretKeyLookup = ownSecretKeyLookup,
       _ownEndpointsLookup = ownEndpointsLookup,
       _feedKeyCache = feedKeyCache,
       _keyRotationService = keyRotationService;

  final CryptoService _crypto;
  final StorageService _storage;
  final Clock _clock;
  final HandshakeTransport _transport;
  final PeerReachabilityMonitor _reachability;
  final Future<Identity?> Function() _identityLookup;
  final Future<Uint8List?> Function() _ownSecretKeyLookup;
  final Future<List<Endpoint>> Function() _ownEndpointsLookup;
  final FeedKeyCache? _feedKeyCache;
  final KeyRotationService? _keyRotationService;

  /// Backoff schedule for queued-accept redelivery. Index is the entry's
  /// persisted `retryCount`, clamped to the last bucket. We never stop
  /// retrying — a follower's phone is offline most of the time, so a
  /// permanent give-up would silently strand the handshake.
  static const List<Duration> _acceptBackoff = [
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 2),
    Duration(minutes: 5),
    Duration(minutes: 10),
    Duration(minutes: 15),
  ];

  /// Serializes retry passes so a reachability-triggered drain can't
  /// interleave with the periodic pump — overlapping passes could double-
  /// POST one accept and let the duplicate's 4xx flip an already-`accepted`
  /// row back to `send-failed`. Mirrors `LifecycleManager._publishChain`.
  Future<void> _retryChain = Future<void>.value();

  /// Queue entry id -> unix seconds of its last delivery attempt. In-memory
  /// and session-scoped: a fresh launch retries immediately (desirable),
  /// while the persisted `retryCount` still drives the backoff exponent
  /// across restarts.
  final Map<int, int> _acceptLastAttemptSec = {};

  // --- Outbound: send a follow request ---

  Future<void> sendFollowRequest(ConnectionCard target) async {
    final identity = await _requireIdentity();
    final secretKey = await _requireSecretKey();
    final ownEndpoints = await _ownEndpointsLookup();
    // Refuse to send a card with no onion. The responder persists this
    // payload as our `inbound_follow_requests` row and dials it on
    // follow-back, so an empty card permanently poisons the return path.
    if (ownEndpoints.where((e) => e.type == 'onion').isEmpty) {
      throw const FollowFailure(
        FollowFailureKind.noEndpoints,
        'our onion is not published yet — cannot send follow-request',
      );
    }
    final connection = await _reachability.probeCard(target);
    if (connection == null) {
      throw const FollowFailure(
        FollowFailureKind.noEndpoints,
        'no reachable endpoint in target connection card',
      );
    }

    final timestamp = _clock.nowUnixSeconds();
    final myEdPk = crockfordBase32Decode(identity.pubkey);
    final theirEdPk = crockfordBase32Decode(target.pubkey);
    final myXSk = _crypto.ed25519ToX25519SecretKey(secretKey);
    final theirXPk = _crypto.ed25519ToX25519PublicKey(theirEdPk);

    final sharedKey = _crypto.deriveSharedKey(
      myXSk,
      theirXPk,
      myEdPk,
      theirEdPk,
      timestamp,
    );

    final ownCard = ConnectionCard(
      pubkey: identity.pubkey,
      endpoints: ownEndpoints,
    );
    final innerCbor = Uint8List.fromList(
      cbor.encode(<String, dynamic>{
        'connection_card': ownCard.toMap(),
        'feed_key_epoch': identity.feedKeyEpoch,
      }),
    );
    final nonce = _crypto.randomBytes(24);
    final ciphertext = _crypto.encrypt(innerCbor, nonce, sharedKey);

    final body = Uint8List.fromList(
      cbor.encode(<String, dynamic>{
        'requester_pubkey': identity.pubkey,
        'encrypted_return_endpoints': ciphertext,
        'nonce': nonce,
        'timestamp': timestamp,
      }),
    );

    final int status;
    try {
      status = await _transport.postFollowRequest(connection.baseUrl, body);
    } catch (e) {
      throw FollowFailure(FollowFailureKind.network, 'send failed: $e');
    }
    if (status != 202) {
      throw FollowFailure(
        FollowFailureKind.network,
        'unexpected response: $status',
      );
    }

    await _storage.saveOutboundRequest(
      FollowRequest(
        pubkey: target.pubkey,
        payload: target.toBytes(),
        createdAt: timestamp,
        requestTimestamp: timestamp,
      ),
    );
  }

  // --- Inbound: accept a pending request ---

  /// Returns the delivery result so the UI can render the outbound state
  /// ("Sent" vs "Pending — retrying").
  Future<AcceptDelivery> acceptFollowRequest(String requesterPubkey) async {
    final identity = await _requireIdentity();
    final secretKey = await _requireSecretKey();
    final inbound = await _storage.getInboundRequest(requesterPubkey);
    if (inbound == null) {
      throw FollowFailure(
        FollowFailureKind.unknownRequester,
        'no pending request from $requesterPubkey',
      );
    }
    final outer = _decodeMap(inbound.payload);
    final inner = _decryptInner(
      outer,
      identity,
      secretKey,
      inbound.requestTimestamp,
    );

    final requesterCard = ConnectionCard.fromMap(
      inner['connection_card'] as Map<dynamic, dynamic>,
    );
    final connection = await _reachability.probeCard(requesterCard);

    final acceptBody = _buildAcceptBody(
      identity: identity,
      secretKey: secretKey,
      requesterCard: requesterCard,
      timestamp: inbound.requestTimestamp,
    );

    var delivery = AcceptDelivery.delivered;
    if (connection == null) {
      delivery = AcceptDelivery.queued;
    } else {
      try {
        final status = await _transport.postFollowAccept(
          connection.baseUrl,
          acceptBody,
        );
        if (status != 202) {
          delivery = AcceptDelivery.queued;
        }
      } catch (_) {
        delivery = AcceptDelivery.queued;
      }
    }

    if (delivery == AcceptDelivery.queued) {
      // Queue against the best onion endpoint we know — that's the only
      // address that's stable enough to retry against later. If the
      // requester's card has no onion, fall back to whatever the probe
      // found, or the card's first endpoint as a last-resort hint.
      final fallbackUrl =
          connection?.baseUrl ?? _firstQueueableUrl(requesterCard);
      await _storage.enqueue(
        requesterPubkey,
        _wrapQueueEntry('$fallbackUrl/follow-accept', acceptBody),
      );
      await _storage.updateInboundRequestStatus(
        requesterPubkey,
        'pending-send',
      );
    } else {
      await _storage.updateInboundRequestStatus(requesterPubkey, 'accepted');
    }
    return delivery;
  }

  Uint8List _wrapQueueEntry(String url, Uint8List body) => Uint8List.fromList(
    cbor.encode(<String, dynamic>{'url': url, 'body': body}),
  );

  // --- Inbound: reject a pending request ---

  Future<void> rejectFollowRequest(String requesterPubkey) =>
      _storage.deleteInboundRequest(requesterPubkey);

  // --- Symmetric follow-back ---

  /// Send a follow request back to a peer who already follows us. The
  /// requester's connection card is recovered by decrypting the stored
  /// inbound payload (same path as `acceptFollowRequest`), so the user
  /// doesn't need to re-scan their QR. Live endpoint resolution is
  /// handled by the reachability monitor inside `sendFollowRequest`'s
  /// `probeCard` call — no caller-side mDNS lookup needed.
  Future<void> followBack(String requesterPubkey) async {
    final inbound = await _storage.getInboundRequest(requesterPubkey);
    if (inbound == null) {
      throw FollowFailure(
        FollowFailureKind.unknownRequester,
        'no inbound request from $requesterPubkey',
      );
    }
    final identity = await _requireIdentity();
    final secretKey = await _requireSecretKey();
    final outer = _decodeMap(inbound.payload);
    final inner = _decryptInner(
      outer,
      identity,
      secretKey,
      inbound.requestTimestamp,
    );
    final card = ConnectionCard.fromMap(
      inner['connection_card'] as Map<dynamic, dynamic>,
    );
    await sendFollowRequest(card);
  }

  // --- Inbound /follow-accept handler entry point ---

  Future<IngestAcceptResult> ingestFollowAccept({
    required String ownerPubkey,
    required Uint8List encryptedFeedKey,
    required Uint8List nonce,
    required int epoch,
    required int timestamp,
  }) async {
    final identity = await _requireIdentity();
    final secretKey = await _requireSecretKey();

    final outbound = await _storage.getOutboundRequest(ownerPubkey);
    if (outbound == null) {
      // Idempotent re-ack: a prior delivery of this accept already created
      // the follow and deleted the outbound row, but its 202 never reached
      // the responder (flaky onion reverse path) so they keep re-POSTing.
      // Returning success lets their retry pump clear the queue and flip the
      // inbound row to 'accepted' instead of looping on a 404 forever.
      final existing = await _storage.getFollow(ownerPubkey);
      if (existing != null) {
        return IngestAcceptResult(follow: existing);
      }
      throw FollowFailure(
        FollowFailureKind.unknownRequester,
        'no outbound request to $ownerPubkey',
      );
    }
    if (outbound.requestTimestamp != timestamp) {
      throw const FollowFailure(
        FollowFailureKind.decryptFailed,
        'timestamp mismatch with stored outbound request',
      );
    }

    final myEdPk = crockfordBase32Decode(identity.pubkey);
    final theirEdPk = crockfordBase32Decode(ownerPubkey);
    final myXSk = _crypto.ed25519ToX25519SecretKey(secretKey);
    final theirXPk = _crypto.ed25519ToX25519PublicKey(theirEdPk);
    final sharedKey = _crypto.deriveSharedKey(
      myXSk,
      theirXPk,
      myEdPk,
      theirEdPk,
      timestamp,
    );

    final Uint8List feedKey;
    try {
      feedKey = _crypto.decrypt(encryptedFeedKey, nonce, sharedKey);
    } catch (e) {
      throw FollowFailure(
        FollowFailureKind.decryptFailed,
        'feed key decryption failed: $e',
      );
    }

    final card = ConnectionCard.fromBytes(outbound.payload);
    final follow = Follow(
      pubkey: ownerPubkey,
      connectionCard: jsonEncode(card.toMap()),
      feedKey: feedKey,
      feedKeyEpoch: epoch,
      // Start at 0 so the first sync after pairing backfills the peer's
      // full history. Setting this to "now" would make sync only fetch
      // events posted *after* the QR scan, hiding everything older — bad
      // UX for both first pairing (peer's existing posts are invisible)
      // and re-pairing (you'd lose access to posts that synced before).
      lastSyncedAt: 0,
    );
    await _storage.saveFollow(follow);
    await _storage.deleteOutboundRequest(ownerPubkey);
    _feedKeyCache?.put(ownerPubkey, feedKey, epoch);

    return IngestAcceptResult(follow: follow);
  }

  // --- Unfollow / removeFollower ---

  /// Stop following [pubkey] (we will no longer receive their posts). If
  /// [pubkey] is also an accepted inbound follower of ours, this is the
  /// symmetric "mutual disconnect" — we also call [removeFollower] so they
  /// can no longer read our future posts. Plan 13.
  Future<void> unfollow(String pubkey) async {
    await _storage.removeFollow(pubkey);
    _feedKeyCache?.remove(pubkey);
    if (await _storage.isAcceptedFollower(pubkey)) {
      await removeFollower(pubkey);
    }
  }

  /// Revoke [pubkey]'s ability to read our future posts (Plan 13). Removes
  /// the accepted inbound follow record and triggers feed-key rotation —
  /// remaining followers receive the new key on their next sync.
  ///
  /// Idempotent against missing rows: if [pubkey] isn't in our accepted
  /// followers (e.g. they were already removed), this is a no-op.
  Future<void> removeFollower(String pubkey) async {
    final wasAccepted = await _storage.isAcceptedFollower(pubkey);
    if (!wasAccepted) return;
    await _storage.removeAcceptedFollower(pubkey);
    // S4: drop every queued sealed delivery (card AND feed-key rows) — a
    // removed follower polling /manifest must not be handed our latest
    // endpoints. Unconditional (unlike rotation below) so the rows die
    // even when no rotator is wired; rotation also sweeps its own rows.
    await clearPendingDeliveriesFor(_storage, pubkey);
    final rotation = _keyRotationService;
    if (rotation != null) {
      await rotation.rotate(removedPubkey: pubkey);
    }
  }

  // --- Retry pump entry point ---

  /// Drains queued accept-payloads. Each queued entry is CBOR
  /// `{ url, body }` where `body` is the encrypted /follow-accept payload.
  ///
  /// Retries indefinitely with per-entry exponential backoff
  /// ([_acceptBackoff]) — an accept is never permanently stranded, since a
  /// follower's phone is offline most of the time. At
  /// [failedStatusThreshold] consecutive failures the inbound row flips to
  /// 'send-failed' for honest UI ("accept undelivered, still retrying"), but
  /// the queue entry is KEPT and keeps retrying; a later success flips the
  /// row back to 'accepted'.
  ///
  /// [onlyPubkey] limits the pass to one requester (the reachability
  /// trigger). [ignoreBackoff] forces an immediate attempt regardless of the
  /// per-entry backoff window (also the reachability trigger). Passes are
  /// serialized via [_retryChain].
  Future<void> retryQueuedAccepts({
    int failedStatusThreshold = 10,
    String? onlyPubkey,
    bool ignoreBackoff = false,
  }) {
    return _retryChain = _retryChain.then(
      (_) => _retryQueuedAcceptsNow(
        failedStatusThreshold: failedStatusThreshold,
        onlyPubkey: onlyPubkey,
        ignoreBackoff: ignoreBackoff,
      ),
    );
  }

  Future<void> _retryQueuedAcceptsNow({
    required int failedStatusThreshold,
    required String? onlyPubkey,
    required bool ignoreBackoff,
  }) async {
    // 'send-failed' rows are still actively retried — that status is a UI
    // signal, not a terminal state. A pubkey has exactly one inbound row, so
    // the two queries never overlap.
    final rows = [
      ...await _storage.getInboundRequestsByStatus('pending-send'),
      ...await _storage.getInboundRequestsByStatus('send-failed'),
    ];
    final seenIds = <int>{};
    for (final inbound in rows) {
      if (onlyPubkey != null && inbound.pubkey != onlyPubkey) continue;
      final entries = await _storage.dequeue(inbound.pubkey);
      // Re-resolve the requester's CURRENT reachable endpoint once per row.
      // The URL baked into the queue entry at accept time goes stale — most
      // commonly an ephemeral LAN port that changes when the requester
      // relaunches, or an onion that wasn't published yet when we queued.
      // Without this, a delivered-but-lost-202 accept retries forever against
      // a dead address and the mutual-follow handshake never finalizes.
      // Best-effort; falls back to the stored URL.
      final freshBaseUrl =
          entries.any((e) => isFollowAcceptQueueEntry(e.eventBlob))
          ? await _resolveRequesterBaseUrl(inbound)
          : null;
      for (final entry in entries) {
        seenIds.add(entry.id);
        // The outbound queue is shared with encrypted comment/reaction
        // events keyed by the same pubkey (the sync engine drains those).
        // Only touch accept wrappers; leave foreign blobs untouched.
        if (!isFollowAcceptQueueEntry(entry.eventBlob)) continue;
        if (!ignoreBackoff && _backoffNotElapsed(entry)) continue;

        final wrapped = _decodeMap(entry.eventBlob);
        final url = wrapped['url'] as String;
        final body = _asBytes(wrapped['body']);

        _acceptLastAttemptSec[entry.id] = _clock.nowUnixSeconds();

        final int status;
        try {
          status = await _transport.postFollowAccept(
            freshBaseUrl ?? _stripAcceptSuffix(url),
            body,
          );
        } on HandshakeTransportException catch (e) {
          // Our own Tor isn't ready — a local failure, not the peer's. Don't
          // spend a retry on it; clear the attempt stamp so the first pass
          // after Tor recovers fires immediately.
          _acceptLastAttemptSec.remove(entry.id);
          _log(
            'retry skip ${inbound.pubkey} transport-not-ready: ${e.message}',
          );
          continue;
        } catch (e) {
          await _onAcceptFailure(inbound, entry, failedStatusThreshold, e);
          continue;
        }

        if (status == 202) {
          await _storage.removeFromQueue(entry.id);
          _acceptLastAttemptSec.remove(entry.id);
          await _storage.updateInboundRequestStatus(inbound.pubkey, 'accepted');
          _log('retry delivered ${inbound.pubkey}');
          // Drop any duplicate accept entries for this pubkey so a stale one
          // can't 4xx later and flip the row back to 'send-failed'.
          await _removeAcceptEntriesFor(inbound.pubkey);
          break;
        }
        await _onAcceptFailure(
          inbound,
          entry,
          failedStatusThreshold,
          'status $status',
        );
      }
    }
    // Hygiene: forget attempt stamps for entries no longer queued. Only safe
    // on a full pass — a targeted pass didn't visit every entry.
    if (onlyPubkey == null) {
      _acceptLastAttemptSec.removeWhere((id, _) => !seenIds.contains(id));
    }
  }

  /// True when [entry]'s backoff window hasn't elapsed since its last
  /// attempt this session. Never-attempted entries (fresh launch, fresh
  /// queue) return false → attempt immediately.
  bool _backoffNotElapsed(QueuedEvent entry) {
    final last = _acceptLastAttemptSec[entry.id];
    if (last == null) return false;
    final idx = entry.retryCount < _acceptBackoff.length
        ? entry.retryCount
        : _acceptBackoff.length - 1;
    return _clock.nowUnixSeconds() - last < _acceptBackoff[idx].inSeconds;
  }

  Future<void> _onAcceptFailure(
    FollowRequest inbound,
    QueuedEvent entry,
    int failedStatusThreshold,
    Object reason,
  ) async {
    await _storage.incrementRetry(entry.id);
    _log(
      'retry failed ${inbound.pubkey} '
      'attempt=${entry.retryCount + 1} reason=$reason',
    );
    // Flip to 'send-failed' once, only from 'pending-send' — re-writing the
    // same status would re-emit `watchInboundFollowers` needlessly, and we
    // must not stomp an 'accepted' row a concurrent path may have set.
    if (entry.retryCount + 1 >= failedStatusThreshold &&
        inbound.status == 'pending-send') {
      await _storage.updateInboundRequestStatus(inbound.pubkey, 'send-failed');
    }
  }

  /// Re-derive the requester's current reachable base URL from their stored
  /// (encrypted) inbound payload, so a stale queued URL — ephemeral LAN port
  /// that rotated on the peer's relaunch, or an onion that wasn't published
  /// when we queued — doesn't permanently strand the accept. Returns null on
  /// any failure so the caller falls back to the queued URL.
  Future<String?> _resolveRequesterBaseUrl(FollowRequest inbound) async {
    try {
      // Mutual follow: reuse the reachability monitor's validated transport —
      // the same path feed sync already dials successfully. It tracks the
      // peer's CURRENT onion and live LAN port, where the frozen request card
      // may carry a stale ephemeral port or an onion that wasn't published at
      // request time. No new address leak vs. probeCard's Tor-only stance: we
      // already follow them, so feed sync dials them over LAN regardless.
      if (await _storage.getFollow(inbound.pubkey) != null) {
        final conn = await _reachability.bestConnectionFor(inbound.pubkey);
        if (conn != null) return conn.baseUrl;
      }
      // Non-mutual (or the monitor hasn't validated a transport yet): fall back
      // to a Tor-only probe of the requester's frozen card, as before.
      final identity = await _identityLookup();
      final sk = await _ownSecretKeyLookup();
      if (identity == null || sk == null) return null;
      final outer = _decodeMap(inbound.payload);
      final inner = _decryptInner(
        outer,
        identity,
        sk,
        inbound.requestTimestamp,
      );
      final card = ConnectionCard.fromMap(
        inner['connection_card'] as Map<dynamic, dynamic>,
      );
      final connection = await _reachability.probeCard(card);
      return connection?.baseUrl;
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeAcceptEntriesFor(String pubkey) async {
    final entries = await _storage.dequeue(pubkey);
    for (final entry in entries) {
      if (isFollowAcceptQueueEntry(entry.eventBlob)) {
        await _storage.removeFromQueue(entry.id);
        _acceptLastAttemptSec.remove(entry.id);
      }
    }
  }

  void _log(String msg) {
    developer.log(msg, name: 'starling.follow');
    // ignore: avoid_print
    print('[starling.follow] $msg');
  }

  String _stripAcceptSuffix(String url) {
    const suffix = '/follow-accept';
    if (url.endsWith(suffix))
      return url.substring(0, url.length - suffix.length);
    return url;
  }

  Future<Identity> _requireIdentity() async {
    final identity = await _identityLookup();
    if (identity == null) {
      throw const FollowFailure(
        FollowFailureKind.unknownRequester,
        'no identity loaded',
      );
    }
    return identity;
  }

  Future<Uint8List> _requireSecretKey() async {
    final sk = await _ownSecretKeyLookup();
    if (sk == null) {
      throw const FollowFailure(
        FollowFailureKind.unknownRequester,
        'no secret key loaded',
      );
    }
    return sk;
  }

  /// Pick a baseUrl to bind a queued accept against when no transport
  /// validated. Onion is preferred — it's stable across restarts, so
  /// stored URLs survive between attempts. Anything else is a guess.
  String _firstQueueableUrl(ConnectionCard card) {
    for (final type in ['onion', 'relay', 'lan-direct', 'direct']) {
      final pick = card.endpoints.firstWhere(
        (e) => e.type == type,
        orElse: () => const Endpoint(type: '', address: ''),
      );
      if (pick.type.isEmpty) continue;
      final addr = pick.address;
      if (addr.startsWith('http://') || addr.startsWith('https://')) {
        return addr;
      }
      return type == 'onion' && !addr.contains(':')
          ? 'http://$addr:80'
          : 'http://$addr';
    }
    return 'http://invalid';
  }

  Map<dynamic, dynamic> _decodeMap(Uint8List bytes) {
    final decoded = cbor.decode(bytes);
    if (decoded is! Map) {
      throw const FollowFailure(
        FollowFailureKind.decryptFailed,
        'expected CBOR map',
      );
    }
    return decoded;
  }

  Map<dynamic, dynamic> _decryptInner(
    Map<dynamic, dynamic> outer,
    Identity identity,
    Uint8List secretKey,
    int timestamp,
  ) {
    final ct = _asBytes(outer['encrypted_return_endpoints']);
    final nonce = _asBytes(outer['nonce']);
    final requesterPk = outer['requester_pubkey'] as String;

    final myEdPk = crockfordBase32Decode(identity.pubkey);
    final theirEdPk = crockfordBase32Decode(requesterPk);
    final myXSk = _crypto.ed25519ToX25519SecretKey(secretKey);
    final theirXPk = _crypto.ed25519ToX25519PublicKey(theirEdPk);
    final sharedKey = _crypto.deriveSharedKey(
      myXSk,
      theirXPk,
      theirEdPk,
      myEdPk,
      timestamp,
    );

    final Uint8List plaintext;
    try {
      plaintext = _crypto.decrypt(ct, nonce, sharedKey);
    } catch (e) {
      throw FollowFailure(
        FollowFailureKind.decryptFailed,
        'return-endpoints decryption failed: $e',
      );
    }
    return _decodeMap(plaintext);
  }

  Uint8List _buildAcceptBody({
    required Identity identity,
    required Uint8List secretKey,
    required ConnectionCard requesterCard,
    required int timestamp,
  }) {
    final myEdPk = crockfordBase32Decode(identity.pubkey);
    final theirEdPk = crockfordBase32Decode(requesterCard.pubkey);
    final myXSk = _crypto.ed25519ToX25519SecretKey(secretKey);
    final theirXPk = _crypto.ed25519ToX25519PublicKey(theirEdPk);
    final sharedKey = _crypto.deriveSharedKey(
      myXSk,
      theirXPk,
      theirEdPk,
      myEdPk,
      timestamp,
    );
    final nonce = _crypto.randomBytes(24);
    final ct = _crypto.encrypt(identity.feedKey, nonce, sharedKey);
    return Uint8List.fromList(
      cbor.encode(<String, dynamic>{
        'owner_pubkey': identity.pubkey,
        'encrypted_feed_key': ct,
        'nonce': nonce,
        'epoch': identity.feedKeyEpoch,
        'timestamp': timestamp,
      }),
    );
  }

  Uint8List _asBytes(dynamic value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    throw FollowFailure(
      FollowFailureKind.decryptFailed,
      'expected bytes, got ${value.runtimeType}',
    );
  }
}
