import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import '../models/models.dart';
import '../services/clock.dart';
import '../services/content_key_service.dart';
import '../services/crypto/crockford_base32.dart';
import '../services/crypto/key_cache.dart';
import '../services/crypto_service.dart';
import '../services/storage_service.dart';
import '../services/types.dart';
import '../utils/feature_flags.dart';
import 'concurrency.dart';
import 'libp2p_upgrader.dart';
import 'manifest_exchange.dart';
import 'outbound_drain.dart';
import 'peer_connection_factory.dart';
import 'peer_reachability_monitor.dart';

/// The narrow surface the sync engine needs from a transport. Implemented
/// by `LanNetworkService` for v1; Plans 11/15 will add Tor/relay-backed
/// implementations behind the same shape.
abstract class SyncTransport {
  Future<Manifest> fetchManifest(
    PeerConnection peer, {
    int? since,
    int? until,
    String? requesterPubkey,
    int? ackRotationAt,
    int? cardSeenAt,
  });

  Future<Envelope> fetchEnvelope(PeerConnection peer, {int? since});

  Future<Uint8List> fetchMedia(PeerConnection peer, String hash);

  /// Push an envelope of events to the peer (Plan 10 outbound queue).
  /// On success the receiver returns 202; transport-level failures throw.
  Future<void> pushEnvelope(PeerConnection peer, Envelope envelope);
}

/// One-call orchestration for "pull what's new from every reachable
/// follow." Mirrors the spec in `app/plans/09-lan-sync.md`:
///
///   for each followed pubkey:
///     resolve LAN peer (Plan 11/15 add Tor + relay)
///     manifest exchange (diff against local event IDs)
///     fetch missing events
///     decrypt + verify (per-item integrity, untrusted envelope)
///     store with is_own=0
///     update last_synced_at
///
/// Concurrency is bounded by [Pool] (default 5).
class SyncEngine {
  SyncEngine({
    required StorageService storage,
    required ContentKeyService contentKey,
    required CryptoService crypto,
    required SyncTransport transport,
    required PeerConnectionFactory peerFactory,
    required PeerReachabilityMonitor reachabilityMonitor,
    required Clock clock,
    required Future<Uint8List?> Function() ownSecretKeyLookup,
    FeedKeyCache? feedKeyCache,
    Libp2pUpgrader? libp2pUpgrader,
    int maxParallelPeers = 5,
  })  : _storage = storage,
        _contentKey = contentKey,
        _crypto = crypto,
        _transport = transport,
        _peerFactory = peerFactory,
        _reachability = reachabilityMonitor,
        _clock = clock,
        _ownSecretKeyLookup = ownSecretKeyLookup,
        _feedKeyCache = feedKeyCache,
        _libp2pUpgrader = libp2pUpgrader,
        _pool = Pool(maxParallelPeers);

  final StorageService _storage;
  final ContentKeyService _contentKey;
  final CryptoService _crypto;
  final SyncTransport _transport;
  final PeerConnectionFactory _peerFactory;
  final PeerReachabilityMonitor _reachability;
  final Clock _clock;
  final Future<Uint8List?> Function() _ownSecretKeyLookup;
  final FeedKeyCache? _feedKeyCache;
  final Libp2pUpgrader? _libp2pUpgrader;
  final Pool _pool;

  /// Runs one sync pass. Returns a per-peer report so the UI can surface
  /// "syncing… 3/5 done" or "Bob unreachable."
  Future<SyncReport> syncNow() async {
    final follows = await _storage.getFollows();
    developer.log(
      'syncNow start: follows=${follows.length} '
      '[${follows.map((f) => f.pubkey).join(",")}]',
      name: 'sync_engine',
    );
    if (follows.isEmpty) {
      return SyncReport(
        startedAt: _clock.nowUnixSeconds(),
        finishedAt: _clock.nowUnixSeconds(),
        peers: const [],
      );
    }

    final startedAt = _clock.nowUnixSeconds();
    final results = await Future.wait(
      follows.map((follow) => _pool.run(() => _syncOnePeer(follow))),
    );
    return SyncReport(
      startedAt: startedAt,
      finishedAt: _clock.nowUnixSeconds(),
      peers: results,
    );
  }

  /// One-shot sync for a single peer, looked up by pubkey. Returns null
  /// if the follow is gone (unfollowed mid-call). Used by on-demand
  /// recovery paths — `EncryptedImage` after a decrypt failure, the
  /// connection-settings refresh button — that want to pull any pending
  /// rotation inline without doing a full app-wide `syncNow()`.
  Future<PeerSyncReport?> syncOnePeerByPubkey(String pubkey) async {
    final follow = await _storage.getFollow(pubkey);
    if (follow == null) return null;
    return _pool.run(() => _syncOnePeer(follow));
  }

  Future<PeerSyncReport> _syncOnePeer(Follow follow) async {
    developer.log(
      'syncOnePeer start pubkey=${follow.pubkey} lastSyncedAt=${follow.lastSyncedAt}',
      name: 'sync_engine',
    );
    final connection = await _peerFactory.resolve(follow.pubkey);
    if (connection == null) {
      developer.log(
        'no transport available for ${follow.pubkey} — peer unreachable',
        name: 'sync_engine',
      );
      return PeerSyncReport(
        pubkey: follow.pubkey,
        status: PeerSyncStatus.unreachable,
      );
    }
    developer.log(
      '${connection.transport.name} peer resolved ${follow.pubkey} -> ${connection.baseUrl}',
      name: 'sync_engine',
    );

    // Plan 11a: if we resolved to Tor and the peer is libp2p-capable, fire a
    // background DCUtR upgrade attempt. The current run continues over Tor;
    // a successful upgrade promotes the peer in the reachability monitor so
    // the next pump picks libp2p-direct automatically.
    final upgrader = _libp2pUpgrader;
    if (kLibp2pEnabled &&
        upgrader != null &&
        connection.transport == PeerTransport.tor) {
      unawaited(upgrader.tryUpgrade(connection, follow));
    }

    final identity = await _storage.getIdentity();
    final exchange =
        ManifestExchange(transport: _transport, storage: _storage);
    final ManifestDiff diff;
    try {
      diff = await exchange.fetchAndDiff(
        connection,
        follow,
        requesterPubkey: identity?.pubkey,
        ackRotationAt: follow.lastReceivedRotationAt,
        cardSeenAt: follow.lastReceivedCardAt,
      );
    } catch (e) {
      developer.log(
        'manifest fetch failed for ${follow.pubkey}: $e',
        name: 'sync_engine',
      );
      _reachability.markUnreachable(follow.pubkey, connection.transport, e);
      return PeerSyncReport(
        pubkey: follow.pubkey,
        status: PeerSyncStatus.unreachable,
        error: e.toString(),
      );
    }
    developer.log(
      'manifest diff for ${follow.pubkey}: peerEvents=${diff.peerEvents.length} '
      'missing=${diff.missingIds.length} windowSince=${diff.windowSince} '
      'newFeedKey=${diff.newFeedKey != null}',
      name: 'sync_engine',
    );

    // Plan 13: if the peer rotated, apply the new feed key BEFORE we try
    // to decrypt their (possibly newly-encrypted) events below.
    Follow currentFollow = follow;
    final delivery = diff.newFeedKey;
    if (delivery != null && identity != null) {
      try {
        currentFollow = await _applyRotatedFeedKey(
          identity: identity,
          follow: follow,
          delivery: delivery,
        );
      } catch (e) {
        developer.log(
          'rotated feed key apply failed for ${follow.pubkey}: $e',
          name: 'sync_engine',
        );
        // Don't abort the sync — we may still be able to read older events
        // with our existing key, and the rotation will be retried next pass.
      }
    }

    // Plan 15: ingest an updated Connection card (e.g. a newly-paired relay
    // endpoint) so the reachability monitor starts probing the new tier.
    final cardDelivery = diff.newConnectionCard;
    if (cardDelivery != null) {
      try {
        currentFollow = await _applyConnectionCard(
          follow: currentFollow,
          delivery: cardDelivery,
        );
      } catch (e) {
        developer.log(
          'connection card apply failed for ${follow.pubkey}: $e',
          name: 'sync_engine',
        );
        // Non-fatal — the card is re-offered on the next manifest response.
      }
    }

    if (diff.missingIds.isEmpty) {
      // Nothing to fetch — but we still advance last_synced_at so the next
      // window is anchored at "now." That requires we at least heard back
      // from the peer, which we did. Drain the outbound queue so queued
      // comments/likes don't sit waiting just because no inbound work
      // was due.
      await _storage.updateLastSynced(follow.pubkey, _clock.nowUnixSeconds());
      final drain = await drainOutboundQueueForPeer(
        storage: _storage,
        transport: _transport,
        follow: currentFollow,
        peer: connection,
      );
      return PeerSyncReport(
        pubkey: follow.pubkey,
        status: PeerSyncStatus.upToDate,
        eventsPushed: drain.pushed,
        eventsPushDropped: drain.dropped,
      );
    }

    final Envelope envelope;
    try {
      envelope = await _transport.fetchEnvelope(
        connection,
        since: diff.windowSince,
      );
    } catch (e) {
      developer.log(
        'envelope fetch failed for ${follow.pubkey}: $e',
        name: 'sync_engine',
      );
      _reachability.markUnreachable(follow.pubkey, connection.transport, e);
      return PeerSyncReport(
        pubkey: follow.pubkey,
        status: PeerSyncStatus.unreachable,
        error: e.toString(),
      );
    }

    developer.log(
      'envelope from ${follow.pubkey}: items=${envelope.items.length}',
      name: 'sync_engine',
    );
    var inserted = 0;
    var skipped = 0;
    var unknownPreserved = 0;
    final receivedAt = _clock.nowUnixSeconds();

    for (final item in envelope.items) {
      if (item.type == 'event') {
        final ok = await _processEventItem(item, currentFollow);
        if (ok) {
          inserted++;
        } else {
          skipped++;
        }
      } else {
        await _storage.saveUnknownEnvelopeItem(
          UnknownEnvelopeItem(
            sourcePubkey: follow.pubkey,
            envelopeVersion: envelope.version,
            type: item.type,
            payload: item.payload,
            extensions: null,
            receivedAt: receivedAt,
          ),
        );
        unknownPreserved++;
      }
    }

    await _storage.updateLastSynced(follow.pubkey, _clock.nowUnixSeconds());
    developer.log(
      'sync complete for ${follow.pubkey}: inserted=$inserted skipped=$skipped '
      'unknownPreserved=$unknownPreserved',
      name: 'sync_engine',
    );

    final drain = await drainOutboundQueueForPeer(
      storage: _storage,
      transport: _transport,
      follow: currentFollow,
      peer: connection,
    );

    return PeerSyncReport(
      pubkey: follow.pubkey,
      status: PeerSyncStatus.synced,
      eventsFetched: inserted,
      eventsSkipped: skipped,
      unknownItemsPreserved: unknownPreserved,
      eventsPushed: drain.pushed,
      eventsPushDropped: drain.dropped,
    );
  }

  /// Decrypts an inline rotation payload and persists the new feed key
  /// for [follow] (Plan 13). Returns the updated [Follow] (with the new
  /// `feedKey` and `lastReceivedRotationAt`). Throws on DH/decrypt failure
  /// — caller logs and falls through.
  Future<Follow> _applyRotatedFeedKey({
    required Identity identity,
    required Follow follow,
    required RotatedFeedKeyDelivery delivery,
  }) async {
    final secretKey = await _ownSecretKeyLookup();
    if (secretKey == null) {
      throw StateError('no secret key available to apply rotated feed key');
    }
    final myEdPk = crockfordBase32Decode(identity.pubkey);
    final theirEdPk = crockfordBase32Decode(follow.pubkey);
    final myXSk = _crypto.ed25519ToX25519SecretKey(secretKey);
    final theirXPk = _crypto.ed25519ToX25519PublicKey(theirEdPk);
    // Mirror the rotator's call: requester=rotator (follow.pubkey),
    // responder=us. The shared key derivation incorporates the timestamp
    // (createdAt of the rotation) so both sides agree.
    final sharedKey = _crypto.deriveSharedKey(
      myXSk,
      theirXPk,
      theirEdPk,
      myEdPk,
      delivery.createdAt,
    );
    final newKey = _crypto.decrypt(
      delivery.encryptedFeedKey,
      delivery.nonce,
      sharedKey,
    );
    // Archive the soon-to-be-old chain root so cached content authored
    // before this rotation stays decryptable. validFrom = the previously
    // archived rotation point (or 0 if first rotation). validUntil =
    // when this rotation took effect, i.e. delivery.createdAt.
    if (follow.feedKey.isNotEmpty) {
      final priorValidFrom = follow.lastReceivedRotationAt;
      await _storage.appendFollowFeedKeyHistory(
        followPubkey: follow.pubkey,
        feedKey: follow.feedKey,
        feedKeyEpoch: follow.feedKeyEpoch,
        validFrom: priorValidFrom,
        validUntil: delivery.createdAt,
      );
      developer.log(
        'archived follow feed key for ${follow.pubkey} '
        'epoch=${follow.feedKeyEpoch} '
        '[$priorValidFrom, ${delivery.createdAt})',
        name: 'sync_engine',
      );
    }
    final updated = follow.copyWith(
      feedKey: newKey,
      feedKeyEpoch: 0,
      lastReceivedRotationAt: delivery.createdAt,
      clearLastDecryptFailureAt: true,
    );
    await _storage.saveFollow(updated);
    _feedKeyCache?.put(follow.pubkey, newKey, 0);
    final newKeyFp = newKey
        .take(4)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    developer.log(
      'applied rotated feed key for ${follow.pubkey} '
      'oldEpoch=${follow.feedKeyEpoch} newEpoch=0 '
      'newKeyFp=$newKeyFp… rotationAt=${delivery.createdAt}',
      name: 'sync_engine',
    );
    return updated;
  }

  /// Verifies and persists an updated Connection card from [delivery]
  /// (Plan 15). Returns the updated [Follow] (new `connectionCard` +
  /// `lastReceivedCardAt`), stored in the same `jsonEncode(card.toMap())`
  /// shape `PeerReachabilityMonitor` parses. Throws on signature/format
  /// mismatch — the caller logs and falls through.
  Future<Follow> _applyConnectionCard({
    required Follow follow,
    required ConnectionCardDelivery delivery,
  }) async {
    // Ignore a card no newer than one we've already applied — the peer only
    // ever advances its card, so an older `created_at` is stale/replayed.
    if (delivery.createdAt < follow.lastReceivedCardAt) return follow;

    final authorPubkey = crockfordBase32Decode(follow.pubkey);
    final sigOk =
        _crypto.verify(authorPubkey, delivery.cardCbor, delivery.sig);
    if (!sigOk) {
      throw StateError('connection card signature invalid');
    }
    final card = ConnectionCard.fromBytes(delivery.cardCbor);
    if (card.pubkey != follow.pubkey) {
      throw StateError(
        'connection card pubkey ${card.pubkey} != follow ${follow.pubkey}',
      );
    }
    final updated = follow.copyWith(
      connectionCard: jsonEncode(card.toMap()),
      lastReceivedCardAt: delivery.createdAt,
    );
    await _storage.saveFollow(updated);
    developer.log(
      'applied connection card for ${follow.pubkey} '
      'endpoints=${card.endpoints.length} cardAt=${delivery.createdAt}',
      name: 'sync_engine',
    );
    return updated;
  }

  /// Processes one envelope item of `type:"event"`. Returns true if the
  /// event was decrypted, verified, and stored; false if it was rejected.
  ///
  /// Authorization: the encrypted-blob's claimed `pubkey` may either be
  /// the source we follow (the source's own event) or a third party's
  /// pubkey (a re-distributed comment/like/tombstone the source received
  /// via `POST /events`). For the third-party case we require the inner
  /// `Event.ref` to anchor to a known event from the source or our own
  /// — otherwise a misbehaving source could ship arbitrary signed events
  /// claiming any ref. The inner Ed25519 signature is always verified
  /// inside `decryptEvent`.
  Future<bool> _processEventItem(EnvelopeItem item, Follow follow) async {
    final EncryptedEvent encrypted;
    try {
      encrypted = EncryptedEvent.fromBytes(item.payload);
    } catch (e) {
      developer.log(
        'malformed EncryptedEvent from ${follow.pubkey}: $e',
        name: 'sync_engine',
      );
      return false;
    }

    // Candidate chain roots in priority order: current Follow.feedKey
    // first (will hit ~always for non-stale follows), then any archived
    // chain roots whose validity window covers the event's createdAt.
    // Each candidate is fed through `decryptEvent`, which derives the
    // per-message AEAD key from `(chainRoot, encrypted.msgSeq)`.
    final candidates = <Uint8List>[follow.feedKey];
    final history = await _storage.getFollowFeedKeyHistory(follow.pubkey);
    for (final h in history) {
      if (h.validFrom <= encrypted.createdAt &&
          encrypted.createdAt < h.validUntil) {
        candidates.add(h.feedKey);
      }
    }
    developer.log(
      'decrypt attempt peer=${follow.pubkey} '
      'eventCreatedAt=${encrypted.createdAt} '
      'eventEpoch=${encrypted.epoch} eventMsgSeq=${encrypted.msgSeq} '
      'currentEpoch=${follow.feedKeyEpoch} '
      'historyTotal=${history.length} candidates=${candidates.length}',
      name: 'sync_engine',
    );
    Event? plain;
    Object? lastError;
    for (final chainRoot in candidates) {
      try {
        plain = _contentKey.decryptEvent(encrypted, chainRoot);
        break;
      } catch (e) {
        lastError = e;
      }
    }
    if (plain == null) {
      developer.log(
        'decrypt/verify failed for ${follow.pubkey} '
        '(epoch=${encrypted.epoch} msgSeq=${encrypted.msgSeq} '
        'tried=${candidates.length}): $lastError',
        name: 'sync_engine',
      );
      // Stamp the staleness signal so the connection-settings tile can
      // surface "Key — stale" and the next sync run knows to look hard
      // for a pending rotation. Cleared on the next successful decrypt
      // below, or when a fresh key lands in `_applyRotatedFeedKey`.
      await _storage.setLastDecryptFailureAt(
        follow.pubkey,
        _clock.nowUnixSeconds(),
      );
      return false;
    }
    // Carry the wire-format msgSeq through to the persisted Event row so
    // media decryption can re-derive the same per-message key without
    // having to re-fetch the EncryptedEvent.
    plain = plain.copyWith(msgSeq: encrypted.msgSeq);

    if (plain.pubkey != follow.pubkey) {
      // Re-distributed event (e.g. a comment from a third party that
      // landed on the source's device). Anchor it: ref must point to a
      // local event whose author is the source we're syncing from, or
      // ourselves. Otherwise drop.
      if (plain.ref == null) {
        developer.log(
          'rejected re-distributed event without ref from '
          '${follow.pubkey}: pubkey=${plain.pubkey}',
          name: 'sync_engine',
        );
        return false;
      }
      final anchor = await _storage.getEvent(plain.ref!);
      if (anchor == null) {
        developer.log(
          'rejected re-distributed event with unknown ref from '
          '${follow.pubkey}: ref=${plain.ref}',
          name: 'sync_engine',
        );
        return false;
      }
      final identity = await _storage.getIdentity();
      final selfPubkey = identity?.pubkey;
      final ok = anchor.pubkey == follow.pubkey || anchor.pubkey == selfPubkey;
      if (!ok) {
        developer.log(
          'rejected re-distributed event whose ref does not anchor to '
          'source or self from ${follow.pubkey}: '
          'anchor.pubkey=${anchor.pubkey}',
          name: 'sync_engine',
        );
        return false;
      }
    }

    try {
      await _storage.saveEvent(plain);
    } catch (e) {
      developer.log(
        'save failed for event ${plain.id}: $e',
        name: 'sync_engine',
      );
      return false;
    }
    await _storage.clearLastDecryptFailureIfSet(follow.pubkey);
    return true;
  }
}

/// Aggregate report for one [SyncEngine.syncNow] call.
class SyncReport {
  const SyncReport({
    required this.startedAt,
    required this.finishedAt,
    required this.peers,
  });
  final int startedAt;
  final int finishedAt;
  final List<PeerSyncReport> peers;

  bool get hadFailures => peers.any((p) => p.status == PeerSyncStatus.unreachable);
  int get totalEventsFetched =>
      peers.fold(0, (sum, p) => sum + p.eventsFetched);
}

/// Per-follow result for one sync pass.
class PeerSyncReport {
  const PeerSyncReport({
    required this.pubkey,
    required this.status,
    this.eventsFetched = 0,
    this.eventsSkipped = 0,
    this.unknownItemsPreserved = 0,
    this.eventsPushed = 0,
    this.eventsPushDropped = 0,
    this.error,
  });
  final String pubkey;
  final PeerSyncStatus status;
  final int eventsFetched;
  final int eventsSkipped;
  final int unknownItemsPreserved;
  final int eventsPushed;
  final int eventsPushDropped;
  final String? error;
}

enum PeerSyncStatus {
  /// Peer responded; new events fetched and stored.
  synced,

  /// Peer responded; we already had everything in the window.
  upToDate,

  /// Couldn't reach the peer (no LAN entry, HTTP failure, timeout).
  unreachable,
}
