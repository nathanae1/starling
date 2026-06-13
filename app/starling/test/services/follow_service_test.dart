import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:starling/models/connection_card.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/crypto_service.dart';
import 'package:starling/services/follow_service.dart';
import 'package:starling/services/mocks/mock_clock.dart';
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../helpers/fake_peer_reachability_monitor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService crypto;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  group('FollowService handshake', () {
    late _Peer alice;
    late _Peer bob;
    late _PairTransport transport;

    setUp(() async {
      alice = await _Peer.build(crypto, label: 'alice');
      bob = await _Peer.build(crypto, label: 'bob');
      transport = _PairTransport({
        alice.baseUrl: alice,
        bob.baseUrl: bob,
      });
      alice.attachTransport(transport, peer: bob);
      bob.attachTransport(transport, peer: alice);
    });

    tearDown(() async {
      await alice.storage.dispose();
      await bob.storage.dispose();
    });

    test('alice → bob: alice ends up with bob\'s feed key + connection card',
        () async {
      await alice.service.sendFollowRequest(bob.connectionCard());
      // Bob now has an inbound row.
      expect(await bob.storage.getInboundRequests(), hasLength(1));

      final delivery =
          await bob.service.acceptFollowRequest(alice.identity.pubkey);
      expect(delivery, AcceptDelivery.delivered);

      final follow = await alice.storage.getFollow(bob.identity.pubkey);
      expect(follow, isNotNull);
      expect(follow!.feedKey, equals(bob.identity.feedKey));
      expect(follow.feedKeyEpoch, equals(bob.identity.feedKeyEpoch));

      // Inbound row marked accepted (so it disappears from pending).
      expect(await bob.storage.getInboundRequests(), isEmpty);
      // Outbound row consumed.
      expect(await alice.storage.getOutboundRequests(), isEmpty);
      // No leftover queue entries.
      expect(await alice.storage.dequeue(bob.identity.pubkey), isEmpty);
    });

    test('reject deletes inbound row, no follows write', () async {
      await alice.service.sendFollowRequest(bob.connectionCard());
      expect(await bob.storage.getInboundRequests(), hasLength(1));

      await bob.service.rejectFollowRequest(alice.identity.pubkey);

      expect(await bob.storage.getInboundRequests(), isEmpty);
      expect(await bob.storage.getFollow(alice.identity.pubkey), isNull);
    });

    test('accept queues retry when transport fails', () async {
      await alice.service.sendFollowRequest(bob.connectionCard());

      // Make the transport fail when bob tries to deliver to alice.
      transport.failNextAcceptTo = alice.baseUrl;
      final delivery =
          await bob.service.acceptFollowRequest(alice.identity.pubkey);
      expect(delivery, AcceptDelivery.queued);

      // Inbound row stays around in pending-send state.
      final pending =
          await bob.storage.getInboundRequestsByStatus('pending-send');
      expect(pending, hasLength(1));
      // A queue entry exists for alice.
      final queued = await bob.storage.dequeue(alice.identity.pubkey);
      expect(queued, hasLength(1));

      // On the next pump, transport works → accept lands.
      transport.failNextAcceptTo = null;
      await bob.service.retryQueuedAccepts();
      expect(await bob.storage.dequeue(alice.identity.pubkey), isEmpty);
      expect(
        await bob.storage.getInboundRequestsByStatus('pending-send'),
        isEmpty,
      );
      final follow = await alice.storage.getFollow(bob.identity.pubkey);
      expect(follow, isNotNull);
      expect(follow!.feedKey, equals(bob.identity.feedKey));
    });

    test('flips to send-failed at threshold, keeps the entry, then recovers',
        () async {
      await alice.service.sendFollowRequest(bob.connectionCard());
      transport.failNextAcceptTo = alice.baseUrl;
      transport.failPersistently = true;
      expect(
        await bob.service.acceptFollowRequest(alice.identity.pubkey),
        AcceptDelivery.queued,
      );

      // Three failing attempts reach the threshold. Advancing the clock past
      // each backoff window guarantees an attempt every pass.
      for (var i = 0; i < 3; i++) {
        bob.clock.advance(3600);
        await bob.service.retryQueuedAccepts(failedStatusThreshold: 3);
      }

      // Row flips to send-failed for the UI...
      expect(
        await bob.storage.getInboundRequestsByStatus('send-failed'),
        hasLength(1),
      );
      // ...but the queue entry is KEPT and keeps retrying (never stranded).
      expect(await bob.storage.dequeue(alice.identity.pubkey), hasLength(1));

      // A later success recovers the row to accepted and delivers the key.
      transport.failPersistently = false;
      transport.failNextAcceptTo = null;
      bob.clock.advance(3600);
      await bob.service.retryQueuedAccepts(failedStatusThreshold: 3);

      expect(await bob.storage.dequeue(alice.identity.pubkey), isEmpty);
      expect(
        await bob.storage.getInboundRequestsByStatus('send-failed'),
        isEmpty,
      );
      final follow = await alice.storage.getFollow(bob.identity.pubkey);
      expect(follow!.feedKey, equals(bob.identity.feedKey));
    });

    test('backoff: no second attempt before the window, one after', () async {
      await alice.service.sendFollowRequest(bob.connectionCard());
      transport.failNextAcceptTo = alice.baseUrl;
      transport.failPersistently = true;
      await bob.service.acceptFollowRequest(alice.identity.pubkey);
      transport.acceptPostCount = 0;

      // First pass attempts (entry never tried this session).
      await bob.service.retryQueuedAccepts();
      expect(transport.acceptPostCount, 1);

      // Immediate second pass is inside the backoff window → no attempt.
      await bob.service.retryQueuedAccepts();
      expect(transport.acceptPostCount, 1);

      // Past the window → attempts again.
      bob.clock.advance(3600);
      await bob.service.retryQueuedAccepts();
      expect(transport.acceptPostCount, 2);
    });

    test('HandshakeTransportException (our Tor down) is not counted', () async {
      await alice.service.sendFollowRequest(bob.connectionCard());
      transport.throwNotReadyOnAccept = true;
      // acceptFollowRequest swallows the throw and queues.
      expect(
        await bob.service.acceptFollowRequest(alice.identity.pubkey),
        AcceptDelivery.queued,
      );
      transport.acceptPostCount = 0;

      // Many passes while Tor is "down": no delivery attempt, no retry spent.
      for (var i = 0; i < 5; i++) {
        bob.clock.advance(3600);
        await bob.service.retryQueuedAccepts(failedStatusThreshold: 3);
      }
      expect(transport.acceptPostCount, 0);
      final entry = (await bob.storage.dequeue(alice.identity.pubkey)).single;
      expect(entry.retryCount, 0, reason: 'local failures must not count');
      expect(
        await bob.storage.getInboundRequestsByStatus('pending-send'),
        hasLength(1),
      );

      // Tor recovers → delivered on the next pass with no backoff to wait.
      transport.throwNotReadyOnAccept = false;
      await bob.service.retryQueuedAccepts(failedStatusThreshold: 3);
      expect(await bob.storage.dequeue(alice.identity.pubkey), isEmpty);
      final follow = await alice.storage.getFollow(bob.identity.pubkey);
      expect(follow!.feedKey, equals(bob.identity.feedKey));
    });

    test('a send-failed row is still retried and recovers', () async {
      await alice.service.sendFollowRequest(bob.connectionCard());
      transport.failNextAcceptTo = alice.baseUrl;
      transport.failPersistently = true;
      await bob.service.acceptFollowRequest(alice.identity.pubkey);
      // Force the terminal-looking status directly; the entry is still queued.
      await bob.storage
          .updateInboundRequestStatus(alice.identity.pubkey, 'send-failed');

      transport.failPersistently = false;
      transport.failNextAcceptTo = null;
      bob.clock.advance(3600);
      await bob.service.retryQueuedAccepts();

      expect(await bob.storage.dequeue(alice.identity.pubkey), isEmpty);
      final follow = await alice.storage.getFollow(bob.identity.pubkey);
      expect(follow!.feedKey, equals(bob.identity.feedKey));
    });

    test('onlyPubkey + ignoreBackoff bypasses the backoff window', () async {
      await alice.service.sendFollowRequest(bob.connectionCard());
      transport.failNextAcceptTo = alice.baseUrl;
      transport.failPersistently = true;
      await bob.service.acceptFollowRequest(alice.identity.pubkey);
      // One failing pass records a recent attempt → backoff would now block.
      await bob.service.retryQueuedAccepts();

      transport.failPersistently = false;
      transport.failNextAcceptTo = null;
      // No clock advance: a normal pass would skip, but ignoreBackoff forces it.
      await bob.service.retryQueuedAccepts(
        onlyPubkey: alice.identity.pubkey,
        ignoreBackoff: true,
      );

      expect(await bob.storage.dequeue(alice.identity.pubkey), isEmpty);
      final follow = await alice.storage.getFollow(bob.identity.pubkey);
      expect(follow!.feedKey, equals(bob.identity.feedKey));
    });

    test('foreign (event-shaped) queue blob is left untouched', () async {
      await alice.service.sendFollowRequest(bob.connectionCard());
      transport.failNextAcceptTo = alice.baseUrl;
      await bob.service.acceptFollowRequest(alice.identity.pubkey);
      // A comment/reaction event queued for the same pubkey shares the table.
      final foreign = Uint8List.fromList(
        cbor.encode(<String, dynamic>{'pubkey': 'x', 'payload': [1, 2, 3]}),
      );
      await bob.storage.enqueue(alice.identity.pubkey, foreign);

      transport.failNextAcceptTo = null;
      await bob.service.retryQueuedAccepts();

      // Accept delivered + removed; the foreign blob survives untouched.
      final remaining = await bob.storage.dequeue(alice.identity.pubkey);
      expect(remaining, hasLength(1));
      expect(remaining.single.eventBlob, equals(foreign));
      expect(remaining.single.retryCount, 0);
    });
  });

  group('FollowService.removeFollower', () {
    test('clears queued card distributions for the removed follower (S4)',
        () async {
      final alice = await _Peer.build(crypto, label: 'alice');
      final bob = await _Peer.build(crypto, label: 'bob');
      final transport = _PairTransport({
        alice.baseUrl: alice,
        bob.baseUrl: bob,
      });
      alice.attachTransport(transport, peer: bob);
      bob.attachTransport(transport, peer: alice);

      // Alice is an accepted follower of bob with a queued card update.
      await bob.storage.saveInboundRequest(FollowRequest(
        pubkey: alice.identity.pubkey,
        payload: Uint8List(0),
        createdAt: 0,
        requestTimestamp: 0,
        status: 'accepted',
      ));
      await bob.storage.queueCardDistribution(
        targetPubkey: alice.identity.pubkey,
        encryptedCard: Uint8List.fromList([1, 2, 3]),
        nonce: Uint8List.fromList(List.filled(24, 1)),
        createdAt: 600,
      );

      await bob.service.removeFollower(alice.identity.pubkey);

      expect(
        await bob.storage.isAcceptedFollower(alice.identity.pubkey),
        isFalse,
      );
      expect(
        await bob.storage.latestPendingCardFor(alice.identity.pubkey),
        isNull,
        reason: 'removal must drop the pending card so a removed follower '
            'polling /manifest is never handed the new endpoints',
      );

      await alice.storage.dispose();
      await bob.storage.dispose();
    });
  });
}

class _Peer {
  _Peer._({
    required this.label,
    required this.crypto,
    required this.identity,
    required this.secretKey,
    required this.storage,
  })  : clock = MockClock(2_000_000),
        baseUrl = 'http://$label.local:8080';

  final String label;
  final CryptoService crypto;
  final Identity identity;
  final Uint8List secretKey;
  final MockStorageService storage;
  final MockClock clock;
  final String baseUrl;

  late FollowService service;

  static Future<_Peer> build(CryptoService crypto, {required String label}) async {
    final kp = await crypto.generateKeyPair();
    final identity = Identity(
      pubkey: crockfordBase32Encode(kp.publicKey),
      feedKey: crypto.randomBytes(32),
      feedKeyEpoch: label == 'bob' ? 7 : 3,
      createdAt: 1_000_000,
    );
    final storage = MockStorageService();
    await storage.saveIdentity(identity);
    return _Peer._(
      label: label,
      crypto: crypto,
      identity: identity,
      secretKey: kp.secretKey,
      storage: storage,
    );
  }

  ConnectionCard connectionCard() => ConnectionCard(
        pubkey: identity.pubkey,
        endpoints: [
          // sendFollowRequest refuses to send a card whose own endpoints
          // lack an onion entry; the fake transport still dials via baseUrl.
          Endpoint(type: 'onion', address: '$label.onion:80'),
          Endpoint(type: 'direct', address: _hostFromUrl(baseUrl)),
        ],
      );

  void attachTransport(_PairTransport transport, {required _Peer peer}) {
    final monitor = FakePeerReachabilityMonitor()
      ..setReachable(peer.identity.pubkey, PeerTransport.lan, peer.baseUrl);
    service = FollowService(
      crypto: crypto,
      storage: storage,
      clock: clock,
      transport: transport,
      reachabilityMonitor: monitor,
      identityLookup: storage.getIdentity,
      ownSecretKeyLookup: () async => secretKey,
      ownEndpointsLookup: () async => connectionCard().endpoints,
    );
  }
}

String _hostFromUrl(String url) {
  final uri = Uri.parse(url);
  return '${uri.host}:${uri.port}';
}

/// Hand-delivers /follow-request and /follow-accept POSTs straight into the
/// peer's storage / FollowService, mimicking the http handlers.
class _PairTransport implements HandshakeTransport {
  _PairTransport(this._byBaseUrl);

  final Map<String, _Peer> _byBaseUrl;
  String? failNextAcceptTo;
  bool failPersistently = false;

  /// When true, every postFollowAccept throws [HandshakeTransportException]
  /// before any delivery — models our own Tor being down (the real
  /// `_pick` throws synchronously before the POST). These must NOT count
  /// against the retry budget.
  bool throwNotReadyOnAccept = false;

  /// Counts postFollowAccept calls that got past the not-ready gate — i.e.
  /// real delivery attempts. Lets backoff tests assert "no attempt before
  /// the window, one after".
  int acceptPostCount = 0;

  @override
  Future<int> postFollowRequest(String baseUrl, Uint8List body) async {
    final peer = _resolve(baseUrl);
    final outer = cbor.decode(body) as Map<dynamic, dynamic>;
    final timestamp = outer['timestamp'] as int;
    await peer.storage.saveInboundRequest(
      FollowRequest(
        pubkey: outer['requester_pubkey'] as String,
        payload: body,
        createdAt: peer.clock.nowUnixSeconds(),
        requestTimestamp: timestamp,
      ),
    );
    return 202;
  }

  @override
  Future<int> postFollowAccept(String baseUrl, Uint8List body) async {
    if (throwNotReadyOnAccept) {
      throw const HandshakeTransportException('Tor not ready (test)');
    }
    acceptPostCount++;
    if (failNextAcceptTo == baseUrl) {
      if (!failPersistently) failNextAcceptTo = null;
      throw http.ClientException('simulated network failure', Uri.parse(baseUrl));
    }
    final peer = _resolve(baseUrl);
    final outer = cbor.decode(body) as Map<dynamic, dynamic>;
    await peer.service.ingestFollowAccept(
      ownerPubkey: outer['owner_pubkey'] as String,
      encryptedFeedKey: _bytes(outer['encrypted_feed_key']),
      nonce: _bytes(outer['nonce']),
      epoch: outer['epoch'] as int,
      timestamp: outer['timestamp'] as int,
    );
    return 202;
  }

  _Peer _resolve(String baseUrl) {
    final peer = _byBaseUrl[baseUrl];
    if (peer == null) {
      throw http.ClientException('no peer at $baseUrl', Uri.parse(baseUrl));
    }
    return peer;
  }

  Uint8List _bytes(dynamic v) {
    if (v is Uint8List) return v;
    if (v is List<int>) return Uint8List.fromList(v);
    throw StateError('expected bytes, got ${v.runtimeType}');
  }
}
