import 'dart:async';
import 'dart:typed_data';

import '../../models/models.dart';
import '../signaling_service.dart';
import '../types.dart';

/// In-memory mock [SignalingService] for testing without real WebSockets.
///
/// Two usage modes:
///  * **Capture-only** (default): [connect] returns a channel whose [send]
///    records into `sentMessages`; tests drive inbound traffic explicitly via
///    [simulateInbound] / [MockSignalingChannel.simulateReceive].
///  * **Loopback**: [link] two services together (by [localPubkey]); then a
///    [send] on one side is delivered to the paired channel's [messages]
///    stream on the other side, firing that side's `onInboundConnection`
///    handler. Lets a full two-peer voice flow run end-to-end in a unit test.
class MockSignalingService implements SignalingService {
  MockSignalingService({this.localPubkey = ''});

  /// This service's own Ed25519 pubkey — used to address loopback peers.
  final String localPubkey;

  final Map<String, SignalingChannel> _channels = {};
  final Map<String, MockSignalingService> _peers = {};
  void Function(SignalingChannel channel)? _inboundHandler;

  /// Wire two services for loopback delivery (symmetric).
  void link(MockSignalingService other) {
    _peers[other.localPubkey] = other;
    other._peers[localPubkey] = this;
  }

  @override
  Future<SignalingChannel> connect(ConnectionCard peer) async {
    final existing = _channels[peer.pubkey];
    if (existing != null && existing.isOpen) return existing;

    final localChannel = MockSignalingChannel(
      remotePubkey: peer.pubkey,
      transport: PeerTransport.lan,
    );
    _channels[peer.pubkey] = localChannel;

    // Loopback: cross-link with the peer service's inbound channel for us,
    // creating + announcing it on first contact.
    final peerService = _peers[peer.pubkey];
    if (peerService != null) {
      var remoteChannel = peerService._channels[localPubkey];
      if (remoteChannel is! MockSignalingChannel || !remoteChannel.isOpen) {
        remoteChannel = MockSignalingChannel(
          remotePubkey: localPubkey,
          transport: PeerTransport.lan,
        );
        peerService._channels[localPubkey] = remoteChannel;
        peerService._inboundHandler?.call(remoteChannel);
      }
      localChannel._peer = remoteChannel;
      remoteChannel._peer = localChannel;
    }
    return localChannel;
  }

  @override
  void onInboundConnection(void Function(SignalingChannel channel) handler) {
    _inboundHandler = handler;
  }

  @override
  Future<void> closeAll() async {
    for (final channel in _channels.values) {
      await channel.close();
    }
    _channels.clear();
  }

  @override
  Map<String, SignalingChannel> get activeChannels =>
      Map.unmodifiable(_channels);

  /// Simulate an inbound connection from a remote peer.
  /// Returns the channel so tests can send messages through it.
  MockSignalingChannel simulateInbound(String remotePubkey) {
    final channel = MockSignalingChannel(
      remotePubkey: remotePubkey,
      transport: PeerTransport.lan,
    );
    _channels[remotePubkey] = channel;
    _inboundHandler?.call(channel);
    return channel;
  }
}

/// In-memory signaling channel for testing.
class MockSignalingChannel implements SignalingChannel {
  MockSignalingChannel({required this.remotePubkey, required this.transport});

  @override
  final String remotePubkey;

  @override
  final PeerTransport transport;

  final _controller = StreamController<Uint8List>.broadcast();
  bool _isOpen = true;

  /// In loopback mode, the channel on the other service this one delivers to.
  MockSignalingChannel? _peer;

  @override
  Future<void> send(Uint8List data) async {
    if (!_isOpen) throw StateError('Channel is closed');
    // Always capture for capture-only tests.
    _sentMessages.add(data);
    // In loopback mode, deliver to the linked channel's inbound stream.
    _peer?._deliver(data);
  }

  @override
  Stream<Uint8List> get messages => _controller.stream;

  @override
  bool get isOpen => _isOpen;

  @override
  Future<void> close() async {
    _isOpen = false;
    await _controller.close();
  }

  /// Messages sent via [send], for test assertions.
  final List<Uint8List> _sentMessages = [];
  List<Uint8List> get sentMessages => List.unmodifiable(_sentMessages);

  /// Simulate receiving a message from the remote peer.
  void simulateReceive(Uint8List data) {
    if (!_isOpen) throw StateError('Channel is closed');
    _controller.add(data);
  }

  void _deliver(Uint8List data) {
    if (!_isOpen || _controller.isClosed) return;
    _controller.add(data);
  }
}
