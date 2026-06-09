import 'dart:async';
import 'dart:typed_data';

import '../models/models.dart';
import 'clock.dart';
import 'crypto_service.dart';
import 'relay_pairing_initiator.dart';
import 'relay_push_coordinator.dart';
import 'storage_service.dart';
import 'types.dart';

/// Orchestrates the phone side of relay pairing (Plan 15): completes the
/// `/pair` handshake, persists the relay, re-signs and fans the updated
/// Connection card to existing followers, and kicks the one-shot backfill.
/// Also handles unpair (forget the relay + redistribute a relay-less card).
///
/// Card distribution reuses the Plan 13 key-rotation delivery path: one
/// `pending_card_distribution` row per follower, picked up on their next
/// `/manifest` response and acked via `card_seen_at`.
class RelayPairingService {
  RelayPairingService({
    required RelayPairingInitiator initiator,
    required RelayPushCoordinator pushCoordinator,
    required CryptoService crypto,
    required StorageService storage,
    required Clock clock,
    required Future<Identity?> Function() identityLookup,
    required Future<Uint8List?> Function() ownSecretKeyLookup,
    required List<Endpoint> Function() ownEndpointsLookup,
    required Future<void> Function() reloadPairedRelay,
  })  : _initiator = initiator,
        _pushCoordinator = pushCoordinator,
        _crypto = crypto,
        _storage = storage,
        _clock = clock,
        _identityLookup = identityLookup,
        _ownSecretKeyLookup = ownSecretKeyLookup,
        _ownEndpointsLookup = ownEndpointsLookup,
        _reloadPairedRelay = reloadPairedRelay;

  final RelayPairingInitiator _initiator;
  final RelayPushCoordinator _pushCoordinator;
  final CryptoService _crypto;
  final StorageService _storage;
  final Clock _clock;
  final Future<Identity?> Function() _identityLookup;
  final Future<Uint8List?> Function() _ownSecretKeyLookup;
  final List<Endpoint> Function() _ownEndpointsLookup;
  final Future<void> Function() _reloadPairedRelay;

  /// Run the full pairing sequence for a scanned [payload]. Throws
  /// [RelayPairingException] on handshake failure (surfaced to the UI).
  Future<RelayPairingResult> pair(RelayPairingPayload payload) async {
    final identity = await _identityLookup();
    final secretKey = await _ownSecretKeyLookup();
    if (identity == null || secretKey == null) {
      throw StateError('identity not ready for relay pairing');
    }
    final result = await _initiator.claim(
      payload: payload,
      ownerPubkeyStoredText: identity.pubkey,
      ownerSecretKey: secretKey,
    );
    await _storage.setPairedRelay(
      relayId: result.relayId,
      relayOnion: result.relayOnion,
      pairedAt: _clock.nowUnixSeconds(),
    );
    // Make the relay endpoint live in `ownEndpoints` BEFORE we sign the
    // card we hand to followers.
    await _reloadPairedRelay();
    await _distributeCard(identity, secretKey);
    // Backfill can be large; don't block the pairing UI on it.
    unawaited(_pushCoordinator.backfill());
    return result;
  }

  /// Forget the paired relay and redistribute a relay-less card so
  /// followers stop probing an endpoint that will no longer serve them.
  Future<void> unpair() async {
    await _storage.clearPairedRelay();
    await _reloadPairedRelay();
    final identity = await _identityLookup();
    final secretKey = await _ownSecretKeyLookup();
    if (identity != null && secretKey != null) {
      await _distributeCard(identity, secretKey);
    }
  }

  Future<void> _distributeCard(Identity identity, Uint8List secretKey) async {
    final card = ConnectionCard(
      pubkey: identity.pubkey,
      endpoints: _ownEndpointsLookup(),
    );
    final cardCbor = card.toBytes();
    final sig = _crypto.sign(secretKey, cardCbor);
    final now = _clock.nowUnixSeconds();
    final followers = await _storage.getAcceptedFollowerPubkeys();
    for (final pubkey in followers) {
      await _storage.queueCardDistribution(
        targetPubkey: pubkey,
        cardCbor: cardCbor,
        sig: sig,
        createdAt: now,
      );
    }
  }
}
