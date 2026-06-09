import 'dart:typed_data';

import '../../models/models.dart';
import '../network_service.dart';
import '../types.dart';

/// No-op NetworkService for testing without real network access.
class MockNetworkService implements NetworkService {
  @override
  Future<Map<String, LanPeer>> discoverLanPeers() async => {};

  @override
  Future<void> registerMdns(String pubkey, int port) async {}

  @override
  Future<void> deregisterMdns() async {}

  @override
  Future<PeerConnection> connectToPeer(ConnectionCard connectionCard) async =>
      PeerConnection(
        pubkey: connectionCard.pubkey,
        baseUrl: 'http://mock:0',
        transport: PeerTransport.lan,
      );

  @override
  Future<Manifest> fetchManifest(
    PeerConnection connection, {
    int? since,
    int? until,
    String? requesterPubkey,
    int? ackRotationAt,
    int? cardSeenAt,
  }) async =>
      Manifest(
        pubkey: connection.pubkey,
        events: [],
        hasOlder: false,
      );

  @override
  Future<List<EncryptedEvent>> fetchEvents(
    PeerConnection connection, {
    int? since,
  }) async =>
      [];

  @override
  Future<Uint8List> fetchMedia(
    PeerConnection connection,
    String hash,
  ) async =>
      Uint8List(0);

  @override
  Future<void> sendFollowRequest(
    PeerConnection connection,
    Uint8List requestPayload,
  ) async {}

  @override
  Future<void> sendFollowAccept(
    PeerConnection connection,
    Uint8List acceptPayload,
  ) async {}
}
