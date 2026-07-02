import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../models/connection_card.dart';
import '../services/clock.dart';
import '../services/mdns_service.dart';
import '../services/storage_service.dart';
import '../services/tor_service.dart';
import '../services/types.dart';
import 'concurrency.dart';

/// Per-transport reachability state. Probes drive the transitions:
/// `unknown` -> `probing` -> (`reachable` | `unreachable`). `markUnreachable`
/// from a real request failure flips to `unreachable` immediately.
enum TransportState { unknown, probing, reachable, unreachable }

class TransportStatus {
  const TransportStatus({
    required this.state,
    this.lastChange,
    this.consecutiveFailures = 0,
    this.lastError,
    this.endpointHint,
  });
  final TransportState state;
  final DateTime? lastChange;
  final int consecutiveFailures;
  final String? lastError;
  // baseUrl associated with the most recent successful probe. Used by
  // `bestConnectionFor` to construct the `PeerConnection` that callers
  // dial.
  final String? endpointHint;

  TransportStatus copyWith({
    TransportState? state,
    DateTime? lastChange,
    int? consecutiveFailures,
    String? lastError,
    String? endpointHint,
    bool clearEndpoint = false,
  }) => TransportStatus(
    state: state ?? this.state,
    lastChange: lastChange ?? this.lastChange,
    consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
    lastError: lastError ?? this.lastError,
    endpointHint: clearEndpoint ? null : (endpointHint ?? this.endpointHint),
  );
}

class PeerReachability {
  const PeerReachability({required this.pubkey, required this.transports});
  final String pubkey;
  final Map<PeerTransport, TransportStatus> transports;

  /// True when any transport currently probes reachable. The canonical
  /// "can I talk to this peer right now" predicate — consumers must not
  /// derive their own (the mDNS-only variant of this is exactly how the
  /// feed ended up saying "Offline" while Tor sync worked fine).
  bool get isReachable =>
      transports.values.any((s) => s.state == TransportState.reachable);
}

/// Centralized peer reachability state machine + probe loop.
///
/// Replaces the per-consumer LAN→Tor cascades from Plan 11b with a single
/// background monitor. Probes each known follow's candidate transports
/// (LAN via mDNS, Tor via stored onion endpoint) every [probeInterval] and
/// on demand. Consumers ask `bestConnectionFor(pubkey)` to get the
/// currently-validated best transport without ever touching a stale
/// endpoint.
class PeerReachabilityMonitor {
  PeerReachabilityMonitor({
    required MdnsService mdns,
    required TorService tor,
    required StorageService storage,
    required http.Client lanProbeClient,
    required http.Client? Function() torProbeClient,
    required Clock clock,
    Duration probeInterval = const Duration(seconds: 60),
    Duration probeTimeout = const Duration(seconds: 5),
    Duration torProbeTimeout = const Duration(seconds: 15),
    Duration firstCallWindow = const Duration(seconds: 5),
  }) : _mdns = mdns,
       _tor = tor,
       _storage = storage,
       _lanProbeClient = lanProbeClient,
       _torProbeClient = torProbeClient,
       _clock = clock,
       _probeInterval = probeInterval,
       _probeTimeout = probeTimeout,
       _torProbeTimeout = torProbeTimeout,
       _firstCallWindow = firstCallWindow;

  final MdnsService _mdns;
  final TorService _tor;
  final StorageService _storage;
  final http.Client _lanProbeClient;
  final http.Client? Function() _torProbeClient;
  // ignore: unused_field
  final Clock _clock;
  final Duration _probeInterval;
  final Duration _probeTimeout;
  final Duration _torProbeTimeout;
  final Duration _firstCallWindow;

  // Transport priority order — first reachable wins. LAN beats libp2p
  // when we're on the same network (no NAT, lowest latency). libp2p-direct
  // (Plan 11a) beats Relay and Tor when DCUtR hole-punching succeeds —
  // Always prefer a phone↔phone path when one is reachable: LAN first
  // (QUIC over UDP is multi-second faster than Tor circuits), then
  // libp2p direct, then the Owner's own onion. The Relay is the last
  // resort — it only wins when every phone↔phone tier is unreachable
  // (phone asleep/offline). Preferring the phone keeps content fresh
  // (the Relay v1 can't serve feed-key rotations) and avoids leaking
  // Follower access patterns to the always-on box.
  //
  // Selection only ever runs over transports the probe loop has already
  // marked reachable, so ranking Tor above Relay never stalls on an
  // asleep phone — an unreachable phone simply isn't a candidate.
  static const List<PeerTransport> _priority = [
    PeerTransport.lan,
    PeerTransport.libp2pDirect,
    PeerTransport.tor,
    PeerTransport.relay,
  ];

  static const List<int> _backoffSeconds = [10, 30, 60, 120];

  final Map<String, PeerReachability> _state = {};
  final Map<(String, PeerTransport), Timer> _backoffTimers = {};
  final Map<(String, PeerTransport), Future<bool>> _inflightProbes = {};
  final Pool _probePool = Pool(5);

  /// Plan 11d — passive liveness probe over an already-promoted libp2p
  /// connection. Installed by `LifecycleManager` via [bindLibp2pProbe]
  /// after `Libp2pNetworkService` is constructed. Lives outside the
  /// constructor to avoid an import cycle with `sync_provider.dart`. Null
  /// during tests and on platforms where libp2p is the stub.
  Future<void> Function(PeerConnection)? _libp2pProbe;

  /// Per-pubkey timestamp (unix ms) of the most recent passive ping. Used
  /// to keep ping cadence proportional to the configured probe interval
  /// rather than firing on every monitor tick.
  final Map<String, int> _lastLibp2pPingMs = {};

  static const Duration _libp2pPingTimeout = Duration(seconds: 3);

  final StreamController<Map<String, PeerReachability>> _stateCtrl =
      StreamController<Map<String, PeerReachability>>.broadcast();

  Timer? _periodicTimer;
  StreamSubscription<Map<String, LanPeer>>? _mdnsSub;
  bool _running = false;

  Stream<Map<String, PeerReachability>> get stateStream => _stateCtrl.stream;

  Map<String, PeerReachability> get state => Map.unmodifiable(_state);

  Future<void> start() async {
    if (_running) return;
    _running = true;
    await _seedFromFollows();
    _mdnsSub = _mdns.peers.listen((_) {
      // mDNS topology changed: re-probe LAN for any peer we know about.
      // Cheap — only LAN, only follows. Catches "peer just appeared" and
      // "peer disappeared" without waiting for the next periodic tick.
      unawaited(_probeAll(transports: const [PeerTransport.lan]));
    });
    _periodicTimer = Timer.periodic(_probeInterval, (_) {
      unawaited(_probeAll());
    });
    unawaited(_probeAll());
  }

  Future<void> stop() async {
    _running = false;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    await _mdnsSub?.cancel();
    _mdnsSub = null;
    for (final t in _backoffTimers.values) {
      t.cancel();
    }
    _backoffTimers.clear();
    _inflightProbes.clear();
    _lastLibp2pPingMs.clear();
    if (!_stateCtrl.isClosed) await _stateCtrl.close();
  }

  /// Returns the best currently-validated `PeerConnection` for [pubkey],
  /// or `null` if nothing is reachable. May briefly wait for probes
  /// already in flight (capped at [firstCallWindow]).
  Future<PeerConnection?> bestConnectionFor(String pubkey) async {
    _ensurePeerEntry(pubkey);

    final immediate = _pickReachable(pubkey);
    if (immediate != null) return immediate;

    final follow = await _storage.getFollow(pubkey);
    final probes = <Future<bool>>[];
    for (final transport in _priority) {
      // See _probeAll — libp2pDirect (Plan 11a) is upgrader-promoted only.
      if (transport == PeerTransport.libp2pDirect) continue;
      final status = _state[pubkey]!.transports[transport]!;
      if (status.state == TransportState.unknown ||
          status.state == TransportState.probing) {
        probes.add(_probePeer(pubkey, transport, follow));
      }
    }

    if (probes.isEmpty) return null;

    try {
      await _firstSuccessOrAll(probes).timeout(_firstCallWindow);
    } on TimeoutException {
      // Fall through — best-effort lookup with whatever has resolved.
    }

    return _pickReachable(pubkey);
  }

  /// One-shot probe of a freshly-supplied [card]. Used by the QR-handshake
  /// flow before a Follow row exists. Doesn't update internal state.
  ///
  /// Tor-only: friend-add must not leak the requester's LAN address to
  /// arbitrary scanned cards, and `lan-direct` hints are unreliable across
  /// NATs (e.g. Android emulator's 10.0.2.0/24 subnet).
  Future<PeerConnection?> probeCard(ConnectionCard card) async {
    final onion = card.endpoints.firstWhere(
      (e) => e.type == 'onion',
      orElse: () => const Endpoint(type: '', address: ''),
    );
    if (onion.type.isEmpty) {
      _log(
        'probeCard pubkey=${card.pubkey} result=no-onion-in-card '
        'endpoint_types=${card.endpoints.map((e) => e.type).toList()}',
      );
      return null;
    }
    if (!_tor.isReady || _torProbeClient() == null) {
      _log(
        'probeCard pubkey=${card.pubkey} result=tor-not-ready '
        'isReady=${_tor.isReady} clientNull=${_torProbeClient() == null}',
      );
      return null;
    }
    final url = httpBaseUrlForAddress(onion.address);
    _log('probeCard pubkey=${card.pubkey} dialing url=$url');
    final result = await _oneShotProbe(card.pubkey, url, PeerTransport.tor);
    _log(
      'probeCard pubkey=${card.pubkey} url=$url '
      'result=${result == null ? "unreachable" : "ok"}',
    );
    return result;
  }

  /// Manually re-probes every known follow on every transport. Used by
  /// the connection-status settings screen so users troubleshooting can
  /// force a refresh without waiting for the periodic tick.
  Future<void> refreshNow() => _probeAll();

  /// Plan 11d — install the libp2p passive-ping callback. Called once by
  /// `LifecycleManager` after `Libp2pNetworkService` is built. Until this
  /// is called, the libp2p branch in [_probeAll] is a no-op (matching the
  /// pre-11d "upgrader-promoted only, never demoted by monitor" behavior).
  /// Idempotent — re-binding is safe across resumes.
  void bindLibp2pProbe(Future<void> Function(PeerConnection) probe) {
    _libp2pProbe = probe;
  }

  /// Caller (e.g., [Libp2pUpgrader] in Plan 11a after a successful DCUtR
  /// upgrade) signals that [transport] for [pubkey] is now reachable via
  /// [baseUrl]. Promotes the transport so the next `bestConnectionFor`
  /// call picks it. Idempotent — re-calling with the same args is cheap.
  void markReachable(String pubkey, PeerTransport transport, String baseUrl) {
    _ensurePeerEntry(pubkey);
    _updateStatus(
      pubkey,
      transport,
      (cur) => cur.copyWith(
        state: TransportState.reachable,
        lastChange: DateTime.now(),
        consecutiveFailures: 0,
        endpointHint: baseUrl,
      ),
    );
    _backoffTimers.remove((pubkey, transport))?.cancel();
  }

  /// Caller (sync engine, media fetcher, follow service) signals that a
  /// real request through [transport] for [pubkey] failed. Marks
  /// unreachable and schedules a backoff re-probe so subsequent calls
  /// route around the dead transport without waiting for the next
  /// periodic tick.
  void markUnreachable(String pubkey, PeerTransport transport, Object reason) {
    _ensurePeerEntry(pubkey);
    _updateStatus(
      pubkey,
      transport,
      (cur) => cur.copyWith(
        state: TransportState.unreachable,
        lastChange: DateTime.now(),
        consecutiveFailures: cur.consecutiveFailures + 1,
        lastError: reason.toString(),
        clearEndpoint: true,
      ),
    );
    _scheduleBackoff(pubkey, transport);
  }

  // --- internals ---

  Future<void> _seedFromFollows() async {
    final follows = await _storage.getFollows();
    for (final f in follows) {
      _ensurePeerEntry(f.pubkey);
    }
    _emit();
  }

  void _ensurePeerEntry(String pubkey) {
    _state.putIfAbsent(
      pubkey,
      () => const PeerReachability(pubkey: '', transports: {})._init(pubkey),
    );
  }

  PeerConnection? _pickReachable(String pubkey) {
    final p = _state[pubkey];
    if (p == null) return null;
    for (final transport in _priority) {
      final status = p.transports[transport];
      if (status?.state == TransportState.reachable &&
          status?.endpointHint != null) {
        return PeerConnection(
          pubkey: pubkey,
          baseUrl: status!.endpointHint!,
          transport: transport,
        );
      }
    }
    return null;
  }

  Future<void> _probeAll({List<PeerTransport>? transports}) async {
    if (!_running) return;
    final follows = await _storage.getFollows();
    final list = transports ?? _priority;
    final tasks = <Future<void>>[];
    for (final f in follows) {
      _ensurePeerEntry(f.pubkey);
      for (final transport in list) {
        // libp2pDirect (Plan 11a) is never *probed up* by the monitor —
        // promotion is the upgrader's job because the only way to verify
        // reachability is to run the full signaling + simultaneous-open
        // dance. Plan 11d adds a passive liveness ping over an already-
        // promoted connection so a silently-killed v6 mapping is caught
        // on the monitor's cadence rather than waiting for the next real
        // sync request to fail.
        if (transport == PeerTransport.libp2pDirect) {
          final status = _state[f.pubkey]!.transports[transport]!;
          if (status.state != TransportState.reachable) continue;
          tasks.add(
            _probePool.run(() => _passivePingLibp2p(f.pubkey).then((_) {})),
          );
          continue;
        }
        tasks.add(
          _probePool.run(() => _probePeer(f.pubkey, transport, f).then((_) {})),
        );
      }
    }
    await Future.wait(tasks, eagerError: false);
  }

  Future<bool> _probePeer(
    String pubkey,
    PeerTransport transport,
    Follow? follow,
  ) async {
    final key = (pubkey, transport);
    final existing = _inflightProbes[key];
    if (existing != null) return existing;

    final url = _candidateUrl(pubkey, transport, follow);
    if (url == null) {
      _updateStatus(
        pubkey,
        transport,
        (cur) => cur.copyWith(
          state: TransportState.unreachable,
          lastChange: DateTime.now(),
          clearEndpoint: true,
        ),
      );
      return false;
    }

    _updateStatus(
      pubkey,
      transport,
      (cur) => cur.copyWith(state: TransportState.probing),
    );

    final completer = Completer<bool>();
    _inflightProbes[key] = completer.future;

    bool ok = false;
    try {
      ok = await _executeProbe(pubkey, url, useTor: transport.dialsViaTor);
    } catch (_) {
      ok = false;
    }

    _updateStatus(
      pubkey,
      transport,
      (cur) => cur.copyWith(
        state: ok ? TransportState.reachable : TransportState.unreachable,
        lastChange: DateTime.now(),
        consecutiveFailures: ok ? 0 : cur.consecutiveFailures + 1,
        endpointHint: ok ? url : null,
        clearEndpoint: !ok,
      ),
    );

    if (!ok) {
      _scheduleBackoff(pubkey, transport);
    } else {
      _backoffTimers.remove(key)?.cancel();
    }

    _inflightProbes.remove(key)?.ignore();
    completer.complete(ok);
    return ok;
  }

  String? _candidateUrl(
    String pubkey,
    PeerTransport transport,
    Follow? follow,
  ) {
    if (transport == PeerTransport.lan) {
      final peer = _mdns.currentPeers()[pubkey];
      if (peer == null) return null;
      return 'http://${peer.host}:${peer.port}';
    }
    if (transport == PeerTransport.tor) {
      if (!_tor.isReady) return null;
      if (follow == null) return null;
      final card = _parseCard(follow.connectionCard);
      if (card == null) return null;
      final onion = card.endpoints.firstWhere(
        (e) => e.type == 'onion',
        orElse: () => const Endpoint(type: '', address: ''),
      );
      if (onion.type.isEmpty) return null;
      return httpBaseUrlForAddress(onion.address);
    }
    if (transport == PeerTransport.relay) {
      // Relay endpoints are onion addresses too — they ride the same Tor
      // SOCKS5 client. The only difference vs the direct-Tor tier is
      // which endpoint type we pull from the Connection card.
      if (!_tor.isReady) return null;
      if (follow == null) return null;
      final card = _parseCard(follow.connectionCard);
      if (card == null) return null;
      final relay = card.endpoints.firstWhere(
        (e) => e.type == 'relay',
        orElse: () => const Endpoint(type: '', address: ''),
      );
      if (relay.type.isEmpty) return null;
      return httpBaseUrlForAddress(relay.address);
    }
    return null;
  }

  ConnectionCard? _parseCard(String raw) {
    if (raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return ConnectionCard.fromMap(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _executeProbe(
    String expectedPubkey,
    String baseUrl, {
    required bool useTor,
  }) async {
    final client = useTor ? _torProbeClient() : _lanProbeClient;
    if (client == null) {
      _log('probe $baseUrl client=null useTor=$useTor');
      return false;
    }
    final timeout = useTor ? _torProbeTimeout : _probeTimeout;
    try {
      final res = await client
          .get(Uri.parse('$baseUrl/status'))
          .timeout(timeout);
      if (res.statusCode != 200) {
        _log('probe $baseUrl -> ${res.statusCode}');
        return false;
      }
      final body = jsonDecode(res.body);
      if (body is! Map) {
        _log('probe $baseUrl bad-body type=${body.runtimeType}');
        return false;
      }
      final pk = body['pubkey'];
      if (pk != expectedPubkey) {
        _log('probe $baseUrl pubkey-mismatch expected=$expectedPubkey got=$pk');
        return false;
      }
      _log('probe $baseUrl ok');
      return true;
    } catch (e) {
      _log(
        'probe $baseUrl failed (useTor=$useTor timeout=${timeout.inSeconds}s): $e',
      );
      return false;
    }
  }

  void _log(String msg) {
    developer.log(msg, name: 'starling.reachability');
    // Mirror to stdout so the line shows up in `flutter run` output; matches
    // the dual-channel pattern used by `[starling.tor]` and
    // `[starling.keychain]`. Keep it terse — this is per-probe.
    // ignore: avoid_print
    print('[starling.reachability] $msg');
  }

  /// Plan 11d — passive liveness probe over an already-promoted libp2p
  /// connection. Caller must have verified the transport is currently
  /// `reachable` (state machine never *promotes* libp2pDirect from here —
  /// that's the upgrader's job). On ping failure, marks unreachable; the
  /// next sync engine pump fires `Libp2pUpgrader.tryUpgrade` on a Tor-
  /// resolved attempt.
  Future<void> _passivePingLibp2p(String pubkey) async {
    final probe = _libp2pProbe;
    if (probe == null) return;
    final status = _state[pubkey]?.transports[PeerTransport.libp2pDirect];
    if (status == null || status.state != TransportState.reachable) return;
    final hint = status.endpointHint;
    if (hint == null) return;

    // Rate-limit relative to the configured probe interval. Monitor ticks
    // are 60s by default, so this is effectively "at most once per tick";
    // the guard exists for callers (e.g. mdns peer-changed re-probe) that
    // can fire the loop more often.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final last = _lastLibp2pPingMs[pubkey];
    if (last != null && nowMs - last < _probeInterval.inMilliseconds ~/ 2) {
      return;
    }
    _lastLibp2pPingMs[pubkey] = nowMs;

    final connection = PeerConnection(
      pubkey: pubkey,
      baseUrl: hint,
      transport: PeerTransport.libp2pDirect,
    );
    try {
      await probe(connection).timeout(_libp2pPingTimeout);
    } catch (e) {
      _log('libp2p passive ping failed for $pubkey: $e — demoting transport');
      markUnreachable(pubkey, PeerTransport.libp2pDirect, e);
    }
  }

  Future<PeerConnection?> _oneShotProbe(
    String pubkey,
    String baseUrl,
    PeerTransport transport,
  ) async {
    final ok = await _executeProbe(
      pubkey,
      baseUrl,
      useTor: transport.dialsViaTor,
    );
    return ok
        ? PeerConnection(pubkey: pubkey, baseUrl: baseUrl, transport: transport)
        : null;
  }

  void _scheduleBackoff(String pubkey, PeerTransport transport) {
    // libp2pDirect (Plan 11a) re-attempts are driven by SyncEngine's normal
    // sync cycle through [Libp2pUpgrader]; scheduling a backoff probe here
    // would call _probePeer with a null candidate URL and re-mark unreachable
    // immediately — pointless churn. The sync engine's own 60s+ pump is the
    // de-facto backoff.
    if (transport == PeerTransport.libp2pDirect) return;
    final key = (pubkey, transport);
    _backoffTimers.remove(key)?.cancel();
    final fails = _state[pubkey]!.transports[transport]!.consecutiveFailures;
    final idx = (fails - 1).clamp(0, _backoffSeconds.length - 1);
    final delay = Duration(seconds: _backoffSeconds[idx]);
    _backoffTimers[key] = Timer(delay, () async {
      if (!_running) return;
      final follow = await _storage.getFollow(pubkey);
      await _probePeer(pubkey, transport, follow);
    });
  }

  void _updateStatus(
    String pubkey,
    PeerTransport transport,
    TransportStatus Function(TransportStatus current) updater,
  ) {
    final cur = _state[pubkey]!.transports[transport]!;
    final updated = updater(cur);
    final newTransports = Map<PeerTransport, TransportStatus>.from(
      _state[pubkey]!.transports,
    )..[transport] = updated;
    _state[pubkey] = PeerReachability(
      pubkey: pubkey,
      transports: newTransports,
    );
    _emit();
  }

  void _emit() {
    if (_stateCtrl.isClosed) return;
    _stateCtrl.add(Map.unmodifiable(_state));
  }

  /// Resolves when the first probe in [probes] reports success, or when
  /// every probe has finished (whichever comes first). Errors from
  /// individual probes are treated as failures, not cancellations.
  Future<void> _firstSuccessOrAll(List<Future<bool>> probes) {
    final completer = Completer<void>();
    var pending = probes.length;
    void onResult(bool ok) {
      if (ok && !completer.isCompleted) {
        completer.complete();
        return;
      }
      pending--;
      if (pending == 0 && !completer.isCompleted) {
        completer.complete();
      }
    }

    for (final p in probes) {
      p.then(onResult, onError: (Object _) => onResult(false));
    }
    return completer.future;
  }
}

extension on PeerReachability {
  PeerReachability _init(String pubkey) => PeerReachability(
    pubkey: pubkey,
    transports: const {
      PeerTransport.lan: TransportStatus(state: TransportState.unknown),
      PeerTransport.libp2pDirect: TransportStatus(
        state: TransportState.unknown,
      ),
      PeerTransport.relay: TransportStatus(state: TransportState.unknown),
      PeerTransport.tor: TransportStatus(state: TransportState.unknown),
    },
  );
}
