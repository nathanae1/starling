import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/media/media_files.dart';
import '../services/relay_pairing_initiator.dart';
import '../services/relay_pairing_service.dart';
import '../services/relay_push_coordinator.dart';
import '../services/relay_push_service.dart';
import '../services/storage/keychain_manager.dart';
import '../services/tor/tor_http_client.dart';
import '../services/types.dart';
import 'app_paths_provider.dart';
import 'follow_provider.dart';
import 'service_providers.dart';

part 'relay_providers.g.dart';

/// The Relay this Owner has paired with (Plan 15), loaded from storage and
/// reloaded on pair/unpair. Watched by `ownEndpoints` so the published
/// Connection card grows (or loses) its relay endpoint the moment pairing
/// state changes.
@Riverpod(keepAlive: true)
class PairedRelayController extends _$PairedRelayController {
  @override
  Future<PairedRelay?> build() =>
      ref.watch(storageServiceProvider).getPairedRelay();

  /// Re-read the paired relay after a pair/unpair so dependents rebuild.
  Future<void> reload() async {
    state = AsyncData(await ref.read(storageServiceProvider).getPairedRelay());
  }
}

/// Shared Tor-backed HTTP client for all relay traffic (pairing + push).
/// Every relay endpoint is a `.onion`, so relay HTTP always rides Arti's
/// SOCKS5 proxy. Returns null until the onion address is published — the
/// same "Tor is ready for outbound" gate used by `torNetworkService`.
///
/// `keepAlive: true` because the wrapped [TorHttpClient] is a long-lived
/// resource that shouldn't be torn down on a transient drop in watchers.
@Riverpod(keepAlive: true)
http.Client? relayTorClient(Ref ref) {
  final onion = ref.watch(onionAddressProvider);
  if (onion == null) return null;
  final tor = ref.watch(torServiceProvider);
  final port = tor.socksPort;
  if (port == 0) return null;
  final client = TorHttpClient(socksHost: '127.0.0.1', socksPort: port);
  ref.onDispose(client.close);
  return client;
}

/// Owner-signed push of EncryptedEvents + media to the paired relay
/// (Plan 15). Null until Tor is ready (see [relayTorClient]).
@Riverpod(keepAlive: true)
RelayPushService? relayPushService(Ref ref) {
  final client = ref.watch(relayTorClientProvider);
  if (client == null) return null;
  return RelayPushService(
    crypto: ref.watch(cryptoServiceProvider),
    httpClient: client,
  );
}

/// Drives the `/pair` handshake against a relay's admin onion (Plan 15).
/// Null until Tor is ready (see [relayTorClient]).
@Riverpod(keepAlive: true)
RelayPairingInitiator? relayPairingInitiator(Ref ref) {
  final client = ref.watch(relayTorClientProvider);
  if (client == null) return null;
  return RelayPairingInitiator(
    crypto: ref.watch(cryptoServiceProvider),
    httpClient: client,
  );
}

/// Best-effort owner→relay push coordinator (Plan 15). Async because it
/// needs the app-support directory to read encrypted media blobs from
/// disk. Null until Tor is ready (see [relayTorClient]).
@Riverpod(keepAlive: true)
Future<RelayPushCoordinator?> relayPushCoordinator(Ref ref) async {
  final push = ref.watch(relayPushServiceProvider);
  final client = ref.watch(relayTorClientProvider);
  if (push == null || client == null) return null;
  final storage = ref.watch(storageServiceProvider);
  final dir = await ref.watch(appSupportDirectoryProvider.future);
  return RelayPushCoordinator(
    pushService: push,
    storage: storage,
    relayClient: client,
    identityLookup: storage.getIdentity,
    ownSecretKeyLookup: () => KeychainManager().loadIdentitySecretKey(),
    mediaBytesLookup: (hash) =>
        readMediaBytes(storage: storage, appSupportDir: dir, hash: hash),
  );
}

/// Phone-side relay pairing orchestrator (Plan 15). Constructed WITHOUT a
/// Tor gate (A9): the Tor-dependent collaborators are lookups resolved at
/// call time, so the local unpair mutation works with Tor down — only
/// pairing itself (and the best-effort wire unpair notify, which the heal
/// pass retries) needs Tor to be up.
@Riverpod(keepAlive: true)
RelayPairingService relayPairingService(Ref ref) {
  final storage = ref.watch(storageServiceProvider);
  return RelayPairingService(
    initiatorLookup: () => ref.read(relayPairingInitiatorProvider),
    pushCoordinatorLookup: () => ref.read(relayPushCoordinatorProvider.future),
    pushServiceLookup: () => ref.read(relayPushServiceProvider),
    crypto: ref.watch(cryptoServiceProvider),
    storage: storage,
    clock: ref.watch(clockProvider),
    identityLookup: storage.getIdentity,
    ownSecretKeyLookup: () => KeychainManager().loadIdentitySecretKey(),
    ownEndpointsLookup: () => ref.read(ownEndpointsProvider),
    reloadPairedRelay: () =>
        ref.read(pairedRelayControllerProvider.notifier).reload(),
  );
}
