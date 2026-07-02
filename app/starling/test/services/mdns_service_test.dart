import 'package:starling/services/mdns_service.dart';
import 'package:starling/services/types.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodChannelMdnsService service;
  late _FakeChannels fake;

  setUp(() {
    fake = _FakeChannels();
    service = MethodChannelMdnsService(
      methodChannel: fake.methodChannel,
      eventChannel: fake.eventChannel,
    );
  });

  tearDown(() async {
    await service.dispose();
    fake.dispose();
  });

  test('register forwards pubkey and port to native', () async {
    await service.register(pubkey: 'alice-pk', port: 49000);
    expect(fake.invocations, hasLength(1));
    expect(fake.invocations.single.method, equals('register'));
    expect(fake.invocations.single.arguments, {
      'pubkey': 'alice-pk',
      'port': 49000,
    });
  });

  test('peer-found events populate the cache and stream', () async {
    final received = <Map<String, LanPeer>>[];
    final sub = service.peers.listen(received.add);
    await pumpEventQueue();

    fake.emit({
      'event': 'peer-found',
      'pubkey': 'bob-pk',
      'host': '10.0.0.5',
      'port': 49001,
    });
    await pumpEventQueue();

    expect(service.currentPeers(), contains('bob-pk'));
    expect(service.currentPeers()['bob-pk']!.host, equals('10.0.0.5'));
    // First yield is the initial empty snapshot, second is after peer-found.
    expect(received, hasLength(greaterThanOrEqualTo(2)));
    expect(received.last['bob-pk']!.port, equals(49001));

    await sub.cancel();
  });

  test('peer-lost removes the entry', () async {
    fake.emit({
      'event': 'peer-found',
      'pubkey': 'bob-pk',
      'host': '10.0.0.5',
      'port': 49001,
    });
    // Subscribe so the broadcast stream is active.
    final sub = service.peers.listen((_) {});
    await pumpEventQueue();

    fake.emit({'event': 'peer-lost', 'pubkey': 'bob-pk'});
    await pumpEventQueue();

    expect(service.currentPeers(), isEmpty);
    await sub.cancel();
  });

  test('cleared event empties the cache', () async {
    fake.emit({
      'event': 'peer-found',
      'pubkey': 'bob-pk',
      'host': '10.0.0.5',
      'port': 49001,
    });
    final sub = service.peers.listen((_) {});
    await pumpEventQueue();

    fake.emit({'event': 'cleared'});
    await pumpEventQueue();

    expect(service.currentPeers(), isEmpty);
    await sub.cancel();
  });

  test('deregister calls native and clears cache', () async {
    fake.emit({
      'event': 'peer-found',
      'pubkey': 'bob-pk',
      'host': '10.0.0.5',
      'port': 49001,
    });
    final sub = service.peers.listen((_) {});
    await pumpEventQueue();

    await service.deregister();
    expect(fake.invocations.last.method, equals('deregister'));
    expect(service.currentPeers(), isEmpty);
    await sub.cancel();
  });
}

class _FakeChannels {
  _FakeChannels() {
    methodChannel = const MethodChannel('test.starling.mdns');
    eventChannel = const EventChannel('test.starling.mdns/peers');

    final binary =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    binary.setMockMethodCallHandler(methodChannel, (call) async {
      invocations.add(call);
      return null;
    });

    // EventChannel issues its own `listen` / `cancel` method calls on the
    // event-channel name. Mock those so the broadcast stream fully sets
    // up; we don't care about asserting on them here.
    binary.setMockMethodCallHandler(
      MethodChannel(eventChannel.name),
      (call) async => null,
    );
  }

  late final MethodChannel methodChannel;
  late final EventChannel eventChannel;
  final invocations = <MethodCall>[];

  /// Pushes an event into the EventChannel as if the native side emitted it.
  /// Routes through the default messenger so the EventChannel's internal
  /// listener (registered by `receiveBroadcastStream`) is invoked.
  void emit(Map<String, Object?> payload) {
    final binary =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    binary.handlePlatformMessage(
      eventChannel.name,
      const StandardMethodCodec().encodeSuccessEnvelope(payload),
      (_) {},
    );
  }

  void dispose() {
    final binary =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    binary.setMockMethodCallHandler(methodChannel, null);
    binary.setMockMethodCallHandler(MethodChannel(eventChannel.name), null);
  }
}
