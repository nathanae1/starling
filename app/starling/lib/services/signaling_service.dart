import '../models/models.dart';
import 'types.dart';

/// Abstract interface for real-time signaling between peers.
///
/// Provides persistent bidirectional channels (WebSocket) for exchanging
/// time-sensitive messages: room invites, SDP offers/answers, ICE candidates,
/// and room lifecycle events.
///
/// Signaling channels are distinct from the feed sync protocol. Feed sync
/// is pull-based HTTP; signaling is push-based WebSocket. Signaling messages
/// are ephemeral (never stored) and encrypted per-recipient with the pairwise
/// signaling key from `CryptoService.deriveSignalingKey` (8-byte KDF ctx
/// `'starsig0'`, pubkeys lexicographically sorted so both peers agree).
///
/// This service is generic enough for future real-time features (DMs, typing
/// indicators) beyond voice rooms.
///
/// Default implementation uses WebSocket on the shelf server (Plan 16).
/// Mock implementation provides in-memory channels for testing.
abstract class SignalingService {
  /// Open a persistent signaling channel to a remote peer.
  ///
  /// Connects to the peer's `/ws/signal` endpoint via LAN or Tor.
  /// The WebSocket upgrade includes Ed25519 auth headers.
  /// Returns a [SignalingChannel] for bidirectional messaging.
  Future<SignalingChannel> connect(ConnectionCard peer);

  /// Register a handler for inbound signaling connections on our server.
  ///
  /// Called once during server setup. When a remote peer connects to our
  /// `/ws/signal` endpoint, the handler is invoked with the authenticated
  /// channel.
  void onInboundConnection(void Function(SignalingChannel channel) handler);

  /// Close all active signaling channels (inbound and outbound).
  Future<void> closeAll();

  /// All currently open signaling channels, keyed by remote pubkey.
  Map<String, SignalingChannel> get activeChannels;
}
