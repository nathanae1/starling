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

  test('pair() persists the relay and queues a verifiable card to each '
      'follower with the relay endpoint', () async {
    final storage = MockStorageService();
    final kp = await crypto.generateKeyPair();
    final ownerPubkey = crockfordBase32Encode(kp.publicKey);
    await storage.saveIdentity(
      Identity(pubkey: ownerPubkey, feedKey: Uint8List(32), createdAt: 0),
    );
    await seedFollower(storage, 'follower-a');
    await seedFollower(storage, 'follower-b');

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

    for (final f in ['follower-a', 'follower-b']) {
      final card = await storage.latestPendingCardFor(f);
      expect(card, isNotNull, reason: 'card queued for $f');
      expect(crypto.verify(kp.publicKey, card!.cardCbor, card.sig), isTrue);
      final decoded = ConnectionCard.fromBytes(card.cardCbor);
      expect(decoded.pubkey, ownerPubkey);
      expect(decoded.endpoints.any((e) => e.type == 'relay'), isTrue);
    }
  });

  test('unpair() forgets the relay and redistributes a relay-less card',
      () async {
    final storage = MockStorageService();
    final kp = await crypto.generateKeyPair();
    final ownerPubkey = crockfordBase32Encode(kp.publicKey);
    await storage.saveIdentity(
      Identity(pubkey: ownerPubkey, feedKey: Uint8List(32), createdAt: 0),
    );
    await storage.setPairedRelay(
      relayId: 'rid-1',
      relayOnion: 'relayhost.onion',
      pairedAt: 1,
    );
    await seedFollower(storage, 'follower-a');

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
    final card = await storage.latestPendingCardFor('follower-a');
    expect(card, isNotNull);
    final decoded = ConnectionCard.fromBytes(card!.cardCbor);
    expect(decoded.endpoints.any((e) => e.type == 'relay'), isFalse);
  });
}
