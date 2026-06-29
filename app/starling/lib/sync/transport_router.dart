import 'dart:typed_data';

import '../models/models.dart';
import '../services/types.dart';
import 'sync_engine.dart' show SyncTransport;

/// Dispatches each [SyncTransport] call to the underlying transport for
/// `connection.transport`. Backings:
///   - LAN: `LanNetworkService` with a default `http.Client`
///   - Tor: `LanNetworkService` with a `TorHttpClient` (SOCKS5 → Arti)
///   - Relay (Plan 15): same backing as Tor — relay endpoints are `.onion`
///     hosts, reachable only through the Tor dialer
///   - libp2p-direct (Plan 11a): `Libp2pNetworkService` over libp2p streams
///
/// The wire-level code is identical for LAN and Tor (HTTP/1.1 to a Starling
/// peer); only the dialer differs. libp2p speaks `/starling/sync/<route>/1`
/// protocols over libp2p streams but carries byte-identical CBOR payloads.
///
/// `libp2p` is nullable so backgrounds and tests that don't run a Swarm
/// can construct a router without one. Routing a libp2pDirect connection
/// through a router built without `libp2p` throws — callers MUST gate via
/// reachability or `kLibp2pEnabled` before producing such a connection.
class TransportRouter implements SyncTransport {
  TransportRouter({
    required SyncTransport lan,
    required SyncTransport tor,
    SyncTransport? libp2p,
  }) : _lan = lan,
       _tor = tor,
       _libp2p = libp2p;

  final SyncTransport _lan;
  final SyncTransport _tor;
  final SyncTransport? _libp2p;

  SyncTransport _pick(PeerConnection peer) {
    switch (peer.transport) {
      case PeerTransport.libp2pDirect:
        final t = _libp2p;
        if (t == null) {
          throw StateError(
            'libp2pDirect connection routed through a TransportRouter that '
            'was not configured with a libp2p transport. Check '
            'kLibp2pEnabled and the DI wiring in syncTransportProvider.',
          );
        }
        return t;
      // Tor and relay both dial .onion endpoints — keep this grouping in
      // sync with PeerTransportDialing.dialsViaTor (types.dart).
      case PeerTransport.tor:
      case PeerTransport.relay:
        return _tor;
      case PeerTransport.lan:
        return _lan;
    }
  }

  @override
  Future<Manifest> fetchManifest(
    PeerConnection peer, {
    int? since,
    int? until,
    String? untilId,
    String? requesterPubkey,
    int? ackRotationAt,
    int? cardSeenAt,
    Uint8List? ackSig,
  }) => _pick(peer).fetchManifest(
    peer,
    since: since,
    until: until,
    untilId: untilId,
    requesterPubkey: requesterPubkey,
    ackRotationAt: ackRotationAt,
    cardSeenAt: cardSeenAt,
    ackSig: ackSig,
  );

  @override
  Future<Envelope> fetchEnvelope(PeerConnection peer, {int? since}) =>
      _pick(peer).fetchEnvelope(peer, since: since);

  @override
  Future<Uint8List> fetchMedia(PeerConnection peer, String hash) =>
      _pick(peer).fetchMedia(peer, hash);

  @override
  Future<void> pushEnvelope(PeerConnection peer, Envelope envelope) =>
      _pick(peer).pushEnvelope(peer, envelope);
}
