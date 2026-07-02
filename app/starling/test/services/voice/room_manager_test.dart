import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starling/models/models.dart';
import 'package:starling/models/profile_content.dart';
import 'package:starling/models/signaling_message.dart';
import 'package:starling/models/voice_room.dart';
import 'package:starling/services/clock.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/mocks/mock_clock.dart';
import 'package:starling/services/mocks/mock_crypto_service.dart';
import 'package:starling/services/mocks/mock_signaling_service.dart';
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/mocks/mock_voice_service.dart';
import 'package:starling/services/signaling/signaling_dispatcher.dart';
import 'package:starling/services/voice/room_manager.dart';
import 'package:starling/services/voice/room_signaling.dart';
import 'package:starling/services/types.dart';
import 'package:starling/services/voice_service.dart';

/// [RoomSignaling] with per-recipient send failures, for the "we KNOW the
/// peer is unreachable" paths.
class _FlakyRoomSignaling extends RoomSignaling {
  _FlakyRoomSignaling({
    required super.signaling,
    required super.dispatcher,
    required super.crypto,
    required super.clock,
    required super.localPubkeyLookup,
    required super.localSecretKeyLookup,
  });

  final Set<String> failTo = {};

  @override
  Future<void> sendTo(
    String recipientPubkey, {
    required SignalingMessageType type,
    required String roomId,
    required Map<String, dynamic> payload,
  }) {
    if (failTo.contains(recipientPubkey)) {
      throw StateError('simulated unreachable: $recipientPubkey');
    }
    return super.sendTo(
      recipientPubkey,
      type: type,
      roomId: roomId,
      payload: payload,
    );
  }
}

class _Peer {
  _Peer(this.pubkey, this.crypto, {Clock? managerClock}) {
    signaling = MockSignalingService(localPubkey: pubkey);
    dispatcher = SignalingDispatcher(
      signaling: signaling,
      crypto: crypto,
      localPubkeyLookup: () async => pubkey,
      localSecretKeyLookup: () async => _secret,
    );
    // RoomSignaling stays on SystemClock even when the manager runs on a
    // MockClock — sealed envelopes carry a ±30s replay window that a mock
    // "advance an hour" would trip.
    roomSignaling = _FlakyRoomSignaling(
      signaling: signaling,
      dispatcher: dispatcher,
      crypto: crypto,
      clock: const SystemClock(),
      localPubkeyLookup: () async => pubkey,
      localSecretKeyLookup: () async => _secret,
    );
    manager = RoomManager(
      roomSignaling: roomSignaling,
      voice: voice,
      storage: storage,
      crypto: crypto,
      clock: managerClock ?? const SystemClock(),
      localPubkeyLookup: () async => pubkey,
    );
    dispatcher.start();
    manager.start();
  }

  final String pubkey;
  final MockCryptoService crypto;
  final _secret = Uint8List(64);
  final storage = MockStorageService();
  final voice = MockVoiceService();
  late final MockSignalingService signaling;
  late final SignalingDispatcher dispatcher;
  late final _FlakyRoomSignaling roomSignaling;
  late final RoomManager manager;

  VoiceParticipant participant(String p) =>
      manager.currentState!.room.participants.firstWhere((x) => x.pubkey == p);

  /// Make [other] a mutual follow: we follow them (active) and they follow us
  /// (accepted inbound request).
  Future<void> makeMutual(String other) async {
    await storage.saveFollow(
      Follow(pubkey: other, connectionCard: '', feedKey: Uint8List(32)),
    );
    await storage.saveInboundRequest(
      FollowRequest(
        pubkey: other,
        payload: Uint8List(0),
        createdAt: 0,
        requestTimestamp: 0,
        status: 'accepted',
      ),
    );
  }

  /// Seed a synced kind=2 profile for [other], so display-name resolution
  /// has something to find.
  Future<void> seedProfile(String other, String name) async {
    await storage.saveEvent(
      Event(
        version: '2026-04-28',
        id: 'profile-$name',
        pubkey: other,
        createdAt: 500,
        kind: EventKind.profile,
        ref: null,
        content: encodeProfileContent(name: name),
        media: const [],
        sig: Uint8List(64),
        msgSeq: null,
      ),
    );
  }
}

String _pk(int fill) =>
    crockfordBase32Encode(Uint8List.fromList(List.filled(32, fill)));

Future<void> _pump() => Future.delayed(const Duration(milliseconds: 30));

void main() {
  final crypto = MockCryptoService();
  final pkA = _pk(1);
  final pkB = _pk(2);
  final pkX = _pk(9);

  late _Peer a;
  late _Peer b;

  setUp(() async {
    a = _Peer(pkA, crypto);
    b = _Peer(pkB, crypto);
    a.signaling.link(b.signaling);
    await a.makeMutual(pkB);
    await b.makeMutual(pkA);
  });

  test(
    'create → invite → accept establishes exactly one offer/answer pair',
    () async {
      final bInvites = <VoiceRoom>[];
      b.manager.incomingInvites.listen(bInvites.add);

      final room = await a.manager.createRoom(
        name: 'Chat',
        inviteePubkeys: [pkB],
      );
      await _pump();

      expect(bInvites, hasLength(1));
      expect(bInvites.first.id, room.id);
      expect(bInvites.first.name, 'Chat');
      expect(bInvites.first.creatorPubkey, pkA);

      await b.manager.acceptInvite(room.id);
      await _pump();

      // Exactly one side is the offerer (lexicographic pubkey rule).
      final aOfferedB = a.voice.offeredPeers.contains(pkB);
      final bOfferedA = b.voice.offeredPeers.contains(pkA);
      expect(
        aOfferedB ^ bOfferedA,
        isTrue,
        reason: 'exactly one peer offers, the other answers',
      );
      if (aOfferedB) {
        expect(b.voice.answeredPeers, contains(pkA));
      } else {
        expect(a.voice.answeredPeers, contains(pkB));
      }

      // Both rosters know each other.
      expect(
        a.manager.currentState!.room.participants.map((p) => p.pubkey),
        containsAll([pkA, pkB]),
      );
      expect(
        b.manager.currentState!.room.participants.map((p) => p.pubkey),
        containsAll([pkA, pkB]),
      );

      // Both sessions are live on the mock WebRTC engine.
      expect(a.voice.sessionRoomId, room.id);
      expect(b.voice.sessionRoomId, room.id);
    },
  );

  test('createRoom rejects a non-mutual-follow invitee', () async {
    // pkX is not a follow of A.
    expect(
      () => a.manager.createRoom(name: 'x', inviteePubkeys: [pkX]),
      throwsStateError,
    );
  });

  test('createRoom enforces the 4-person cap (max 3 invitees)', () async {
    expect(
      () => a.manager.createRoom(
        name: 'x',
        inviteePubkeys: [_pk(2), _pk(3), _pk(4), _pk(5)],
      ),
      throwsArgumentError,
    );
  });

  test('decline does not start a session', () async {
    final room = await a.manager.createRoom(
      name: 'Chat',
      inviteePubkeys: [pkB],
    );
    await _pump();
    await b.manager.declineInvite(room.id);
    await _pump();
    expect(b.manager.inCall, isFalse);
    expect(b.voice.sessionRoomId, isNull);
  });

  test('creator closing the room ends the callee session', () async {
    final room = await a.manager.createRoom(
      name: 'Chat',
      inviteePubkeys: [pkB],
    );
    await _pump();
    await b.manager.acceptInvite(room.id);
    await _pump();
    expect(b.manager.inCall, isTrue);

    await a.manager.closeRoom();
    await _pump();

    expect(a.manager.inCall, isFalse);
    expect(
      b.manager.inCall,
      isFalse,
      reason: 'roomClose tears down the callee',
    );
    expect(a.voice.sessionEnded, isTrue);
    expect(b.voice.sessionEnded, isTrue);
  });

  test('mute broadcasts mute status to the peer', () async {
    final room = await a.manager.createRoom(
      name: 'Chat',
      inviteePubkeys: [pkB],
    );
    await _pump();
    await b.manager.acceptInvite(room.id);
    await _pump();

    await a.manager.setMuted(true);
    await _pump();

    expect(a.voice.micMuted, isTrue);
    final bParticipantA = b.manager.currentState!.room.participants.firstWhere(
      (p) => p.pubkey == pkA,
    );
    expect(bParticipantA.isMuted, isTrue);
  });

  test(
    'a peer reconnecting flips the call-wide anyReconnecting flag',
    () async {
      final room = await a.manager.createRoom(
        name: 'Chat',
        inviteePubkeys: [pkB],
      );
      await _pump();
      await b.manager.acceptInvite(room.id);
      await _pump();

      expect(a.manager.currentState!.anyReconnecting, isFalse);

      a.voice.emitPeerState(pkB, ParticipantConnectionState.reconnecting);
      await _pump();
      expect(a.manager.currentState!.anyReconnecting, isTrue);

      a.voice.emitPeerState(pkB, ParticipantConnectionState.connected);
      await _pump();
      expect(a.manager.currentState!.anyReconnecting, isFalse);
    },
  );

  test(
    'connection quality from the engine propagates to the participant',
    () async {
      final room = await a.manager.createRoom(
        name: 'Chat',
        inviteePubkeys: [pkB],
      );
      await _pump();
      await b.manager.acceptInvite(room.id);
      await _pump();

      a.voice.emitConnectionQuality({pkB: ConnectionQuality.poor});
      await _pump();

      final participantB = a.manager.currentState!.room.participants.firstWhere(
        (p) => p.pubkey == pkB,
      );
      expect(participantB.quality, ConnectionQuality.poor);
    },
  );

  test('startRoomCall pings every member; the live mesh caps at 4', () async {
    // A chatroom of 5 (A + B,C,D,E). The text room is unbounded, but the live
    // call stays a ≤4 mesh: the 5th to join is declined 'full'.
    final pkC = _pk(3), pkD = _pk(4), pkE = _pk(5);
    final c = _Peer(pkC, crypto);
    final d = _Peer(pkD, crypto);
    final e = _Peer(pkE, crypto);
    for (final peer in [b, c, d, e]) {
      a.signaling.link(peer.signaling);
      await a.makeMutual(peer.pubkey);
      await peer.makeMutual(pkA);
    }

    final invites = <String, int>{};
    for (final peer in [b, c, d, e]) {
      peer.manager.incomingInvites.listen((_) {
        invites[peer.pubkey] = (invites[peer.pubkey] ?? 0) + 1;
      });
    }

    final room = await a.manager.startRoomCall(
      chatroomId: 'chat-1',
      name: 'Big room',
      memberPubkeys: [pkB, pkC, pkD, pkE],
    );
    await _pump();

    // Every member is pinged (the only presence broadcast).
    expect(invites.keys, containsAll([pkB, pkC, pkD, pkE]));

    // Fill the mesh to the cap, then a 5th tries to join.
    await b.manager.acceptInvite(room.id);
    await _pump();
    await c.manager.acceptInvite(room.id);
    await _pump();
    await d.manager.acceptInvite(room.id);
    await _pump();
    await e.manager.acceptInvite(room.id);
    await _pump();

    final aConnected = {...a.voice.offeredPeers, ...a.voice.answeredPeers};
    expect(aConnected, containsAll([pkB, pkC, pkD]));
    expect(
      aConnected.contains(pkE),
      isFalse,
      reason: 'the 5th joiner is declined full — no mesh connection with it',
    );
  });

  group('timeouts and terminal states', () {
    late MockClock aClock;
    late MockClock bClock;

    setUp(() async {
      aClock = MockClock(1000);
      bClock = MockClock(1000);
      a = _Peer(pkA, crypto, managerClock: aClock);
      b = _Peer(pkB, crypto, managerClock: bClock);
      a.signaling.link(b.signaling);
      await a.makeMutual(pkB);
      await b.makeMutual(pkA);
    });

    test('unanswered invite resolves to No answer at 61s', () async {
      await a.manager.createRoom(name: 'Chat', inviteePubkeys: [pkB]);
      await _pump();

      // Just under the deadline: still ringing.
      aClock.advance(59);
      a.manager.sweepDeadlines();
      expect(
        a.participant(pkB).connectionState,
        ParticipantConnectionState.connecting,
      );

      aClock.advance(2);
      a.manager.sweepDeadlines();
      final p = a.participant(pkB);
      expect(p.connectionState, ParticipantConnectionState.disconnected);
      expect(p.endReason, ParticipantEndReason.noAnswer);
    });

    test('a failed invite send flags unreachable immediately', () async {
      a.roomSignaling.failTo.add(pkB);
      await a.manager.createRoom(name: 'Chat', inviteePubkeys: [pkB]);
      await _pump();

      final p = a.participant(pkB);
      expect(p.connectionState, ParticipantConnectionState.disconnected);
      expect(p.endReason, ParticipantEndReason.unreachable);
    });

    test('retryParticipant re-invites, restamps the deadline, and clears '
        'the end reason; the peer can then join', () async {
      final bInvites = <VoiceRoom>[];
      b.manager.incomingInvites.listen(bInvites.add);
      final room = await a.manager.createRoom(
        name: 'Chat',
        inviteePubkeys: [pkB],
      );
      await _pump();

      aClock.advance(61);
      a.manager.sweepDeadlines();
      expect(a.participant(pkB).endReason, ParticipantEndReason.noAnswer);

      await a.manager.retryParticipant(pkB);
      await _pump();
      final retried = a.participant(pkB);
      expect(retried.connectionState, ParticipantConnectionState.connecting);
      expect(retried.endReason, isNull);

      // The re-invite refreshed B's existing pending invite — no second
      // sheet emission.
      expect(bInvites, hasLength(1));

      // The restamped deadline holds for another full window.
      aClock.advance(59);
      a.manager.sweepDeadlines();
      expect(
        a.participant(pkB).connectionState,
        ParticipantConnectionState.connecting,
      );

      await b.manager.acceptInvite(room.id);
      await _pump();
      final aOfferedB = a.voice.offeredPeers.contains(pkB);
      final bOfferedA = b.voice.offeredPeers.contains(pkA);
      expect(aOfferedB ^ bOfferedA, isTrue);
    });

    test('decline reasons map to labeled states', () async {
      final room = await a.manager.createRoom(
        name: 'Chat',
        inviteePubkeys: [pkB],
      );
      await _pump();

      // Plain decline (user tapped Decline).
      await b.manager.declineInvite(room.id);
      await _pump();
      expect(a.participant(pkB).endReason, ParticipantEndReason.declined);
    });

    test("invite expiry sends 'timeout' → creator sees No answer, "
        'not Declined', () async {
      final room = await a.manager.createRoom(
        name: 'Chat',
        inviteePubkeys: [pkB],
      );
      await _pump();

      await b.manager.expireInvite(room.id);
      await _pump();
      expect(a.participant(pkB).endReason, ParticipantEndReason.noAnswer);
    });

    test('a second concurrent invite is auto-declined busy', () async {
      final pkC = _pk(3);
      final c = _Peer(pkC, crypto);
      c.signaling.link(b.signaling);
      await c.makeMutual(pkB);
      await b.makeMutual(pkC);

      // A's call is ringing on B…
      await a.manager.createRoom(name: 'First', inviteePubkeys: [pkB]);
      await _pump();

      // …when C calls B too.
      await c.manager.createRoom(name: 'Second', inviteePubkeys: [pkB]);
      await _pump();

      expect(c.participant(pkB).endReason, ParticipantEndReason.busy);
      // B never saw a second sheet: only A's invite is pending.
      expect(b.manager.inCall, isFalse);
    });

    test('pending invite expires via the TTL sweep (missed on our side, '
        'No answer on theirs)', () async {
      final room = await a.manager.createRoom(
        name: 'Chat',
        inviteePubkeys: [pkB],
      );
      await _pump();

      final retired = <String>[];
      b.manager.retiredInvites.listen(retired.add);

      bClock.advance(61);
      b.manager.sweepDeadlines();
      await _pump();

      expect(retired, [room.id]);
      expect(a.participant(pkB).endReason, ParticipantEndReason.noAnswer);
      await expectLater(
        () => b.manager.acceptInvite(room.id),
        throwsStateError,
      );
    });

    test('closeRoom reaches unanswered invitees — their pending invite is '
        'retired', () async {
      final room = await a.manager.createRoom(
        name: 'Chat',
        inviteePubkeys: [pkB],
      );
      await _pump();

      final retired = <String>[];
      b.manager.retiredInvites.listen(retired.add);

      await a.manager.closeRoom();
      await _pump();

      expect(retired, [room.id]);
      await expectLater(
        () => b.manager.acceptInvite(room.id),
        throwsStateError,
      );
    });

    test('a late accept into a dead room gets a roomClose back', () async {
      final room = await a.manager.createRoom(
        name: 'Chat',
        inviteePubkeys: [pkB],
      );
      await _pump();

      // A abandons the call in a way that never notifies B (roomLeave goes
      // to present peers only — nobody).
      await a.manager.leaveRoom();
      expect(a.manager.inCall, isFalse);

      final bEnds = <RoomEndReason>[];
      b.manager.roomEnded.listen(bEnds.add);

      // B answers the stale ring: the accept bounces off A's dead room and
      // the roomClose reply tears B down ("This call has ended").
      await b.manager.acceptInvite(room.id);
      await _pump();

      expect(b.manager.inCall, isFalse);
      expect(bEnds, [RoomEndReason.closedByCreator]);
    });

    test('caller + roster names resolve from LOCAL profiles, never the wire',
        () async {
      // B knows A as "Alex" (synced profile); A knows B as "Bob".
      await b.seedProfile(pkA, 'Alex');
      await a.seedProfile(pkB, 'Bob');

      final bInvites = <VoiceRoom>[];
      b.manager.incomingInvites.listen(bInvites.add);

      final room = await a.manager.createRoom(
        name: 'Chat',
        inviteePubkeys: [pkB],
      );
      await _pump();

      // The ringing sheet gets a name, not 8 hex chars of pubkey.
      expect(bInvites.single.creatorDisplayName, 'Alex');

      // A's roster carries B's local name for the tiles.
      expect(a.participant(pkB).displayName, 'Bob');

      await b.manager.acceptInvite(room.id);
      await _pump();
      expect(b.participant(pkA).displayName, 'Alex');
    });

    test('expired invite records a Missed history row on the invitee',
        () async {
      final room = await a.manager.createRoom(
        name: 'Chat',
        inviteePubkeys: [pkB],
      );
      await _pump();

      await b.manager.expireInvite(room.id);
      final rows = await b.storage.getRecentVoiceRooms();
      expect(rows.single.missed, isTrue);
      expect(rows.single.creatorPubkey, pkA);
    });

    test('creator hanging up an unanswered ring records a Missed row',
        () async {
      await a.manager.createRoom(name: 'Chat', inviteePubkeys: [pkB]);
      await _pump();

      await a.manager.closeRoom();
      await _pump();

      final rows = await b.storage.getRecentVoiceRooms();
      expect(rows.single.missed, isTrue);
    });

    test('mute state rides roomAccept — a joiner sees pre-existing mutes',
        () async {
      final room = await a.manager.createRoom(
        name: 'Chat',
        inviteePubkeys: [pkB],
      );
      await _pump();
      // A mutes BEFORE B joins: the muteStatus broadcast reaches nobody, so
      // only the accept-reply payload can carry it.
      await a.manager.setMuted(true);

      await b.manager.acceptInvite(room.id);
      await _pump();

      expect(b.participant(pkA).isMuted, isTrue);
    });

    test("the engine's reserved self level lights the local tile only",
        () async {
      await a.manager.createRoom(name: 'Chat', inviteePubkeys: [pkB]);
      await _pump();

      a.voice.emitAudioLevels(const {kSelfAudioLevelKey: 0.5});
      await _pump();

      expect(a.participant(pkA).isSpeaking, isTrue);
      expect(a.participant(pkB).isSpeaking, isFalse);
    });

    test('creator close emits closedByCreator to the joined peer', () async {
      final room = await a.manager.createRoom(
        name: 'Chat',
        inviteePubkeys: [pkB],
      );
      await _pump();
      await b.manager.acceptInvite(room.id);
      await _pump();

      final bEnds = <RoomEndReason>[];
      b.manager.roomEnded.listen(bEnds.add);

      await a.manager.closeRoom();
      await _pump();

      expect(bEnds, [RoomEndReason.closedByCreator]);
    });
  });
}
