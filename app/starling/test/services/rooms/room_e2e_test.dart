import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starling/models/models.dart';
import 'package:starling/models/protocol_version.dart';
import 'package:starling/server/handlers/events_push_handler.dart';
import 'package:starling/services/clock.dart';
import 'package:starling/services/content_key_service.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/crypto/key_cache.dart';
import 'package:starling/services/crypto/pairwise_content_key_service.dart';
import 'package:starling/services/crypto/publish_lock.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/crypto_service.dart';
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/room_key_rotation_service.dart';
import 'package:starling/services/room_message_service.dart';
import 'package:starling/services/room_service.dart';
import 'package:starling/services/types.dart';

/// Plan 17 end-to-end with REAL crypto (Sodium): a chatroom converges across
/// members via the outbound-queue fan-out + ingest loopback, new members are
/// backfilled, and removing a member rotates the key with backward secrecy.
class _FixedClock implements Clock {
  _FixedClock(this.value);
  int value;
  @override
  int nowUnixSeconds() => value;
}

class _Party {
  _Party(
    this.kp,
    this.pubkey,
    this.storage,
    this.contentKey,
    this.clock,
    this.identity,
    this.rooms,
    this.messages,
  );
  final KeyPair kp;
  final String pubkey;
  final MockStorageService storage;
  final ContentKeyService contentKey;
  final _FixedClock clock;
  final Identity identity;
  final RoomService rooms;
  final RoomMessageService messages;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CryptoService crypto;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  Future<_Party> makeParty({int now = 1_700_000_000}) async {
    final kp = await crypto.generateKeyPair();
    final pubkey = crockfordBase32Encode(kp.publicKey);
    final feedKey = crypto.randomBytes(32);
    final storage = MockStorageService();
    final clock = _FixedClock(now);
    final contentKey = PairwiseContentKeyService(
      crypto: crypto,
      cache: FeedKeyCache()..put(pubkey, feedKey, 0),
      ownPubkey: pubkey,
      ownSecretKey: kp.secretKey,
    );
    final identity = Identity(
      pubkey: pubkey,
      feedKey: feedKey,
      feedKeyEpoch: 0,
      createdAt: now,
    );
    await storage.saveIdentity(identity);
    final lock = PublishLock();
    final rotation = DefaultRoomKeyRotationService(
      crypto: crypto,
      contentKey: contentKey,
      storage: storage,
      clock: clock,
      identityLookup: () async => identity,
      ownSecretKeyLookup: () async => kp.secretKey,
      publishLock: lock,
    );
    final rooms = DefaultRoomService(
      crypto: crypto,
      contentKey: contentKey,
      storage: storage,
      clock: clock,
      identityLookup: () async => identity,
      ownSecretKeyLookup: () async => kp.secretKey,
      rotationService: rotation,
      publishLock: lock,
    );
    final messages = DefaultRoomMessageService(
      contentKey: contentKey,
      storage: storage,
      clock: clock,
      identityLookup: () async => identity,
      publishLock: lock,
    );
    return _Party(
      kp,
      pubkey,
      storage,
      contentKey,
      clock,
      identity,
      rooms,
      messages,
    );
  }

  // Make X regard Y as a mutual follow (active outbound + accepted inbound).
  Future<void> see(_Party x, _Party y) async {
    await x.storage.saveFollow(
      Follow(pubkey: y.pubkey, connectionCard: '', feedKey: Uint8List(32)),
    );
    await x.storage.saveInboundRequest(
      FollowRequest(
        pubkey: y.pubkey,
        payload: Uint8List(0),
        createdAt: 0,
        requestTimestamp: 0,
        status: 'accepted',
      ),
    );
  }

  Future<void> link(_Party a, _Party b) async {
    await see(a, b);
    await see(b, a);
  }

  // Drain from's queue for `to` and ingest it, exactly as the transport would.
  Future<void> deliver(_Party from, _Party to) async {
    final queued = await from.storage.dequeue(to.pubkey);
    if (queued.isEmpty) return;
    final envelope = Envelope(
      version: kStarlingProtocolVersion,
      items: queued
          .map(
            (q) =>
                EnvelopeItem(type: q.itemType ?? 'event', payload: q.eventBlob),
          )
          .toList(),
    );
    await ingestPushedEnvelope(
      storage: to.storage,
      contentKey: to.contentKey,
      clock: to.clock,
      envelope: envelope,
      crypto: crypto,
      identity: to.identity,
      ownSecretKey: to.kp.secretKey,
    );
    for (final q in queued) {
      await from.storage.removeFromQueue(q.id);
    }
  }

  Future<List<String>> texts(_Party p, String roomId) async {
    final msgs = await p.storage.getEventsByRef(
      roomId,
      kind: EventKind.roomMessage,
    );
    return msgs.map((e) => utf8.decode(e.content)).toList();
  }

  test(
    '3-member convergence: create → fan-out → both timelines equal',
    () async {
      final a = await makeParty();
      final b = await makeParty();
      final c = await makeParty();
      await link(a, b);
      await link(a, c);

      a.clock.value = 1000;
      final roomId = await a.rooms.createRoom(
        name: 'Book club',
        memberPubkeys: [b.pubkey, c.pubkey],
      );
      await deliver(a, b);
      await deliver(a, c);

      expect((await b.storage.getRoom(roomId))?.name, 'Book club');
      expect((await c.storage.getRoom(roomId))?.name, 'Book club');

      a.clock.value = 1001;
      await a.messages.send(roomId: roomId, text: 'hello all');
      await deliver(a, b);
      await deliver(a, c);

      expect(await texts(b, roomId), contains('hello all'));
      expect(await texts(c, roomId), equals(await texts(b, roomId)));
    },
  );

  test('offline member converges after reconnect', () async {
    final a = await makeParty();
    final b = await makeParty();
    await link(a, b);

    a.clock.value = 2000;
    final roomId = await a.rooms.createRoom(
      name: 'Quiet room',
      memberPubkeys: [b.pubkey],
    );
    a.clock.value = 2001;
    await a.messages.send(roomId: roomId, text: 'you there?');
    // B was offline for the whole exchange — deliver everything at once now.
    await deliver(a, b);

    expect((await b.storage.getRoom(roomId))?.name, 'Quiet room');
    expect(await texts(b, roomId), contains('you there?'));
  });

  test('added member is backfilled with prior history', () async {
    final a = await makeParty();
    final b = await makeParty();
    final c = await makeParty();
    await link(a, b);
    await link(a, c);

    a.clock.value = 3000;
    final roomId = await a.rooms.createRoom(
      name: 'Growing room',
      memberPubkeys: [b.pubkey],
    );
    a.clock.value = 3001;
    await a.messages.send(roomId: roomId, text: 'early message');
    await deliver(a, b);

    a.clock.value = 3002;
    await a.rooms.addMember(roomId, c.pubkey);
    await deliver(a, c);

    // C reads history that predates its join (bounded replay + current key).
    expect(await texts(c, roomId), contains('early message'));
    final members = await c.storage.getRoomMembers(roomId);
    expect(
      members.where((m) => m.isActive).map((m) => m.pubkey),
      contains(c.pubkey),
    );
  });

  test(
    'announceCall authors a durable roomCallStarted seen by members',
    () async {
      final a = await makeParty();
      final b = await makeParty();
      await link(a, b);

      a.clock.value = 5000;
      final roomId = await a.rooms.createRoom(
        name: 'Call room',
        memberPubkeys: [b.pubkey],
      );
      await deliver(a, b);

      a.clock.value = 5001;
      await a.rooms.announceCall(roomId: roomId, callId: 'call-abc');
      await deliver(a, b);

      final calls = await b.storage.getEventsByRef(
        roomId,
        kind: EventKind.roomCallStarted,
      );
      expect(calls, hasLength(1));
      final content = decodeRoomCallStartedContent(calls.first.content);
      expect(content.callId, 'call-abc');
      expect(content.starterPubkey, a.pubkey);
    },
  );

  test('removing a member rotates the key — backward secrecy', () async {
    final a = await makeParty();
    final b = await makeParty();
    final c = await makeParty();
    await link(a, b);
    await link(a, c);

    a.clock.value = 4000;
    final roomId = await a.rooms.createRoom(
      name: 'Secret room',
      memberPubkeys: [b.pubkey, c.pubkey],
    );
    a.clock.value = 4001;
    await a.messages.send(roomId: roomId, text: 'before removal');
    await deliver(a, b);
    await deliver(a, c);
    expect(await texts(c, roomId), contains('before removal'));

    // Remove C → rotate the key, re-seal to B only.
    a.clock.value = 4002;
    await a.rooms.removeMember(roomId, c.pubkey);
    await deliver(a, b);

    // A new message goes only to remaining members.
    a.clock.value = 4003;
    final msg2Id = await a.messages.send(roomId: roomId, text: 'after removal');
    await deliver(a, b);
    await deliver(a, c); // C's queue holds nothing for it — no-op.

    // B (holds the new key) sees the post-rotation message.
    expect(await texts(b, roomId), contains('after removal'));
    // C never receives it, and could not decrypt it even if handed the bytes:
    expect(await texts(c, roomId), isNot(contains('after removal')));

    final msg2Wire = await a.storage.getEncryptedPayload(msg2Id);
    final msg2Enc = EncryptedEvent.fromBytes(msg2Wire!);
    final cRoom = await c.storage.getRoom(roomId);
    expect(
      () => c.contentKey.decryptEvent(msg2Enc, cRoom!.roomKey),
      throwsA(anything),
      reason: 'removed member must not decrypt post-rotation messages',
    );

    // B (new key) decrypts the same bytes fine.
    final bRoom = await b.storage.getRoom(roomId);
    final plain = b.contentKey.decryptEvent(msg2Enc, bRoom!.roomKey);
    expect(utf8.decode(plain.content), 'after removal');

    // B's roster reflects the removal.
    final bMembers = await b.storage.getRoomMembers(roomId);
    expect(bMembers.firstWhere((m) => m.pubkey == c.pubkey).isActive, isFalse);
  });
}
