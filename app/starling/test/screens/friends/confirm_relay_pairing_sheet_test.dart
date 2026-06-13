import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starling/providers/relay_providers.dart';
import 'package:starling/screens/friends/confirm_relay_pairing_sheet.dart';
import 'package:starling/services/crypto/crockford_base32.dart';
import 'package:starling/services/crypto/sodium_crypto_service.dart';
import 'package:starling/services/mocks/mock_clock.dart';
import 'package:starling/services/mocks/mock_storage_service.dart';
import 'package:starling/services/relay_pairing_initiator.dart';
import 'package:starling/services/relay_pairing_service.dart';
import 'package:starling/services/relay_push_coordinator.dart';
import 'package:starling/services/relay_push_service.dart';
import 'package:starling/services/types.dart';
import 'package:starling/theme/starling_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SodiumCryptoService crypto;

  setUpAll(() async {
    crypto = await SodiumCryptoService.init();
  });

  /// Real [RelayPairingService] over a mock `/pair` transport so the sheet's
  /// error mapping is exercised through the real initiator code path.
  Future<RelayPairingService> buildService({
    required http.Client pairClient,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final storage = MockStorageService();
    final kp = await crypto.generateKeyPair();
    await storage.saveIdentity(Identity(
      pubkey: crockfordBase32Encode(kp.publicKey),
      feedKey: Uint8List(32),
      createdAt: 0,
    ));
    return RelayPairingService(
      initiator: RelayPairingInitiator(
        crypto: crypto,
        httpClient: pairClient,
        timeout: timeout,
      ),
      pushCoordinator: RelayPushCoordinator(
        pushService: RelayPushService(
          crypto: crypto,
          httpClient: MockClient((_) async => http.Response('', 202)),
        ),
        storage: storage,
        relayClient: MockClient((_) async => http.Response('', 200)),
        identityLookup: storage.getIdentity,
        ownSecretKeyLookup: () async => kp.secretKey,
        mediaBytesLookup: (_) async => null,
      ),
      crypto: crypto,
      storage: storage,
      clock: MockClock(),
      identityLookup: storage.getIdentity,
      ownSecretKeyLookup: () async => kp.secretKey,
      ownEndpointsLookup: () => const [],
      reloadPairedRelay: () async {},
    );
  }

  Widget harness(RelayPairingService service) {
    final container = ProviderContainer(overrides: [
      relayPairingServiceProvider.overrideWith((ref) async => service),
    ]);
    addTearDown(container.dispose);
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildStarlingMaterialTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ConfirmRelayPairingSheet(
              payload: RelayPairingPayload(
                relayOnion: 'admin.onion',
                pairingToken: Uint8List.fromList(List.filled(32, 7)),
                relayVersion: '1',
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('409 from /pair shows the already-claimed guidance, not the '
      'raw status line', (tester) async {
    final service = await buildService(
      pairClient: MockClient(
        (_) async => http.Response('token already used', 409),
      ),
    );
    await tester.pumpWidget(harness(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pair relay'));
    await tester.pumpAndSettle();

    expect(find.textContaining('already claimed'), findsOneWidget);
    expect(find.textContaining('pair failed: 409'), findsNothing);
  });

  testWidgets('transport timeout shows the relay-may-still-be-setting-up '
      'message', (tester) async {
    final service = await buildService(
      timeout: const Duration(seconds: 1),
      pairClient: MockClient((_) async {
        await Future<void>.delayed(const Duration(seconds: 5));
        return http.Response('', 200);
      }),
    );
    await tester.pumpWidget(harness(service));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pair relay'));
    await tester.pump();
    // While in flight, the patience hint is visible.
    expect(find.textContaining('can take a minute'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2)); // past the 1s timeout
    expect(find.textContaining('didn’t respond in time'), findsOneWidget);
    expect(find.textContaining('Unexpected error'), findsNothing);

    // Flush the mock transport's pending 5s delay so no timers leak.
    await tester.pump(const Duration(seconds: 5));
  });
}
