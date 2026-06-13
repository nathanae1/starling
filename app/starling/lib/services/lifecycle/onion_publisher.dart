import 'dart:async';
import 'dart:developer' as developer;

import '../tor_service.dart';

/// Owns the device's single onion-service publish lifecycle: it forwards
/// virtual port 80 to the embedded HTTP server's current local port and,
/// crucially, **retries on failure with capped exponential backoff**.
///
/// Before this existed, a transient Tor error during `createOnionService`
/// (or a failed `ensureTorInit`) left the device dark over Tor for the
/// whole session — the only re-trigger was an HTTP-server port change, so
/// the friends screen showed "Tor starting…" forever and
/// `FollowService.sendFollowRequest` threw `noEndpoints`.
///
/// Extracted from `LifecycleManager` so the timer + backoff + supersede
/// state machine is unit-testable (the manager is `WidgetRef`-coupled and
/// untestable). Provider writes stay in the manager via [onAddress] so a
/// late retry timer never touches `ref` after teardown.
class OnionPublisher {
  OnionPublisher({
    required Future<void> Function() ensureTorInit,
    required TorService Function() tor,
    required void Function(String address) onAddress,
    List<Duration> backoff = const [
      Duration(seconds: 10),
      Duration(seconds: 30),
      Duration(seconds: 60),
      Duration(minutes: 2),
      Duration(minutes: 5),
    ],
  })  : _ensureTorInit = ensureTorInit,
        _tor = tor,
        _onAddress = onAddress,
        _backoff = backoff;

  final Future<void> Function() _ensureTorInit;
  final TorService Function() _tor;
  final void Function(String address) _onAddress;
  final List<Duration> _backoff;

  /// The port we currently *want* published. A pending retry or a chained
  /// publish only proceeds while it still matches — a newer [requestPublish]
  /// (port change) or a [reset] supersedes outstanding work.
  int? _desiredPort;
  String? _onionAddress;
  int? _onionPort;

  /// Serializes overlapping publish calls so the recorded [_onionPort]
  /// can't disagree with the proxy's actual target when port events arrive
  /// back-to-back.
  Future<void> _publishChain = Future<void>.value();
  Timer? _retryTimer;
  int _failures = 0;

  String? get onionAddress => _onionAddress;
  int? get onionPort => _onionPort;

  /// Publish (or re-target) the onion to [port]. A port change resets the
  /// backoff and cancels any pending retry; the same port once published is
  /// a no-op. The bridge re-targets the live reverse proxy in place when the
  /// port differs, so the `.onion` address is stable across rebinds.
  void requestPublish(int port) {
    if (port != _desiredPort) {
      _failures = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
    }
    _desiredPort = port;
    _publishChain = _publishChain.then((_) => _publishNow(port));
  }

  /// Cancel any pending retry and clear all state. Called on
  /// shutdown/dispose so no timer outlives the owning widget. Does not touch
  /// the address provider — the caller owns that.
  void reset() {
    _desiredPort = null;
    _onionAddress = null;
    _onionPort = null;
    _failures = 0;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<void> _publishNow(int port) async {
    // Superseded by a newer requestPublish or a reset while we waited in the
    // chain.
    if (port != _desiredPort) return;
    if (_onionAddress != null && _onionPort == port) {
      _log('publishOnion skipped (already have $_onionAddress port=$port)');
      return;
    }
    try {
      _log('publishOnion begin port=$port (was ${_onionPort ?? "unset"})');
      // Inside the try so a failed Tor init is retried too — `_ensureTorInit`
      // nulls its own memoized future on failure, but nothing else re-calls
      // it.
      await _ensureTorInit();
      final tor = _tor();
      _log('publishOnion calling createOnionService isReady=${tor.isReady}');
      final addr = await tor.createOnionService(port);
      // A reset / port-change may have landed while we awaited.
      if (port != _desiredPort) {
        _log('publishOnion result ignored (superseded; desired=$_desiredPort)');
        return;
      }
      _onionAddress = addr;
      _onionPort = port;
      _failures = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
      _onAddress(addr);
      _log('onion=$addr port=$port');
    } catch (e, st) {
      if (port != _desiredPort) return;
      final delay =
          _backoff[_failures < _backoff.length ? _failures : _backoff.length - 1];
      _failures++;
      _log('createOnionService failed (retry #$_failures in '
          '${delay.inSeconds}s): $e\n$st');
      _scheduleRetry(port, delay);
    }
  }

  void _scheduleRetry(int port, Duration delay) {
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      // reset() nulls _desiredPort; a port change set a different one.
      if (port != _desiredPort) return;
      _publishChain = _publishChain.then((_) => _publishNow(port));
    });
  }

  void _log(String msg) {
    developer.log(msg, name: 'starling.tor');
    // ignore: avoid_print
    print('[starling.tor] $msg');
  }
}
