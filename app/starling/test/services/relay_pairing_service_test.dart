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

  const onionEndpoints = [Endpoint(type: 'onion', address: 'phone.onion:80')];

  /// Service wired for tests. [pushClient] backs the RelayPushService used
  /// for the wire unpair notify; null [pushClient] simulates Tor down.
  RelayPairingService buildService({
    required MockStorageService storage,
    required KeyPair kp,
    http.Client? pairClient,
    http.Client? Function()? pushClient,
    List<Endpoint> Function()? endpoints,
  }) {
    return RelayPairingService(
      initiatorLookup: () => RelayPairingInitiator(
        crypto: crypto,
        httpClient: pairClient ?? MockClient((_) async => http.Response('', 200)),
      ),
      pushCoordinatorLookup: () async => buildCoordinator(storage, kp),
      pushServiceLookup: () {
        final client = (pushClient ?? () => MockClient((_) async => http.Response('', 200)))();
        return client == null
            ? null
            : RelayPushService(crypto: crypto, httpClient: client);
      },
      crypto: crypto,
      storage: storage,
      clock: MockClock(),
      identityLookup: storage.getIdentity,
      ownSecretKeyLookup: () async => kp.secretKey,
      ownEndpointsLookup: endpoints ?? () => onionEndpoints,
      reloadPairedRelay: () async {},
    );
  }

  Future<KeyPair> seedIdentity(MockStorageService storage) async {
    final kp = await crypto.generateKeyPair();
    await storage.saveIdentity(
      Identity(
        pubkey: crockfordBase32Encode(kp.publicKey),
        feedKey: Uint8List(32),
        createdAt: 0,
      ),
    );
    return kp;
  }

  Future<void> seedFollower(MockStorageService storage, String pubkey) =>
      storage.saveInboundRequest(
        FollowRequest(
          pubkey: pubkey,
          payload: Uint8List(0),
          createdAt: 0,
          requestTimestamp: 0,
          status: 'accepted',
        ),
      );

  /// Decrypt a queued card the way the follower's sync engine does:
  /// reverse the requester/responder derivation with the delivery's
  /// `createdAt` bound in.
  Uint8List unseal(
    KeyPair owner,
    KeyPair follower,
    PendingCardDistribution card,
  ) {
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
    final kp = await seedIdentity(storage);
    final ownerPubkey = crockfordBase32Encode(kp.publicKey);
    final followerA = await crypto.generateKeyPair();
    final followerB = await crypto.generateKeyPair();
    await seedFollower(storage, crockfordBase32Encode(followerA.publicKey));
    await seedFollower(storage, crockfordBase32Encode(followerB.publicKey));

    final service = buildService(
      storage: storage,
      kp: kp,
      pairClient: MockClient((req) async {
        expect(req.url.path, '/pair');
        return http.Response.bytes(
          cbor.encode(<String, dynamic>{
            'relay_onion': 'relayhost.onion',
            'relay_id': 'rid-1',
          }),
          200,
        );
      }),
      // Simulates `ownEndpoints` after the relay endpoint is advertised.
      endpoints: () => const [
        Endpoint(type: 'onion', address: 'phone.onion:80'),
        Endpoint(type: 'relay', address: 'relayhost.onion:80'),
      ],
    );

    final result = await service.pair(
      RelayPairingPayload(
        relayOnion: 'admin.onion',
        pairingToken: Uint8List.fromList(List.filled(32, 7)),
        relayVersion: '1',
      ),
    );

    expect(result.relayOnion, 'relayhost.onion');
    final paired = await storage.getPairedRelay();
    expect(paired?.relayOnion, 'relayhost.onion');
    // Fan-out completed → the crash marker is cleared again (A2).
    expect((await storage.getRelayFanoutState()).pendingCardFanout, isFalse);

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

  test('pair() refuses to fan out a degenerate card (no onion endpoint) '
      'and leaves the heal marker set; heal() finishes the job once the '
      'onion is back (A6 + A2)', () async {
    final storage = MockStorageService();
    final kp = await seedIdentity(storage);
    final followerA = await crypto.generateKeyPair();
    final followerAPubkey = crockfordBase32Encode(followerA.publicKey);
    await seedFollower(storage, followerAPubkey);

    var endpoints = const <Endpoint>[]; // Arti not published yet.
    final service = buildService(
      storage: storage,
      kp: kp,
      pairClient: MockClient(
        (_) async => http.Response.bytes(
          cbor.encode(<String, dynamic>{
            'relay_onion': 'relayhost.onion',
            'relay_id': 'rid-1',
          }),
          200,
        ),
      ),
      endpoints: () => endpoints,
    );

    await service.pair(
      RelayPairingPayload(
        relayOnion: 'admin.onion',
        pairingToken: Uint8List.fromList(List.filled(32, 7)),
        relayVersion: '1',
      ),
    );

    // Pairing succeeded, but no endpoint-less card was sealed.
    expect((await storage.getPairedRelay())?.relayOnion, 'relayhost.onion');
    expect(await storage.latestPendingCardFor(followerAPubkey), isNull);
    expect((await storage.getRelayFanoutState()).pendingCardFanout, isTrue);

    // Onion comes back → heal distributes and clears the marker.
    endpoints = const [
      Endpoint(type: 'onion', address: 'phone.onion:80'),
      Endpoint(type: 'relay', address: 'relayhost.onion:80'),
    ];
    await service.heal();
    final card = await storage.latestPendingCardFor(followerAPubkey);
    expect(card, isNotNull);
    final decoded = ConnectionCard.fromBytes(unseal(kp, followerA, card!));
    expect(decoded.endpoints.any((e) => e.type == 'relay'), isTrue);
    expect((await storage.getRelayFanoutState()).pendingCardFanout, isFalse);
  });

  test('unpair() forgets the relay, notifies it over the wire, and '
      'redistributes a relay-less card', () async {
    final storage = MockStorageService();
    final kp = await seedIdentity(storage);
    final followerA = await crypto.generateKeyPair();
    final followerAPubkey = crockfordBase32Encode(followerA.publicKey);
    await storage.setPairedRelay(
      relayId: 'rid-1',
      relayOnion: 'relayhost.onion',
      pairedAt: 1,
    );
    await seedFollower(storage, followerAPubkey);

    final unpairPosts = <http.Request>[];
    final service = buildService(
      storage: storage,
      kp: kp,
      pushClient: () => MockClient((req) async {
        if (req.url.path == '/unpair') {
          unpairPosts.add(req);
          return http.Response('', 200);
        }
        return http.Response('unexpected', 500);
      }),
    );

    await service.unpair();

    expect(await storage.getPairedRelay(), isNull);
    // The relay was told, with an owner-signed request (A3).
    expect(unpairPosts, hasLength(1));
    expect(unpairPosts.single.url.host, 'relayhost.onion');
    expect(
      unpairPosts.single.headers.keys.map((k) => k.toLowerCase()),
      containsAll(['x-starling-pubkey', 'x-starling-ts', 'x-starling-sig']),
    );
    final state = await storage.getRelayFanoutState();
    expect(state.pendingUnpairOnion, isNull);
    expect(state.pendingCardFanout, isFalse);
    final card = await storage.latestPendingCardFor(followerAPubkey);
    expect(card, isNotNull);
    final decoded = ConnectionCard.fromBytes(unseal(kp, followerA, card!));
    expect(decoded.endpoints.any((e) => e.type == 'relay'), isFalse);
  });

  test('unpair() with Tor down still unpairs locally; heal() delivers the '
      'wire notify later (A3 + A9)', () async {
    final storage = MockStorageService();
    final kp = await seedIdentity(storage);
    await storage.setPairedRelay(
      relayId: 'rid-1',
      relayOnion: 'relayhost.onion',
      pairedAt: 1,
    );

    var torUp = false;
    final unpairPosts = <http.Request>[];
    final service = buildService(
      storage: storage,
      kp: kp,
      pushClient: () => torUp
          ? MockClient((req) async {
              unpairPosts.add(req);
              return http.Response('', 200);
            })
          : null,
    );

    await service.unpair();

    // Local unpair landed without any network.
    expect(await storage.getPairedRelay(), isNull);
    expect(unpairPosts, isEmpty);
    expect(
      (await storage.getRelayFanoutState()).pendingUnpairOnion,
      'relayhost.onion',
    );

    // Tor still down: heal makes no progress but keeps the marker.
    await service.heal();
    expect(
      (await storage.getRelayFanoutState()).pendingUnpairOnion,
      'relayhost.onion',
    );

    torUp = true;
    await service.heal();
    expect(unpairPosts, hasLength(1));
    expect((await storage.getRelayFanoutState()).pendingUnpairOnion, isNull);
  });

  test('unpair notify treats any non-5xx answer as done — a 404 from an '
      'old relay must not retry forever', () async {
    final storage = MockStorageService();
    final kp = await seedIdentity(storage);
    await storage.setPairedRelay(
      relayId: 'rid-1',
      relayOnion: 'relayhost.onion',
      pairedAt: 1,
    );

    var posts = 0;
    final service = buildService(
      storage: storage,
      kp: kp,
      pushClient: () => MockClient((req) async {
        posts++;
        return http.Response('no such route', 404);
      }),
    );

    await service.unpair();
    expect(posts, 1);
    expect((await storage.getRelayFanoutState()).pendingUnpairOnion, isNull);
  });

  test('heal() gives up the unpair notify after the attempt cap', () async {
    final storage = MockStorageService();
    final kp = await seedIdentity(storage);
    await storage.setPairedRelay(
      relayId: 'rid-1',
      relayOnion: 'relayhost.onion',
      pairedAt: 1,
    );

    final service = buildService(
      storage: storage,
      kp: kp,
      // Every attempt is a transport failure (relay gone for good).
      pushClient: () =>
          MockClient((_) async => throw http.ClientException('refused')),
    );

    await service.unpair();
    expect(
      (await storage.getRelayFanoutState()).pendingUnpairOnion,
      'relayhost.onion',
    );

    for (var i = 0; i < kMaxUnpairNotifyAttempts; i++) {
      await service.heal();
      expect((await storage.getRelayFanoutState()).unpairNotifyAttempts, i + 1);
    }
    // The capped attempt count makes the NEXT heal give up.
    await service.heal();
    expect((await storage.getRelayFanoutState()).pendingUnpairOnion, isNull);
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

    // No identity saved in storage → lookup yields null.
    final service = buildService(storage: storage, kp: kp);

    await expectLater(service.unpair(), throwsStateError);

    // The relay row survives: a cleared row with no redistributed card
    // would strand followers on the dead relay.
    expect((await storage.getPairedRelay())?.relayOnion, 'relayhost.onion');
    expect(await storage.latestPendingCardFor(followerAPubkey), isNull);
    final state = await storage.getRelayFanoutState();
    expect(state.pendingCardFanout, isFalse);
    expect(state.pendingUnpairOnion, isNull);
  });
}
