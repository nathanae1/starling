import 'dart:convert';
import 'dart:typed_data';

import 'package:starling/models/models.dart';
import 'package:starling/services/content_key_service.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/crypto/key_cache.dart';
import 'package:starling/services/crypto/pairwise_content_key_service.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/crypto_service.dart';
import 'package:starling/services/mocks/mock_clock.dart';
import 'package:starling/services/mocks/mock_mdns_service.dart';
import '../helpers/fake_peer_reachability_monitor.dart';
import 'package:starling/services/storage/database.dart';
import 'package:starling/services/storage/drift_storage_service.dart';
import 'package:starling/services/types.dart';
import 'package:starling/sync/peer_connection_factory.dart';
import 'package:starling/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CryptoService crypto;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  group('SyncEngine', () {
    late _Peer alice;
    late _Peer bob;
    late _RouteableTransport transport;
    late MockMdnsService bobMdns;
    late FakePeerReachabilityMonitor bobMonitor;
    late SyncEngine bobEngine;

    setUp(() async {
      alice = await _Peer.build(crypto, label: 'alice');
      bob = await _Peer.build(crypto, label: 'bob');

      transport = _RouteableTransport({
        alice.identity.pubkey: alice,
      });
      bobMdns = MockMdnsService();
      // Bob's mDNS sees Alice as a reachable peer.
      bobMdns.setPeer(LanPeer(
        pubkey: alice.identity.pubkey,
        host: '10.0.0.1',
        port: 49000,
      ));

      // Bob has an active follow on Alice using Alice's feed key.
      await bob.storage.saveFollow(Follow(
        pubkey: alice.identity.pubkey,
        connectionCard: '',
        feedKey: alice.identity.feedKey,
        feedKeyEpoch: alice.identity.feedKeyEpoch,
        lastSyncedAt: 0,
      ));

      bobMonitor = FakePeerReachabilityMonitor()
        ..setReachable(
          alice.identity.pubkey,
          PeerTransport.lan,
          'http://10.0.0.1:49000',
        );
      bobEngine = SyncEngine(
        storage: bob.storage,
        contentKey: bob.contentKey,
        crypto: crypto,
        transport: transport,
        peerFactory: PeerConnectionFactory(monitor: bobMonitor),
        reachabilityMonitor: bobMonitor,
        clock: bob.clock,
        ownSecretKeyLookup: () async => bob.secretKey,
      );
    });

    tearDown(() async {
      await alice.dispose();
      await bob.dispose();
      await bobMdns.dispose();
    });

    test('pulls all of alice\'s events and decrypts them', () async {
      // Alice publishes 3 posts.
      for (var i = 0; i < 3; i++) {
        alice.clock.advance(60);
        await alice.publishPost('hello $i');
      }

      final report = await bobEngine.syncNow();
      expect(report.peers, hasLength(1));
      expect(report.peers.single.status, equals(PeerSyncStatus.synced));
      expect(report.peers.single.eventsFetched, equals(3));

      final stored = await bob.storage
          .getEvents(pubkey: alice.identity.pubkey);
      expect(stored, hasLength(3));
      expect(stored.every((e) => e.kind == EventKind.post), isTrue);

      // last_synced_at advanced.
      final follow = await bob.storage.getFollow(alice.identity.pubkey);
      expect(follow!.lastSyncedAt, greaterThan(0));
    });

    test('ingests a validly-signed connection card from the peer (Plan 15)',
        () async {
      final card = ConnectionCard(
        pubkey: alice.identity.pubkey,
        endpoints: const [
          Endpoint(type: 'onion', address: 'phone.onion:80'),
          Endpoint(type: 'relay', address: 'relayhost.onion:80'),
        ],
      );
      final cardCbor = card.toBytes();
      transport.queueCardFor(
        peerPubkey: alice.identity.pubkey,
        delivery: ConnectionCardDelivery(
          cardCbor: cardCbor,
          sig: crypto.sign(alice.secretKey, cardCbor),
          createdAt: 5000,
        ),
      );

      await bobEngine.syncOnePeerByPubkey(alice.identity.pubkey);

      final follow = await bob.storage.getFollow(alice.identity.pubkey);
      expect(follow!.connectionCard, isNotEmpty);
      expect(follow.lastReceivedCardAt, equals(5000));
      final stored = ConnectionCard.fromMap(
        jsonDecode(follow.connectionCard) as Map<String, dynamic>,
      );
      expect(stored.endpoints.any((e) => e.type == 'relay'), isTrue);
    });

    test('rejects a connection card with an invalid signature (Plan 15)',
        () async {
      final card = ConnectionCard(
        pubkey: alice.identity.pubkey,
        endpoints: const [Endpoint(type: 'relay', address: 'evil.onion:80')],
      );
      transport.queueCardFor(
        peerPubkey: alice.identity.pubkey,
        delivery: ConnectionCardDelivery(
          cardCbor: card.toBytes(),
          sig: Uint8List(64), // not a valid signature
          createdAt: 5000,
        ),
      );

      await bobEngine.syncOnePeerByPubkey(alice.identity.pubkey);

      // The seeded follow's card was empty; a bad sig must leave it untouched.
      final follow = await bob.storage.getFollow(alice.identity.pubkey);
      expect(follow!.connectionCard, isEmpty);
      expect(follow.lastReceivedCardAt, equals(0));
    });

    test('re-running syncNow does not duplicate events', () async {
      alice.clock.advance(60);
      await alice.publishPost('once');

      await bobEngine.syncNow();
      final after1 = await bob.storage.getEvents(pubkey: alice.identity.pubkey);
      expect(after1, hasLength(1));

      // Second sync within the same window should diff manifest → empty.
      await bobEngine.syncNow();
      final after2 = await bob.storage.getEvents(pubkey: alice.identity.pubkey);
      expect(after2, hasLength(1));
    });

    test('peer not in mDNS cache → marked unreachable, sync continues',
        () async {
      bobMdns.removePeer(alice.identity.pubkey);
      bobMonitor.clear();
      final report = await bobEngine.syncNow();
      expect(report.peers.single.status, equals(PeerSyncStatus.unreachable));

      final stored =
          await bob.storage.getEvents(pubkey: alice.identity.pubkey);
      expect(stored, isEmpty);
    });

    test('tampered EncryptedEvent payload is skipped, not stored', () async {
      alice.clock.advance(60);
      await alice.publishPost('legit');

      // Inject a tampered encrypted event with the same pubkey but
      // garbage payload, alongside the legit one.
      transport.tamperNextEnvelopeFor = alice.identity.pubkey;

      final report = await bobEngine.syncNow();
      expect(report.peers.single.status, equals(PeerSyncStatus.synced));
      // The legit event went through; the tampered one was rejected.
      expect(report.peers.single.eventsFetched, equals(1));
      expect(report.peers.single.eventsSkipped, equals(1));

      final stored =
          await bob.storage.getEvents(pubkey: alice.identity.pubkey);
      expect(stored, hasLength(1));
    });

    test('unknown EnvelopeItem types are routed to opaque storage', () async {
      alice.clock.advance(60);
      await alice.publishPost('legit');

      // Inject a future "commit" item alongside the event.
      transport.injectExtraItemFor = alice.identity.pubkey;
      transport.injectedItem = EnvelopeItem(
        type: 'commit',
        payload: Uint8List.fromList([1, 2, 3, 4]),
      );

      final report = await bobEngine.syncNow();
      expect(report.peers.single.eventsFetched, equals(1));
      expect(report.peers.single.unknownItemsPreserved, equals(1));

      final unknown =
          await bob.storage.getUnknownEnvelopeItemsByType('commit');
      expect(unknown, hasLength(1));
      expect(unknown.single.sourcePubkey, equals(alice.identity.pubkey));
      expect(unknown.single.payload, equals(Uint8List.fromList([1, 2, 3, 4])));
    });

    test('peer error is contained — reports unreachable, no crash', () async {
      transport.failNextManifestFor = alice.identity.pubkey;
      final report = await bobEngine.syncNow();
      expect(report.peers.single.status, equals(PeerSyncStatus.unreachable));
      expect(report.peers.single.error, isNotNull);
    });

    test(
        'rotated feed key in manifest response is decrypted, follow.feedKey '
        'and lastReceivedRotationAt are persisted, new posts decrypt',
        () async {
      // Alice publishes one post under her *current* feed key, which Bob
      // already has. Then alice rotates: she encrypts a new feed key for
      // bob, queues it, and publishes a post under the new key. Bob syncs
      // and should receive both: the rotation payload (applied first) and
      // the new post (decrypted with the new key).
      alice.clock.advance(60);
      await alice.publishPost('pre-rotation');

      // First sync: bob picks up the pre-rotation post with the old key.
      final pre = await bobEngine.syncNow();
      expect(pre.peers.single.eventsFetched, equals(1));

      // Now alice rotates. We need to plumb a delivery into the transport.
      final rotationAt = alice.clock.nowUnixSeconds() + 30;
      alice.clock.advance(30);
      final newKey = crypto.randomBytes(32);

      // Wrap the new key for bob using alice's (sender) and bob's (recipient)
      // identities — same convention KeyRotationService uses.
      final aliceEdPk = crockfordBase32Decode(alice.identity.pubkey);
      final bobEdPk = crockfordBase32Decode(bob.identity.pubkey);
      final aliceXSk = crypto.ed25519ToX25519SecretKey(alice.secretKey);
      final bobXPk = crypto.ed25519ToX25519PublicKey(bobEdPk);
      final shared = crypto.deriveSharedKey(
        aliceXSk,
        bobXPk,
        aliceEdPk,
        bobEdPk,
        rotationAt,
      );
      final wrapped = alice.contentKey.encryptFeedKey(newKey, shared);
      final nonce = Uint8List.fromList(wrapped.sublist(0, 24));
      final ct = Uint8List.fromList(wrapped.sublist(24));

      // Tell the transport to attach this delivery to alice's next manifest
      // response targeted at bob.
      transport.queueRotationFor(
        peerPubkey: alice.identity.pubkey,
        delivery: RotatedFeedKeyDelivery(
          encryptedFeedKey: ct,
          nonce: nonce,
          createdAt: rotationAt,
        ),
      );
      // Update alice's identity to the new key so her _RouteableTransport
      // re-encrypts subsequent envelope items under it.
      await alice.storage.saveIdentity(alice.identity.copyWith(
        feedKey: newKey,
        feedKeyValidFrom: rotationAt,
      ));
      alice.identity = (await alice.storage.getIdentity())!;

      // Alice publishes a post under the new key.
      alice.clock.advance(10);
      await alice.publishPostWithKey('post-rotation', newKey, 0);

      final post = await bobEngine.syncNow();
      expect(post.peers.single.status, equals(PeerSyncStatus.synced));

      // Bob's follow row now has the new feed key and ack timestamp.
      final follow = await bob.storage.getFollow(alice.identity.pubkey);
      expect(follow!.feedKey, equals(newKey));
      expect(follow.lastReceivedRotationAt, equals(rotationAt));

      // Both events end up stored — pre-rotation (still readable, plaintext
      // on disk; the wire re-encryption uses the new key which bob now has)
      // and post-rotation.
      final stored =
          await bob.storage.getEvents(pubkey: alice.identity.pubkey);
      expect(stored.map((e) => String.fromCharCodes(e.content)).toSet(),
          equals({'pre-rotation', 'post-rotation'}));
    });

    test('syncOnePeerByPubkey runs the full per-peer sync for one follow',
        () async {
      alice.clock.advance(60);
      await alice.publishPost('targeted');

      final report = await bobEngine.syncOnePeerByPubkey(alice.identity.pubkey);
      expect(report, isNotNull);
      expect(report!.status, equals(PeerSyncStatus.synced));
      expect(report.eventsFetched, equals(1));

      final stored =
          await bob.storage.getEvents(pubkey: alice.identity.pubkey);
      expect(stored, hasLength(1));
    });

    test('syncOnePeerByPubkey returns null when the follow does not exist',
        () async {
      final report = await bobEngine.syncOnePeerByPubkey('not-a-real-pubkey');
      expect(report, isNull);
    });

    test(
        'event decrypt failure stamps lastDecryptFailureAt; rotation clears '
        'it', () async {
      // Bob's stored feedKey is alice's current key. Tamper the next
      // envelope so decrypt/verify fails — that should stamp
      // last_decrypt_failure_at on the follow.
      alice.clock.advance(60);
      await alice.publishPost('legit');
      transport.tamperNextEnvelopeFor = alice.identity.pubkey;

      await bobEngine.syncNow();
      final afterFailure =
          await bob.storage.getFollow(alice.identity.pubkey);
      expect(afterFailure!.lastDecryptFailureAt, isNotNull);

      // Now alice rotates her feed key. Bob's next sync should pull the
      // rotation, which clears the staleness stamp.
      final rotationAt = alice.clock.nowUnixSeconds() + 30;
      alice.clock.advance(30);
      final newKey = crypto.randomBytes(32);
      final aliceEdPk = crockfordBase32Decode(alice.identity.pubkey);
      final bobEdPk = crockfordBase32Decode(bob.identity.pubkey);
      final aliceXSk = crypto.ed25519ToX25519SecretKey(alice.secretKey);
      final bobXPk = crypto.ed25519ToX25519PublicKey(bobEdPk);
      final shared = crypto.deriveSharedKey(
        aliceXSk,
        bobXPk,
        aliceEdPk,
        bobEdPk,
        rotationAt,
      );
      final wrapped = alice.contentKey.encryptFeedKey(newKey, shared);
      transport.queueRotationFor(
        peerPubkey: alice.identity.pubkey,
        delivery: RotatedFeedKeyDelivery(
          encryptedFeedKey: Uint8List.fromList(wrapped.sublist(24)),
          nonce: Uint8List.fromList(wrapped.sublist(0, 24)),
          createdAt: rotationAt,
        ),
      );
      await alice.storage.saveIdentity(alice.identity.copyWith(
        feedKey: newKey,
        feedKeyValidFrom: rotationAt,
      ));
      alice.identity = (await alice.storage.getIdentity())!;

      await bobEngine.syncOnePeerByPubkey(alice.identity.pubkey);
      final afterRotation =
          await bob.storage.getFollow(alice.identity.pubkey);
      expect(afterRotation!.feedKey, equals(newKey));
      expect(afterRotation.lastDecryptFailureAt, isNull);
    });

    test(
        'follow_feed_key_history archives the prior chain root on rotation '
        'so cached pre-rotation content stays decryptable', () async {
      // Pre-rotation: alice publishes one post under her current feedKey.
      alice.clock.advance(60);
      await alice.publishPost('pre-rotation');
      // Bob first-syncs and stores the post. Confirm both sides match.
      await bobEngine.syncNow();
      final bobBeforeRotation =
          await bob.storage.getFollow(alice.identity.pubkey);
      expect(bobBeforeRotation!.feedKey, equals(alice.identity.feedKey));

      // Capture the pre-rotation key for assertion.
      final priorKey = Uint8List.fromList(alice.identity.feedKey);

      // Alice rotates. We deliver the new key inline on the next manifest.
      final rotationAt = alice.clock.nowUnixSeconds() + 30;
      alice.clock.advance(30);
      final newKey = crypto.randomBytes(32);
      final aliceEdPk = crockfordBase32Decode(alice.identity.pubkey);
      final bobEdPk = crockfordBase32Decode(bob.identity.pubkey);
      final aliceXSk = crypto.ed25519ToX25519SecretKey(alice.secretKey);
      final bobXPk = crypto.ed25519ToX25519PublicKey(bobEdPk);
      final shared = crypto.deriveSharedKey(
        aliceXSk,
        bobXPk,
        aliceEdPk,
        bobEdPk,
        rotationAt,
      );
      final wrapped = alice.contentKey.encryptFeedKey(newKey, shared);
      transport.queueRotationFor(
        peerPubkey: alice.identity.pubkey,
        delivery: RotatedFeedKeyDelivery(
          encryptedFeedKey: Uint8List.fromList(wrapped.sublist(24)),
          nonce: Uint8List.fromList(wrapped.sublist(0, 24)),
          createdAt: rotationAt,
        ),
      );
      await alice.storage.saveIdentity(alice.identity.copyWith(
        feedKey: newKey,
        feedKeyValidFrom: rotationAt,
        msgSeqCounter: 0,
      ));
      alice.identity = (await alice.storage.getIdentity())!;

      // Sync — bob applies the rotation. Old key should land in the
      // follow_feed_key_history table; current Follow.feedKey is newKey.
      await bobEngine.syncOnePeerByPubkey(alice.identity.pubkey);
      final bobAfterRotation =
          await bob.storage.getFollow(alice.identity.pubkey);
      expect(bobAfterRotation!.feedKey, equals(newKey));

      final history =
          await bob.storage.getFollowFeedKeyHistory(alice.identity.pubkey);
      expect(history, hasLength(1));
      expect(history.single.feedKey, equals(priorKey));
      expect(history.single.validUntil, equals(rotationAt));
    });
  });
}

class _Peer {
  _Peer._({
    required this.label,
    required this.crypto,
    required this.identity,
    required this.secretKey,
    required this.db,
    required this.storage,
    required this.contentKey,
  }) : clock = MockClock(2_000_000);

  final String label;
  final CryptoService crypto;
  Identity identity;
  final Uint8List secretKey;
  final AppDatabase db;
  final DriftStorageService storage;
  final ContentKeyService contentKey;
  final MockClock clock;

  static Future<_Peer> build(CryptoService crypto, {required String label}) async {
    final kp = await crypto.generateKeyPair();
    final pubkey = crockfordBase32Encode(kp.publicKey);
    final feedKey = crypto.randomBytes(32);
    final identity = Identity(
      pubkey: pubkey,
      feedKey: feedKey,
      feedKeyEpoch: 0,
      createdAt: 1_000_000,
    );

    final db = AppDatabase.memory();
    final clock = MockClock(2_000_000);
    final storage = DriftStorageService(db, clock);
    await storage.saveIdentity(identity);

    final cache = FeedKeyCache()..put(pubkey, feedKey, 0);
    final contentKey = PairwiseContentKeyService(
      crypto: crypto,
      cache: cache,
      ownPubkey: pubkey,
      ownSecretKey: kp.secretKey,
    );

    return _Peer._(
      label: label,
      crypto: crypto,
      identity: identity,
      secretKey: kp.secretKey,
      db: db,
      storage: storage,
      contentKey: contentKey,
    );
  }

  Future<void> publishPost(String content) async {
    final event = Event(
      version: '2026-03-24',
      id: '',
      pubkey: identity.pubkey,
      createdAt: clock.nowUnixSeconds(),
      kind: EventKind.post,
      content: Uint8List.fromList(content.codeUnits),
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
    identity = (await storage.getIdentity())!;
  }

  /// Like [publishPost], but signs/stores plaintext only — used in
  /// rotation tests where the wire encryption happens elsewhere with a
  /// specific key.
  Future<void> publishPostWithKey(
    String content,
    Uint8List feedKey,
    int epoch,
  ) async {
    final event = Event(
      version: '2026-03-24',
      id: '',
      pubkey: identity.pubkey,
      createdAt: clock.nowUnixSeconds(),
      kind: EventKind.post,
      content: Uint8List.fromList(content.codeUnits),
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
    identity = (await storage.getIdentity())!;
  }

  Future<void> dispose() async {
    await db.close();
  }
}

/// Routes manifest / envelope / media calls between in-memory peers, with
/// hooks for tests to inject failures or mutate the response.
class _RouteableTransport implements SyncTransport {
  _RouteableTransport(this._peers);
  final Map<String, _Peer> _peers;

  String? failNextManifestFor;
  String? tamperNextEnvelopeFor;
  String? injectExtraItemFor;
  EnvelopeItem? injectedItem;
  final Map<String, RotatedFeedKeyDelivery> _queuedDeliveries = {};
  final Map<String, ConnectionCardDelivery> _queuedCards = {};

  void queueRotationFor({
    required String peerPubkey,
    required RotatedFeedKeyDelivery delivery,
  }) {
    _queuedDeliveries[peerPubkey] = delivery;
  }

  void queueCardFor({
    required String peerPubkey,
    required ConnectionCardDelivery delivery,
  }) {
    _queuedCards[peerPubkey] = delivery;
  }

  @override
  Future<Manifest> fetchManifest(
    PeerConnection peer, {
    int? since,
    int? until,
    String? requesterPubkey,
    int? ackRotationAt,
    int? cardSeenAt,
  }) async {
    if (failNextManifestFor == peer.pubkey) {
      failNextManifestFor = null;
      throw Exception('simulated manifest failure');
    }
    final source = _peers[peer.pubkey]!;
    final events = await source.storage.getEvents(
      pubkey: peer.pubkey,
      since: since,
    );
    final delivery = _queuedDeliveries.remove(peer.pubkey);
    final cardDelivery = _queuedCards.remove(peer.pubkey);
    return Manifest(
      pubkey: peer.pubkey,
      events: events
          .map((e) => ManifestEntry(id: e.id, createdAt: e.createdAt))
          .toList(),
      hasOlder: false,
      newFeedKey: delivery,
      newConnectionCard: cardDelivery,
    );
  }

  @override
  Future<Envelope> fetchEnvelope(
    PeerConnection peer, {
    int? since,
  }) async {
    final source = _peers[peer.pubkey]!;
    // Re-read identity to pick up any rotations the test made via
    // `saveIdentity`.
    source.identity = (await source.storage.getIdentity())!;
    final events = await source.storage.getEvents(
      pubkey: peer.pubkey,
      since: since,
    );
    final items = <EnvelopeItem>[];
    for (final event in events) {
      final msgSeq = event.msgSeq ?? 0;
      final encrypted = source.contentKey.encryptEvent(
        event,
        source.identity.feedKey,
        source.identity.feedKeyEpoch,
        msgSeq,
      );
      items.add(EnvelopeItem(type: 'event', payload: encrypted.toBytes()));
    }

    if (tamperNextEnvelopeFor == peer.pubkey) {
      tamperNextEnvelopeFor = null;
      // Add a tampered "event" item with random bytes that won't decrypt.
      items.add(EnvelopeItem(
        type: 'event',
        payload: EncryptedEvent(
          pubkey: peer.pubkey,
          createdAt: events.isEmpty ? 0 : events.first.createdAt + 1,
          epoch: 0,
          msgSeq: 0,
          nonce: Uint8List(24),
          payload: Uint8List.fromList(List.filled(64, 0xFF)),
        ).toBytes(),
      ));
    }

    if (injectExtraItemFor == peer.pubkey && injectedItem != null) {
      items.add(injectedItem!);
      injectExtraItemFor = null;
      injectedItem = null;
    }

    return Envelope(version: '2026-03-24', items: items);
  }

  @override
  Future<Uint8List> fetchMedia(PeerConnection peer, String hash) async {
    return Uint8List(0);
  }

  @override
  Future<void> pushEnvelope(PeerConnection peer, Envelope envelope) async {
    pushedEnvelopes
        .putIfAbsent(peer.pubkey, () => <Envelope>[])
        .add(envelope);
    if (failNextPushFor == peer.pubkey) {
      failNextPushFor = null;
      throw Exception('simulated push failure');
    }
  }

  String? failNextPushFor;
  final Map<String, List<Envelope>> pushedEnvelopes = {};
}
