import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../services/crypto_service.dart';
import '../../services/types.dart';

/// Creates a shelf [Handler] for the `/ws/signal` endpoint.
///
/// Authenticates the WebSocket upgrade request via Ed25519 signature,
/// then upgrades to WebSocket and invokes [onChannel] with the
/// authenticated [SignalingChannel].
///
/// Auth headers on the upgrade request:
/// - `X-Starling-Pubkey`: base64-encoded Ed25519 public key
/// - `X-Starling-Sig`: base64-encoded Ed25519 signature of
///   `"websocket-upgrade" + X-Starling-Timestamp`
/// - `X-Starling-Timestamp`: unix timestamp (rejected if >30s old)
Handler signalingHandler({
  required CryptoService crypto,
  required void Function(SignalingChannel channel) onChannel,
}) {
  return (Request request) {
    // --- Authenticate the upgrade request ---
    final pubkeyHeader = request.headers['x-starling-pubkey'];
    final sigHeader = request.headers['x-starling-sig'];
    final timestampHeader = request.headers['x-starling-timestamp'];

    if (pubkeyHeader == null || sigHeader == null || timestampHeader == null) {
      return Response(401, body: 'Missing auth headers');
    }

    final timestamp = int.tryParse(timestampHeader);
    if (timestamp == null) {
      return Response(401, body: 'Invalid timestamp');
    }

    // Reject timestamps older than 30 seconds (replay protection).
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if ((now - timestamp).abs() > 30) {
      return Response(401, body: 'Timestamp expired');
    }

    final Uint8List pubkeyBytes;
    final Uint8List sigBytes;
    try {
      pubkeyBytes = base64.decode(pubkeyHeader);
      sigBytes = base64.decode(sigHeader);
    } catch (e) {
      return Response(401, body: 'Invalid base64 encoding');
    }

    final message = 'websocket-upgrade$timestampHeader';
    final messageBytes = Uint8List.fromList(utf8.encode(message));

    if (!crypto.verify(pubkeyBytes, messageBytes, sigBytes)) {
      return Response(401, body: 'Invalid signature');
    }

    // --- Auth passed, upgrade to WebSocket ---
    // Create the WebSocket handler in this closure so it captures the
    // authenticated pubkey.
    final wsHandler = webSocketHandler((WebSocketChannel webSocket, _) {
      final channel = WebSocketSignalingChannel(
        remotePubkey: pubkeyHeader,
        transport: PeerTransport.lan,
        webSocket: webSocket,
      );
      onChannel(channel);
    });

    return wsHandler(request);
  };
}

/// [SignalingChannel] implementation backed by a [WebSocketChannel].
///
/// Used by both the server (inbound connections) and client (outbound
/// connections via [WsSignalingService]).
class WebSocketSignalingChannel implements SignalingChannel {
  WebSocketSignalingChannel({
    required this.remotePubkey,
    required this.transport,
    required WebSocketChannel webSocket,
  }) : _webSocket = webSocket {
    _subscription = _webSocket.stream.listen(
      (data) {
        if (data is List<int>) {
          _controller.add(Uint8List.fromList(data));
        }
      },
      onDone: () {
        _isOpen = false;
        _controller.close();
      },
      onError: (Object error) {
        _controller.addError(error);
      },
    );
  }

  final WebSocketChannel _webSocket;
  final _controller = StreamController<Uint8List>.broadcast();
  late final StreamSubscription<dynamic> _subscription;
  bool _isOpen = true;

  @override
  final String remotePubkey;

  @override
  final PeerTransport transport;

  @override
  Future<void> send(Uint8List data) async {
    if (!_isOpen) throw StateError('Channel is closed');
    _webSocket.sink.add(data);
  }

  @override
  Stream<Uint8List> get messages => _controller.stream;

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> close() async {
    if (!_isOpen) return;
    _isOpen = false;
    await _subscription.cancel();
    await _webSocket.sink.close();
    await _controller.close();
  }
}
