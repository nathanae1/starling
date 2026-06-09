import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/connection_card.dart';
import '../services/crypto/key_rotation_service.dart';
import '../services/follow_service.dart';
import '../services/storage/keychain_manager.dart';
import '../services/tor/tor_http_client.dart';
import '../sync/peer_reachability_provider.dart';
import 'identity_provider.dart';
import 'relay_providers.dart';
import 'service_providers.dart';

part 'follow_provider.g.dart';

/// Endpoints we currently advertise to peers. Tor-only: friend-add and
/// the connection cards that ride inside follow-request payloads must
/// not carry LAN hints, both to avoid leaking the local address and
/// because LAN-direct addresses are unreliable across NATs (e.g. Android
/// emulator's 10.0.2.0/24). Returns an empty list until Arti has
/// published our onion service — callers (QR sheet, follow request) gate
/// their UX on that.
///
/// Plan 15: once the Owner pairs a relay, its `.onion` is appended as a
/// `type:'relay'` endpoint. Followers rank it last (phone-onion first),
/// so it only carries traffic when the phone is unreachable.
@riverpod
List<Endpoint> ownEndpoints(Ref ref) {
  final onion = ref.watch(onionAddressProvider);
  if (onion == null) return const [];
  final endpoints = [Endpoint(type: 'onion', address: '$onion:80')];
  final relay = ref.watch(pairedRelayControllerProvider).value;
  if (relay != null) {
    endpoints.add(Endpoint(type: 'relay', address: '${relay.relayOnion}:80'));
  }
  return endpoints;
}

/// Singleton [KeyRotationService] (Plan 13) — generates a new feed key on
/// follower removal and queues per-follower wrapped distributions.
@riverpod
KeyRotationService keyRotationService(Ref ref) {
  return KeyRotationService(
    crypto: ref.watch(cryptoServiceProvider),
    contentKey: ref.watch(contentKeyServiceProvider),
    storage: ref.watch(storageServiceProvider),
    clock: ref.watch(clockProvider),
    feedKeyCache: ref.watch(feedKeyCacheProvider),
    publishLock: ref.watch(publishLockProvider),
    ownSecretKeyLookup: _loadSecretKey,
  );
}

/// Singleton [FollowService] for the running app. Constructs the real
/// HTTP transport, wires identity / secret-key lookups, and points the
/// service at the live storage + crypto. Handshake requests to `.onion`
/// endpoints route through Arti's SOCKS5 proxy via [TorHttpClient]; LAN
/// endpoints continue to use the default `http.Client`.
@Riverpod(keepAlive: true)
FollowService followService(Ref ref) {
  final crypto = ref.watch(cryptoServiceProvider);
  final storage = ref.watch(storageServiceProvider);
  final clock = ref.watch(clockProvider);
  final httpClient = http.Client();
  ref.onDispose(httpClient.close);

  // Cache one Tor client per SOCKS port. The lookup runs on every send,
  // so we read TorService synchronously and rebuild the wrapper only
  // when the port changes (rare — only across `tor.shutdown()`+`init`).
  TorHttpClient? cachedTorClient;
  int cachedSocksPort = 0;
  http.Client? torClientLookup() {
    final tor = ref.read(torServiceProvider);
    final port = tor.socksPort;
    if (port == 0) return null;
    if (port != cachedSocksPort) {
      cachedTorClient?.close();
      cachedTorClient = TorHttpClient(socksHost: '127.0.0.1', socksPort: port);
      cachedSocksPort = port;
    }
    return cachedTorClient;
  }

  ref.onDispose(() => cachedTorClient?.close());

  return FollowService(
    crypto: crypto,
    storage: storage,
    clock: clock,
    transport: HandshakeTransport(httpClient, torClient: torClientLookup),
    reachabilityMonitor: ref.watch(peerReachabilityMonitorProvider),
    identityLookup: storage.getIdentity,
    ownSecretKeyLookup: _loadSecretKey,
    ownEndpointsLookup: () async {
      // Reads the latest endpoints lazily so we don't hold a stale capture.
      return ref.read(ownEndpointsProvider);
    },
    feedKeyCache: ref.watch(feedKeyCacheProvider),
    keyRotationService: ref.watch(keyRotationServiceProvider),
  );
}

Future<Uint8List?> _loadSecretKey() async {
  final keychain = KeychainManager();
  final encoded = await keychain.read(KeychainManager.identitySecretKeyName);
  if (encoded == null) return null;
  return Uint8List.fromList(base64Decode(encoded));
}

/// Convenience: assemble the connection card we share via QR. Returns
/// `null` until the onion endpoint is available so the QR sheet can show
/// a loading state instead of publishing a card with no reachable
/// transport.
@riverpod
ConnectionCard? ownConnectionCard(Ref ref) {
  final identityAsync = ref.watch(identityControllerProvider);
  final identity = identityAsync.value;
  if (identity == null) return null;
  final endpoints = ref.watch(ownEndpointsProvider);
  if (endpoints.isEmpty) return null;
  return ConnectionCard(pubkey: identity.pubkey, endpoints: endpoints);
}
