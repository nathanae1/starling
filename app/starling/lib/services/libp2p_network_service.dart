import 'dart:async';
import 'dart:typed_data';

import 'package:cbor/simple.dart';

import '../models/models.dart';
import '../sync/manifest_codec.dart';
import '../sync/sync_engine.dart' show SyncTransport;
import 'lan_network_service.dart' show NetworkException;
import 'libp2p/libp2p_service.dart';
import 'network_service.dart';
import 'types.dart';

/// libp2p-stream-based `NetworkService` + `SyncTransport`. Plan 11a — the
/// preferred direct-connect tier. Each public method opens a single libp2p
/// stream with the matching `/starling/sync/<route>/1` protocol, writes
/// one length-delimited CBOR request frame, reads one CBOR response frame,
/// and closes.
///
/// `connection.baseUrl` is a synthetic `libp2p://<peer-id>` string supplied
/// by [Libp2pUpgrader] when it called `markReachable` on the reachability
/// monitor; this service parses the peer-id out of the URL and hands it to
/// the bridge, which already holds the established connection.
///
/// All response payloads are byte-identical to the HTTP variants
/// ([LanNetworkService]) — same CBOR shapes for manifest, envelope, follow
/// payloads, media bytes — so decoders downstream of the transport layer
/// are unchanged.
class Libp2pNetworkService implements NetworkService, SyncTransport {
  Libp2pNetworkService({
    required Libp2pService libp2p,
    Duration timeout = const Duration(seconds: 10),
  }) : _libp2p = libp2p,
       _timeout = timeout;

  final Libp2pService _libp2p;
  final Duration _timeout;

  // --- protocol IDs ---

  static const String _pManifest = '/starling/sync/manifest/1';
  static const String _pEvents = '/starling/sync/events/1';
  static const String _pEventsPush = '/starling/sync/events-push/1';
  static const String _pMedia = '/starling/sync/media/1';
  static const String _pFollowRequest = '/starling/sync/follow-request/1';
  static const String _pFollowAccept = '/starling/sync/follow-accept/1';
  static const String _pPing = '/starling/sync/ping/1';

  // --- helpers ---

  /// Parse the peer-id out of a `libp2p://<peer-id>` baseUrl. Throws a
  /// [NetworkException] if [connection.baseUrl] is not in the expected
  /// shape so callers can route the failure through the same path as any
  /// other transport-layer error.
  String _peerIdOf(PeerConnection connection) {
    const prefix = 'libp2p://';
    final url = connection.baseUrl;
    if (!url.startsWith(prefix)) {
      throw NetworkException(
        'expected libp2p:// baseUrl, got "$url"',
        connection.pubkey,
      );
    }
    final id = url.substring(prefix.length);
    if (id.isEmpty) {
      throw NetworkException(
        'libp2p baseUrl missing peer-id',
        connection.pubkey,
      );
    }
    return id;
  }

  /// Single-shot request/response over a fresh stream. Catches the bridge's
  /// own exceptions and re-throws as [NetworkException] tagged with the
  /// peer pubkey, matching the contract `SyncEngine` expects.
  Future<Uint8List> _exchange(
    PeerConnection connection,
    String protocol,
    Uint8List request,
  ) async {
    final peerId = _peerIdOf(connection);
    Libp2pStream? stream;
    try {
      stream = await _libp2p.openStream(peerId, protocol);
      await stream.write(request, finish: true);
      return await stream.read(timeout: _timeout);
    } on Libp2pStreamException catch (e) {
      throw NetworkException(
        '$protocol failed: ${e.message}',
        connection.pubkey,
      );
    } on Libp2pUnavailableException catch (e) {
      throw NetworkException(
        '$protocol unavailable: ${e.message}',
        connection.pubkey,
      );
    } finally {
      await stream?.close();
    }
  }

  Uint8List _encode(Map<String, dynamic> map) =>
      Uint8List.fromList(cbor.encode(map));

  Uint8List _toBytes(dynamic value, String pubkey) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    throw NetworkException('expected bytes, got ${value.runtimeType}', pubkey);
  }

  // --- discovery (not applicable to libp2p — peers come from the
  // reachability monitor + connection cards, not mDNS) ---

  @override
  Future<Map<String, LanPeer>> discoverLanPeers() async => const {};

  @override
  Future<void> registerMdns(String pubkey, int port) async {}

  @override
  Future<void> deregisterMdns() async {}

  @override
  Future<PeerConnection> connectToPeer(ConnectionCard connectionCard) async {
    throw UnimplementedError(
      'Libp2pNetworkService.connectToPeer is not used — callers obtain a '
      'PeerConnection via PeerConnectionFactory after Libp2pUpgrader '
      'promotes the peer to libp2pDirect.',
    );
  }

  // --- Sync fetches ---

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
    final req = <String, dynamic>{};
    if (since != null) req['since'] = since;
    if (until != null) req['until'] = until;
    // Paging cursor, not identity — sent on every transport (incl. relay).
    if (until != null && untilId != null) req['until_id'] = untilId;
    // S7: mirror LanNetworkService — no identity params over a relay
    // connection. libp2p can't currently carry one, but keep the guards
    // aligned so they can't drift apart.
    if (connection.transport != PeerTransport.relay) {
      if (requesterPubkey != null) req['requester_pubkey'] = requesterPubkey;
      if (ackRotationAt != null && ackRotationAt > 0) {
        req['ack_rotation_at'] = ackRotationAt;
      }
      if (cardSeenAt != null && cardSeenAt > 0) {
        req['card_seen_at'] = cardSeenAt;
      }
      if (ackSig != null) req['ack_sig'] = ackSig;
    }
    final body = await _exchange(connection, _pManifest, _encode(req));
    final decoded = cbor.decode(body);
    if (decoded is! Map) {
      throw NetworkException('manifest body not a CBOR map', connection.pubkey);
    }
    return parseManifestResponse(
      decoded,
      toBytes: (value) => _toBytes(value, connection.pubkey),
    );
  }

  @override
  Future<List<EncryptedEvent>> fetchEvents(
    PeerConnection connection, {
    int? since,
  }) async {
    final env = await fetchEnvelope(connection, since: since);
    return [
      for (final item in env.items)
        if (item.type == 'event') EncryptedEvent.fromBytes(item.payload),
    ];
  }

  @override
  Future<Envelope> fetchEnvelope(
    PeerConnection connection, {
    int? since,
  }) async {
    final req = <String, dynamic>{};
    if (since != null) req['since'] = since;
    final body = await _exchange(connection, _pEvents, _encode(req));
    return Envelope.fromBytes(body);
  }

  @override
  Future<Uint8List> fetchMedia(PeerConnection connection, String hash) async {
    final req = <String, dynamic>{'hash': hash};
    return _exchange(connection, _pMedia, _encode(req));
  }

  // --- Follow ---

  @override
  Future<void> sendFollowRequest(
    PeerConnection connection,
    Uint8List requestPayload,
  ) async {
    // The follow payload is already an opaque CBOR-encoded request from the
    // follow service — wrap it once more so the responder sees the same
    // shape as on every other route (single CBOR map per stream).
    await _exchange(
      connection,
      _pFollowRequest,
      _encode({'payload': requestPayload}),
    );
  }

  @override
  Future<void> sendFollowAccept(
    PeerConnection connection,
    Uint8List acceptPayload,
  ) async {
    await _exchange(
      connection,
      _pFollowAccept,
      _encode({'payload': acceptPayload}),
    );
  }

  // --- Push (used by post fanout) ---

  @override
  Future<void> pushEnvelope(
    PeerConnection connection,
    Envelope envelope,
  ) async {
    await _exchange(connection, _pEventsPush, envelope.toBytes());
  }

  /// Round-trip the `/starling/sync/ping/1` protocol on an already-promoted
  /// libp2p connection. Used by [PeerReachabilityMonitor] as a passive
  /// liveness probe: cheap when the QUIC connection is healthy, throws
  /// (via [NetworkException] from [_exchange]) when the carrier silently
  /// evicted the v6 mapping or the swarm dropped the peer. The monitor
  /// catches that and demotes — re-promotion stays the upgrader's job.
  Future<void> ping(PeerConnection connection) async {
    await _exchange(
      connection,
      _pPing,
      Uint8List.fromList(cbor.encode(const <String, dynamic>{})),
    );
  }
}
