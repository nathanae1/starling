import 'dart:async';
import 'dart:developer' as developer;

import '../sync/peer_reachability_monitor.dart';
import 'clock.dart';
import 'follow_service.dart';

/// Drives redelivery of both queued handshake legs — /follow-accept payloads
/// AND queued outbound /follow-request cards. Two triggers:
///
/// 1. A periodic [interval] tick (foreground) that runs a full backoff-aware
///    pass via [FollowService.retryQueuedAccepts] +
///    [FollowService.retryQueuedRequests].
/// 2. A reachability transition: when a peer's pubkey flips to reachable in
///    [PeerReachabilityMonitor], we immediately drain that pubkey's queued
///    payloads (bypassing backoff), subject to a per-pubkey
///    [reconnectCooldown]. Modeled on [ReconnectPusher].
///
/// Backoff and the never-strand policy live inside the FollowService drains;
/// this pump only decides *when* to ask.
///
/// Limitation: the monitor only probes follows, so the reachability trigger
/// fires only for peers we already follow (the mutual-follow case). Fresh
/// outbound requests and non-mutual requesters are covered by the periodic
/// backoff pass.
class FollowRetryPump {
  FollowRetryPump({
    required this.followService,
    this.reachability,
    this.clock = const SystemClock(),
    this.interval = const Duration(seconds: 30),
    this.failedStatusThreshold = 10,
    this.reconnectCooldown = const Duration(minutes: 1),
  });

  final FollowService followService;
  final PeerReachabilityMonitor? reachability;
  final Clock clock;
  final Duration interval;

  /// Consecutive-failure count at which the inbound row flips to
  /// 'send-failed' for display. NOT a cap — retries continue past it.
  final int failedStatusThreshold;

  /// Minimum gap between reachability-triggered drains for one pubkey.
  /// Protects against flappy reachability re-emitting "reachable".
  final Duration reconnectCooldown;

  Timer? _timer;
  bool _running = false;

  StreamSubscription<Map<String, PeerReachability>>? _sub;
  final Set<String> _reachableNow = {};
  final Map<String, int> _lastTriggerAt = {};

  void start() {
    _timer ??= Timer.periodic(interval, (_) => _tick());

    final monitor = reachability;
    if (monitor != null && _sub == null) {
      // Seed from the current snapshot so peers already reachable before we
      // subscribed don't immediately trigger a (redundant) drain.
      for (final entry in monitor.state.entries) {
        if (entry.value.isReachable) _reachableNow.add(entry.key);
      }
      _sub = monitor.stateStream.listen(_onState);
    }
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    await _sub?.cancel();
    _sub = null;
    _reachableNow.clear();
    _lastTriggerAt.clear();
  }

  Future<void> _tick() async {
    if (_running) return;
    _running = true;
    try {
      await followService.retryQueuedAccepts(
        failedStatusThreshold: failedStatusThreshold,
      );
      await followService.retryQueuedRequests(
        failedStatusThreshold: failedStatusThreshold,
      );
    } catch (_) {
      // Errors are logged inside FollowService; the pump itself never fails.
    } finally {
      _running = false;
    }
  }

  void _onState(Map<String, PeerReachability> snapshot) {
    final newlyReachable = <String>[];
    final stillReachable = <String>{};
    for (final entry in snapshot.entries) {
      if (entry.value.isReachable) {
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

    final now = clock.nowUnixSeconds();
    final cooldownSec = reconnectCooldown.inSeconds;
    for (final pubkey in newlyReachable) {
      final lastAt = _lastTriggerAt[pubkey] ?? 0;
      if (lastAt != 0 && now - lastAt < cooldownSec) continue;
      _lastTriggerAt[pubkey] = now;
      // Fire-and-forget: a no-op when nothing is queued for this pubkey.
      // FollowService serializes this against the periodic tick.
      unawaited(_triggerFor(pubkey));
    }
  }

  Future<void> _triggerFor(String pubkey) async {
    try {
      await followService.retryQueuedAccepts(
        onlyPubkey: pubkey,
        ignoreBackoff: true,
        failedStatusThreshold: failedStatusThreshold,
      );
      await followService.retryQueuedRequests(
        onlyPubkey: pubkey,
        ignoreBackoff: true,
        failedStatusThreshold: failedStatusThreshold,
      );
    } catch (e) {
      developer.log(
        'reachability-triggered drain failed for $pubkey: $e',
        name: 'follow_retry_pump',
      );
    }
  }
}
