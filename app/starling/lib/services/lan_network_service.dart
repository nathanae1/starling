import 'dart:async';
import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import '../sync/manifest_ack.dart' show hexEncodeAckSig;
import '../sync/manifest_codec.dart';
import '../sync/sync_engine.dart' show SyncTransport;
import 'mdns_service.dart';
import 'network_service.dart';
import 'types.dart';

/// HTTP-based `NetworkService` + `SyncTransport`. Used for LAN sync
/// (Plan 09) and, with a [TorHttpClient] swapped in for [httpClient],
/// for Tor sync (Plan 11b). Plan 15 will add a relay tier.
///
/// The class is transport-agnostic at the wire level: the difference
/// between LAN and Tor is just which `http.Client` does the dialing.
/// `TransportRouter` (in `sync/transport_router.dart`) picks the right
/// instance per [PeerConnection.transport].
class LanNetworkService implements NetworkService, SyncTransport {
  LanNetworkService({
    required MdnsService mdns,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 10),
  })  : _mdns = mdns,
        _http = httpClient ?? http.Client(),
        _timeout = timeout;

  final MdnsService _mdns;
  final http.Client _http;
  final Duration _timeout;

  // --- Discovery ---

  @override
  Future<Map<String, LanPeer>> discoverLanPeers() async => _mdns.currentPeers();

  @override
  Future<void> registerMdns(String pubkey, int port) =>
      _mdns.register(pubkey: pubkey, port: port);

  @override
  Future<void> deregisterMdns() => _mdns.deregister();

  // --- Peer connections ---

  @override
  Future<PeerConnection> connectToPeer(ConnectionCard connectionCard) async {
    // The connection card is the handshake-time contact card. For LAN sync
    // the live peer cache is authoritative, not the card. Higher layers
    // (Plan 11/15) will pick onion / relay endpoints from the card here.
    throw UnimplementedError(
      'LanNetworkService.connectToPeer is not used by Plan 09 sync — '
      'callers should resolve a LanPeer via the discovery cache and build '
      'a PeerConnection directly. See PeerConnectionFactory.',
    );
  }

  // --- Sync HTTP fetches ---

  @override
  Future<Manifest> fetchManifest(
    PeerConnection connection, {
    int? since,
    int? until,
    String? untilId,
    String? requesterPubkey,
    int? ackRotationAt,
    int? cardSeenAt,
    Uint8List? ackSig,
  }) async {
    final query = <String, String>{};
    if (since != null) query['since'] = since.toString();
    if (until != null) query['until'] = until.toString();
    // Paging cursor, not identity — sent on every transport (incl. relay).
    if (until != null && untilId != null) query['until_id'] = untilId;
    // S7: never identify ourselves to a relay. The relay ignores these
    // params (it holds no per-follower state), but sending them would hand
    // the relay operator each follower's pubkey + poll cadence — exactly
    // the access-pattern leak the relay tier is designed to avoid. Direct
    // peer connections (lan/tor/libp2p) keep them: the peer needs them to
    // attach pending deliveries and honor acks.
    if (connection.transport != PeerTransport.relay) {
      if (requesterPubkey != null) {
        query['requester_pubkey'] = requesterPubkey;
      }
      if (ackRotationAt != null && ackRotationAt > 0) {
        query['ack_rotation_at'] = ackRotationAt.toString();
      }
      if (cardSeenAt != null && cardSeenAt > 0) {
        query['card_seen_at'] = cardSeenAt.toString();
      }
      if (ackSig != null) {
        query['ack_sig'] = hexEncodeAckSig(ackSig);
      }
    }
    final uri = Uri.parse('${connection.baseUrl}/manifest')
        .replace(queryParameters: query.isEmpty ? null : query);
    final res = await _http.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw NetworkException(
        'manifest fetch failed: ${res.statusCode}',
        connection.pubkey,
        statusCode: res.statusCode,
      );
    }
    final decoded = cbor.decode(res.bodyBytes);
    if (decoded is! Map) {
      throw NetworkException('manifest body not a CBOR map', connection.pubkey);
    }
    return parseManifestResponse(decoded, toBytes: _toBytes);
  }

  Uint8List _toBytes(dynamic value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    throw NetworkException(
      'expected bytes in manifest payload, got ${value.runtimeType}',
      '',
    );
  }

  @override
  Future<List<EncryptedEvent>> fetchEvents(
    PeerConnection connection, {
    int? since,
  }) async {
    final query = <String, String>{};
    if (since != null) query['since'] = since.toString();
    final uri = Uri.parse('${connection.baseUrl}/events')
        .replace(queryParameters: query.isEmpty ? null : query);
    final res = await _http.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw NetworkException(
        'events fetch failed: ${res.statusCode}',
        connection.pubkey,
        statusCode: res.statusCode,
      );
    }
    final envelope = Envelope.fromBytes(res.bodyBytes);
    final out = <EncryptedEvent>[];
    for (final item in envelope.items) {
      if (item.type == 'event') {
        out.add(EncryptedEvent.fromBytes(item.payload));
      }
      // Unknown item types are ignored at this layer; the sync engine
      // pulls them from the envelope directly via fetchEnvelope().
    }
    return out;
  }

  /// Variant of [fetchEvents] that returns the raw `Envelope` so callers
  /// can route unknown item types into opaque storage. This is the entry
  /// point used by the sync engine via [SyncTransport].
  @override
  Future<Envelope> fetchEnvelope(
    PeerConnection connection, {
    int? since,
  }) async {
    final query = <String, String>{};
    if (since != null) query['since'] = since.toString();
    final uri = Uri.parse('${connection.baseUrl}/events')
        .replace(queryParameters: query.isEmpty ? null : query);
    final res = await _http.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw NetworkException(
        'events fetch failed: ${res.statusCode}',
        connection.pubkey,
        statusCode: res.statusCode,
      );
    }
    return Envelope.fromBytes(res.bodyBytes);
  }

  @override
  Future<Uint8List> fetchMedia(PeerConnection connection, String hash) async {
    final uri = Uri.parse('${connection.baseUrl}/media/$hash');
    final res = await _http.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw NetworkException(
        'media fetch failed: ${res.statusCode}',
        connection.pubkey,
        statusCode: res.statusCode,
      );
    }
    return res.bodyBytes;
  }

  // --- Follow operations (Plan 08 wiring runs through FollowService directly,
  // but Plan 11+ will call these from the relay/Tor tier). ---

  @override
  Future<void> sendFollowRequest(
    PeerConnection connection,
    Uint8List requestPayload,
  ) async {
    final uri = Uri.parse('${connection.baseUrl}/follow-request');
    final res = await _http
        .post(uri, headers: const {'content-type': 'application/cbor'},
            body: requestPayload)
        .timeout(_timeout);
    if (res.statusCode != 202) {
      throw NetworkException(
        'follow-request failed: ${res.statusCode}',
        connection.pubkey,
        statusCode: res.statusCode,
      );
    }
  }

  @override
  Future<void> sendFollowAccept(
    PeerConnection connection,
    Uint8List acceptPayload,
  ) async {
    final uri = Uri.parse('${connection.baseUrl}/follow-accept');
    final res = await _http
        .post(uri, headers: const {'content-type': 'application/cbor'},
            body: acceptPayload)
        .timeout(_timeout);
    if (res.statusCode != 202) {
      throw NetworkException(
        'follow-accept failed: ${res.statusCode}',
        connection.pubkey,
        statusCode: res.statusCode,
      );
    }
  }

  // --- Push: peer-to-peer envelope (Plan 10). Owner→relay push lives in
  //     RelayPushService, which keeps the owner key out of this transport. ---

  @override
  Future<void> pushEnvelope(
    PeerConnection connection,
    Envelope envelope,
  ) async {
    final uri = Uri.parse('${connection.baseUrl}/events');
    final res = await _http
        .post(
          uri,
          headers: const {'content-type': 'application/cbor'},
          body: envelope.toBytes(),
        )
        .timeout(_timeout);
    if (res.statusCode != 202) {
      throw NetworkException(
        'pushEnvelope failed: ${res.statusCode}',
        connection.pubkey,
        statusCode: res.statusCode,
      );
    }
  }

  /// Closes the underlying HTTP client. Tests should call this in tearDown
  /// when the service was constructed without an injected client.
  void close() => _http.close();
}

class NetworkException implements Exception {
  const NetworkException(this.message, this.peerPubkey, {this.statusCode});
  final String message;
  final String peerPubkey;

  /// HTTP status when the peer answered with an error, null for
  /// transport-level failures (no response). Callers use this to tell
  /// "the peer rejected it" (4xx — retrying won't help) from "it never
  /// arrived" (retry when connectivity returns).
  final int? statusCode;

  @override
  String toString() => 'NetworkException($peerPubkey): $message';
}
