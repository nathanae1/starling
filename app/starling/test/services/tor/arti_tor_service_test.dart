// Real-Tor integration test for Plan 11a.
//
// Skipped unless `STARLING_REAL_TOR=1` is in the environment, because:
//  - it requires a real network and Tor directory authorities
//  - it loads `libarti_bridge.so` / `arti_bridge.xcframework`, which only
//    exists on devices where `native/arti_bridge/build.sh` has run
//  - bootstrap takes 10–60 seconds
//
// Usage on a connected device or on a host with a host-built libarti_bridge:
//   STARLING_REAL_TOR=1 flutter test test/services/tor/

import 'dart:io';

import 'package:starling/services/tor/arti_tor_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

bool get _enabled => Platform.environment['STARLING_REAL_TOR'] == '1';

void main() {
  test(
    'bootstraps and publishes a stable v3 onion address',
    () async {
      final supportDir = await getApplicationSupportDirectory();
      final dataDir = Directory('${supportDir.path}/tor-test')
        ..createSync(recursive: true);

      final svc = ArtiTorService();
      try {
        await svc.init(dataDir.path);

        // Poll status until ready or 60s elapsed.
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (!svc.getStatus().isReady && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        final status = svc.getStatus();
        expect(
          status.isReady,
          isTrue,
          reason: 'Arti did not finish bootstrapping within 60s',
        );
        expect(status.bootstrapPercent, 100);

        // Publish onion service. The on-device HTTP server isn't running
        // here — we only check the address shape and persistence.
        const fakeLocalPort = 12345;
        final onion1 = await svc.createOnionService(fakeLocalPort);
        expect(onion1, endsWith('.onion'));
        // v3 onion = 56-char base32 + ".onion" = 62 chars total.
        expect(onion1.length, 62);

        // Calling create again with the same data dir should hand back
        // the cached address from the same Inner state.
        final onion2 = await svc.createOnionService(fakeLocalPort);
        expect(onion2, onion1);
      } finally {
        await svc.shutdown();
      }
    },
    skip: _enabled ? false : 'set STARLING_REAL_TOR=1 to run',
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'keypair survives a shutdown / re-init cycle',
    () async {
      final supportDir = await getApplicationSupportDirectory();
      final dataDir = Directory('${supportDir.path}/tor-test')
        ..createSync(recursive: true);

      String? first;
      {
        final svc = ArtiTorService();
        try {
          await svc.init(dataDir.path);
          final deadline = DateTime.now().add(const Duration(seconds: 60));
          while (!svc.getStatus().isReady &&
              DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
          first = await svc.createOnionService(12345);
        } finally {
          await svc.shutdown();
        }
      }
      expect(first, isNotNull);

      final svc = ArtiTorService();
      try {
        await svc.init(dataDir.path);
        final deadline = DateTime.now().add(const Duration(seconds: 60));
        while (!svc.getStatus().isReady && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        final second = await svc.createOnionService(12345);
        expect(second, first);
      } finally {
        await svc.shutdown();
      }
    },
    skip: _enabled ? false : 'set STARLING_REAL_TOR=1 to run',
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
