import 'dart:async';
// `dart:ffi` brings the `NativePort` extension on `SendPort` into scope,
// which exposes `.nativePort` (the integer port id) that we hand to the
// worker isolate so Rust can `Dart_PostCObject_DL` directly to this
// isolate without a worker round-trip.
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cbor/simple.dart';

import 'libp2p_bridge_isolate.dart';
import 'libp2p_service.dart';

/// Plan 11a — FFI-backed `Libp2pService`. Drives the
/// `native/libp2p_bridge` Rust crate via the worker isolate defined in
/// `libp2p_bridge_isolate.dart`.
///
/// Plan 11c rewrote this class: every public method is now a `_call`
/// to the worker over `SendPort`s. The main isolate never invokes FFI
/// directly — long-running native calls (`lp_dial_direct` up to 8 s,
/// `lp_stream_read` up to 30 s) cannot freeze the UI. The worker
/// isolate is spawned lazily on the first `init()` and torn down on
/// `shutdown()`.
///
/// Native-Port events bypass the worker entirely. A `RawReceivePort`
/// on this isolate registers with Rust at init time; events posted via
/// `Dart_PostCObject_DL` arrive here without a worker round-trip.
class Libp2pBridge implements Libp2pService {
  Libp2pBridge();

  Isolate? _worker;
  SendPort? _workerSendPort;
  RawReceivePort? _eventPort;
  final _eventCtrl = StreamController<Libp2pEvent>.broadcast();

  /// Live outbound + inbound connections keyed by remote peer.
  /// Populated by `peer_connected` events from Rust so [openStream] can
  /// look up the FFI conn_id (the bridge currently keeps one conn per
  /// peer).
  final Map<String, int> _connByPeer = {};
  final Map<String, void Function(Libp2pStream)> _inboundHandlers = {};
  String _localPeerId = '';
  bool _listening = false;

  @override
  bool get isReady => _workerSendPort != null && _listening;

  @override
  String get localPeerId => _localPeerId;

  @override
  Stream<Libp2pEvent> get events => _eventCtrl.stream;

  // --- worker plumbing ---

  Future<SendPort> _ensureWorker() async {
    final existing = _workerSendPort;
    if (existing != null) return existing;
    final init = ReceivePort();
    _worker = await Isolate.spawn(
      libp2pWorkerEntry,
      init.sendPort,
      debugName: 'libp2p-bridge-worker',
    );
    final sendPort = await init.first as SendPort;
    init.close();
    _workerSendPort = sendPort;
    return sendPort;
  }

  Future<Map<String, dynamic>> _call(
    String cmd,
    Map<String, dynamic> args,
  ) async {
    final worker = await _ensureWorker();
    final reply = ReceivePort();
    worker.send({'cmd': cmd, 'args': args, 'reply': reply.sendPort});
    final result = await reply.first;
    reply.close();
    return (result as Map).cast<String, dynamic>();
  }

  // --- Libp2pService impl ---

  @override
  Future<void> init(String dataDir, Uint8List ed25519Seed) async {
    if (ed25519Seed.length != 32) {
      throw const Libp2pUnavailableException('seed must be 32 bytes');
    }
    // Register the event port on THIS isolate before init, so the worker
    // can hand its `native port` integer to Rust during lp_init/setEventPort.
    // Events therefore arrive here directly — no worker round-trip.
    _eventPort ??= RawReceivePort(_onEvent);

    final result = await _call('init', {
      'data_dir': dataDir,
      'seed': ed25519Seed,
      'event_port': _eventPort!.sendPort.nativePort,
    });
    final err = result['error'];
    if (err is String) {
      throw Libp2pUnavailableException(err);
    }
    _localPeerId = (result['local_peer_id'] as String?) ?? '';
  }

  @override
  Future<void> listen() async {
    final result = await _call('listen', const {});
    final err = result['error'];
    if (err is String) {
      throw Libp2pUnavailableException(err);
    }
    _listening = true;
  }

  @override
  Future<List<Uint8List>> observedAddrs() async {
    if (_workerSendPort == null) return const [];
    final result = await _call('observed_addrs', const {});
    final err = result['error'];
    if (err is String) {
      throw Libp2pUnavailableException(err);
    }
    final cbor = result['cbor'];
    if (cbor is! Uint8List) {
      return const [];
    }
    return _decodeMultiaddrList(cbor);
  }

  @override
  Future<void> addObservedAddr(Uint8List multiaddr) async {
    if (_workerSendPort == null) return;
    final result = await _call('add_observed_addr', {'multiaddr': multiaddr});
    final err = result['error'];
    if (err is String) {
      throw Libp2pUnavailableException(err);
    }
  }

  @override
  Future<void> dialDirect(
    String remotePeerId,
    List<Uint8List> remoteAddrs, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_workerSendPort == null) {
      throw const Libp2pDialException('bridge not initialized');
    }
    final addrsCbor = _encodeMultiaddrList(remoteAddrs);
    final result = await _call('dial_direct', {
      'peer_id': remotePeerId,
      'addrs_cbor': addrsCbor,
      'timeout_ms': timeout.inMilliseconds,
    });
    final err = result['error'];
    if (err is String) {
      throw Libp2pDialException(err);
    }
    final connId = result['conn_id'] as int;
    _connByPeer[remotePeerId] = connId;
  }

  @override
  Future<Libp2pStream> openStream(String remotePeerId, String protocol) async {
    if (_workerSendPort == null) {
      throw const Libp2pStreamException('bridge not initialized');
    }
    final connId = _connByPeer[remotePeerId];
    if (connId == null) {
      throw Libp2pStreamException(
        'no live connection to $remotePeerId — dial first',
      );
    }
    final result = await _call('open_stream', {
      'conn_id': connId,
      'protocol': protocol,
    });
    final err = result['error'];
    if (err is String) {
      throw Libp2pStreamException(err);
    }
    final streamId = result['stream_id'] as int;
    return _WorkerStream(
      bridge: this,
      streamId: streamId,
      remotePeerId: remotePeerId,
      protocol: protocol,
    );
  }

  @override
  void registerInboundHandler(
    String protocol,
    void Function(Libp2pStream stream) handler,
  ) {
    _inboundHandlers[protocol] = handler;
    // Fire-and-forget — the worker registration is idempotent on the
    // Rust side and synchronous in practice. We don't surface errors
    // through the void return; if the registration fails the Rust
    // side will reset the inbound stream and the consumer never sees
    // it. (Mirrors the pre-Plan-11c behaviour.)
    unawaited(_call('register_inbound_handler', {'protocol': protocol}));
  }

  @override
  Future<void> shutdown() async {
    final hadWorker = _workerSendPort != null;
    if (hadWorker) {
      await _call('shutdown', const {});
    }
    _workerSendPort = null;
    _worker?.kill(priority: Isolate.immediate);
    _worker = null;
    _eventPort?.close();
    _eventPort = null;
    // Drop in-memory state that pointed at the now-defunct native handle.
    // Leaving these populated across a shutdown → init cycle would
    // produce stale `connId`s / handler entries that point at swarm
    // objects the Rust side already dropped.
    _connByPeer.clear();
    _inboundHandlers.clear();
    _localPeerId = '';
    // `_eventCtrl` is intentionally NOT closed — the bridge is a
    // keep-alive Riverpod singleton; LifecycleManager calls
    // shutdown/init across every foreground/background cycle, and
    // consumers subscribed to `events` expect to keep receiving after
    // resume. The controller dies with the process.
    _listening = false;
  }

  // --- event-port handling (events arrive directly from Rust, NOT via
  // the worker isolate) ---

  void _onEvent(dynamic message) {
    if (message is! Uint8List) return;
    final decoded = cbor.decode(message);
    if (decoded is! Map) return;
    final type = decoded['type'];
    switch (type) {
      case 'peer_connected':
        final peerId = decoded['peer_id'] as String;
        _eventCtrl.add(Libp2pPeerConnected(peerId: peerId));
        break;
      case 'peer_disconnected':
        final peerId = decoded['peer_id'] as String;
        _connByPeer.remove(peerId);
        _eventCtrl.add(Libp2pPeerDisconnected(peerId: peerId));
        break;
      case 'identify_received':
        final peerId = decoded['peer_id'] as String;
        final observed = _asBytes(decoded['observed_addr']);
        final listen = (decoded['listen_addrs'] as List? ?? const [])
            .map(_asBytes)
            .toList(growable: false);
        _eventCtrl.add(
          Libp2pIdentifyReceived(
            peerId: peerId,
            observedAddr: observed,
            listenAddrs: listen,
          ),
        );
        break;
      case 'observed_addr_changed':
        final ma = _asBytes(decoded['multiaddr']);
        _eventCtrl.add(Libp2pObservedAddrChanged(multiaddr: ma));
        break;
      case 'inbound_stream':
        _dispatchInbound(decoded);
        break;
    }
  }

  void _dispatchInbound(Map<dynamic, dynamic> decoded) {
    final protocol = decoded['protocol'] as String;
    final streamId = (decoded['stream_id'] as int);
    final peerId = decoded['peer_id'] as String;
    final handler = _inboundHandlers[protocol];
    if (handler == null) return;
    final stream = _WorkerStream(
      bridge: this,
      streamId: streamId,
      remotePeerId: peerId,
      protocol: protocol,
    );
    handler(stream);
  }
}

class _WorkerStream implements Libp2pStream {
  _WorkerStream({
    required this.bridge,
    required this.streamId,
    required this.remotePeerId,
    required this.protocol,
  });

  final Libp2pBridge bridge;
  final int streamId;
  @override
  final String remotePeerId;
  @override
  final String protocol;

  bool _closed = false;

  @override
  Future<void> write(Uint8List data, {bool finish = false}) async {
    if (_closed) {
      throw const Libp2pStreamException('stream closed');
    }
    final result = await bridge._call('stream_write', {
      'stream_id': streamId,
      'data': data,
      'finish': finish,
    });
    final err = result['error'];
    if (err is String) {
      throw Libp2pStreamException(err);
    }
    if (finish) _closed = true;
  }

  @override
  Future<Uint8List> read({Duration? timeout}) async {
    if (_closed) {
      throw const Libp2pStreamException('stream closed');
    }
    final ms = timeout?.inMilliseconds ?? 30000;
    final result = await bridge._call('stream_read', {
      'stream_id': streamId,
      'timeout_ms': ms,
    });
    final err = result['error'];
    if (err is String) {
      throw Libp2pStreamException(err);
    }
    return result['data'] as Uint8List;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await bridge._call('stream_close', {'stream_id': streamId});
  }
}

Uint8List _asBytes(dynamic v) {
  if (v is Uint8List) return v;
  if (v is List<int>) return Uint8List.fromList(v);
  return Uint8List(0);
}

Uint8List _encodeMultiaddrList(List<Uint8List> addrs) {
  return Uint8List.fromList(cbor.encode(addrs));
}

List<Uint8List> _decodeMultiaddrList(Uint8List bytes) {
  final decoded = cbor.decode(bytes);
  if (decoded is! List) return const [];
  return decoded.map(_asBytes).toList(growable: false);
}
