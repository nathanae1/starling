import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'providers/deep_link_provider.dart';
import 'providers/identity_provider.dart';
import 'providers/service_providers.dart';
import 'providers/sync_provider.dart';
import 'router.dart';
import 'screens/friends/confirm_request_sheet.dart';
import 'services/clock.dart';
import 'services/content_key_service.dart';
import 'services/crypto/crockford_base32.dart';
import 'services/crypto/key_cache.dart';
import 'services/crypto/pairwise_content_key_service.dart';
import 'services/crypto/sodium_crypto_service.dart';
import 'services/lifecycle/lifecycle_manager.dart';
import 'services/mdns_service.dart';
import 'services/signaling/ws_signaling_service.dart';
import 'services/storage/database.dart';
import 'services/storage/drift_storage_service.dart';
import 'services/storage/keychain_manager.dart';
import 'services/storage/retention.dart';
import 'services/tor/arti_tor_service.dart';
import 'theme/starling_theme.dart';
import 'utils/connection_card_parser.dart';
import 'widgets/sheet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final keychain = KeychainManager();
  final storage = await _initStorageService(keychain);
  final crypto = await SodiumCryptoService.init();

  final mdns = MethodChannelMdnsService();
  final torService = _shouldUseRealTor() ? ArtiTorService() : null;

  final overrides = [
    storageServiceProvider.overrideWithValue(storage),
    cryptoServiceProvider.overrideWithValue(crypto),
    mdnsServiceProvider.overrideWithValue(mdns),
    if (torService != null) torServiceProvider.overrideWithValue(torService),
  ];

  // If identity already exists at launch, hydrate the feed-key cache and
  // wire the real PairwiseContentKeyService. Without identity (pre-onboarding
  // or restore-in-progress) we stay on MockContentKeyService — nothing in
  // Plan 04's scope actually invokes it, and the first launch after
  // onboarding will wire it up.
  final identity = await storage.getIdentity();
  if (identity == null) {
    _keysLog('boot identity=null (pre-onboarding or restore-in-progress)');
  } else {
    _keysLog(
      'boot identity pubkey=${identity.pubkey} '
      'feedKeyFp=${_shortBytes(identity.feedKey)} '
      'epoch=${identity.feedKeyEpoch} '
      'msgSeq=${identity.msgSeqCounter}',
    );
  }
  if (identity != null) {
    final secretKey = await keychain.loadIdentitySecretKey();
    if (secretKey == null) {
      _keysLog(
        'WARNING boot secret_key=null but identity row present — '
        'PairwiseContentKeyService will NOT be wired (signing/decrypt broken)',
      );
    } else {
      _keysLog(
        'boot secret_key loaded len=${secretKey.length} '
        'fp=${_shortBytes(secretKey)}',
      );
      // libsodium Ed25519: 64-byte secret key carries the 32-byte public
      // key in its trailing half. Compare against the DB-stored pubkey to
      // surface the silent-mismatch failure mode (rebuild bumped one store
      // but not the other).
      if (secretKey.length == 64) {
        final derivedPub = Uint8List.sublistView(secretKey, 32, 64);
        final derivedPubEnc = _crockfordSafe(derivedPub);
        if (derivedPubEnc != identity.pubkey) {
          _keysLog(
            'WARNING pubkey MISMATCH: '
            'identity.pubkey=${identity.pubkey} '
            'derivedFromSecret=$derivedPubEnc — '
            'keychain secret was regenerated independently of DB identity',
          );
        } else {
          _keysLog('boot pubkey match OK (keychain secret ↔ DB identity)');
        }
      } else {
        _keysLog(
          'WARNING boot secret_key unexpected len=${secretKey.length} '
          '(expected 64 for Ed25519)',
        );
      }

      final follows = await storage.getFollows();
      final cache = FeedKeyCache()
        ..put(identity.pubkey, identity.feedKey, identity.feedKeyEpoch);
      for (final f in follows) {
        cache.put(f.pubkey, f.feedKey, f.feedKeyEpoch);
      }
      _keysLog('boot FeedKeyCache hydrated entries=${follows.length + 1}');
      if (kDebugMode) {
        final preview = follows.take(20);
        for (final f in preview) {
          _keysLog(
            'boot follow pubkey=${f.pubkey} '
            'feedKeyFp=${_shortBytes(f.feedKey)} '
            'epoch=${f.feedKeyEpoch} '
            'lastDecryptFailureAt=${f.lastDecryptFailureAt}',
          );
        }
        if (follows.length > 20) {
          _keysLog('boot follow … (+${follows.length - 20} more)');
        }
      }
      final contentKey = PairwiseContentKeyService(
        crypto: crypto,
        cache: cache,
        ownPubkey: identity.pubkey,
        ownSecretKey: secretKey,
      );
      overrides.add(
        contentKeyServiceProvider
            .overrideWithValue(contentKey as ContentKeyService),
      );
      // KeyRotationService (Plan 13) and PairwiseContentKeyService both
      // read from this single cache instance — rotations must update the
      // same cache the publish path reads from.
      overrides.add(feedKeyCacheProvider.overrideWithValue(cache));

      // Run retention once per launch — fire-and-forget. The DB is already
      // open and encrypted by the time we get here.
      unawaited(_runRetention(storage));

      // Plan 11c: build the container first, then construct the
      // production WsSignalingService against the already-built
      // container and install it in the runtime-settable production slot.
      // This replaces the previous `late ProviderContainer` closure
      // pattern — see `productionSignalingProvider` in
      // `lib/providers/service_providers.dart`.
      final container = ProviderContainer(overrides: overrides);
      final wsSignaling = WsSignalingService(
        crypto: crypto,
        peerFactory: (pubkey) =>
            container.read(peerConnectionFactoryProvider).resolve(pubkey),
        localPubkey: identity.pubkey,
        localSecretKey: secretKey,
      );
      container.read(productionSignalingProvider.notifier).set(wsSignaling);

      runApp(
        UncontrolledProviderScope(
          container: container,
          child: const StarlingApp(),
        ),
      );
      return;
    }
  }

  // No identity (or no secret key) — leave the mock signaling binding in
  // place. Retention still runs.
  unawaited(_runRetention(storage));

  runApp(ProviderScope(overrides: overrides, child: const StarlingApp()));
}

Future<DriftStorageService> _initStorageService(KeychainManager keychain) async {
  var dbKey = await keychain.read(KeychainManager.dbKeyName);
  if (dbKey == null) {
    final random = Random.secure();
    final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
    dbKey = keyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    await keychain.write(KeychainManager.dbKeyName, dbKey);
  }

  final db = AppDatabase.encrypted(dbKey);
  return DriftStorageService(db, const SystemClock());
}

/// First 8 hex chars of [bytes] for safe-to-log fingerprints. Same shape as
/// `_StarlingAppState._short` so log lines can be diffed across the two sites.
String _shortBytes(Uint8List bytes) {
  final hex = bytes
      .take(4)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '$hex…';
}

String _crockfordSafe(Uint8List bytes) {
  try {
    return crockfordBase32Encode(bytes);
  } catch (e) {
    return 'encode_failed:$e';
  }
}

/// Boot-time key state line — always-on (warnings included). DevTools sees
/// it via `developer.log`; Xcode/adb console sees it via `print`.
void _keysLog(String msg) {
  developer.log(msg, name: 'starling.keys');
  // ignore: avoid_print
  print('[starling.keys] $msg');
}

Future<void> _runRetention(DriftStorageService storage) async {
  try {
    final supportDir = await getApplicationSupportDirectory();
    final retention = RetentionService(
      storage: storage,
      mediaRoot: supportDir,
    );
    await retention.run();
  } catch (e, st) {
    developer.log('retention failed: $e',
        name: 'starling.retention', stackTrace: st);
  }
}

/// Real Tor only on iOS/Android — those are the only platforms the
/// `arti_bridge` Rust crate is cross-compiled for in Plan 11. Desktop
/// `flutter test` and `flutter run` on macOS keep the [MockTorService]
/// default from `service_providers.dart`.
bool _shouldUseRealTor() {
  if (kIsWeb) return false;
  return Platform.isIOS || Platform.isAndroid;
}

class StarlingApp extends ConsumerStatefulWidget {
  const StarlingApp({super.key});

  @override
  ConsumerState<StarlingApp> createState() => _StarlingAppState();
}

class _StarlingAppState extends ConsumerState<StarlingApp>
    with WidgetsBindingObserver {
  LifecycleManager? _lifecycle;
  ProviderSubscription<AsyncValue<ParsedInvite>>? _deepLinkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = LifecycleManager(ref: ref)..start();
    _deepLinkSub = ref.listenManual<AsyncValue<ParsedInvite>>(
      deepLinkInvitesProvider,
      (_, next) {
        final invite = next.value;
        if (invite is ValidInvite) {
          final ctx = ref.read(routerProvider).routerDelegate.navigatorKey
              .currentContext;
          if (ctx != null) {
            showStarlingSheet(
              context: ctx,
              builder: (_) => ConfirmRequestSheet(card: invite.card),
            );
          }
        }
      },
    );
    // Debug: dump identity + per-follow key state every time the
    // identity controller hydrates. Fires on first launch and again
    // after any subsequent identity refresh — so a hot restart is
    // enough to surface the dump (no full kill required).
    ref.listenManual<AsyncValue<dynamic>>(
      identityControllerProvider,
      (_, next) {
        if (next is AsyncData) {
          unawaited(_debugDumpKeyState());
        }
      },
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_lifecycle?.stop());
    _deepLinkSub?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_lifecycle?.onResume());
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(_lifecycle?.onPause());
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _debugDumpKeyState() async {
    try {
      final storage = ref.read(storageServiceProvider);
      final identity = await storage.getIdentity();
      if (identity == null) {
        _debugLine('no identity row');
        return;
      }
      _debugLine(
        'IDENTITY pubkey=${identity.pubkey} '
        'feedKey=${_short(identity.feedKey)} '
        'epoch=${identity.feedKeyEpoch}',
      );
      final follows = await storage.getFollows();
      _debugLine('FOLLOWS count=${follows.length}');
      for (final f in follows) {
        _debugLine(
          'FOLLOW pubkey=${f.pubkey} '
          'feedKey=${_short(f.feedKey)} '
          'epoch=${f.feedKeyEpoch} '
          'lastSyncedAt=${f.lastSyncedAt} '
          'lastReceivedRotationAt=${f.lastReceivedRotationAt} '
          'lastDecryptFailureAt=${f.lastDecryptFailureAt}',
        );
      }
    } catch (e, st) {
      _debugLine('KEY DUMP FAILED: $e\n$st');
    }
  }

  /// Routes a debug line through both `developer.log` (for DevTools) and
  /// `print` (for `flutter run` stdout / Xcode console). Intentionally
  /// loud so we can compare key state across devices without hunting in
  /// filtered log panels.
  void _debugLine(String msg) {
    developer.log(msg, name: 'starling.debug.keys');
    // ignore: avoid_print
    print('[starling.debug.keys] $msg');
  }

  /// First 8 hex chars of [bytes]. Enough to compare across devices in a
  /// log line without putting a full key on screen.
  static String _short(Uint8List bytes) {
    final hex = bytes
        .take(4)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '$hex…';
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Starling',
      theme: buildStarlingMaterialTheme(),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

final routerProvider = Provider((ref) => buildRouter(ref));
