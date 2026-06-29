import '../services/types.dart';
import 'peer_reachability_monitor.dart';

/// Thin façade over [PeerReachabilityMonitor]. Resolves a follow's pubkey
/// to the best currently-validated `PeerConnection` (Plan 11c). The
/// monitor is what does the actual probing and state-tracking; this
/// class exists so consumers don't need to know about state machines —
/// they just call `resolve(pubkey)` and get a connection or `null`.
class PeerConnectionFactory {
  PeerConnectionFactory({required PeerReachabilityMonitor monitor})
    : _monitor = monitor;

  final PeerReachabilityMonitor _monitor;

  /// Returns the best currently-validated transport for [pubkey], or
  /// `null` if nothing is reachable. Briefly waits for in-flight probes
  /// (capped at the monitor's `firstCallWindow`).
  Future<PeerConnection?> resolve(String pubkey) =>
      _monitor.bestConnectionFor(pubkey);
}
