import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starling/models/models.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/mocks/mock_clock.dart';
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/relay_pairing_initiator.dart';
import 'package:starling/services/relay_pairing_service.dart';
import 'package:starling/services/relay_push_coordinator.dart';
import 'package:starling/services/relay_push_service.dart';
import 'package:starling/services/types.dart';

void main() {
  late SodiumCryptoService crypto;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  RelayPushCoordinator buildCoordinator(
    MockStorageService storage,
    KeyPair kp,
  ) {
    return RelayPushCoordinator(
      pushService: RelayPushService(
        crypto: crypto,
        httpClient: MockClient((_) async => http.Response('', 202)),
      ),
      storage: storage,
      relayClient: MockClient(
        (_) async => http.Response.bytes(
          cbor.encode(<String, dynamic>{'events': <dynamic>[]}),
          200,
        ),
      ),
      identityLookup: storage.getIdentity,
      ownSecretKeyLookup: () async => kp.secretKey,
      mediaBytesLookup: (_) async => null,
    );
  }

  Future<void> seedFollower(MockStorageService storage, String pubkey) =>
      storage.saveInboundRequest(FollowRequest(
        pubkey: pubkey,
        payload: Uint8List(0),
        createdAt: 0,
        requestTimestamp: 0,
        status: 'accepted',
      ));

  /// Decrypt a queued card the way the follower's sync engine does:
  /// reverse the requester/responder derivation with the delivery's
  /// `createdAt` bound in.
  Uint8List unseal(KeyPair owner, KeyPair follower, PendingCardDistribution card) {
    final shared = crypto.deriveSharedKey(
      crypto.ed25519ToX25519SecretKey(follower.secretKey),
      crypto.ed25519ToX25519PublicKey(owner.publicKey),
      owner.publicKey,
      follower.publicKey,
      card.createdAt,
    );
    return crypto.decrypt(card.encryptedCard, card.nonce, shared);
  }

  test('pair() persists the relay and queues a sealed card to each '
      'follower with the relay endpoint', () async {
    final storage = MockStorageService();
    final kp = await crypto.generateKeyPair();
    final followerA = await crypto.generateKeyPair();
    final followerB = await crypto.generateKeyPair();
    final ownerPubkey = crockfordBase32Encode(kp.publicKey);
    await storage.saveIdentity(
      Identity(pubkey: ownerPubkey, feedKey: Uint8List(32), createdAt: 0),
    );
    await seedFollower(storage, crockfordBase32Encode(followerA.publicKey));
    await seedFollower(storage, crockfordBase32Encode(followerB.publicKey));

    final initiator = RelayPairingInitiator(
      crypto: crypto,
      httpClient: MockClient((req) async {
        expect(req.url.path, '/pair');
        return http.Response.bytes(
          cbor.encode(<String, dynamic>{
            'relay_onion': 'relayhost.onion',
            'relay_id': 'rid-1',
          }),
          200,
        );
      }),
    );

    final service = RelayPairingService(
      initiator: initiator,
      pushCoordinator: buildCoordinator(storage, kp),
      crypto: crypto,
      storage: storage,
      clock: MockClock(),
      identityLookup: storage.getIdentity,
      ownSecretKeyLookup: () async => kp.secretKey,
      // Simulates `ownEndpoints` after the relay endpoint is advertised.
      ownEndpointsLookup: () => const [
        Endpoint(type: 'onion', address: 'phone.onion:80'),
        Endpoint(type: 'relay', address: 'relayhost.onion:80'),
      ],
      reloadPairedRelay: () async {},
    );

    final result = await service.pair(RelayPairingPayload(
      relayOnion: 'admin.onion',
      pairingToken: Uint8List.fromList(List.filled(32, 7)),
      relayVersion: '1',
    ));

    expect(result.relayOnion, 'relayhost.onion');
    final paired = await storage.getPairedRelay();
    expect(paired?.relayOnion, 'relayhost.onion');

    for (final follower in [followerA, followerB]) {
      final f = crockfordBase32Encode(follower.publicKey);
      final card = await storage.latestPendingCardFor(f);
      expect(card, isNotNull, reason: 'card queued for $f');
      final decoded = ConnectionCard.fromBytes(unseal(kp, follower, card!));
      expect(decoded.pubkey, ownerPubkey);
      expect(decoded.endpoints.any((e) => e.type == 'relay'), isTrue);
      // Sealed per recipient: the other follower's key must NOT open it.
      final other = identical(follower, followerA) ? followerB : followerA;
      expect(() => unseal(kp, other, card), throwsA(anything));
    }
  });

  test('unpair() forgets the relay and redistributes a relay-less card',
      () async {
    final storage = MockStorageService();
    final kp = await crypto.generateKeyPair();
    final followerA = await crypto.generateKeyPair();
    final followerAPubkey = crockfordBase32Encode(followerA.publicKey);
    final ownerPubkey = crockfordBase32Encode(kp.publicKey);
    await storage.saveIdentity(
      Identity(pubkey: ownerPubkey, feedKey: Uint8List(32), createdAt: 0),
    );
    await storage.setPairedRelay(
      relayId: 'rid-1',
      relayOnion: 'relayhost.onion',
      pairedAt: 1,
    );
    await seedFollower(storage, followerAPubkey);

    final service = RelayPairingService(
      initiator: RelayPairingInitiator(
        crypto: crypto,
        httpClient: MockClient((_) async => http.Response('', 200)),
      ),
      pushCoordinator: buildCoordinator(storage, kp),
      crypto: crypto,
      storage: storage,
      clock: MockClock(),
      identityLookup: storage.getIdentity,
      ownSecretKeyLookup: () async => kp.secretKey,
      ownEndpointsLookup: () =>
          const [Endpoint(type: 'onion', address: 'phone.onion:80')],
      reloadPairedRelay: () async {},
    );

    await service.unpair();

    expect(await storage.getPairedRelay(), isNull);
    final card = await storage.latestPendingCardFor(followerAPubkey);
    expect(card, isNotNull);
    final decoded = ConnectionCard.fromBytes(unseal(kp, followerA, card!));
    expect(decoded.endpoints.any((e) => e.type == 'relay'), isFalse);
  });

  test('unpair() throws before mutating anything when identity is '
      'unavailable — no half-unpair', () async {
    final storage = MockStorageService();
    final kp = await crypto.generateKeyPair();
    final followerA = await crypto.generateKeyPair();
    final followerAPubkey = crockfordBase32Encode(followerA.publicKey);
    await storage.setPairedRelay(
      relayId: 'rid-1',
      relayOnion: 'relayhost.onion',
      pairedAt: 1,
    );
    await seedFollower(storage, followerAPubkey);

    final service = RelayPairingService(
      initiator: RelayPairingInitiator(
        crypto: crypto,
        httpClient: MockClient((_) async => http.Response('', 200)),
      ),
      pushCoordinator: buildCoordinator(storage, kp),
      crypto: crypto,
      storage: storage,
      clock: MockClock(),
      // No identity saved in storage → lookup yields null.
      identityLookup: storage.getIdentity,
      ownSecretKeyLookup: () async => kp.secretKey,
      ownEndpointsLookup: () =>
          const [Endpoint(type: 'onion', address: 'phone.onion:80')],
      reloadPairedRelay: () async {},
    );

    await expectLater(service.unpair(), throwsStateError);

    // The relay row survives: a cleared row with no redistributed card
    // would strand followers on the dead relay.
    expect((await storage.getPairedRelay())?.relayOnion, 'relayhost.onion');
    expect(await storage.latestPendingCardFor(followerAPubkey), isNull);
  });
}
