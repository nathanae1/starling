import 'dart:async';
import 'dart:typed_data';

import '../../models/signaling_message.dart';
import '../../models/voice_room.dart';
import '../clock.dart';
import '../crypto_service.dart';
import '../storage_service.dart';
import '../voice_service.dart';
import 'room_signaling.dart';

/// Orchestrates a voice room over the signaling plane + WebRTC engine
/// (Plan 16 §Phase C).
///
/// Mesh convergence is decentralized and glare-free:
///  * The creator's invite carries the full `roster` and a shared
///    `session_key`. Invites are accepted only from a **mutual follow**.
///  * On join, a node broadcasts `roomAccept` to every roster member; each
///    already-present member replies once (presence gossip) so both sides
///    learn each other are present.
///  * For each present peer pair, the node with the lexicographically smaller
///    pubkey sends the WebRTC `offer` (the other answers) — exactly one
///    offerer per pair, guarded by `_offeredTo`.
class RoomManager {
  RoomManager({
    required RoomSignaling roomSignaling,
    required VoiceService voice,
    required StorageService storage,
    required CryptoService crypto,
    required Clock clock,
    required Future<String?> Function() localPubkeyLookup,
    Future<void> Function(String roomId, String callId)? announceCall,
    this.speakingThreshold = 0.02,
  }) : _roomSignaling = roomSignaling,
       _voice = voice,
       _storage = storage,
       _crypto = crypto,
       _clock = clock,
       _localPubkeyLookup = localPubkeyLookup,
       _announceCall = announceCall;

  final RoomSignaling _roomSignaling;
  final VoiceService _voice;
  final StorageService _storage;
  final CryptoService _crypto;
  final Clock _clock;
  final Future<String?> Function() _localPubkeyLookup;

  /// Plan 17: authors the durable `roomCallStarted` record when a chatroom
  /// call starts, so offline members see it on next sync. Null for the Plan
  /// 16 direct-call path (no durable record).
  final Future<void> Function(String roomId, String callId)? _announceCall;

  /// Normalized audio level above which a participant is rendered "speaking".
  final double speakingThreshold;

  final _stateCtrl = StreamController<VoiceRoomState?>.broadcast();
  final _inviteCtrl = StreamController<VoiceRoom>.broadcast();

  VoiceRoom? _room;

  /// The per-call history PK (Plan 16 `voice_rooms`), kept DISTINCT from the
  /// signaling `_room.id`. For a Plan 16 direct call the two are equal; for a
  /// Plan 17 chatroom call the signaling id is the chatroomId while this is a
  /// fresh call id, so a second call doesn't overwrite the first's history.
  String? _callId;
  final Map<String, VoiceParticipant> _roster = {};
  final Set<String> _present = {};
  final Set<String> _offeredTo = {};
  Set<String> _invitedRoster = {};
  final Map<String, _PendingInvite> _pendingInvites = {};
  Uint8List? _sessionKey;
  bool _localMuted = false;
  bool _speakerMode = false;
  String? _localPubkey;
  bool _started = false;
  final _subs = <StreamSubscription<dynamic>>[];
  VoiceRoomState? _lastState;

  /// Live room state; null when idle.
  Stream<VoiceRoomState?> get state => _stateCtrl.stream;

  /// Inbound room invites awaiting the user's accept/decline.
  Stream<VoiceRoom> get incomingInvites => _inviteCtrl.stream;

  VoiceRoomState? get currentState => _lastState;
  bool get inCall => _room != null;

  /// Idempotent. Wires the signaling + WebRTC event streams.
  void start() {
    if (_started) return;
    _started = true;
    _roomSignaling.start();
    _subs.add(_roomSignaling.inbound.listen((s) => unawaited(_onSignal(s))));
    _subs.add(
      _voice.localIceCandidates.listen((c) => unawaited(_onLocalIce(c))),
    );
    _subs.add(_voice.peerStates.listen(_onPeerState));
    _subs.add(_voice.audioLevels.listen(_onAudioLevels));
    _subs.add(_voice.connectionQuality.listen(_onConnectionQuality));
  }

  Future<void> stop() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _roomSignaling.stop();
    _started = false;
  }

  // --- public actions ---

  Future<VoiceRoom> createRoom({
    required String name,
    required List<String> inviteePubkeys,
  }) async {
    if (_room != null) throw StateError('already in a room');
    if (inviteePubkeys.length > kMaxRoomInvitees) {
      throw ArgumentError('at most $kMaxRoomInvitees invitees');
    }
    final me = await _requireLocalPubkey();
    for (final p in inviteePubkeys) {
      if (!await _isMutualFollow(p)) {
        throw StateError('not a mutual follow: $p');
      }
    }

    final roomId = _hex(_crypto.randomBytes(16));
    _sessionKey = _crypto.randomBytes(32);
    final now = _clock.nowUnixSeconds();

    _resetSession();
    _callId = roomId; // Plan 16 direct call: history PK == signaling id.
    _invitedRoster = {me, ...inviteePubkeys};
    _present.add(me);
    _roster[me] = VoiceParticipant(
      pubkey: me,
      connectionState: ParticipantConnectionState.connected,
    );
    for (final p in inviteePubkeys) {
      _roster[p] = VoiceParticipant(
        pubkey: p,
        connectionState: ParticipantConnectionState.connecting,
      );
    }
    _room = VoiceRoom(
      id: roomId,
      name: name,
      creatorPubkey: me,
      createdAt: now,
      invitedPubkeys: inviteePubkeys,
    );

    await _voice.startSession(roomId);
    await _saveHistoryRoom();
    await _storage.saveVoiceRoomParticipant(_callId!, me, joinedAt: now);

    final sessionHex = _hex(_sessionKey!);
    for (final p in inviteePubkeys) {
      await _safeSend(p, SignalingMessageType.roomInvite, roomId, {
        'name': name,
        'creator': me,
        'roster': _invitedRoster.toList(),
        'session_key': sessionHex,
      });
    }
    _emitState();
    return _room!;
  }

  /// Plan 17: start the single live call for chatroom [chatroomId]. Unlike
  /// [createRoom], the signaling roomId IS the chatroomId (so concurrent
  /// starts converge on one mesh), the per-call history is keyed on a fresh
  /// callId, and a durable `roomCallStarted` record is authored for offline
  /// members. The ≤4 mesh cap is enforced on accept, not here — every member
  /// is pinged even in a large room.
  Future<VoiceRoom> startRoomCall({
    required String chatroomId,
    required String name,
    required List<String> memberPubkeys,
  }) async {
    if (_room != null) throw StateError('already in a room');
    final me = await _requireLocalPubkey();
    final others = memberPubkeys.where((p) => p != me).toList();
    final callId = _hex(_crypto.randomBytes(16));
    _sessionKey = _crypto.randomBytes(32);
    final now = _clock.nowUnixSeconds();

    _resetSession();
    _callId = callId; // distinct from the signaling id (= chatroomId)
    _invitedRoster = {me, ...others};
    _present.add(me);
    _roster[me] = VoiceParticipant(
      pubkey: me,
      connectionState: ParticipantConnectionState.connected,
    );
    for (final p in others) {
      _roster[p] = VoiceParticipant(
        pubkey: p,
        connectionState: ParticipantConnectionState.connecting,
      );
    }
    _room = VoiceRoom(
      id: chatroomId,
      name: name,
      creatorPubkey: me,
      createdAt: now,
      invitedPubkeys: others,
    );

    await _voice.startSession(chatroomId);
    await _saveHistoryRoom();
    await _storage.saveVoiceRoomParticipant(callId, me, joinedAt: now);

    // Durable "call started" record so offline members learn of it on sync.
    await _announceCall?.call(chatroomId, callId);

    // Live presence ping — the ONLY presence broadcast — to every member.
    final sessionHex = _hex(_sessionKey!);
    for (final p in others) {
      await _safeSend(p, SignalingMessageType.roomInvite, chatroomId, {
        'name': name,
        'creator': me,
        'roster': _invitedRoster.toList(),
        'session_key': sessionHex,
        'call_id': callId,
        'chatroom': true,
      });
    }
    _emitState();
    return _room!;
  }

  Future<void> acceptInvite(String roomId) async {
    final pending = _pendingInvites.remove(roomId);
    if (pending == null) throw StateError('no pending invite for $roomId');
    if (_room != null) throw StateError('already in a room');
    final me = await _requireLocalPubkey();
    final creator = pending.invite.creatorPubkey;

    _resetSession();
    // Chatroom calls carry a distinct call_id; direct calls key on roomId.
    _callId = pending.callId ?? roomId;
    _sessionKey = pending.sessionKeyHex != null
        ? _unhex(pending.sessionKeyHex!)
        : null;
    _invitedRoster = {...pending.roster, creator};
    _present
      ..add(me)
      ..add(creator);

    final now = _clock.nowUnixSeconds();
    _roster[me] = VoiceParticipant(
      pubkey: me,
      connectionState: ParticipantConnectionState.connected,
    );
    for (final p in _invitedRoster) {
      if (p == me) continue;
      _roster[p] = VoiceParticipant(
        pubkey: p,
        connectionState: ParticipantConnectionState.connecting,
      );
    }
    _room = VoiceRoom(
      id: roomId,
      name: pending.invite.name,
      creatorPubkey: creator,
      createdAt: now,
      invitedPubkeys: _invitedRoster
          .where((p) => p != me && p != creator)
          .toList(),
    );

    await _voice.startSession(roomId);
    await _saveHistoryRoom();
    await _storage.saveVoiceRoomParticipant(_callId!, me, joinedAt: now);

    final sessionHex = _sessionKey != null ? _hex(_sessionKey!) : '';
    for (final p in _invitedRoster) {
      if (p == me) continue;
      await _safeSend(p, SignalingMessageType.roomAccept, roomId, {
        'session_key': sessionHex,
      });
    }
    await _maybeOffer(creator);
    _emitState();
  }

  Future<void> declineInvite(String roomId) async {
    final pending = _pendingInvites.remove(roomId);
    if (pending == null) return;
    await _safeSend(
      pending.invite.creatorPubkey,
      SignalingMessageType.roomDecline,
      roomId,
      const {},
    );
  }

  Future<void> setMuted(bool muted) async {
    _localMuted = muted;
    await _voice.setMicMuted(muted);
    final room = _room;
    if (room != null) {
      for (final p in _present) {
        if (p == _localPubkey) continue;
        await _safeSend(p, SignalingMessageType.muteStatus, room.id, {
          'muted': muted,
        });
      }
    }
    _emitState();
  }

  Future<void> setSpeaker(bool speaker) async {
    _speakerMode = speaker;
    await _voice.setSpeakerMode(speaker);
    _emitState();
  }

  Future<void> leaveRoom() async {
    final room = _room;
    if (room == null) return;
    for (final p in _present.toList()) {
      if (p == _localPubkey) continue;
      await _safeSend(p, SignalingMessageType.roomLeave, room.id, const {});
    }
    await _endSession();
  }

  Future<void> closeRoom() async {
    final room = _room;
    if (room == null) return;
    final me = await _requireLocalPubkey();
    if (me != room.creatorPubkey) {
      await leaveRoom();
      return;
    }
    for (final p in _present.toList()) {
      if (p == me) continue;
      await _safeSend(p, SignalingMessageType.roomClose, room.id, const {});
    }
    await _endSession();
  }

  // --- inbound signaling ---

  Future<void> _onSignal(VoiceSignal sig) async {
    final msg = sig.message;
    final from = msg.senderPubkey;
    switch (msg.type) {
      case SignalingMessageType.roomInvite:
        await _onInvite(msg);
      case SignalingMessageType.roomAccept:
        await _onAccept(from, msg);
      case SignalingMessageType.roomDecline:
        _onDecline(from, msg);
      case SignalingMessageType.roomLeave:
        await _onLeave(from, msg);
      case SignalingMessageType.roomClose:
        await _onClose(from, msg);
      case SignalingMessageType.offer:
        await _onOffer(from, msg);
      case SignalingMessageType.answer:
        await _onAnswer(from, msg);
      case SignalingMessageType.iceCandidate:
        await _onRemoteIce(from, msg);
      case SignalingMessageType.muteStatus:
        _onMuteStatus(from, msg);
      case SignalingMessageType.libp2pConnect:
        break; // never delivered here; RoomSignaling filters it out
    }
  }

  Future<void> _onInvite(SignalingMessage msg) async {
    if (_room != null) {
      await _safeSend(
        msg.senderPubkey,
        SignalingMessageType.roomDecline,
        msg.roomId,
        {'reason': 'busy'},
      );
      return;
    }
    final creator = (msg.payload['creator'] as String?) ?? msg.senderPubkey;
    if (!await _isMutualFollow(creator)) return;
    final name = (msg.payload['name'] as String?) ?? 'Voice room';
    final roster = _asStringList(msg.payload['roster']);
    final invite = VoiceRoom(
      id: msg.roomId,
      name: name,
      creatorPubkey: creator,
      createdAt: _clock.nowUnixSeconds(),
      invitedPubkeys: roster.where((p) => p != creator).toList(),
    );
    _pendingInvites[msg.roomId] = _PendingInvite(
      invite: invite,
      roster: roster,
      sessionKeyHex: msg.payload['session_key'] as String?,
      callId: msg.payload['call_id'] as String?,
    );
    _inviteCtrl.add(invite);
  }

  Future<void> _onAccept(String from, SignalingMessage msg) async {
    final room = _room;
    if (room == null || msg.roomId != room.id) return;
    if (!_invitedRoster.contains(from)) return;
    if (!_sessionKeyMatches(msg.payload['session_key'])) return;

    final firstSight = !_present.contains(from);
    // Live-call cap: the mesh stays ≤ kMaxRoomParticipants even in an
    // unbounded chatroom. A joiner beyond the cap is declined 'full'.
    if (firstSight && _present.length >= kMaxRoomParticipants) {
      await _safeSend(from, SignalingMessageType.roomDecline, room.id, {
        'reason': 'full',
      });
      return;
    }
    _present.add(from);
    _setParticipantState(from, ParticipantConnectionState.connecting);
    await _storage.saveVoiceRoomParticipant(
      _callId!,
      from,
      joinedAt: _clock.nowUnixSeconds(),
    );
    if (firstSight) {
      final sessionHex = _sessionKey != null ? _hex(_sessionKey!) : '';
      await _safeSend(from, SignalingMessageType.roomAccept, room.id, {
        'session_key': sessionHex,
      });
    }
    await _maybeOffer(from);
    _emitState();
  }

  void _onDecline(String from, SignalingMessage msg) {
    if (_room == null || msg.roomId != _room!.id) return;
    _setParticipantState(from, ParticipantConnectionState.disconnected);
    _emitState();
  }

  Future<void> _onLeave(String from, SignalingMessage msg) async {
    if (_room == null || msg.roomId != _room!.id) return;
    _present.remove(from);
    _offeredTo.remove(from);
    _roster.remove(from);
    await _voice.removePeer(from);
    _emitState();
  }

  Future<void> _onClose(String from, SignalingMessage msg) async {
    final room = _room;
    if (room == null || msg.roomId != room.id) return;
    if (from != room.creatorPubkey) return;
    await _endSession();
  }

  Future<void> _onOffer(String from, SignalingMessage msg) async {
    final room = _room;
    if (room == null || msg.roomId != room.id) return;
    if (!_invitedRoster.contains(from)) return;
    final firstSight = !_present.contains(from);
    if (firstSight && _present.length >= kMaxRoomParticipants) {
      await _safeSend(from, SignalingMessageType.roomDecline, room.id, {
        'reason': 'full',
      });
      return;
    }
    _present.add(from);
    try {
      final answer = await _voice.createAnswer(from, msg.payload);
      await _safeSend(from, SignalingMessageType.answer, room.id, answer);
    } catch (_) {
      _setParticipantState(from, ParticipantConnectionState.disconnected);
      _emitState();
    }
  }

  Future<void> _onAnswer(String from, SignalingMessage msg) async {
    if (_room == null || msg.roomId != _room!.id) return;
    await _voice.setRemoteAnswer(from, msg.payload);
  }

  Future<void> _onRemoteIce(String from, SignalingMessage msg) async {
    if (_room == null || msg.roomId != _room!.id) return;
    await _voice.addRemoteIceCandidate(from, msg.payload);
  }

  void _onMuteStatus(String from, SignalingMessage msg) {
    if (_room == null || msg.roomId != _room!.id) return;
    final cur = _roster[from];
    if (cur == null) return;
    _roster[from] = cur.copyWith(isMuted: msg.payload['muted'] == true);
    _emitState();
  }

  // --- WebRTC engine events ---

  Future<void> _onLocalIce(VoiceIceCandidate c) async {
    final room = _room;
    if (room == null) return;
    await _safeSend(
      c.peerPubkey,
      SignalingMessageType.iceCandidate,
      room.id,
      c.candidate,
    );
  }

  void _onPeerState(VoicePeerState s) {
    if (_room == null) return;
    _setParticipantState(s.peerPubkey, s.state);
    _emitState();
  }

  void _onAudioLevels(Map<String, double> levels) {
    if (_room == null) return;
    var changed = false;
    for (final pubkey in _roster.keys.toList()) {
      final speaking = (levels[pubkey] ?? 0) > speakingThreshold;
      final cur = _roster[pubkey]!;
      if (cur.isSpeaking != speaking) {
        _roster[pubkey] = cur.copyWith(isSpeaking: speaking);
        changed = true;
      }
    }
    if (changed) _emitState();
  }

  void _onConnectionQuality(Map<String, ConnectionQuality> quality) {
    if (_room == null) return;
    var changed = false;
    for (final entry in quality.entries) {
      final cur = _roster[entry.key];
      if (cur == null) continue;
      if (cur.quality != entry.value) {
        _roster[entry.key] = cur.copyWith(quality: entry.value);
        changed = true;
      }
    }
    if (changed) _emitState();
  }

  // --- internals ---

  Future<void> _maybeOffer(String peer) async {
    if (_room == null || _offeredTo.contains(peer)) return;
    if (!_present.contains(peer)) return;
    final me = await _requireLocalPubkey();
    if (peer == me || me.compareTo(peer) >= 0) return; // the other side offers
    _offeredTo.add(peer);
    try {
      final offer = await _voice.createOffer(peer);
      await _safeSend(peer, SignalingMessageType.offer, _room!.id, offer);
    } catch (_) {
      _offeredTo.remove(peer);
      _setParticipantState(peer, ParticipantConnectionState.disconnected);
      _emitState();
    }
  }

  Future<void> _endSession() async {
    final callId = _callId;
    await _voice.endSession();
    if (callId != null) {
      await _storage.updateVoiceRoomEnded(callId, _clock.nowUnixSeconds());
    }
    _resetSession();
    _room = null;
    _sessionKey = null;
    _localMuted = false;
    _speakerMode = false;
    _emitState();
  }

  void _resetSession() {
    _roster.clear();
    _present.clear();
    _offeredTo.clear();
    _invitedRoster = {};
    _callId = null;
  }

  /// Persist the current call to Plan 16 `voice_rooms` history under [_callId]
  /// (kept distinct from the signaling `_room.id` for chatroom calls).
  Future<void> _saveHistoryRoom() async {
    final room = _room;
    final callId = _callId;
    if (room == null || callId == null) return;
    await _storage.saveVoiceRoom(
      VoiceRoom(
        id: callId,
        name: room.name,
        creatorPubkey: room.creatorPubkey,
        createdAt: room.createdAt,
        invitedPubkeys: room.invitedPubkeys,
        participants: _roster.values.toList(),
      ),
    );
  }

  void _setParticipantState(String pubkey, ParticipantConnectionState st) {
    final cur = _roster[pubkey];
    _roster[pubkey] = cur == null
        ? VoiceParticipant(pubkey: pubkey, connectionState: st)
        : cur.copyWith(connectionState: st);
  }

  void _emitState() {
    if (_room == null) {
      _lastState = null;
    } else {
      _lastState = VoiceRoomState(
        room: _room!.copyWith(participants: _roster.values.toList()),
        localMuted: _localMuted,
        speakerMode: _speakerMode,
      );
    }
    if (!_stateCtrl.isClosed) _stateCtrl.add(_lastState);
  }

  Future<String> _requireLocalPubkey() async {
    final pk = _localPubkey ??= await _localPubkeyLookup();
    if (pk == null || pk.isEmpty) {
      throw StateError('room_manager: local identity not available');
    }
    return pk;
  }

  Future<bool> _isMutualFollow(String pubkey) async {
    final follow = await _storage.getFollow(pubkey);
    if (follow == null || follow.status != 'active') return false;
    return _storage.isAcceptedFollower(pubkey);
  }

  bool _sessionKeyMatches(Object? got) {
    final key = _sessionKey;
    if (key == null) return true; // no session key in play
    return got is String && got == _hex(key);
  }

  Future<void> _safeSend(
    String pubkey,
    SignalingMessageType type,
    String roomId,
    Map<String, dynamic> payload,
  ) async {
    try {
      await _roomSignaling.sendTo(
        pubkey,
        type: type,
        roomId: roomId,
        payload: payload,
      );
    } catch (_) {
      // Unreachable peer / transient signaling failure — the participant
      // stays in its current (connecting/disconnected) state; the next
      // accept/offer round re-attempts.
    }
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _unhex(String hex) {
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static List<String> _asStringList(Object? v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return const [];
  }
}

class _PendingInvite {
  _PendingInvite({
    required this.invite,
    required this.roster,
    required this.sessionKeyHex,
    this.callId,
  });
  final VoiceRoom invite;
  final List<String> roster;
  final String? sessionKeyHex;

  /// Plan 17: distinct per-call history id for a chatroom call (null for a
  /// Plan 16 direct call, where the history keys on the roomId).
  final String? callId;
}
