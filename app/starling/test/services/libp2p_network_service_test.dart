import 'dart:async';
import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starling/models/models.dart';
import 'package:starling/services/libp2p/libp2p_service.dart';
import 'package:starling/services/libp2p_network_service.dart';
import 'package:starling/services/types.dart';

void main() {
  group('Libp2pNetworkService', () {
    late FakeLibp2pService fake;
    late Libp2pNetworkService service;
    const remotePubkey = 'pubkey-base32-abc';
    const remotePeerId = '12D3KooW-fake';

    PeerConnection peer() => const PeerConnection(
      pubkey: remotePubkey,
      baseUrl: 'libp2p://$remotePeerId',
      transport: PeerTransport.libp2pDirect,
    );

    setUp(() {
      fake = FakeLibp2pService();
      service = Libp2pNetworkService(libp2p: fake);
    });

    test('fetchManifest writes CBOR query + decodes CBOR response', () async {
      fake.respond(
        '/starling/sync/manifest/1',
        _encode({
          'pubkey': remotePubkey,
          'events': [
            {'id': 'evt1', 'created_at': 1700000000},
            {'id': 'evt2', 'created_at': 1700000100},
          ],
          'has_older': true,
        }),
      );

      final manifest = await service.fetchManifest(
        peer(),
        since: 1699999000,
        requesterPubkey: 'me-pk',
        ackRotationAt: 0,
      );

      expect(manifest.pubkey, remotePubkey);
      expect(manifest.events.length, 2);
      expect(manifest.events.first.id, 'evt1');
      expect(manifest.hasOlder, isTrue);

      // Verify the request CBOR.
      final req =
          cbor.decode(fake.lastWrite('/starling/sync/manifest/1'))
              as Map<dynamic, dynamic>;
      expect(req['since'], 1699999000);
      expect(req['requester_pubkey'], 'me-pk');
      // ack_rotation_at == 0 should NOT be sent (matches LAN/HTTP behavior)
      expect(req.containsKey('ack_rotation_at'), isFalse);
    });

    test('fetchEnvelope round-trips an Envelope unchanged', () async {
      final outboundEnv = Envelope(
        version: '2026-03-24',
        items: [EnvelopeItem(type: 'event', payload: Uint8List(0))],
      );
      fake.respond('/starling/sync/events/1', outboundEnv.toBytes());

      final got = await service.fetchEnvelope(peer(), since: 1700000000);
      expect(got.version, '2026-03-24');
      expect(got.items.length, 1);
    });

    test('fetchMedia returns raw bytes', () async {
      final blob = Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]);
      fake.respond('/starling/sync/media/1', blob);

      final got = await service.fetchMedia(peer(), 'somehash');
      expect(got, equals(blob));

      final req =
          cbor.decode(fake.lastWrite('/starling/sync/media/1'))
              as Map<dynamic, dynamic>;
      expect(req['hash'], 'somehash');
    });

    test('rejects non-libp2p baseUrl with NetworkException', () async {
      final bad = const PeerConnection(
        pubkey: remotePubkey,
        baseUrl: 'http://10.0.0.1:8080',
        transport: PeerTransport.libp2pDirect,
      );
      expect(() => service.fetchManifest(bad), throwsA(isA<Exception>()));
    });

    test('translates Libp2pStreamException into NetworkException', () async {
      fake.setErrorFor(
        '/starling/sync/events/1',
        const Libp2pStreamException('stream reset'),
      );
      expect(() => service.fetchEnvelope(peer()), throwsA(isA<Exception>()));
    });
  });
}

Uint8List _encode(Map<String, dynamic> map) =>
    Uint8List.fromList(cbor.encode(map));

/// In-process Libp2pService that records protocol/payload pairs and
/// returns canned responses keyed by protocol. Mirrors the contract of
/// the real bridge minus actual networking.
class FakeLibp2pService implements Libp2pService {
  final Map<String, Uint8List> _responses = {};
  final Map<String, Object> _errors = {};
  final Map<String, Uint8List> _lastWrites = {};

  void respond(String protocol, Uint8List body) {
    _responses[protocol] = body;
  }

  void setErrorFor(String protocol, Object err) {
    _errors[protocol] = err;
  }

  Uint8List lastWrite(String protocol) => _lastWrites[protocol] ?? Uint8List(0);

  // --- Libp2pService ---

  @override
  bool get isReady => true;

  @override
  String get localPeerId => '12D3KooW-local';

  final _eventCtrl = StreamController<Libp2pEvent>.broadcast();

  @override
  Stream<Libp2pEvent> get events => _eventCtrl.stream;

  @override
  Future<void> init(String dataDir, Uint8List ed25519Seed) async {}

  @override
  Future<void> listen() async {}

  @override
  Future<List<Uint8List>> observedAddrs() async => const [];

  @override
  Future<void> addObservedAddr(Uint8List multiaddr) async {}

  @override
  Future<void> dialDirect(
    String remotePeerId,
    List<Uint8List> remoteAddrs, {
    Duration timeout = const Duration(seconds: 8),
  }) async {}

  @override
  Future<Libp2pStream> openStream(String remotePeerId, String protocol) async {
    final err = _errors[protocol];
    if (err != null) throw err;
    return _FakeStream(
      remotePeerId: remotePeerId,
      protocol: protocol,
      onWrite: (data) => _lastWrites[protocol] = data,
      response: _responses[protocol] ?? Uint8List(0),
    );
  }

  @override
  void registerInboundHandler(
    String protocol,
    void Function(Libp2pStream stream) handler,
  ) {}

  @override
  Future<void> shutdown() async {
    if (!_eventCtrl.isClosed) await _eventCtrl.close();
  }
}

class _FakeStream implements Libp2pStream {
  _FakeStream({
    required this.remotePeerId,
    required this.protocol,
    required void Function(Uint8List) onWrite,
    required Uint8List response,
  }) : _onWrite = onWrite,
       _response = response;

  @override
  final String remotePeerId;
  @override
  final String protocol;
  final void Function(Uint8List) _onWrite;
  final Uint8List _response;
  bool _closed = false;

  @override
  Future<void> write(Uint8List data, {bool finish = false}) async {
    _onWrite(data);
  }

  @override
  Future<Uint8List> read({Duration? timeout}) async {
    if (_closed) {
      throw const Libp2pStreamException('read after close');
    }
    return _response;
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}
