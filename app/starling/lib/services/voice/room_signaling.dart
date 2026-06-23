import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../../models/connection_card.dart';
import '../../models/signaling_message.dart';
import '../clock.dart';
import '../crypto_service.dart';
import '../signaling/signaling_dispatcher.dart';
import '../signaling/signaling_envelope.dart';
import '../signaling_service.dart';
import '../types.dart';

/// One inbound voice [SignalingMessage] together with the channel it arrived
/// on. The channel is owned by [SignalingService] — consumers must NOT close
/// it (it is shared with the dispatcher and any other feature).
class VoiceSignal {
  const VoiceSignal({required this.channel, required this.message});
  final SignalingChannel channel;
  final SignalingMessage message;
}

/// The voice-room coordination layer that sits on top of the generic
/// [SignalingService] (Plan 16 §Phase A).
///
/// The substrate is strictly pairwise — a voice room of N participants is an
/// app-level fan-out over N pairwise channels. [RoomSignaling] owns:
///
///  * **Fan-out send** — re-seals a *fresh-timestamped* copy of a
///    [SignalingMessage] per recipient (the ±30s replay window in
///    [unwrapSignalingMessage] forbids reusing a sealed frame), and delivers
///    each over that peer's channel.
///  * **Unified inbound** — voice messages arrive on two paths: inbound
///    channels routed by the [SignalingDispatcher] (already unwrapped) and
///    outbound channels we opened via [SignalingService.connect] (raw bytes
///    we unwrap here). Both feed [inbound] after a dedup pass keyed on the
///    [SignalingMessage] equality tuple, so the double path is harmless.
///  * **Reconnect** — sends always route through [SignalingService.connect],
///    which returns a pooled open channel or dials a fresh one.
class RoomSignaling {
  RoomSignaling({
    required SignalingService signaling,
    required SignalingDispatcher dispatcher,
    required CryptoService crypto,
    required Clock clock,
    required Future<String?> Function() localPubkeyLookup,
    required Future<Uint8List?> Function() localSecretKeyLookup,
  })  : _signaling = signaling,
        _dispatcher = dispatcher,
        _crypto = crypto,
        _clock = clock,
        _localPubkeyLookup = localPubkeyLookup,
        _localSecretKeyLookup = localSecretKeyLookup;

  final SignalingService _signaling;
  final SignalingDispatcher _dispatcher;
  final CryptoService _crypto;
  final Clock _clock;
  final Future<String?> Function() _localPubkeyLookup;
  final Future<Uint8List?> Function() _localSecretKeyLookup;

  final _controller = StreamController<VoiceSignal>.broadcast();

  /// Channels we opened (outbound) and subscribe to directly. Inbound
  /// channels are handled by the dispatcher, so they are intentionally NOT
  /// here — keyed by channel identity.
  final Map<SignalingChannel, StreamSubscription<Uint8List>> _attached = {};

  /// Recently-seen message keys for cross-path dedup. Bounded FIFO.
  final LinkedHashSet<String> _seen = LinkedHashSet<String>();
  static const int _seenCap = 512;

  bool _started = false;

  /// All inbound voice signaling messages (every type except
  /// `libp2pConnect`), deduped across the inbound/outbound paths.
  Stream<VoiceSignal> get inbound => _controller.stream;

  /// Idempotent. Registers with the dispatcher so inbound voice messages are
  /// routed here.
  void start() {
    if (_started) return;
    _started = true;
    _dispatcher.registerVoiceHandler(_onDispatched);
  }

  /// Seal [payload] as a [type] message for [roomId] and send it to a single
  /// recipient. Throws [StateError] (from [SignalingService.connect]) if the
  /// peer has no reachable LAN/Tor transport right now.
  Future<void> sendTo(
    String recipientPubkey, {
    required SignalingMessageType type,
    required String roomId,
    required Map<String, dynamic> payload,
  }) async {
    final channel = await _signaling.connect(_cardFor(recipientPubkey));
    _attach(channel);
    await _sealAndSend(channel, recipientPubkey, type, roomId, payload);
  }

  /// Fan a message out to every recipient. [payloadFor] supplies a
  /// per-recipient payload (e.g. the room session key sealed to each peer);
  /// when null, [payload] is sent to everyone. Per-recipient failures are
  /// collected and rethrown as a list so the caller can mark only the
  /// unreachable participants.
  Future<void> fanOut(
    List<String> recipientPubkeys, {
    required SignalingMessageType type,
    required String roomId,
    Map<String, dynamic>? payload,
    Map<String, dynamic> Function(String pubkey)? payloadFor,
  }) async {
    assert(payload != null || payloadFor != null,
        'fanOut needs either payload or payloadFor');
    final failures = <String, Object>{};
    await Future.wait(recipientPubkeys.map((pubkey) async {
      try {
        await sendTo(
          pubkey,
          type: type,
          roomId: roomId,
          payload: payloadFor?.call(pubkey) ?? payload!,
        );
      } catch (e) {
        failures[pubkey] = e;
      }
    }));
    if (failures.isNotEmpty) {
      throw FanOutException(failures);
    }
  }

  Future<void> stop() async {
    _dispatcher.unregisterVoiceHandler(_onDispatched);
    for (final sub in _attached.values) {
      await sub.cancel();
    }
    _attached.clear();
    _seen.clear();
    _started = false;
  }

  // --- internals ---

  ConnectionCard _cardFor(String pubkey) => ConnectionCard.fromMap({
        // `connect` only needs the pubkey: a pooled open channel short-circuits
        // before endpoint resolution, and otherwise the reachability monitor
        // (not these endpoints) resolves a transport. Mirrors Libp2pUpgrader.
        'pubkey': pubkey,
        'endpoints': const [],
        'capabilities': const [],
      });

  Future<void> _sealAndSend(
    SignalingChannel channel,
    String recipientPubkey,
    SignalingMessageType type,
    String roomId,
    Map<String, dynamic> payload,
  ) async {
    final localPubkey = await _localPubkeyLookup();
    final localSecretKey = await _localSecretKeyLookup();
    if (localPubkey == null || localPubkey.isEmpty || localSecretKey == null) {
      throw StateError('room_signaling: identity not ready');
    }
    final message = SignalingMessage(
      type: type,
      roomId: roomId,
      senderPubkey: localPubkey,
      timestamp: _clock.nowUnixSeconds(),
      payload: payload,
    );
    final envelope = wrapSignalingMessage(
      crypto: _crypto,
      message: message,
      myPubkey: localPubkey,
      mySecretKey: localSecretKey,
      recipientPubkey: recipientPubkey,
    );
    await channel.send(envelope);
  }

  void _attach(SignalingChannel channel) {
    if (_attached.containsKey(channel)) return;
    final sub = channel.messages.listen(
      (bytes) => unawaited(_ingestRaw(channel, bytes)),
      onDone: () {
        _attached.remove(channel)?.cancel();
      },
      onError: (Object _) {},
    );
    _attached[channel] = sub;
  }

  Future<void> _ingestRaw(SignalingChannel channel, Uint8List bytes) async {
    final localPubkey = await _localPubkeyLookup();
    final localSecretKey = await _localSecretKeyLookup();
    if (localPubkey == null || localPubkey.isEmpty || localSecretKey == null) {
      return;
    }
    final SignalingMessage msg;
    try {
      msg = unwrapSignalingMessage(
        crypto: _crypto,
        envelopeBytes: bytes,
        myPubkey: localPubkey,
        mySecretKey: localSecretKey,
      );
    } on SignalingEnvelopeException {
      return;
    } catch (_) {
      return;
    }
    _emit(channel, msg);
  }

  /// Called by [SignalingDispatcher] for inbound voice messages (already
  /// unwrapped).
  void _onDispatched(SignalingChannel channel, SignalingMessage msg) =>
      _emit(channel, msg);

  void _emit(SignalingChannel channel, SignalingMessage msg) {
    if (msg.type == SignalingMessageType.libp2pConnect) return;
    final key = '${msg.type.value}|${msg.roomId}|${msg.senderPubkey}'
        '|${msg.timestamp}';
    if (!_markSeen(key)) return;
    if (_controller.isClosed) return;
    _controller.add(VoiceSignal(channel: channel, message: msg));
  }

  bool _markSeen(String key) {
    if (_seen.contains(key)) return false;
    _seen.add(key);
    if (_seen.length > _seenCap) {
      _seen.remove(_seen.first);
    }
    return true;
  }
}

/// Thrown by [RoomSignaling.fanOut] when one or more recipients could not be
/// reached. [failures] maps the unreachable pubkey to the underlying error.
class FanOutException implements Exception {
  FanOutException(this.failures);
  final Map<String, Object> failures;
  @override
  String toString() =>
      'FanOutException(${failures.length} unreachable: ${failures.keys})';
}
