import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;
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
import 'manifest_ack.dart';
import 'manifest_exchange.dart';
import 'outbound_drain.dart';
import 'sealed_delivery.dart';
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
    String? untilId,
    String? requesterPubkey,
    int? ackRotationAt,
    int? cardSeenAt,
    Uint8List? ackSig,
  });

  Future<Envelope> fetchEnvelope(PeerConnection peer, {int? since});

  Future<Uint8List> fetchMedia(PeerConnection peer, String hash);

  /// Push an envelope of events to the peer (Plan 10 outbound queue).
  /// On success the receiver returns 202; transport-level failures throw.
  Future<void> pushEnvelope(PeerConnection peer, Envelope envelope);
}

/// How often each follow gets a FULL (un-windowed, paged) manifest diff
/// (D1). The windowed cursor can't see events that arrived at a store out
/// of author-time order; the daily full pass converges them.
const int kFullManifestSyncIntervalSecs = 86400;

/// Tolerated forward clock skew when advancing the sync cursor to a peer
/// event's `created_at` — one absurdly future-dated event must not jump
/// the cursor past everything that follows it.
const int kMaxCursorSkewSecs = 300;

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
  }) : _storage = storage,
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

  /// Mirrors the sync decision spine to both `developer.log` (for DevTools)
  /// and `print` (so the path is visible in a plain `flutter run` console —
  /// matching `FollowService._log` and the reachability monitor). The
  /// resolve outcome, manifest/envelope failures, and terminal status are
  /// what you need to tell "peer unreachable" apart from "manifest fetch
  /// failed" apart from "synced fine but UI stale" when a follow won't sync.
  void _log(String msg) {
    developer.log(msg, name: 'sync_engine');
    // ignore: avoid_print
    print('[sync_engine] $msg');
  }

  /// Runs one sync pass. Returns a per-peer report so the UI can surface
  /// "syncing… 3/5 done" or "Bob unreachable."
  Future<SyncReport> syncNow() async {
    final follows = await _storage.getFollows();
    _log(
      'syncNow start: follows=${follows.length} '
      '[${follows.map((f) => f.pubkey).join(",")}]',
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
    _log(
      'syncOnePeer start pubkey=${follow.pubkey} lastSyncedAt=${follow.lastSyncedAt}',
    );
    final connection = await _peerFactory.resolve(follow.pubkey);
    if (connection == null) {
      _log('no transport available for ${follow.pubkey} — peer unreachable');
      return PeerSyncReport(
        pubkey: follow.pubkey,
        status: PeerSyncStatus.unreachable,
      );
    }
    _log(
      '${connection.transport.name} peer resolved ${follow.pubkey} -> ${connection.baseUrl}',
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
    final exchange = ManifestExchange(transport: _transport, storage: _storage);

    // S3a: prove we control `requester_pubkey` before the peer honors our
    // delivery acks. Skipped when there's nothing to ack.
    Uint8List? ackSig;
    if (identity != null &&
        (follow.lastReceivedRotationAt > 0 || follow.lastReceivedCardAt > 0)) {
      final secretKey = await _ownSecretKeyLookup();
      if (secretKey != null) {
        ackSig = signManifestAck(
          _crypto,
          requesterSecretKey: secretKey,
          ownerPubkey: crockfordBase32Decode(follow.pubkey),
          ackRotationAt: follow.lastReceivedRotationAt,
          cardSeenAt: follow.lastReceivedCardAt,
        );
      }
    }

    // D1: the windowed diff is the cheap steady-state; a full paged diff
    // runs on the first sync, on a stale full-pass stamp, or when the
    // windowed manifest overflowed its page (has_older).
    var ranFull =
        follow.lastFullSyncAt == 0 ||
        _clock.nowUnixSeconds() - follow.lastFullSyncAt >=
            kFullManifestSyncIntervalSecs;

    ManifestDiff diff;
    try {
      diff = ranFull
          ? await exchange.fetchAndDiffFull(
              connection,
              follow,
              requesterPubkey: identity?.pubkey,
              ackRotationAt: follow.lastReceivedRotationAt,
              cardSeenAt: follow.lastReceivedCardAt,
              ackSig: ackSig,
            )
          : await exchange.fetchAndDiff(
              connection,
              follow,
              requesterPubkey: identity?.pubkey,
              ackRotationAt: follow.lastReceivedRotationAt,
              cardSeenAt: follow.lastReceivedCardAt,
              ackSig: ackSig,
            );
      if (!ranFull && diff.hasOlder) {
        // The window itself overflowed a manifest page — the diff is
        // incomplete. Redo as a full paged pass (acks were already
        // honored above, so omit them here).
        ranFull = true;
        diff = await exchange.fetchAndDiffFull(connection, follow);
      }
    } catch (e) {
      _log('manifest fetch failed for ${follow.pubkey}: $e');
      _reachability.markUnreachable(follow.pubkey, connection.transport, e);
      return PeerSyncReport(
        pubkey: follow.pubkey,
        status: PeerSyncStatus.unreachable,
        error: e.toString(),
      );
    }
    _log(
      'manifest diff for ${follow.pubkey}: peerEvents=${diff.peerEvents.length} '
      'missing=${diff.missingIds.length} windowSince=${diff.windowSince} '
      'newFeedKey=${diff.newFeedKey != null}',
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
    if (cardDelivery != null && identity != null) {
      try {
        currentFollow = await _applyConnectionCard(
          identity: identity,
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
      // Nothing to fetch. Advance the cursor only to author-time we
      // actually observed (never wall-clock — D1), stamp a completed full
      // pass, and drain the outbound queue so queued comments/likes don't
      // sit waiting just because no inbound work was due.
      await _advanceCursor(follow, diff);
      if (ranFull) {
        await _storage.updateLastFullSynced(
          follow.pubkey,
          _clock.nowUnixSeconds(),
        );
      }
      final drain = await _drainOutbound(currentFollow, connection);
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
      _log('envelope fetch failed for ${follow.pubkey}: $e');
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

    await _advanceCursor(follow, diff);
    if (ranFull) {
      await _storage.updateLastFullSynced(
        follow.pubkey,
        _clock.nowUnixSeconds(),
      );
    }
    _log(
      'sync complete for ${follow.pubkey}: inserted=$inserted skipped=$skipped '
      'unknownPreserved=$unknownPreserved',
    );

    final drain = await _drainOutbound(currentFollow, connection);

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

  /// D1: advance `lastSyncedAt` to the max author `created_at` observed in
  /// the manifest — never wall-clock. An empty window doesn't advance; the
  /// next window simply re-covers the same (cheap, id-deduped) range. A
  /// far-future `created_at` from a skewed clock is clamped so it can't
  /// jump the cursor past everything that follows it; `since` is inclusive
  /// so the boundary event harmlessly re-lists next pass.
  Future<void> _advanceCursor(Follow follow, ManifestDiff diff) async {
    final maxAt = diff.maxCreatedAt;
    if (maxAt == null) return;
    final clamped = math.min(
      maxAt,
      _clock.nowUnixSeconds() + kMaxCursorSkewSecs,
    );
    if (clamped > follow.lastSyncedAt) {
      await _storage.updateLastSynced(follow.pubkey, clamped);
    }
  }

  /// Drain the outbound queue toward [follow] — unless the connection is a
  /// relay. The relay's POST /events requires the OWNER's signature, so a
  /// follower envelope just 401s (D9); queued comments/likes target the
  /// owner's phone and wait for a direct tier (lan/tor/libp2p).
  Future<OutboundDrainResult> _drainOutbound(
    Follow follow,
    PeerConnection connection,
  ) async {
    if (connection.transport == PeerTransport.relay) {
      return const OutboundDrainResult(pushed: 0, dropped: 0, retried: 0);
    }
    return drainOutboundQueueForPeer(
      storage: _storage,
      transport: _transport,
      follow: follow,
      peer: connection,
    );
  }

  /// Decrypts an inline rotation payload and persists the new feed key
  /// for [follow] (Plan 13). Returns the updated [Follow] (with the new
  /// `feedKey` and `lastReceivedRotationAt`). Throws on DH/decrypt failure
  /// — caller logs and falls through.
  Future<Follow> _applyRotatedFeedKey({
    required Identity identity,
    required Follow follow,
    required SealedDelivery delivery,
  }) async {
    // Ignore a rotation no newer than one we've already applied: a replayed
    // *older* delivery still decrypts (its key binds its own createdAt), and
    // without this gate it would regress `follow.feedKey`. Safe to gate on
    // the wire `created_at` for the same reason as the card path below — an
    // inflated timestamp changes the derived key and fails decryption.
    if (delivery.createdAt < follow.lastReceivedRotationAt) return follow;

    final secretKey = await _ownSecretKeyLookup();
    if (secretKey == null) {
      throw StateError('no secret key available to apply rotated feed key');
    }
    final newKey = unsealDeliveryPayload(
      _crypto,
      senderEdPk: crockfordBase32Decode(follow.pubkey),
      recipientEdPk: crockfordBase32Decode(identity.pubkey),
      recipientSecretKey: secretKey,
      delivery: delivery,
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

  /// Decrypts and persists an updated Connection card from [delivery]
  /// (Plan 15). Returns the updated [Follow] (new `connectionCard` +
  /// `lastReceivedCardAt`), stored in the same `jsonEncode(card.toMap())`
  /// shape `PeerReachabilityMonitor` parses. Throws on decrypt/format
  /// mismatch — the caller logs and falls through.
  Future<Follow> _applyConnectionCard({
    required Identity identity,
    required Follow follow,
    required SealedDelivery delivery,
  }) async {
    // Ignore a card no newer than one we've already applied. Safe to gate
    // on the wire `created_at`: it's bound into the shared-key derivation,
    // so a replayed delivery with an inflated timestamp fails decryption
    // instead of pinning `lastReceivedCardAt`.
    if (delivery.createdAt < follow.lastReceivedCardAt) return follow;

    final secretKey = await _ownSecretKeyLookup();
    if (secretKey == null) {
      throw StateError('no secret key available to apply connection card');
    }
    final cardCbor = unsealDeliveryPayload(
      _crypto,
      senderEdPk: crockfordBase32Decode(follow.pubkey),
      recipientEdPk: crockfordBase32Decode(identity.pubkey),
      recipientSecretKey: secretKey,
      delivery: delivery,
    );
    final card = ConnectionCard.fromBytes(cardCbor);
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

  bool get hadFailures =>
      peers.any((p) => p.status == PeerSyncStatus.unreachable);
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
