import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:starling/models/models.dart';
import 'package:starling/services/content_key_service.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/crypto/key_cache.dart';
import 'package:starling/services/crypto/key_rotation_service.dart';
import 'package:starling/services/crypto/pairwise_content_key_service.dart';
import 'package:starling/services/crypto/publish_lock.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/crypto_service.dart';
import 'package:starling/services/follow_service.dart';
import 'package:starling/services/mocks/mock_clock.dart';
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/types.dart';
import 'package:starling/sync/manifest_exchange.dart';
import 'package:starling/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../helpers/fake_peer_reachability_monitor.dart';

/// Plan 13 end-to-end scenario: Alice has Bob and Carol as accepted
/// followers. Alice removes Bob, the rotation propagates to Carol on her
/// next sync, and Bob loses access to future posts while keeping the old
/// ones he already has.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService crypto;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  test('alice removes bob → carol gets new key, bob does not', () async {
    final scene = await _Scene.build(crypto);

    // Alice posts P1 (encrypted under her current feed key).
    await scene.alice.publish('P1');
    // Carol syncs and decrypts P1.
    await scene.carolSyncWithAlice();
    expect(
      (await scene.carol.storage.getEvents(pubkey: scene.alice.identity.pubkey))
          .map((e) => _content(e.content))
          .toSet(),
      equals({'P1'}),
    );
    // Bob syncs and decrypts P1.
    await scene.bobSyncWithAlice();
    expect(
      (await scene.bob.storage.getEvents(pubkey: scene.alice.identity.pubkey))
          .map((e) => _content(e.content))
          .toSet(),
      equals({'P1'}),
    );

    // Alice removes bob: rotation fires, carol gets a pending distribution,
    // bob does not.
    await scene.alice.followService
        .removeFollower(scene.bob.identity.pubkey);

    expect(
      await scene.alice.storage
          .latestPendingDistributionFor(scene.carol.identity.pubkey),
      isNotNull,
    );
    expect(
      await scene.alice.storage
          .latestPendingDistributionFor(scene.bob.identity.pubkey),
      isNull,
    );

    // Alice posts P2 under the *new* feed key.
    await scene.alice.publish('P2');

    // Carol syncs again — receives the new feed key in the manifest, then
    // decrypts P2 successfully.
    await scene.carolSyncWithAlice();
    final carolStored =
        await scene.carol.storage.getEvents(pubkey: scene.alice.identity.pubkey);
    expect(
      carolStored.map((e) => _content(e.content)).toSet(),
      equals({'P1', 'P2'}),
    );

    // Carol's follow row now reflects the rotation.
    final carolFollow =
        await scene.carol.storage.getFollow(scene.alice.identity.pubkey);
    expect(carolFollow!.lastReceivedRotationAt, isPositive);

    // Bob still has P1 locally. Bob syncs again; the manifest still lists
    // P1 + P2, but bob's feed key is the OLD one — P2 won't decrypt.
    await scene.bobSyncWithAlice();
    final bobStored =
        await scene.bob.storage.getEvents(pubkey: scene.alice.identity.pubkey);
    expect(
      bobStored.map((e) => _content(e.content)).toSet(),
      equals({'P1'}), // P2 dropped because decrypt fails
    );

    await scene.dispose();
  });
}

String _content(Uint8List bytes) => String.fromCharCodes(bytes);

class _Scene {
  _Scene({
    required this.alice,
    required this.bob,
    required this.carol,
  });

  final _Peer alice;
  final _Peer bob;
  final _Peer carol;

  static Future<_Scene> build(CryptoService crypto) async {
    final alice = await _Peer.build(crypto, label: 'alice');
    final bob = await _Peer.build(crypto, label: 'bob');
    final carol = await _Peer.build(crypto, label: 'carol');

    // Wire bidirectional follow handshake helpers — bob and carol each
    // both follow alice (so they have alice's feed key) AND are accepted
    // inbound followers of alice (so alice has them recorded for the
    // rotation distribution).
    final transport = _ScenePairTransport(
      peers: {alice.baseUrl: alice, bob.baseUrl: bob, carol.baseUrl: carol},
    );
    final reachableByPubkey = <String, String>{
      alice.identity.pubkey: alice.baseUrl,
      bob.identity.pubkey: bob.baseUrl,
      carol.identity.pubkey: carol.baseUrl,
    };
    alice.attachFollowTransport(transport, reachableByPubkey);
    bob.attachFollowTransport(transport, reachableByPubkey);
    carol.attachFollowTransport(transport, reachableByPubkey);

    // Bob → follows alice
    await _completeOneWayFollow(requester: bob, target: alice);
    // Carol → follows alice
    await _completeOneWayFollow(requester: carol, target: alice);

    return _Scene(alice: alice, bob: bob, carol: carol);
  }

  Future<void> dispose() async {
    await alice.storage.dispose();
    await bob.storage.dispose();
    await carol.storage.dispose();
  }

  /// Make carol perform a sync against alice over the in-memory shim.
  Future<void> carolSyncWithAlice() => _runSync(syncer: carol, peer: alice);

  /// Make bob perform a sync against alice over the in-memory shim.
  Future<void> bobSyncWithAlice() => _runSync(syncer: bob, peer: alice);

  Future<void> _runSync({required _Peer syncer, required _Peer peer}) async {
    final follow = await syncer.storage.getFollow(peer.identity.pubkey);
    if (follow == null) return;
    final exchange = ManifestExchange(
      transport: _DirectSyncTransport(peer),
      storage: syncer.storage,
    );
    final identity = await syncer.storage.getIdentity();
    final diff = await exchange.fetchAndDiff(
      PeerConnection(
        pubkey: peer.identity.pubkey,
        baseUrl: peer.baseUrl,
        transport: PeerTransport.lan,
      ),
      follow,
      requesterPubkey: identity?.pubkey,
      ackRotationAt: follow.lastReceivedRotationAt,
    );

    // Apply rotation if present.
    Follow currentFollow = follow;
    if (diff.newFeedKey != null && identity != null) {
      final delivery = diff.newFeedKey!;
      final myEdPk = crockfordBase32Decode(identity.pubkey);
      final theirEdPk = crockfordBase32Decode(peer.identity.pubkey);
      final myXSk = syncer.crypto.ed25519ToX25519SecretKey(syncer.secretKey);
      final theirXPk = syncer.crypto.ed25519ToX25519PublicKey(theirEdPk);
      final shared = syncer.crypto.deriveSharedKey(
        myXSk,
        theirXPk,
        theirEdPk,
        myEdPk,
        delivery.createdAt,
      );
      final newKey = syncer.crypto.decrypt(
        delivery.encryptedFeedKey,
        delivery.nonce,
        shared,
      );
      currentFollow = follow.copyWith(
        feedKey: newKey,
        feedKeyEpoch: 0,
        lastReceivedRotationAt: delivery.createdAt,
      );
      await syncer.storage.saveFollow(currentFollow);
    }

    if (diff.missingIds.isEmpty) {
      await syncer.storage.updateLastSynced(
        peer.identity.pubkey,
        syncer.clock.nowUnixSeconds(),
      );
      return;
    }

    final envelope =
        await _DirectSyncTransport(peer).fetchEnvelope(
      PeerConnection(
        pubkey: peer.identity.pubkey,
        baseUrl: peer.baseUrl,
        transport: PeerTransport.lan,
      ),
      since: diff.windowSince,
    );
    for (final item in envelope.items) {
      if (item.type != 'event') continue;
      try {
        final encrypted = EncryptedEvent.fromBytes(item.payload);
        final plain =
            syncer.contentKey.decryptEvent(encrypted, currentFollow.feedKey);
        await syncer.storage.saveEvent(plain);
      } catch (_) {
        // Drop undecryptable items — that's the expected outcome for bob
        // post-rotation.
      }
    }

    await syncer.storage.updateLastSynced(
      peer.identity.pubkey,
      syncer.clock.nowUnixSeconds(),
    );
  }
}

/// One-direction follow: [requester] follows [target]. After this, [requester]
/// has [target]'s feed key (`follow_entries`) and [target] has [requester]
/// as an accepted inbound follower (`inbound_follow_request_entries` with
/// status='accepted').
Future<void> _completeOneWayFollow({
  required _Peer requester,
  required _Peer target,
}) async {
  await requester.followService.sendFollowRequest(target.connectionCard());
  await target.followService.acceptFollowRequest(requester.identity.pubkey);
}

class _Peer {
  _Peer._({
    required this.label,
    required this.crypto,
    required this.identity,
    required this.secretKey,
    required this.storage,
    required this.cache,
    required this.contentKey,
    required this.publishLock,
  })  : clock = MockClock(2_000_000),
        baseUrl = 'http://$label.local:8080';

  final String label;
  final CryptoService crypto;
  Identity identity;
  final Uint8List secretKey;
  final MockStorageService storage;
  final FeedKeyCache cache;
  final ContentKeyService contentKey;
  final PublishLock publishLock;
  final MockClock clock;
  final String baseUrl;

  late FollowService followService;
  late KeyRotationService keyRotation;

  static Future<_Peer> build(CryptoService crypto, {required String label}) async {
    final kp = await crypto.generateKeyPair();
    final identity = Identity(
      pubkey: crockfordBase32Encode(kp.publicKey),
      feedKey: crypto.randomBytes(32),
      feedKeyEpoch: 0,
      feedKeyValidFrom: 1_000_000,
      createdAt: 1_000_000,
    );
    final storage = MockStorageService();
    await storage.saveIdentity(identity);
    final cache = FeedKeyCache()..put(identity.pubkey, identity.feedKey, 0);
    final contentKey = PairwiseContentKeyService(
      crypto: crypto,
      cache: cache,
      ownPubkey: identity.pubkey,
      ownSecretKey: kp.secretKey,
    );
    final publishLock = PublishLock();
    final peer = _Peer._(
      label: label,
      crypto: crypto,
      identity: identity,
      secretKey: kp.secretKey,
      storage: storage,
      cache: cache,
      contentKey: contentKey,
      publishLock: publishLock,
    );
    peer.keyRotation = KeyRotationService(
      crypto: crypto,
      contentKey: contentKey,
      storage: storage,
      clock: peer.clock,
      feedKeyCache: cache,
      publishLock: publishLock,
      ownSecretKeyLookup: () async => kp.secretKey,
    );
    return peer;
  }

  ConnectionCard connectionCard() => ConnectionCard(
        pubkey: identity.pubkey,
        endpoints: [Endpoint(type: 'direct', address: _hostFromUrl(baseUrl))],
      );

  void attachFollowTransport(
    _ScenePairTransport transport,
    Map<String, String> reachableByPubkey,
  ) {
    final monitor = FakePeerReachabilityMonitor();
    reachableByPubkey.forEach((pubkey, baseUrl) {
      monitor.setReachable(pubkey, PeerTransport.lan, baseUrl);
    });
    followService = FollowService(
      crypto: crypto,
      storage: storage,
      clock: clock,
      transport: transport,
      reachabilityMonitor: monitor,
      identityLookup: storage.getIdentity,
      ownSecretKeyLookup: () async => secretKey,
      ownEndpointsLookup: () async => connectionCard().endpoints,
      feedKeyCache: cache,
      keyRotationService: keyRotation,
    );
  }

  Future<void> publish(String text) =>
      publishLock.synchronized(() async {
        clock.advance(60);
        final event = Event(
          version: '2026-03-24',
          id: '',
          pubkey: identity.pubkey,
          createdAt: clock.nowUnixSeconds(),
          kind: EventKind.post,
          content: Uint8List.fromList(text.codeUnits),
          sig: Uint8List(64),
        );
        final identityRow = (await storage.getIdentity())!;
        final msgSeq = identityRow.msgSeqCounter;
        final result = contentKey.signAndEncryptForAudience(
          event,
          Audience.broadcast,
          msgSeq: msgSeq,
        );
        await storage.saveEvent(result.signed);
        await storage.saveIdentity(
          identityRow.copyWith(msgSeqCounter: msgSeq + 1),
        );
      });
}

String _hostFromUrl(String url) {
  final uri = Uri.parse(url);
  return '${uri.host}:${uri.port}';
}

class _ScenePairTransport implements HandshakeTransport {
  _ScenePairTransport({required this.peers});
  final Map<String, _Peer> peers;

  @override
  Future<int> postFollowRequest(String baseUrl, Uint8List body) async {
    final peer = peers[baseUrl]!;
    final outer = cbor.decode(body) as Map<dynamic, dynamic>;
    final timestamp = outer['timestamp'] as int;
    await peer.storage.saveInboundRequest(FollowRequest(
      pubkey: outer['requester_pubkey'] as String,
      payload: body,
      createdAt: peer.clock.nowUnixSeconds(),
      requestTimestamp: timestamp,
    ));
    return 202;
  }

  @override
  Future<int> postFollowAccept(String baseUrl, Uint8List body) async {
    final peer = peers[baseUrl]!;
    final outer = cbor.decode(body) as Map<dynamic, dynamic>;
    await peer.followService.ingestFollowAccept(
      ownerPubkey: outer['owner_pubkey'] as String,
      encryptedFeedKey: _bytes(outer['encrypted_feed_key']),
      nonce: _bytes(outer['nonce']),
      epoch: outer['epoch'] as int,
      timestamp: outer['timestamp'] as int,
    );
    return 202;
  }

  Uint8List _bytes(dynamic v) {
    if (v is Uint8List) return v;
    if (v is List<int>) return Uint8List.fromList(v);
    throw http.ClientException('expected bytes');
  }
}

/// SyncTransport that reads directly from a single source peer's storage,
/// matching what the real /manifest + /events handlers would return.
class _DirectSyncTransport implements SyncTransport {
  _DirectSyncTransport(this._source);
  final _Peer _source;

  @override
  Future<Manifest> fetchManifest(
    PeerConnection peer, {
    int? since,
    int? until,
    String? requesterPubkey,
    int? ackRotationAt,
    int? cardSeenAt,
  }) async {
    if (requesterPubkey != null && ackRotationAt != null && ackRotationAt > 0) {
      await _source.storage
          .markDistributionsDelivered(requesterPubkey, ackRotationAt);
    }
    final events = await _source.storage.getEvents(
      pubkey: _source.identity.pubkey,
      since: since,
    );
    RotatedFeedKeyDelivery? delivery;
    if (requesterPubkey != null) {
      final pending =
          await _source.storage.latestPendingDistributionFor(requesterPubkey);
      if (pending != null) {
        delivery = RotatedFeedKeyDelivery(
          encryptedFeedKey: pending.encryptedFeedKey,
          nonce: pending.nonce,
          createdAt: pending.createdAt,
        );
      }
    }
    return Manifest(
      pubkey: _source.identity.pubkey,
      events: events
          .map((e) => ManifestEntry(id: e.id, createdAt: e.createdAt))
          .toList(),
      hasOlder: false,
      newFeedKey: delivery,
    );
  }

  @override
  Future<Envelope> fetchEnvelope(PeerConnection peer, {int? since}) async {
    // Re-read identity to pick up any rotations.
    _source.identity = (await _source.storage.getIdentity())!;
    final events = await _source.storage.getEvents(
      pubkey: _source.identity.pubkey,
      since: since,
    );
    final items = <EnvelopeItem>[];
    for (final event in events) {
      // Use the event's persisted msg_seq when available (set at publish);
      // fall back to 0 for tests that build events without going through
      // the publisher.
      final msgSeq = event.msgSeq ?? 0;
      final encrypted = _source.contentKey.encryptEvent(
        event,
        _source.identity.feedKey,
        _source.identity.feedKeyEpoch,
        msgSeq,
      );
      items.add(EnvelopeItem(type: 'event', payload: encrypted.toBytes()));
    }
    return Envelope(version: '2026-03-24', items: items);
  }

  @override
  Future<Uint8List> fetchMedia(PeerConnection peer, String hash) async =>
      Uint8List(0);

  @override
  Future<void> pushEnvelope(PeerConnection peer, Envelope envelope) async {}
}
