import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starling/services/lan_network_service.dart';
import 'package:starling/services/mocks/mock_mdns_service.dart';
import 'package:starling/services/types.dart';

void main() {
  // S7: relay connections must not carry follower-identifying params —
  // the relay ignores them, but its operator/logs would see each
  // follower's pubkey + poll cadence. Direct connections keep them.
  group('LanNetworkService.fetchManifest identity params', () {
    late Uri captured;
    late LanNetworkService service;

    setUp(() {
      service = LanNetworkService(
        mdns: MockMdnsService(),
        httpClient: MockClient((req) async {
          captured = req.url;
          return http.Response.bytes(
            cbor.encode(<String, dynamic>{
              'pubkey': 'peer-1',
              'events': <dynamic>[],
              'has_older': false,
            }),
            200,
            headers: const {'content-type': 'application/cbor'},
          );
        }),
      );
    });

    Future<void> fetch(PeerTransport transport) => service.fetchManifest(
      PeerConnection(
        pubkey: 'peer-1',
        baseUrl: 'http://peer.example:80',
        transport: transport,
      ),
      since: 100,
      requesterPubkey: 'me-pubkey',
      ackRotationAt: 500,
      cardSeenAt: 600,
      ackSig: Uint8List.fromList(List.filled(64, 0xAB)),
    );

    test(
      'relay transport strips requester_pubkey and all ack params',
      () async {
        await fetch(PeerTransport.relay);
        expect(captured.queryParameters, {'since': '100'});
      },
    );

    for (final transport in [PeerTransport.lan, PeerTransport.tor]) {
      test('${transport.name} transport sends identity + ack params', () async {
        await fetch(transport);
        final q = captured.queryParameters;
        expect(q['since'], '100');
        expect(q['requester_pubkey'], 'me-pubkey');
        expect(q['ack_rotation_at'], '500');
        expect(q['card_seen_at'], '600');
        expect(q['ack_sig'], 'ab' * 64);
      });
    }
  });
}
