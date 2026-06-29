import 'package:http/http.dart' as http;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../providers/service_providers.dart';
import '../services/tor/tor_http_client.dart';
import 'peer_reachability_monitor.dart';

part 'peer_reachability_provider.g.dart';

/// Singleton [PeerReachabilityMonitor]. Kept alive across the app
/// lifecycle so probe state survives screen transitions. `start()` must
/// be invoked once at launch — `main.dart`'s `_StarlingAppState.initState`
/// does that.
@Riverpod(keepAlive: true)
PeerReachabilityMonitor peerReachabilityMonitor(Ref ref) {
  final lanClient = http.Client();

  // Tor probe client mirrors followServiceProvider's pattern: rebuild the
  // wrapper if the SOCKS port changes (rare, only across `tor.shutdown()`
  // + `init`). Returns null until Tor's SOCKS proxy is bound — the
  // monitor treats that as "Tor unavailable for now."
  TorHttpClient? cachedTorClient;
  int cachedSocksPort = 0;
  http.Client? torLookup() {
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

  final monitor = PeerReachabilityMonitor(
    mdns: ref.watch(mdnsServiceProvider),
    tor: ref.watch(torServiceProvider),
    storage: ref.watch(storageServiceProvider),
    lanProbeClient: lanClient,
    torProbeClient: torLookup,
    clock: ref.watch(clockProvider),
  );

  ref.onDispose(() {
    monitor.stop();
    lanClient.close();
    cachedTorClient?.close();
  });

  return monitor;
}

/// Live reachability state keyed by pubkey. Seeded with the monitor's
/// current snapshot so first build doesn't flash empty before the stream
/// emits.
@riverpod
Stream<Map<String, PeerReachability>> peerReachabilityState(Ref ref) async* {
  final monitor = ref.watch(peerReachabilityMonitorProvider);
  yield monitor.state;
  yield* monitor.stateStream;
}
