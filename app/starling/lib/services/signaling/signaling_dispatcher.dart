import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import '../../models/signaling_message.dart';
import '../../services/types.dart';
import '../../sync/libp2p_upgrader.dart';
import '../crypto_service.dart';
import '../signaling_service.dart';
import 'signaling_envelope.dart';

/// Handler for inbound voice-room signaling messages (Plan 16). Registered
/// by `RoomSignaling.start`; receives every voice [SignalingMessageType] on
/// the channel it arrived on, already decrypted.
typedef VoiceSignalingHandler = void Function(
  SignalingChannel channel,
  SignalingMessage message,
);

/// Single owner of [SignalingService.onInboundConnection]. Listens to each
/// authenticated channel, decrypts incoming [EphemeralEncryptedEvent]
/// envelopes, and routes the inner [SignalingMessage] by type.
/// [SignalingMessageType.libp2pConnect] is dispatched to
/// [Libp2pUpgrader.handleInboundLibp2pConnect]; every voice type is routed to
/// the registered [VoiceSignalingHandler] (Plan 16 voice rooms).
///
/// The identity + secret key are looked up via the provided closures on
/// every inbound message — see `[[project_target_users]]`-style note:
/// onboarding can complete after the dispatcher starts, so we can't
/// pre-cache the secret at start().
class SignalingDispatcher {
  SignalingDispatcher({
    required SignalingService signaling,
    Libp2pUpgrader? upgrader,
    required CryptoService crypto,
    required Future<String?> Function() localPubkeyLookup,
    required Future<Uint8List?> Function() localSecretKeyLookup,
  })  : _signaling = signaling,
        _upgrader = upgrader,
        _crypto = crypto,
        _localPubkeyLookup = localPubkeyLookup,
        _localSecretKeyLookup = localSecretKeyLookup;

  final SignalingService _signaling;
  final Libp2pUpgrader? _upgrader;
  final CryptoService _crypto;
  final Future<String?> Function() _localPubkeyLookup;
  final Future<Uint8List?> Function() _localSecretKeyLookup;

  bool _started = false;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  VoiceSignalingHandler? _voiceHandler;

  /// Register the single consumer of inbound voice-room messages. Replacing
  /// an existing handler is allowed (idempotent re-registration).
  void registerVoiceHandler(VoiceSignalingHandler handler) {
    _voiceHandler = handler;
  }

  /// Remove [handler] if it is the currently-registered voice handler.
  void unregisterVoiceHandler(VoiceSignalingHandler handler) {
    if (identical(_voiceHandler, handler)) _voiceHandler = null;
  }

  /// Idempotent. Registers the dispatcher as the single inbound-channel
  /// consumer.
  void start() {
    if (_started) return;
    _started = true;
    _signaling.onInboundConnection((channel) {
      final sub = channel.messages.listen((bytes) {
        // Per-message handling is async — but we don't await the future
        // because Stream.listen never propagates errors out of an async
        // callback and we want concurrent envelopes to interleave freely.
        unawaited(_handleMessage(channel, bytes));
      });
      _subscriptions.add(sub);
    });
  }

  Future<void> _handleMessage(
    SignalingChannel channel,
    Uint8List bytes,
  ) async {
    final localPubkey = await _localPubkeyLookup();
    final localSecretKey = await _localSecretKeyLookup();
    if (localPubkey == null ||
        localPubkey.isEmpty ||
        localSecretKey == null) {
      developer.log(
        'signaling_dispatcher: identity not ready, dropping inbound bytes',
        name: 'signaling_dispatcher',
      );
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
    } on SignalingEnvelopeException catch (e) {
      developer.log(
        'signaling_dispatcher: dropped malformed envelope: $e',
        name: 'signaling_dispatcher',
      );
      return;
    } catch (e) {
      developer.log(
        'signaling_dispatcher: unexpected unwrap failure: $e',
        name: 'signaling_dispatcher',
      );
      return;
    }

    switch (msg.type) {
      case SignalingMessageType.libp2pConnect:
        _upgrader?.handleInboundLibp2pConnect(channel, msg);
      case SignalingMessageType.roomInvite:
      case SignalingMessageType.roomAccept:
      case SignalingMessageType.roomDecline:
      case SignalingMessageType.roomLeave:
      case SignalingMessageType.roomClose:
      case SignalingMessageType.offer:
      case SignalingMessageType.answer:
      case SignalingMessageType.iceCandidate:
      case SignalingMessageType.muteStatus:
      case SignalingMessageType.speakingStatus:
        final handler = _voiceHandler;
        if (handler != null) {
          handler(channel, msg);
        } else {
          developer.log(
            'signaling_dispatcher: no voice handler registered, dropping '
            '${msg.type.value}',
            name: 'signaling_dispatcher',
          );
        }
    }
  }

  Future<void> stop() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _started = false;
  }
}
