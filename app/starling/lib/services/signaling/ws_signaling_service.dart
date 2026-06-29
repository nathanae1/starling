import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/io.dart';

import '../../models/models.dart';
import '../../server/handlers/signaling_handler.dart';
import '../crypto_service.dart';
import '../signaling_service.dart';
import '../types.dart';

/// Lazy lookup that returns the currently best-validated [PeerConnection]
/// for the given pubkey, or null if no transport is reachable. Backed by
/// `PeerConnectionFactory.resolve` in production. Kept as a closure so the
/// service can be constructed in `main.dart` before the
/// `ProviderContainer` exists.
typedef PeerConnectionLookup = Future<PeerConnection?> Function(String pubkey);

/// WebSocket-based [SignalingService] implementation.
///
/// Outbound connections: opens a WebSocket to the peer's `/ws/signal`
/// endpoint (resolved via [PeerConnectionLookup]) with Ed25519 auth
/// headers. Signaling intentionally rides HTTP-style transports (LAN or
/// Tor) — libp2p is *bootstrapped by* signaling, not used *for* signaling.
///
/// Inbound connections: handled by [signalingHandler] on the shelf server,
/// which calls [handleInbound] for each authenticated connection.
class WsSignalingService implements SignalingService {
  WsSignalingService({
    required this.crypto,
    required PeerConnectionLookup peerFactory,
    required this.localPubkey,
    required this.localSecretKey,
  }) : _peerFactory = peerFactory;

  final CryptoService crypto;
  final PeerConnectionLookup _peerFactory;

  /// Our Ed25519 public key (Crockford-base32-encoded).
  final String localPubkey;

  /// Our 64-byte Ed25519 secret key (for signing auth headers).
  final Uint8List localSecretKey;

  final Map<String, SignalingChannel> _channels = {};
  void Function(SignalingChannel channel)? _inboundHandler;

  @override
  Future<SignalingChannel> connect(ConnectionCard peer) async {
    final existing = _channels[peer.pubkey];
    if (existing != null && existing.isOpen) return existing;

    final peerConn = await _peerFactory(peer.pubkey);
    if (peerConn == null) {
      throw StateError(
        'no reachable transport for ${peer.pubkey} — wait for the next '
        'reachability tick',
      );
    }
    if (peerConn.transport == PeerTransport.libp2pDirect) {
      // Signaling cannot ride libp2p — libp2p is established *by* signaling
      // via DCUtR. On the cold-initiator path this branch is rare; the next
      // reachability tick that surfaces a LAN or Tor candidate recovers.
      throw StateError(
        'signaling cannot ride libp2p_direct for ${peer.pubkey} — '
        'wait for next reachability tick',
      );
    }

    final httpUri = Uri.parse(peerConn.baseUrl);
    final wsScheme = httpUri.scheme == 'https' ? 'wss' : 'ws';
    final wsUri = httpUri.replace(scheme: wsScheme, path: '/ws/signal');

    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000)
        .toString();
    final message = 'websocket-upgrade$timestamp';
    final sig = crypto.sign(
      localSecretKey,
      Uint8List.fromList(utf8.encode(message)),
    );

    final webSocket = IOWebSocketChannel.connect(
      wsUri,
      headers: {
        'X-Starling-Pubkey': localPubkey,
        'X-Starling-Sig': base64.encode(sig),
        'X-Starling-Timestamp': timestamp,
      },
    );
    await webSocket.ready;

    final channel = WebSocketSignalingChannel(
      remotePubkey: peer.pubkey,
      transport: peerConn.transport,
      webSocket: webSocket,
    );

    _channels[peer.pubkey] = channel;
    channel.messages.listen(
      null,
      onDone: () {
        _channels.remove(peer.pubkey);
      },
    );

    return channel;
  }

  @override
  void onInboundConnection(void Function(SignalingChannel channel) handler) {
    _inboundHandler = handler;
  }

  /// Called by the server's signaling handler when an authenticated
  /// inbound WebSocket connection is established.
  void handleInbound(SignalingChannel channel) {
    _channels[channel.remotePubkey] = channel;

    channel.messages.listen(
      null,
      onDone: () {
        _channels.remove(channel.remotePubkey);
      },
    );

    _inboundHandler?.call(channel);
  }

  @override
  Future<void> closeAll() async {
    final channels = List<SignalingChannel>.from(_channels.values);
    _channels.clear();
    for (final channel in channels) {
      await channel.close();
    }
  }

  @override
  Map<String, SignalingChannel> get activeChannels =>
      Map.unmodifiable(_channels);
}
