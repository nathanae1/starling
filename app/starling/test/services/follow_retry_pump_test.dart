import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starling/models/connection_card.dart';
import 'package:starling/services/follow_retry_pump.dart';
import 'package:starling/services/follow_service.dart';
import 'package:starling/services/mocks/mock_clock.dart';
import 'package:starling/services/mocks/mock_crypto_service.dart';
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/types.dart';

import '../helpers/fake_peer_reachability_monitor.dart';

/// Records calls to [retryQueuedAccepts] so we can assert what the pump asked
/// for. All the super-constructor deps are inert — the override never reaches
/// the real implementation.
class _RecordingFollowService extends FollowService {
  _RecordingFollowService()
    : super(
        crypto: MockCryptoService(),
        storage: MockStorageService(),
        clock: MockClock(),
        transport: _NoopTransport(),
        reachabilityMonitor: FakePeerReachabilityMonitor(),
        identityLookup: () async => null,
        ownSecretKeyLookup: () async => null,
        ownEndpointsLookup: () async => const <Endpoint>[],
      );

  final List<({String? onlyPubkey, bool ignoreBackoff})> calls = [];

  @override
  Future<void> retryQueuedAccepts({
    int failedStatusThreshold = 10,
    String? onlyPubkey,
    bool ignoreBackoff = false,
  }) async {
    calls.add((onlyPubkey: onlyPubkey, ignoreBackoff: ignoreBackoff));
  }
}

class _NoopTransport implements HandshakeTransport {
  @override
  Future<int> postFollowRequest(String baseUrl, Uint8List body) =>
      throw UnimplementedError();
  @override
  Future<int> postFollowAccept(String baseUrl, Uint8List body) =>
      throw UnimplementedError();
}

/// Flush pending microtasks so a stream event + its fire-and-forget handler
/// run before assertions.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  const alice = 'alice-pubkey';

  late _RecordingFollowService service;
  late FakePeerReachabilityMonitor monitor;
  late MockClock clock;
  late FollowRetryPump pump;

  setUp(() {
    service = _RecordingFollowService();
    monitor = FakePeerReachabilityMonitor();
    clock = MockClock(1000);
    pump = FollowRetryPump(
      followService: service,
      reachability: monitor,
      clock: clock,
      reconnectCooldown: const Duration(minutes: 1),
    );
    pump.start();
  });

  tearDown(() async {
    await pump.stop();
    await monitor.dispose();
  });

  test('reachable transition drains that pubkey, bypassing backoff', () async {
    monitor.emitReachable(alice, PeerTransport.lan, 'http://alice.local');
    await _settle();

    expect(service.calls, hasLength(1));
    expect(service.calls.single.onlyPubkey, alice);
    expect(service.calls.single.ignoreBackoff, isTrue);
  });

  test(
    'cooldown suppresses a re-trigger within the window, allows it after',
    () async {
      monitor.emitReachable(alice, PeerTransport.lan, 'http://alice.local');
      await _settle();
      expect(service.calls, hasLength(1));

      // Flap within the cooldown window → no second drain.
      monitor.emitUnreachable(alice);
      await _settle();
      monitor.emitReachable(alice, PeerTransport.lan, 'http://alice.local');
      await _settle();
      expect(service.calls, hasLength(1));

      // Flap again past the cooldown → drains once more.
      clock.advance(61);
      monitor.emitUnreachable(alice);
      await _settle();
      monitor.emitReachable(alice, PeerTransport.lan, 'http://alice.local');
      await _settle();
      expect(service.calls, hasLength(2));
    },
  );

  test(
    'a peer already reachable at start does not trigger on re-emit',
    () async {
      // Seed the monitor BEFORE a fresh pump starts.
      await pump.stop();
      monitor.emitReachable(alice, PeerTransport.lan, 'http://alice.local');
      final seeded = _RecordingFollowService();
      final seededPump = FollowRetryPump(
        followService: seeded,
        reachability: monitor,
        clock: clock,
      )..start();

      // Same peer, still reachable → not a transition → no drain.
      monitor.emitReachable(alice, PeerTransport.lan, 'http://alice.local');
      await _settle();
      expect(seeded.calls, isEmpty);

      await seededPump.stop();
    },
  );
}
