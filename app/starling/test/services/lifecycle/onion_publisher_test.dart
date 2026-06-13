import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starling/services/lifecycle/onion_publisher.dart';
import 'package:starling/services/mocks/mock_tor_service.dart';

/// MockTorService plus a call log so tests can assert how many publishes ran
/// and on which ports. Reuses the parent's `failCreateOnionCount` injector.
class _CountingTor extends MockTorService {
  int createCalls = 0;
  final List<int> ports = [];

  @override
  Future<String> createOnionService(int localPort) {
    createCalls++;
    ports.add(localPort);
    return super.createOnionService(localPort);
  }
}

OnionPublisher _publisher(
  _CountingTor tor, {
  required List<String> addrs,
  Future<void> Function()? ensureTorInit,
}) =>
    OnionPublisher(
      ensureTorInit: ensureTorInit ?? () async {},
      tor: () => tor,
      onAddress: addrs.add,
    );

void main() {
  test('publishes on first request; same port is idempotent', () {
    fakeAsync((async) {
      final tor = _CountingTor();
      final addrs = <String>[];
      final pub = _publisher(tor, addrs: addrs);

      pub.requestPublish(56000);
      async.flushMicrotasks();
      expect(addrs, hasLength(1));
      expect(pub.onionPort, 56000);
      expect(tor.createCalls, 1);

      // Same port → skip; no new createOnionService, address unchanged.
      pub.requestPublish(56000);
      async.flushMicrotasks();
      expect(tor.createCalls, 1);
      expect(addrs, hasLength(1));
    });
  });

  test('retries with backoff after failure, then succeeds', () {
    fakeAsync((async) {
      final tor = _CountingTor()..failCreateOnionCount = 2;
      final addrs = <String>[];
      final pub = _publisher(tor, addrs: addrs);

      pub.requestPublish(56000);
      async.flushMicrotasks(); // attempt 1 → throws, schedule +10s
      expect(tor.createCalls, 1);
      expect(addrs, isEmpty);

      async.elapse(const Duration(seconds: 10)); // attempt 2 → throws, +30s
      expect(tor.createCalls, 2);
      expect(addrs, isEmpty);

      async.elapse(const Duration(seconds: 30)); // attempt 3 → succeeds
      expect(tor.createCalls, 3);
      expect(addrs, hasLength(1));
      expect(pub.onionPort, 56000);
    });
  });

  test('backoff caps at the last bucket on persistent failure', () {
    fakeAsync((async) {
      final tor = _CountingTor()..failCreateOnionCount = 100;
      final pub = _publisher(tor, addrs: <String>[]);

      pub.requestPublish(56000);
      async.flushMicrotasks();
      expect(tor.createCalls, 1);

      // Scheduled delays follow 10/30/60/120/300/300/300…
      for (final secs in [10, 30, 60, 120, 300, 300, 300]) {
        async.elapse(Duration(seconds: secs));
      }
      expect(tor.createCalls, 8); // 1 initial + 7 retries

      pub.reset(); // clear the still-pending retry timer for fakeAsync
    });
  });

  test('a failing ensureTorInit is retried too', () {
    fakeAsync((async) {
      var initCalls = 0;
      final tor = _CountingTor();
      final addrs = <String>[];
      final pub = _publisher(
        tor,
        addrs: addrs,
        ensureTorInit: () async {
          initCalls++;
          if (initCalls < 2) throw StateError('tor init boom');
        },
      );

      pub.requestPublish(56000);
      async.flushMicrotasks(); // attempt 1: ensureTorInit throws
      expect(initCalls, 1);
      expect(tor.createCalls, 0); // never reached createOnionService
      expect(addrs, isEmpty);

      async.elapse(const Duration(seconds: 10)); // attempt 2: init ok → publish
      expect(initCalls, 2);
      expect(tor.createCalls, 1);
      expect(addrs, hasLength(1));
    });
  });

  test('a port change supersedes a pending retry and resets backoff', () {
    fakeAsync((async) {
      // Only the first (port-A) attempt fails; port B will succeed.
      final tor = _CountingTor()..failCreateOnionCount = 1;
      final addrs = <String>[];
      final pub = _publisher(tor, addrs: addrs);

      pub.requestPublish(56000);
      async.flushMicrotasks(); // A fails, schedules +10s retry
      expect(tor.ports, [56000]);
      expect(addrs, isEmpty);

      // Switch port before the A-retry fires.
      pub.requestPublish(57000);
      async.flushMicrotasks(); // B publishes immediately
      expect(tor.ports, [56000, 57000]);
      expect(addrs, hasLength(1));
      expect(pub.onionPort, 57000);

      // The stale A retry timer was cancelled by the port change.
      async.elapse(const Duration(minutes: 10));
      expect(tor.ports, [56000, 57000]);
      expect(addrs, hasLength(1));
    });
  });

  test('reset cancels a pending retry — nothing fires afterward', () {
    fakeAsync((async) {
      final tor = _CountingTor()..failCreateOnionCount = 100;
      final addrs = <String>[];
      final pub = _publisher(tor, addrs: addrs);

      pub.requestPublish(56000);
      async.flushMicrotasks(); // attempt 1 fails, schedules retry
      expect(tor.createCalls, 1);

      pub.reset();
      async.elapse(const Duration(hours: 1));
      expect(tor.createCalls, 1); // no further attempts
      expect(addrs, isEmpty);
      expect(pub.onionAddress, isNull);
    });
  });

  test('retargets to a new port after a successful publish', () {
    fakeAsync((async) {
      final tor = _CountingTor();
      final addrs = <String>[];
      final pub = _publisher(tor, addrs: addrs);

      pub.requestPublish(56000);
      async.flushMicrotasks();
      expect(pub.onionPort, 56000);
      expect(tor.ports, [56000]);

      pub.requestPublish(57000);
      async.flushMicrotasks();
      expect(pub.onionPort, 57000);
      expect(tor.ports, [56000, 57000]);
      expect(addrs, hasLength(2));
    });
  });
}
