import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ffi_bindings.dart';

/// Plan 11c — dedicated long-lived worker isolate that owns the
/// `Libp2pBindings` handle and serializes every FFI call.
///
/// Why: native FFI calls are synchronous from Dart's perspective —
/// `runtime.block_on` on the Rust side can block the calling thread for
/// up to 30 seconds (`lp_stream_read`'s timeout), and per-call
/// `Isolate.run` (the arti pattern) carries per-spawn overhead that
/// dominates at libp2p's call rate (~30+ FFI calls per sync pump). A
/// single long-lived worker isolate:
///   * keeps the main UI isolate responsive across the longest possible
///     FFI stall,
///   * gives single-owner FFI access — no two isolates ever touch the
///     opaque handle concurrently, eliminating a class of subtle bugs,
///   * matches the dominant pattern in mature Flutter native plugins
///     (sqflite, isar, drift `NativeDatabase`).
///
/// Event delivery from Rust to Dart is NOT routed through the worker.
/// Each event is posted via `Dart_PostCObject_DL` directly to a
/// `RawReceivePort` registered on the main isolate (the worker passes
/// that port's native port number to `lp_set_event_port` once at init).
/// This keeps event latency at a single isolate hop instead of two.
///
/// Wire format on the worker's `ReceivePort`:
/// ```
/// {
///   'cmd': <String>,
///   'args': <Map<String, dynamic>>,
///   'reply': <SendPort>,
/// }
/// ```
/// The worker dispatches on `cmd`, calls the matching binding, and
/// sends a result map back via `reply`. Convention:
///   * Success: a `Map<String, dynamic>` carrying any return values.
///   * Failure: `{'error': <String>}` — the bridge throws a typed
///     exception based on `cmd`.

/// Entry point for `Isolate.spawn`. Owns the FFI handle for the
/// lifetime of the worker.
void libp2pWorkerEntry(SendPort initSendPort) {
  final receivePort = ReceivePort();
  initSendPort.send(receivePort.sendPort);

  final state = _WorkerState(Libp2pBindings.load());

  receivePort.listen((dynamic message) {
    if (message is! Map) return;
    final cmd = message['cmd'] as String?;
    final args = (message['args'] as Map?)?.cast<String, dynamic>() ?? const {};
    final reply = message['reply'] as SendPort?;
    if (cmd == null || reply == null) return;

    try {
      final result = state.dispatch(cmd, args);
      reply.send(result);
    } catch (e) {
      reply.send({'error': e.toString()});
    }

    if (cmd == 'shutdown') {
      // Bridge requested teardown — close the port so the isolate exits
      // cleanly once the reply has been delivered.
      receivePort.close();
    }
  });
}

class _WorkerState {
  _WorkerState(this._bindings);

  final Libp2pBindings _bindings;
  Pointer<Void> _handle = nullptr;
  String _localPeerId = '';

  Map<String, dynamic> dispatch(String cmd, Map<String, dynamic> args) {
    switch (cmd) {
      case 'init':
        return _init(args);
      case 'listen':
        return _listen();
      case 'observed_addrs':
        return _observedAddrs();
      case 'add_observed_addr':
        return _addObservedAddr(args);
      case 'dial_direct':
        return _dialDirect(args);
      case 'open_stream':
        return _openStream(args);
      case 'stream_write':
        return _streamWrite(args);
      case 'stream_read':
        return _streamRead(args);
      case 'stream_close':
        return _streamClose(args);
      case 'register_inbound_handler':
        return _registerInboundHandler(args);
      case 'local_peer_id':
        return {'local_peer_id': _localPeerId};
      case 'shutdown':
        return _shutdown();
      default:
        return {'error': 'unknown command: $cmd'};
    }
  }

  Map<String, dynamic> _init(Map<String, dynamic> args) {
    if (_handle != nullptr) {
      return {'local_peer_id': _localPeerId};
    }
    final dataDir = args['data_dir'] as String;
    final seed = args['seed'] as Uint8List;
    final eventPort = args['event_port'] as int;

    if (seed.length != 32) {
      return {'error': 'seed must be 32 bytes (got ${seed.length})'};
    }

    final dirPtr = dataDir.toNativeUtf8();
    final seedPtr = malloc.allocate<Uint8>(32);
    try {
      seedPtr.asTypedList(32).setAll(0, seed);
      final postCObject = NativeApi.postCObject.cast<Void>();
      _handle = _bindings.init(dirPtr, seedPtr, 32, postCObject);
    } finally {
      seedPtr.asTypedList(32).fillRange(0, 32, 0);
      malloc.free(seedPtr);
      malloc.free(dirPtr);
    }
    if (_handle == nullptr) {
      return {'error': 'lp_init failed: ${_lastError()}'};
    }

    final pid = _bindings.localPeerId(_handle);
    if (pid != nullptr) {
      _localPeerId = pid.toDartString();
      _bindings.stringFree(pid);
    }

    _bindings.setEventPort(_handle, eventPort);
    return {'local_peer_id': _localPeerId};
  }

  Map<String, dynamic> _listen() {
    if (_handle == nullptr) {
      return {'error': 'init not called'};
    }
    final rc = _bindings.listen(_handle);
    if (rc != Libp2pStatusCode.ok) {
      return {'error': 'lp_listen rc=$rc: ${_lastError()}'};
    }
    return {};
  }

  Map<String, dynamic> _observedAddrs() {
    if (_handle == nullptr) {
      return {'addrs': <Uint8List>[]};
    }
    var bufSize = 4096;
    while (true) {
      final buf = malloc.allocate<Uint8>(bufSize);
      try {
        final n = _bindings.observedAddrs(_handle, buf, bufSize);
        if (n == Libp2pStatusCode.errBufferTooSmall) {
          bufSize *= 2;
          if (bufSize > 1 << 20) {
            return {'error': 'observed addrs too large'};
          }
          continue;
        }
        if (n < 0) {
          return {'error': 'observed_addrs rc=$n: ${_lastError()}'};
        }
        if (n == 0) return {'addrs': const <Uint8List>[]};
        final bytes = Uint8List.fromList(buf.asTypedList(n));
        return {'cbor': bytes};
      } finally {
        malloc.free(buf);
      }
    }
  }

  Map<String, dynamic> _addObservedAddr(Map<String, dynamic> args) {
    if (_handle == nullptr) return {};
    final multiaddr = args['multiaddr'] as Uint8List;
    final ptr = malloc.allocate<Uint8>(multiaddr.length);
    try {
      ptr.asTypedList(multiaddr.length).setAll(0, multiaddr);
      final rc = _bindings.addObservedAddr(_handle, ptr, multiaddr.length);
      if (rc != Libp2pStatusCode.ok) {
        return {'error': 'lp_add_observed_addr rc=$rc: ${_lastError()}'};
      }
    } finally {
      malloc.free(ptr);
    }
    return {};
  }

  Map<String, dynamic> _dialDirect(Map<String, dynamic> args) {
    if (_handle == nullptr) {
      return {'error': 'bridge not initialized'};
    }
    final peerId = args['peer_id'] as String;
    final addrsCbor = args['addrs_cbor'] as Uint8List;
    final timeoutMs = args['timeout_ms'] as int;

    final peerPtr = peerId.toNativeUtf8();
    final addrsPtr = malloc.allocate<Uint8>(addrsCbor.length);
    try {
      addrsPtr.asTypedList(addrsCbor.length).setAll(0, addrsCbor);
      final connId = _bindings.dialDirect(
        _handle,
        peerPtr,
        addrsPtr,
        addrsCbor.length,
        timeoutMs,
      );
      if (connId < 0) {
        return {'error': 'dial rc=$connId: ${_lastError()}'};
      }
      return {'conn_id': connId};
    } finally {
      malloc.free(addrsPtr);
      malloc.free(peerPtr);
    }
  }

  Map<String, dynamic> _openStream(Map<String, dynamic> args) {
    if (_handle == nullptr) {
      return {'error': 'bridge not initialized'};
    }
    final connId = args['conn_id'] as int;
    final protocol = args['protocol'] as String;
    final protoPtr = protocol.toNativeUtf8();
    try {
      final streamId = _bindings.openStream(_handle, connId, protoPtr);
      if (streamId < 0) {
        return {'error': 'open_stream rc=$streamId: ${_lastError()}'};
      }
      return {'stream_id': streamId};
    } finally {
      malloc.free(protoPtr);
    }
  }

  Map<String, dynamic> _streamWrite(Map<String, dynamic> args) {
    if (_handle == nullptr) {
      return {'error': 'bridge not initialized'};
    }
    final streamId = args['stream_id'] as int;
    final data = args['data'] as Uint8List;
    final finish = args['finish'] as bool;
    final ptr = malloc.allocate<Uint8>(data.isEmpty ? 1 : data.length);
    try {
      if (data.isNotEmpty) {
        ptr.asTypedList(data.length).setAll(0, data);
      }
      final rc = _bindings.streamWrite(
        _handle,
        streamId,
        ptr,
        data.length,
        finish,
      );
      if (rc != Libp2pStatusCode.ok) {
        return {'error': 'write rc=$rc: ${_lastError()}'};
      }
    } finally {
      malloc.free(ptr);
    }
    return {};
  }

  Map<String, dynamic> _streamRead(Map<String, dynamic> args) {
    if (_handle == nullptr) {
      return {'error': 'bridge not initialized'};
    }
    final streamId = args['stream_id'] as int;
    final timeoutMs = args['timeout_ms'] as int;
    var bufSize = 64 * 1024;
    while (true) {
      final buf = malloc.allocate<Uint8>(bufSize);
      try {
        final n = _bindings.streamRead(
          _handle,
          streamId,
          buf,
          bufSize,
          timeoutMs,
        );
        if (n == Libp2pStatusCode.errBufferTooSmall) {
          bufSize *= 2;
          if (bufSize > 16 << 20) {
            return {'error': 'frame too large'};
          }
          continue;
        }
        if (n < 0) {
          return {'error': 'read rc=$n: ${_lastError()}'};
        }
        return {'data': Uint8List.fromList(buf.asTypedList(n))};
      } finally {
        malloc.free(buf);
      }
    }
  }

  Map<String, dynamic> _streamClose(Map<String, dynamic> args) {
    if (_handle == nullptr) return {};
    final streamId = args['stream_id'] as int;
    _bindings.streamClose(_handle, streamId);
    return {};
  }

  Map<String, dynamic> _registerInboundHandler(Map<String, dynamic> args) {
    if (_handle == nullptr) return {};
    final protocol = args['protocol'] as String;
    final ptr = protocol.toNativeUtf8();
    try {
      final rc = _bindings.registerInboundHandler(_handle, ptr);
      if (rc != Libp2pStatusCode.ok) {
        return {'error': 'register_inbound_handler rc=$rc: ${_lastError()}'};
      }
    } finally {
      malloc.free(ptr);
    }
    return {};
  }

  Map<String, dynamic> _shutdown() {
    if (_handle != nullptr) {
      _bindings.shutdown(_handle);
      _handle = nullptr;
    }
    _localPeerId = '';
    return {};
  }

  String _lastError() {
    final ptr = _bindings.lastError();
    if (ptr == nullptr) return '';
    try {
      return ptr.toDartString();
    } finally {
      _bindings.stringFree(ptr);
    }
  }
}
