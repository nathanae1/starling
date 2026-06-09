import 'dart:typed_data';

import '../models/models.dart';
import 'types.dart';

/// Abstract interface for peer discovery and communication.
///
/// Implemented in Plan 09 (LAN) and Plan 11 (Tor).
/// Mock implementation returns empty/simulated results.
abstract class NetworkService {
  // --- LAN discovery ---

  Future<Map<String, LanPeer>> discoverLanPeers();

  Future<void> registerMdns(String pubkey, int port);

  Future<void> deregisterMdns();

  // --- Peer connections ---

  Future<PeerConnection> connectToPeer(ConnectionCard connectionCard);

  // --- Sync operations ---

  Future<Manifest> fetchManifest(
    PeerConnection connection, {
    int? since,
    int? until,
    String? requesterPubkey,
    int? ackRotationAt,
    int? cardSeenAt,
  });

  Future<List<EncryptedEvent>> fetchEvents(
    PeerConnection connection, {
    int? since,
  });

  Future<Uint8List> fetchMedia(PeerConnection connection, String hash);

  // --- Follow operations ---

  Future<void> sendFollowRequest(
    PeerConnection connection,
    Uint8List requestPayload,
  );

  Future<void> sendFollowAccept(
    PeerConnection connection,
    Uint8List acceptPayload,
  );
}
