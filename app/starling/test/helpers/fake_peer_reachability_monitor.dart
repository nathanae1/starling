import 'dart:async';

import 'package:starling/models/connection_card.dart';
import 'package:starling/services/types.dart';
import 'package:starling/sync/peer_reachability_monitor.dart';

/// In-memory stand-in for [PeerReachabilityMonitor]. Tests pre-seed the
/// `(pubkey, transport)` -> baseUrl map so `bestConnectionFor` and
/// `probeCard` deterministically return the expected `PeerConnection`
/// without spinning up the real probe machinery.
class FakePeerReachabilityMonitor implements PeerReachabilityMonitor {
  final Map<String, Map<PeerTransport, String>> _reachable = {};
  final List<({String pubkey, PeerTransport transport, Object reason})>
  markedUnreachable = [];

  /// When true, [probeCard] resolves to `null` regardless of the reachable
  /// map — models a frozen request card whose onion can't be reached over
  /// Tor (e.g. it wasn't published at request time), while the live monitor
  /// ([bestConnectionFor]) still has a validated transport for the peer.
  bool failProbeCard = false;

  // Backs [stateStream]/[state] so consumers (e.g. FollowRetryPump,
  // ReconnectPusher) that diff reachability transitions can be driven
  // deterministically via [emitReachable].
  final StreamController<Map<String, PeerReachability>> _stateCtrl =
      StreamController<Map<String, PeerReachability>>.broadcast();
  final Map<String, PeerReachability> _snapshot = {};

  void setReachable(String pubkey, PeerTransport transport, String baseUrl) {
    _reachable.putIfAbsent(pubkey, () => {})[transport] = baseUrl;
  }

  /// Mark [pubkey] reachable on [transport] and emit a fresh snapshot on
  /// [stateStream] (mirrors the real monitor promoting a transport). Also
  /// updates the `bestConnectionFor` map so probes stay consistent.
  void emitReachable(String pubkey, PeerTransport transport, String baseUrl) {
    setReachable(pubkey, transport, baseUrl);
    _snapshot[pubkey] = PeerReachability(
      pubkey: pubkey,
      transports: {
        transport: const TransportStatus(state: TransportState.reachable),
      },
    );
    _stateCtrl.add(Map.unmodifiable(_snapshot));
  }

  /// Mark [pubkey] unreachable and emit a snapshot that omits it (mirrors a
  /// transport demotion). Lets tests drive reachable→unreachable→reachable
  /// flaps for cooldown coverage.
  void emitUnreachable(String pubkey) {
    _snapshot.remove(pubkey);
    _reachable.remove(pubkey);
    _stateCtrl.add(Map.unmodifiable(_snapshot));
  }

  void clear() => _reachable.clear();

  Future<void> dispose() async {
    if (!_stateCtrl.isClosed) await _stateCtrl.close();
  }

  @override
  Future<PeerConnection?> bestConnectionFor(String pubkey) async {
    final tier = _reachable[pubkey];
    if (tier == null) return null;
    // Mirrors the real monitor's tier preference (relay last).
    for (final transport in [
      PeerTransport.lan,
      PeerTransport.libp2pDirect,
      PeerTransport.tor,
      PeerTransport.relay,
    ]) {
      final url = tier[transport];
      if (url != null) {
        return PeerConnection(
          pubkey: pubkey,
          baseUrl: url,
          transport: transport,
        );
      }
    }
    return null;
  }

  @override
  Future<PeerConnection?> probeCard(ConnectionCard card) async =>
      failProbeCard ? null : bestConnectionFor(card.pubkey);

  @override
  void markUnreachable(String pubkey, PeerTransport transport, Object reason) {
    markedUnreachable.add((
      pubkey: pubkey,
      transport: transport,
      reason: reason,
    ));
    _reachable[pubkey]?.remove(transport);
  }

  @override
  void markReachable(String pubkey, PeerTransport transport, String baseUrl) {
    setReachable(pubkey, transport, baseUrl);
  }

  @override
  void bindLibp2pProbe(Future<void> Function(PeerConnection) probe) {
    // No-op — fake never runs the periodic probe loop.
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> refreshNow() async {}

  @override
  Stream<Map<String, PeerReachability>> get stateStream => _stateCtrl.stream;

  @override
  Map<String, PeerReachability> get state => Map.unmodifiable(_snapshot);
}
