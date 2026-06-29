import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart';

import '../../services/clock.dart';

/// Per-IP fixed-window rate limiter. Returns 429 with `Retry-After: 60`
/// once a remote address exceeds [requestsPerMinute] within [window].
///
/// Fixed window over token bucket: simpler, no float math, the boundary-
/// burst flaw is acceptable for the loopback/LAN threat model at this rate.
class RateLimiter {
  RateLimiter({
    required this.requestsPerMinute,
    this.window = const Duration(minutes: 1),
    Clock? clock,
  }) : _clock = clock ?? const SystemClock() {
    _sweepTimer = Timer.periodic(window, (_) => _sweep());
  }

  final int requestsPerMinute;
  final Duration window;
  final Clock _clock;
  final Map<String, _Bucket> _buckets = {};
  late final Timer _sweepTimer;

  Middleware get middleware => (Handler inner) {
    return (Request request) async {
      final addr = _remoteAddress(request);
      final now = _clock.nowUnixSeconds();
      final bucket = _buckets.putIfAbsent(
        addr,
        () => _Bucket(windowStart: now),
      );
      if (now - bucket.windowStart >= window.inSeconds) {
        bucket.windowStart = now;
        bucket.count = 0;
      }
      bucket.count += 1;
      if (bucket.count > requestsPerMinute) {
        return Response(
          429,
          body: 'rate limit exceeded',
          headers: const {'retry-after': '60'},
        );
      }
      return inner(request);
    };
  };

  void dispose() {
    _sweepTimer.cancel();
    _buckets.clear();
  }

  void _sweep() {
    final now = _clock.nowUnixSeconds();
    final cutoff = window.inSeconds * 2;
    _buckets.removeWhere((_, bucket) => now - bucket.windowStart > cutoff);
  }

  String _remoteAddress(Request request) {
    final info = request.context['shelf.io.connection_info'];
    if (info is HttpConnectionInfo) {
      return info.remoteAddress.address;
    }
    final synthetic = request.context['starling.test.remote_address'];
    if (synthetic is String) return synthetic;
    return 'unknown';
  }
}

class _Bucket {
  _Bucket({required this.windowStart});
  int windowStart;
  int count = 0;
}
