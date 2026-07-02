import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../../models/profile_content.dart';
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

  /// How long a remote participant may sit in `connecting` before the sweep
  /// resolves it to a labeled terminal state ("No answer" / "Couldn't
  /// reach"). Locked product decision: 60 s, per-participant, no global
  /// call abort.
  static const Duration participantTimeout = Duration(seconds: 60);

  /// How long an unanswered inbound invite stays valid. Past this it expires
  /// (best-effort timeout-decline + missed-call record) so a dead creator
  /// can't leave a stale ring behind.
  static const Duration inviteTtl = Duration(seconds: 60);

  static const Duration _sweepInterval = Duration(seconds: 5);

  final _stateCtrl = StreamController<VoiceRoomState?>.broadcast();
  final _inviteCtrl = StreamController<VoiceRoom>.broadcast();
  final _inviteRetiredCtrl = StreamController<String>.broadcast();
  final _roomEndedCtrl = StreamController<RoomEndReason>.broadcast();

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
  Timer? _sweepTimer;

  /// Unix seconds at which each remote participant last entered
  /// `connecting`, for the sweep's per-participant deadline. Maintained by
  /// [_setParticipantState].
  final Map<String, int> _connectingSince = {};

  /// Live room state; null when idle.
  Stream<VoiceRoomState?> get state => _stateCtrl.stream;

  /// Inbound room invites awaiting the user's accept/decline.
  Stream<VoiceRoom> get incomingInvites => _inviteCtrl.stream;

  /// Room ids whose pending invite was retired out from under the user —
  /// TTL expiry, or the creator closed the call before it was answered. The
  /// ringing sheet listens and closes ("This call has ended").
  Stream<String> get retiredInvites => _inviteRetiredCtrl.stream;

  /// Why the last call ended, emitted on teardown. Drives the non-creator
  /// "Call ended" snackbar (a silent pop is indistinguishable from a bug).
  Stream<RoomEndReason> get roomEnded => _roomEndedCtrl.stream;

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
    _subs.add(
      _voice.renegotiationNeeded.listen(
        (p) => unawaited(_onRenegotiationNeeded(p)),
      ),
    );
    // Always on (cheap no-op ticks while idle): pending-invite expiry must
    // run OUTSIDE calls too, not just while a room is up.
    _sweepTimer ??= Timer.periodic(_sweepInterval, (_) => sweepDeadlines());
  }

  Future<void> stop() async {
    _sweepTimer?.cancel();
    _sweepTimer = null;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _roomSignaling.stop();
    _started = false;
  }

  /// One deadline pass: expire stale pending invites and resolve remote
  /// participants stuck in `connecting` past [participantTimeout] to a
  /// labeled terminal state. Called by the periodic timer; exposed so tests
  /// can drive it directly against a mock clock.
  @visibleForTesting
  void sweepDeadlines() {
    final now = _clock.nowUnixSeconds();

    final expired = _pendingInvites.entries
        .where((e) => now - e.value.receivedAt >= inviteTtl.inSeconds)
        .map((e) => e.key)
        .toList();
    for (final roomId in expired) {
      unawaited(expireInvite(roomId));
    }

    if (_room == null) return;
    var changed = false;
    for (final entry in _connectingSince.entries.toList()) {
      final p = entry.key;
      if (p == _localPubkey) continue;
      if (now - entry.value < participantTimeout.inSeconds) continue;
      final cur = _roster[p];
      if (cur == null ||
          cur.connectionState != ParticipantConnectionState.connecting) {
        _connectingSince.remove(p);
        continue;
      }
      _setParticipantState(
        p,
        ParticipantConnectionState.disconnected,
        // Accepted (present) but media never came up → "Couldn't reach";
        // never answered the invite at all → "No answer".
        endReason: _present.contains(p)
            ? ParticipantEndReason.unreachable
            : ParticipantEndReason.noAnswer,
      );
      changed = true;
    }
    if (changed) _emitState();
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
    _setParticipantState(me, ParticipantConnectionState.connected);
    for (final p in inviteePubkeys) {
      _setParticipantState(p, ParticipantConnectionState.connecting);
    }
    _room = VoiceRoom(
      id: roomId,
      name: name,
      creatorPubkey: me,
      createdAt: now,
      invitedPubkeys: inviteePubkeys,
    );

    await _voice.startSession(roomId);
    await _populateDisplayNames();
    await _saveHistoryRoom();
    await _storage.saveVoiceRoomParticipant(
      _callId!,
      me,
      displayName: await _displayName(me),
      joinedAt: now,
    );

    final sessionHex = _hex(_sessionKey!);
    for (final p in inviteePubkeys) {
      final ok = await _safeSend(p, SignalingMessageType.roomInvite, roomId, {
        'name': name,
        'creator': me,
        'roster': _invitedRoster.toList(),
        'session_key': sessionHex,
      });
      // A failed invite send means we KNOW the peer is unreachable — flag
      // it now instead of faking a 60s spinner.
      if (!ok) {
        _setParticipantState(
          p,
          ParticipantConnectionState.disconnected,
          endReason: ParticipantEndReason.unreachable,
        );
      }
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
    _setParticipantState(me, ParticipantConnectionState.connected);
    for (final p in others) {
      _setParticipantState(p, ParticipantConnectionState.connecting);
    }
    _room = VoiceRoom(
      id: chatroomId,
      name: name,
      creatorPubkey: me,
      createdAt: now,
      invitedPubkeys: others,
    );

    await _voice.startSession(chatroomId);
    await _populateDisplayNames();
    await _saveHistoryRoom();
    await _storage.saveVoiceRoomParticipant(
      callId,
      me,
      displayName: await _displayName(me),
      joinedAt: now,
    );

    // Durable "call started" record so offline members learn of it on sync.
    await _announceCall?.call(chatroomId, callId);

    // Live presence ping — the ONLY presence broadcast — to every member.
    final sessionHex = _hex(_sessionKey!);
    for (final p in others) {
      final ok = await _safeSend(
        p,
        SignalingMessageType.roomInvite,
        chatroomId,
        {
          'name': name,
          'creator': me,
          'roster': _invitedRoster.toList(),
          'session_key': sessionHex,
          'call_id': callId,
          'chatroom': true,
        },
      );
      if (!ok) {
        _setParticipantState(
          p,
          ParticipantConnectionState.disconnected,
          endReason: ParticipantEndReason.unreachable,
        );
      }
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
    _setParticipantState(me, ParticipantConnectionState.connected);
    for (final p in _invitedRoster) {
      if (p == me) continue;
      _setParticipantState(p, ParticipantConnectionState.connecting);
    }
    _room = VoiceRoom(
      id: roomId,
      name: pending.invite.name,
      creatorPubkey: creator,
      creatorDisplayName: pending.invite.creatorDisplayName,
      createdAt: now,
      invitedPubkeys: _invitedRoster
          .where((p) => p != me && p != creator)
          .toList(),
    );

    await _voice.startSession(roomId);
    await _populateDisplayNames();
    await _saveHistoryRoom();
    await _storage.saveVoiceRoomParticipant(
      _callId!,
      me,
      displayName: await _displayName(me),
      joinedAt: now,
    );

    final sessionHex = _sessionKey != null ? _hex(_sessionKey!) : '';
    for (final p in _invitedRoster) {
      if (p == me) continue;
      await _safeSend(p, SignalingMessageType.roomAccept, roomId, {
        'session_key': sessionHex,
        // Mute state rides the accept so existing members see the joiner's
        // real state (and vice versa on the reply) — old clients ignore it.
        'muted': _localMuted,
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

  /// Retire a pending invite that was never answered — the ringing sheet
  /// timed out, was swipe-dismissed, or the TTL sweep expired it. Records a
  /// missed-call history row and sends a best-effort decline with reason
  /// 'timeout' so the creator's tile resolves to "No answer" (not
  /// "Declined"); notifies [retiredInvites] so any open sheet closes.
  Future<void> expireInvite(String roomId) async {
    final pending = _pendingInvites.remove(roomId);
    if (pending == null) return;
    _inviteRetiredCtrl.add(roomId);
    await _recordMissedInvite(pending, roomId);
    await _safeSend(
      pending.invite.creatorPubkey,
      SignalingMessageType.roomDecline,
      roomId,
      const {'reason': 'timeout'},
    );
  }

  /// Write the invitee-side "Missed" history row for an unanswered invite.
  /// Keyed on the call id, so answering a later retry of the same call
  /// upserts the row back to a normal (non-missed) entry.
  Future<void> _recordMissedInvite(
    _PendingInvite pending,
    String roomId,
  ) async {
    final now = _clock.nowUnixSeconds();
    await _storage.saveVoiceRoom(
      VoiceRoom(
        id: pending.callId ?? roomId,
        name: pending.invite.name,
        creatorPubkey: pending.invite.creatorPubkey,
        createdAt: now,
        endedAt: now,
        missed: true,
      ),
    );
  }

  /// Missed-call row for an invite we auto-declined busy (mid-call, or a
  /// second concurrent ring). Mutual-follow gated — the busy reply itself
  /// is sent regardless, but only friends earn history rows.
  Future<void> _recordMissedBusy(SignalingMessage msg) async {
    final creator = (msg.payload['creator'] as String?) ?? msg.senderPubkey;
    if (!await _isMutualFollow(creator)) return;
    final now = _clock.nowUnixSeconds();
    await _storage.saveVoiceRoom(
      VoiceRoom(
        id: (msg.payload['call_id'] as String?) ?? msg.roomId,
        name: (msg.payload['name'] as String?) ?? 'Voice room',
        creatorPubkey: creator,
        createdAt: now,
        endedAt: now,
        missed: true,
      ),
    );
  }

  /// Re-attempt a participant whose tile resolved to "No answer" /
  /// "Couldn't reach". Never-accepted → re-send the invite; accepted but
  /// media never came up → tear down the half-open connection and redo the
  /// offer exchange.
  Future<void> retryParticipant(String pubkey) async {
    final room = _room;
    if (room == null) return;
    final me = await _requireLocalPubkey();
    if (pubkey == me || !_invitedRoster.contains(pubkey)) return;

    // Back to `connecting`: clears the end reason and restamps the 60s
    // deadline (via _setParticipantState).
    _setParticipantState(pubkey, ParticipantConnectionState.connecting);
    _emitState();

    if (!_present.contains(pubkey)) {
      // Chatroom calls carry the distinct call id (see startRoomCall).
      final isChatroom = _callId != null && _callId != room.id;
      final ok = await _safeSend(
        pubkey,
        SignalingMessageType.roomInvite,
        room.id,
        {
          'name': room.name,
          'creator': room.creatorPubkey,
          'roster': _invitedRoster.toList(),
          'session_key': _sessionKey != null ? _hex(_sessionKey!) : '',
          if (isChatroom) 'call_id': _callId,
          if (isChatroom) 'chatroom': true,
        },
      );
      if (!ok) {
        _setParticipantState(
          pubkey,
          ParticipantConnectionState.disconnected,
          endReason: ParticipantEndReason.unreachable,
        );
        _emitState();
      }
      return;
    }

    // Present but never connected: drop the half-open peer connection and
    // restart the pair. If we're the offerer we re-offer directly; if
    // they are, nudge them with a fresh accept carrying `retry` so they
    // drop their side and re-offer (old clients ignore the extra key —
    // harmless no-op).
    await _voice.removePeer(pubkey);
    _offeredTo.remove(pubkey);
    if (me.compareTo(pubkey) < 0) {
      await _maybeOffer(pubkey);
    } else {
      final ok = await _safeSend(
        pubkey,
        SignalingMessageType.roomAccept,
        room.id,
        {
          'session_key': _sessionKey != null ? _hex(_sessionKey!) : '',
          'retry': true,
          'muted': _localMuted,
        },
      );
      if (!ok) {
        _setParticipantState(
          pubkey,
          ParticipantConnectionState.disconnected,
          endReason: ParticipantEndReason.unreachable,
        );
        _emitState();
      }
    }
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
    // Close the FULL invited roster, not just _present — an invitee who
    // never answered still holds a valid pending invite; without this a
    // late accept would ring into a dead room.
    for (final p in _invitedRoster) {
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
      // A retry ping for the room we're already in is not a competing
      // call — ignore it (busy-declining would flip our tile to "Busy" on
      // the sender's side while we're connected).
      if (msg.roomId == _room!.id) return;
      await _safeSend(
        msg.senderPubkey,
        SignalingMessageType.roomDecline,
        msg.roomId,
        {'reason': 'busy'},
      );
      await _recordMissedBusy(msg);
      return;
    }
    final creator = (msg.payload['creator'] as String?) ?? msg.senderPubkey;
    final existing = _pendingInvites[msg.roomId];
    if (existing != null && existing.invite.creatorPubkey == creator) {
      // A retry ping for the call that's already ringing — refresh its TTL
      // deadline, don't stack a second sheet.
      _pendingInvites[msg.roomId] = existing.copyWith(
        receivedAt: _clock.nowUnixSeconds(),
      );
      return;
    }
    if (_pendingInvites.isNotEmpty) {
      // A different call is already ringing — auto-busy the second one at
      // the service layer so the UI can never stack invite sheets.
      await _safeSend(
        msg.senderPubkey,
        SignalingMessageType.roomDecline,
        msg.roomId,
        {'reason': 'busy'},
      );
      await _recordMissedBusy(msg);
      return;
    }
    if (!await _isMutualFollow(creator)) return;
    final name = (msg.payload['name'] as String?) ?? 'Voice room';
    final roster = _asStringList(msg.payload['roster']);
    final invite = VoiceRoom(
      id: msg.roomId,
      name: name,
      creatorPubkey: creator,
      // Resolved locally from the creator's synced profile — the ringing
      // sheet must show a name, not 8 hex chars of pubkey.
      creatorDisplayName: await _displayName(creator),
      createdAt: _clock.nowUnixSeconds(),
      invitedPubkeys: roster.where((p) => p != creator).toList(),
    );
    _pendingInvites[msg.roomId] = _PendingInvite(
      invite: invite,
      roster: roster,
      sessionKeyHex: msg.payload['session_key'] as String?,
      callId: msg.payload['call_id'] as String?,
      receivedAt: _clock.nowUnixSeconds(),
    );
    _inviteCtrl.add(invite);
  }

  Future<void> _onAccept(String from, SignalingMessage msg) async {
    final room = _room;
    if (room == null || msg.roomId != room.id) {
      // A late accept for a call we're no longer in (or never were) —
      // without a reply their pending invite rings into a dead room. Tell
      // them it's over.
      await _safeSend(
        from,
        SignalingMessageType.roomClose,
        msg.roomId,
        const {},
      );
      return;
    }
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
    if (msg.payload['retry'] == true && !firstSight) {
      // The peer restarted our pair (their Retry tile): drop the half-open
      // connection so the fresh offer exchange below starts clean.
      await _voice.removePeer(from);
      _offeredTo.remove(from);
    }
    _present.add(from);
    _setParticipantState(from, ParticipantConnectionState.connecting);
    // The accept carries the sender's current mute state — without it a
    // joiner renders everyone unmuted until their next toggle.
    final muted = msg.payload['muted'];
    if (muted is bool) {
      final cur = _roster[from];
      if (cur != null) _roster[from] = cur.copyWith(isMuted: muted);
    }
    await _populateDisplayNames();
    await _storage.saveVoiceRoomParticipant(
      _callId!,
      from,
      displayName: await _displayName(from),
      joinedAt: _clock.nowUnixSeconds(),
    );
    if (firstSight) {
      final sessionHex = _sessionKey != null ? _hex(_sessionKey!) : '';
      await _safeSend(from, SignalingMessageType.roomAccept, room.id, {
        'session_key': sessionHex,
        'muted': _localMuted,
      });
    }
    await _maybeOffer(from);
    _emitState();
  }

  void _onDecline(String from, SignalingMessage msg) {
    if (_room == null || msg.roomId != _room!.id) return;
    // Peers send busy/full reasons and expiry sends 'timeout' — surface the
    // honest label instead of collapsing everything to "unreachable".
    final reason = switch (msg.payload['reason']) {
      'busy' => ParticipantEndReason.busy,
      'full' => ParticipantEndReason.roomFull,
      'timeout' => ParticipantEndReason.noAnswer,
      _ => ParticipantEndReason.declined,
    };
    _setParticipantState(
      from,
      ParticipantConnectionState.disconnected,
      endReason: reason,
    );
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
    // A close can also retire a pending (still-ringing) invite: the creator
    // ended the call before we answered, or our late accept bounced off a
    // dead room. The sheet shows "This call has ended." — and the ring we
    // never answered is a missed call.
    final pending = _pendingInvites[msg.roomId];
    if (pending != null && from == pending.invite.creatorPubkey) {
      _pendingInvites.remove(msg.roomId);
      _inviteRetiredCtrl.add(msg.roomId);
      await _recordMissedInvite(pending, msg.roomId);
      return;
    }
    final room = _room;
    if (room == null || msg.roomId != room.id) return;
    if (from != room.creatorPubkey) return;
    await _endSession(reason: RoomEndReason.closedByCreator);
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
      // The engine reports the local mic under the reserved self key (it
      // doesn't know our pubkey) — translate it so the self tile lights up.
      final level = pubkey == _localPubkey
          ? levels[kSelfAudioLevelKey]
          : levels[pubkey];
      final speaking = (level ?? 0) > speakingThreshold;
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
      final ok = await _safeSend(
        peer,
        SignalingMessageType.offer,
        _room!.id,
        offer,
      );
      if (!ok) {
        _offeredTo.remove(peer);
        _setParticipantState(
          peer,
          ParticipantConnectionState.disconnected,
          endReason: ParticipantEndReason.unreachable,
        );
        _emitState();
      }
    } catch (_) {
      _offeredTo.remove(peer);
      _setParticipantState(
        peer,
        ParticipantConnectionState.disconnected,
        endReason: ParticipantEndReason.unreachable,
      );
      _emitState();
    }
  }

  /// The engine performed an ICE restart for [peer] and needs a fresh
  /// offer/answer exchange. Only the offerer side acts; the answerer's
  /// restart rides on the offerer's re-offer.
  Future<void> _onRenegotiationNeeded(String peer) async {
    if (_room == null || !_present.contains(peer)) return;
    final me = await _requireLocalPubkey();
    if (me.compareTo(peer) >= 0) return;
    _offeredTo.remove(peer);
    await _maybeOffer(peer);
  }

  Future<void> _endSession({RoomEndReason reason = RoomEndReason.left}) async {
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
    if (!_roomEndedCtrl.isClosed) _roomEndedCtrl.add(reason);
  }

  void _resetSession() {
    _roster.clear();
    _present.clear();
    _offeredTo.clear();
    _connectingSince.clear();
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

  /// Single write path for participant connection state. Maintains the
  /// sweep's `connecting` deadline stamp, and the end reason: entering any
  /// non-disconnected state clears it (a retry wipes "No answer"); entering
  /// disconnected sets [endReason] when given, else preserves what's there
  /// (an engine-level drop must not erase a known "Declined").
  void _setParticipantState(
    String pubkey,
    ParticipantConnectionState st, {
    ParticipantEndReason? endReason,
  }) {
    final cur = _roster[pubkey];
    final disconnected = st == ParticipantConnectionState.disconnected;
    _roster[pubkey] = cur == null
        ? VoiceParticipant(
            pubkey: pubkey,
            connectionState: st,
            endReason: disconnected ? endReason : null,
          )
        : cur.copyWith(
            connectionState: st,
            endReason: endReason,
            clearEndReason: !disconnected,
          );
    if (st == ParticipantConnectionState.connecting) {
      _connectingSince[pubkey] = _clock.nowUnixSeconds();
    } else {
      _connectingSince.remove(pubkey);
    }
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

  /// Per-session display-name cache (null cached too, so a friend with no
  /// synced profile isn't re-read on every event).
  final Map<String, String?> _displayNames = {};

  /// Resolve [pubkey]'s display name from their latest synced kind=2
  /// profile. Strictly local — a wire-carried name would be spoofable, and
  /// invites only come from mutual follows whose profiles sync with their
  /// feed anyway.
  Future<String?> _displayName(String pubkey) async {
    if (_displayNames.containsKey(pubkey)) return _displayNames[pubkey];
    String? name;
    try {
      final event = await _storage.getLatestProfile(pubkey);
      if (event != null) {
        final n = decodeProfileContent(event.content)?.name.trim();
        if (n != null && n.isNotEmpty) name = n;
      }
    } catch (_) {
      name = null;
    }
    return _displayNames[pubkey] = name;
  }

  /// Fill in roster display names from local profiles (cached, so repeat
  /// calls are cheap). Skips self — the tile renders "You".
  Future<void> _populateDisplayNames() async {
    for (final p in _roster.keys.toList()) {
      if (p == _localPubkey) continue;
      final name = await _displayName(p);
      if (name == null) continue;
      final cur = _roster[p];
      if (cur != null && cur.displayName != name) {
        _roster[p] = cur.copyWith(displayName: name);
      }
    }
  }

  bool _sessionKeyMatches(Object? got) {
    final key = _sessionKey;
    if (key == null) return true; // no session key in play
    return got is String && got == _hex(key);
  }

  /// Sends without throwing; returns false on failure. Callers for whom a
  /// failed send is meaningful (invites, offers, retry nudges — "we KNOW
  /// the peer is unreachable") check the result and flag the participant
  /// immediately; fire-and-forget traffic (ICE, mute, leave/close) ignores
  /// it.
  Future<bool> _safeSend(
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
      return true;
    } catch (_) {
      return false;
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
    required this.receivedAt,
    this.callId,
  });
  final VoiceRoom invite;
  final List<String> roster;
  final String? sessionKeyHex;

  /// Unix seconds at (re-)receipt — the TTL deadline for the sweep. A
  /// retry ping for the same room refreshes it.
  final int receivedAt;

  /// Plan 17: distinct per-call history id for a chatroom call (null for a
  /// Plan 16 direct call, where the history keys on the roomId).
  final String? callId;

  _PendingInvite copyWith({int? receivedAt}) => _PendingInvite(
    invite: invite,
    roster: roster,
    sessionKeyHex: sessionKeyHex,
    receivedAt: receivedAt ?? this.receivedAt,
    callId: callId,
  );
}
