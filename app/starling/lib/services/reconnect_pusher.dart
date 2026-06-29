import 'dart:async';
import 'dart:developer' as developer;

import '../models/envelope.dart';
import '../models/event.dart';
import '../models/protocol_version.dart';
import '../sync/peer_reachability_monitor.dart';
import '../sync/sync_engine.dart';
import 'clock.dart';
import 'storage_service.dart';

/// Watches `PeerReachabilityMonitor` for accepted-follower reachability
/// transitions and, on every transition into "reachable," pushes recent
/// own events to that follower so they catch up faster than the next
/// 1-min pull tick on their side.
///
/// Receivers dedupe by event id, so re-pushes are safe. We only push
/// **own** events: third-party events we re-distribute don't have stable
/// wire bytes on disk (they were decrypted then discarded), and the
/// follower will pick those up via their own pull.
class ReconnectPusher {
  ReconnectPusher({
    required StorageService storage,
    required SyncTransport transport,
    required PeerReachabilityMonitor reachability,
    required Clock clock,
    this.window = const Duration(days: 7),
    this.maxEvents = 50,
    this.cooldown = const Duration(minutes: 5),
  }) : _storage = storage,
       _transport = transport,
       _reachability = reachability,
       _clock = clock;

  final StorageService _storage;
  final SyncTransport _transport;
  final PeerReachabilityMonitor _reachability;
  final Clock _clock;

  /// How far back to look for own events when catching up a follower.
  final Duration window;

  /// Cap on events per push so we don't blast a long-offline follower.
  final int maxEvents;

  /// Per-follower minimum gap between catch-up pushes. Protects against
  /// flappy reachability and back-to-back reachable emissions.
  final Duration cooldown;

  StreamSubscription<Map<String, PeerReachability>>? _sub;
  final Set<String> _reachableNow = {};
  final Map<String, int> _lastPushAt = {};
  bool _running = false;

  void start() {
    if (_running) return;
    _running = true;
    // Seed `_reachableNow` from the monitor's current snapshot so we don't
    // immediately push to peers whose state was already "reachable" before
    // we subscribed (pump restart, lifecycle resume).
    for (final entry in _reachability.state.entries) {
      if (_isReachable(entry.value)) {
        _reachableNow.add(entry.key);
      }
    }
    _sub = _reachability.stateStream.listen(_onState);
  }

  Future<void> stop() async {
    _running = false;
    await _sub?.cancel();
    _sub = null;
    _reachableNow.clear();
  }

  void _onState(Map<String, PeerReachability> snapshot) {
    final newlyReachable = <String>[];
    final stillReachable = <String>{};
    for (final entry in snapshot.entries) {
      if (_isReachable(entry.value)) {
        stillReachable.add(entry.key);
        if (!_reachableNow.contains(entry.key)) {
          newlyReachable.add(entry.key);
        }
      }
    }
    _reachableNow
      ..clear()
      ..addAll(stillReachable);
    if (newlyReachable.isEmpty) return;
    unawaited(_handleReconnects(newlyReachable));
  }

  bool _isReachable(PeerReachability p) {
    for (final status in p.transports.values) {
      if (status.state == TransportState.reachable) return true;
    }
    return false;
  }

  Future<void> _handleReconnects(List<String> pubkeys) async {
    final Set<String> followers;
    try {
      followers = (await _storage.getAcceptedFollowerPubkeys()).toSet();
    } catch (e) {
      developer.log(
        'reconnect: follower lookup failed: $e',
        name: 'reconnect_pusher',
      );
      return;
    }
    final identity = await _storage.getIdentity();
    if (identity == null) return;

    final now = _clock.nowUnixSeconds();
    final cooldownSec = cooldown.inSeconds;

    final targets = <String>[];
    for (final pubkey in pubkeys) {
      if (!followers.contains(pubkey)) continue;
      final lastAt = _lastPushAt[pubkey] ?? 0;
      if (now - lastAt < cooldownSec) continue;
      _lastPushAt[pubkey] = now;
      targets.add(pubkey);
    }
    if (targets.isEmpty) return;

    final envelope = await _buildOwnCatchupEnvelope(identity.pubkey, now);
    if (envelope == null || envelope.items.isEmpty) return;

    await Future.wait(
      targets.map((p) => _pushOne(p, envelope)),
      eagerError: false,
    );
  }

  Future<Envelope?> _buildOwnCatchupEnvelope(String ownPubkey, int now) async {
    final since = now - window.inSeconds;
    final List<Event> events;
    try {
      events = await _storage.getOwnAndIncomingRefs(
        ownPubkey,
        since: since,
        limit: maxEvents,
      );
    } catch (e) {
      developer.log(
        'reconnect: event lookup failed: $e',
        name: 'reconnect_pusher',
      );
      return null;
    }
    final items = <EnvelopeItem>[];
    for (final ev in events) {
      if (ev.pubkey != ownPubkey) continue;
      final bytes = await _storage.getEncryptedPayload(ev.id);
      if (bytes == null) continue;
      items.add(EnvelopeItem(type: 'event', payload: bytes));
    }
    if (items.isEmpty) return null;
    return Envelope(version: kStarlingProtocolVersion, items: items);
  }

  Future<void> _pushOne(String pubkey, Envelope envelope) async {
    try {
      final conn = await _reachability.bestConnectionFor(pubkey);
      if (conn == null) return;
      await _transport.pushEnvelope(conn, envelope);
      developer.log(
        'reconnect: pushed ${envelope.items.length} item(s) to '
        '$pubkey via ${conn.transport.name}',
        name: 'reconnect_pusher',
      );
    } catch (e) {
      developer.log(
        'reconnect: push to $pubkey failed: $e',
        name: 'reconnect_pusher',
      );
    }
  }
}
