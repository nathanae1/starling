import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:starling/models/connection_card.dart';
import 'package:starling/server/handlers/follow_accept_handler.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/follow_service.dart';
import 'package:starling/services/mocks/mock_clock.dart';
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

import '../helpers/fake_peer_reachability_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SodiumCryptoService crypto;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  group('followAcceptHandler', () {
    late MockStorageService storage;
    late MockClock clock;
    late FollowService service;
    late Identity ownIdentity;
    late Uint8List ownSecretKey;
    late Identity peerIdentity;
    late Uint8List peerSecretKey;
    late int handshakeTimestamp;

    setUp(() async {
      clock = MockClock(2_000_000);
      storage = MockStorageService();

      // "We" are the requester (alice). Peer is bob — they're accepting.
      final aliceKp = await crypto.generateKeyPair();
      final bobKp = await crypto.generateKeyPair();
      ownIdentity = Identity(
        pubkey: crockfordBase32Encode(aliceKp.publicKey),
        feedKey: crypto.randomBytes(32),
        feedKeyEpoch: 4,
        createdAt: 1_500_000,
      );
      ownSecretKey = aliceKp.secretKey;
      peerIdentity = Identity(
        pubkey: crockfordBase32Encode(bobKp.publicKey),
        feedKey: crypto.randomBytes(32),
        feedKeyEpoch: 9,
        createdAt: 1_400_000,
      );
      peerSecretKey = bobKp.secretKey;

      await storage.saveIdentity(ownIdentity);
      handshakeTimestamp = 1_900_000;
      await storage.saveOutboundRequest(
        FollowRequest(
          pubkey: peerIdentity.pubkey,
          payload: ConnectionCard(
            pubkey: peerIdentity.pubkey,
            endpoints: const [
              Endpoint(type: 'direct', address: 'bob.local:9000'),
            ],
          ).toBytes(),
          createdAt: handshakeTimestamp,
          requestTimestamp: handshakeTimestamp,
        ),
      );

      service = FollowService(
        crypto: crypto,
        storage: storage,
        clock: clock,
        transport: HandshakeTransport(http.Client()),
        reachabilityMonitor: FakePeerReachabilityMonitor(),
        identityLookup: storage.getIdentity,
        ownSecretKeyLookup: () async => ownSecretKey,
        ownEndpointsLookup: () async => const [],
      );
    });

    tearDown(() => storage.dispose());

    Uint8List buildAcceptBody({
      Uint8List? feedKeyOverride,
      int? timestampOverride,
      int? epochOverride,
    }) {
      final timestamp = timestampOverride ?? handshakeTimestamp;
      final feedKey = feedKeyOverride ?? peerIdentity.feedKey;
      final myEdPk = crockfordBase32Decode(peerIdentity.pubkey);
      final theirEdPk = crockfordBase32Decode(ownIdentity.pubkey);
      final myXSk = crypto.ed25519ToX25519SecretKey(peerSecretKey);
      final theirXPk = crypto.ed25519ToX25519PublicKey(theirEdPk);
      final sharedKey = crypto.deriveSharedKey(
        myXSk,
        theirXPk,
        theirEdPk,
        myEdPk,
        timestamp,
      );
      final nonce = crypto.randomBytes(24);
      final ct = crypto.encrypt(feedKey, nonce, sharedKey);
      return Uint8List.fromList(
        cbor.encode(<String, dynamic>{
          'owner_pubkey': peerIdentity.pubkey,
          'encrypted_feed_key': ct,
          'nonce': nonce,
          'epoch': epochOverride ?? peerIdentity.feedKeyEpoch,
          'timestamp': timestamp,
        }),
      );
    }

    Future<Response> postBytes(Uint8List body) async {
      final handler = followAcceptHandler(followService: service);
      return handler(
        Request(
          'POST',
          Uri.parse('http://localhost/follow-accept'),
          body: body,
        ),
      );
    }

    test('valid CBOR → 202 + follows row written', () async {
      final res = await postBytes(buildAcceptBody());
      expect(res.statusCode, 202);
      final follow = await storage.getFollow(peerIdentity.pubkey);
      expect(follow, isNotNull);
      expect(follow!.feedKey, equals(peerIdentity.feedKey));
      expect(follow.feedKeyEpoch, equals(peerIdentity.feedKeyEpoch));
      // Outbound row consumed.
      expect(await storage.getOutboundRequests(), isEmpty);
    });

    test('invalid CBOR → 400', () async {
      final res = await postBytes(Uint8List.fromList([0xff, 0xff]));
      expect(res.statusCode, 400);
      expect(await storage.getFollow(peerIdentity.pubkey), isNull);
    });

    test('missing owner_pubkey → 400', () async {
      final body = Uint8List.fromList(
        cbor.encode(<String, dynamic>{
          'encrypted_feed_key': Uint8List(32),
          'nonce': Uint8List(24),
          'epoch': 1,
          'timestamp': 1,
        }),
      );
      final res = await postBytes(body);
      expect(res.statusCode, 400);
    });

    test('unknown owner (no outbound row) → 404', () async {
      final body = buildAcceptBody();
      // Wipe the outbound row.
      await storage.deleteOutboundRequest(peerIdentity.pubkey);
      final res = await postBytes(body);
      expect(res.statusCode, 404);
    });

    test('timestamp mismatch → 400 (decryption-class failure)', () async {
      final res = await postBytes(
        buildAcceptBody(timestampOverride: handshakeTimestamp + 999),
      );
      expect(res.statusCode, 400);
      expect(await storage.getFollow(peerIdentity.pubkey), isNull);
    });
  });
}
