import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import '../models/models.dart';
import '../sync/sealed_delivery.dart';
import 'clock.dart';
import 'crypto_service.dart';
import 'relay_pairing_initiator.dart';
import 'relay_push_coordinator.dart';
import 'relay_push_service.dart';
import 'storage_service.dart';
import 'types.dart';

/// The heal pass stops retrying `POST /unpair` after this many failed
/// attempts — the relay is simply gone (wiped by its admin, or its onion
/// key erased), and its copy of the card fan-out already tells followers
/// to stop probing it.
const int kMaxUnpairNotifyAttempts = 20;

/// Orchestrates the phone side of relay pairing (Plan 15): completes the
/// `/pair` handshake, persists the relay, seals the updated Connection
/// card to each existing follower, and kicks the one-shot backfill.
/// Also handles unpair (forget the relay locally, tell the relay to wipe
/// itself over the wire, and redistribute a relay-less card).
///
/// Card distribution reuses the Plan 13 key-rotation delivery path: one
/// `pending_card_distribution` row per follower (sealed with the same DH
/// construction as a wrapped feed key), picked up on their next
/// `/manifest` response and acked via `card_seen_at`.
///
/// Crash safety (A2/A3): both [pair] and [unpair] set persisted markers
/// (`RelayFanoutState`) BEFORE mutating pairing state and clear them only
/// after the side effect lands — card sealed + queued for every follower,
/// relay's `POST /unpair` answered. [heal] (run from the reconcile tick)
/// retries whatever a crash, a Tor outage, or the degenerate-card guard
/// left pending.
///
/// Construction is Tor-independent (A9): the Tor-gated collaborators are
/// injected as lookups resolved at call time, so local unpair works with
/// Tor down — only the best-effort wire notify waits for the heal pass.
class RelayPairingService {
  RelayPairingService({
    required RelayPairingInitiator? Function() initiatorLookup,
    required Future<RelayPushCoordinator?> Function() pushCoordinatorLookup,
    required RelayPushService? Function() pushServiceLookup,
    required CryptoService crypto,
    required StorageService storage,
    required Clock clock,
    required Future<Identity?> Function() identityLookup,
    required Future<Uint8List?> Function() ownSecretKeyLookup,
    required List<Endpoint> Function() ownEndpointsLookup,
    required Future<void> Function() reloadPairedRelay,
  }) : _initiatorLookup = initiatorLookup,
       _pushCoordinatorLookup = pushCoordinatorLookup,
       _pushServiceLookup = pushServiceLookup,
       _crypto = crypto,
       _storage = storage,
       _clock = clock,
       _identityLookup = identityLookup,
       _ownSecretKeyLookup = ownSecretKeyLookup,
       _ownEndpointsLookup = ownEndpointsLookup,
       _reloadPairedRelay = reloadPairedRelay;

  final RelayPairingInitiator? Function() _initiatorLookup;
  final Future<RelayPushCoordinator?> Function() _pushCoordinatorLookup;
  final RelayPushService? Function() _pushServiceLookup;
  final CryptoService _crypto;
  final StorageService _storage;
  final Clock _clock;
  final Future<Identity?> Function() _identityLookup;
  final Future<Uint8List?> Function() _ownSecretKeyLookup;
  final List<Endpoint> Function() _ownEndpointsLookup;
  final Future<void> Function() _reloadPairedRelay;

  /// Run the full pairing sequence for a scanned [payload]. Throws
  /// [RelayPairingException] on handshake failure and [StateError] when
  /// identity or Tor isn't ready (both surfaced to the UI).
  Future<RelayPairingResult> pair(RelayPairingPayload payload) async {
    final identity = await _identityLookup();
    final secretKey = await _ownSecretKeyLookup();
    if (identity == null || secretKey == null) {
      throw StateError('identity not ready for relay pairing');
    }
    final initiator = _initiatorLookup();
    if (initiator == null) {
      throw StateError('Tor not ready for relay pairing');
    }
    final result = await initiator.claim(
      payload: payload,
      ownerPubkeyStoredText: identity.pubkey,
      ownerSecretKey: secretKey,
    );
    // Marker first: a crash after the row lands but before the card fans
    // out must leave evidence for the heal pass — a relay advertised to no
    // follower serves nobody.
    await _storage.setPendingCardFanout(true);
    await _storage.setPairedRelay(
      relayId: result.relayId,
      relayOnion: result.relayOnion,
      pairedAt: _clock.nowUnixSeconds(),
    );
    // Make the relay endpoint live in `ownEndpoints` BEFORE we sign the
    // card we hand to followers.
    await _reloadPairedRelay();
    if (await _distributeCard(identity, secretKey)) {
      await _storage.setPendingCardFanout(false);
    }
    // Backfill can be large; don't block the pairing UI on it.
    unawaited(
      _pushCoordinatorLookup().then((coordinator) => coordinator?.backfill()),
    );
    return result;
  }

  /// Forget the paired relay, tell it to wipe itself (best-effort over
  /// Tor), and redistribute a relay-less card so followers stop probing an
  /// endpoint that will no longer serve them. The local mutation never
  /// depends on the network: with Tor down the wire notify is left to the
  /// heal pass. Throws [StateError] before mutating anything if the
  /// identity isn't available — a half-unpair (row cleared, card never
  /// redistributed) would leave followers probing the dead relay forever.
  Future<void> unpair() async {
    final identity = await _identityLookup();
    final secretKey = await _ownSecretKeyLookup();
    if (identity == null || secretKey == null) {
      throw StateError('identity not ready for relay unpair');
    }
    final relay = await _storage.getPairedRelay();
    // One atomic step: heal markers + row delete. Split writes would open
    // a crash window where the relay gets wiped by the heal pass while
    // the phone still believes it's paired (or vice versa).
    if (relay != null) {
      await _storage.beginRelayUnpair(relay.relayOnion);
    } else {
      await _storage.setPendingCardFanout(true);
      await _storage.clearPairedRelay();
    }
    // Make the card relay-less BEFORE we seal it for followers.
    await _reloadPairedRelay();
    if (relay != null && await _notifyRelayUnpair(relay.relayOnion)) {
      await _storage.setPendingUnpair(null);
    }
    if (await _distributeCard(identity, secretKey)) {
      await _storage.setPendingCardFanout(false);
    }
  }

  /// Retry whatever pair/unpair left pending (A2/A3): the wire unpair
  /// notify and the Connection card fan-out. Run from the reconcile tick
  /// (which also covers startup). Never throws.
  Future<void> heal() async {
    try {
      final state = await _storage.getRelayFanoutState();
      final unpairOnion = state.pendingUnpairOnion;
      if (unpairOnion != null) {
        if (state.unpairNotifyAttempts >= kMaxUnpairNotifyAttempts) {
          developer.log(
            'giving up unpair notify to $unpairOnion after '
            '${state.unpairNotifyAttempts} attempts',
            name: 'relay_pairing',
          );
          await _storage.setPendingUnpair(null);
        } else if (await _notifyRelayUnpair(unpairOnion)) {
          await _storage.setPendingUnpair(null);
        } else {
          await _storage.incrementUnpairNotifyAttempts();
        }
      }
      if (state.pendingCardFanout) {
        final identity = await _identityLookup();
        final secretKey = await _ownSecretKeyLookup();
        if (identity == null || secretKey == null) return;
        if (await _distributeCard(identity, secretKey)) {
          await _storage.setPendingCardFanout(false);
          developer.log('healed pending card fan-out', name: 'relay_pairing');
        }
      }
    } catch (e) {
      developer.log('relay heal pass failed: $e', name: 'relay_pairing');
    }
  }

  /// Best-effort `POST /unpair`. Returns true when the notify is DONE —
  /// either the relay answered 200, or it answered anything else < 500
  /// (403: it already forgot us; 404: an old relay without the route —
  /// retrying can't help). Transport errors and 5xx return false so the
  /// heal pass retries.
  Future<bool> _notifyRelayUnpair(String relayOnion) async {
    final push = _pushServiceLookup();
    if (push == null) return false; // Tor not up — heal pass retries.
    final identity = await _identityLookup();
    final secretKey = await _ownSecretKeyLookup();
    if (identity == null || secretKey == null) return false;
    try {
      await push.unpairRelay(
        relayBaseUrl: httpBaseUrlForAddress(relayOnion),
        ownerPubkeyBytes: decodeStoredPubkey(identity.pubkey),
        ownerSecretKey: secretKey,
      );
      return true;
    } on RelayPushException catch (e) {
      developer.log('unpair notify failed: $e', name: 'relay_pairing');
      final status = e.statusCode;
      return status != null && status < 500;
    } catch (e) {
      developer.log('unpair notify failed: $e', name: 'relay_pairing');
      return false;
    }
  }

  /// Seal the current Connection card to every accepted follower. Returns
  /// false WITHOUT sealing when the card would be degenerate (A6): the
  /// endpoint list has no phone onion — Arti not yet published, or the
  /// 30s pause-debounce nulled it — and a card that names no way to reach
  /// the phone must never fan out. The pending marker stays set and the
  /// heal pass retries once the onion is back.
  Future<bool> _distributeCard(Identity identity, Uint8List secretKey) async {
    final endpoints = _ownEndpointsLookup();
    if (!endpoints.any((e) => e.type == 'onion')) {
      developer.log(
        'refusing to fan out a card with no onion endpoint '
        '(${endpoints.length} endpoints); heal pass will retry',
        name: 'relay_pairing',
      );
      return false;
    }
    final card = ConnectionCard(pubkey: identity.pubkey, endpoints: endpoints);
    // Sealing (see `sync/sealed_delivery.dart`) binds `now` into the DH
    // derivation and authenticates us as the author. Note this does NOT
    // keep the card from a removed-but-not-yet-cleared follower (they
    // still hold valid keys); FollowService.removeFollower clears their
    // pending rows for that.
    await sealAndQueueForAcceptedFollowers(
      crypto: _crypto,
      storage: _storage,
      channel: connectionCardChannel,
      identity: identity,
      secretKey: secretKey,
      plaintext: card.toBytes(),
      createdAt: _clock.nowUnixSeconds(),
    );
    return true;
  }
}
