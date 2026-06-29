import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Hand-written bindings to `native/libp2p_bridge/include/libp2p_bridge.h`.
/// Layouts here MUST match the `#[repr(C)]` types in `libp2p_bridge/src/lib.rs`.
///
/// On Android the shared library `libp2p_bridge.so` is loaded by name from
/// the per-arch `jniLibs/` directory; on iOS the static
/// `libp2p_bridge.xcframework` is linked into the app binary, so we resolve
/// symbols from `process()`. Note: the artifact name dropped the leading
/// `lib` in Plan 11b so the CocoaPods-derived `-l"p2p_bridge"` flag resolves
/// to `libp2p_bridge.a` inside the xcframework.
///
/// Plan 11a — direct-connect transport tier via rust-libp2p (DCUtR + QUIC +
/// Noise + yamux + Identify). The FFI shape mirrors `arti_bridge` (opaque
/// handle, per-thread last-error slot, `catch_unwind` panic guards). The one
/// addition is the Dart Native Port channel used to deliver Swarm events
/// asynchronously without blocking the FFI call site.
class Libp2pStatusCode {
  /// Successful operation.
  static const int ok = 0;

  /// One of the input pointers was null.
  static const int errNull = -1;

  /// String could not be decoded as UTF-8.
  static const int errUtf8 = -2;

  /// A Rust panic was caught at the FFI boundary.
  static const int errPanic = -3;

  /// The handle has not been initialized or has been shut down.
  static const int errNotInitialized = -4;

  /// The Swarm could not bind a listener (port conflict, permission denied).
  static const int errListen = -5;

  /// `lp_dial_direct` timed out before connecting or hole-punching failed.
  static const int errDialTimeout = -6;

  /// The remote peer rejected the protocol or stream negotiation failed.
  static const int errProtocol = -7;

  /// A stream operation found the stream closed, reset, or otherwise gone.
  static const int errStreamClosed = -8;

  /// Output buffer too small; caller should resize and retry.
  static const int errBufferTooSmall = -9;

  /// Operation not yet implemented in the native crate. Returned by stubs
  /// before Plan 11a's Rust impl lands.
  static const int errUnimplemented = -10;
}

/// `lp_init(data_dir, seed_ptr, seed_len, post_c_object_fn_ptr) -> *LpHandle`
///
/// - [data_dir]: filesystem path for libp2p PeerStore caches (no secrets).
/// - [seed]: 32-byte Ed25519 seed extracted via
///   `crypto_sign_ed25519_sk_to_seed`. Bridge copies it then zeroizes the
///   copy. Caller MUST zeroize its buffer immediately after this returns.
/// - [seedLen]: must be 32; any other value returns null with `lp_last_error`
///   set.
/// - [postCObjectFnPtr]: pointer obtained from `NativeApi.postCObject`. The
///   bridge stores it process-globally via `allo-isolate::store_dart_post_cobject`
///   so the tokio event loop can `Dart_PostCObject(port, msg)` from non-isolate
///   threads without re-entering Dart.
typedef Libp2pInitNative =
    Pointer<Void> Function(Pointer<Utf8>, Pointer<Uint8>, Size, Pointer<Void>);
typedef Libp2pInitDart =
    Pointer<Void> Function(Pointer<Utf8>, Pointer<Uint8>, int, Pointer<Void>);

/// `lp_listen(handle) -> c_int` — bind UDP/QUIC listeners and start the
/// swarm loop. Idempotent.
typedef Libp2pListenNative = Int32 Function(Pointer<Void>);
typedef Libp2pListenDart = int Function(Pointer<Void>);

/// `lp_observed_addrs(handle, out_buf, buf_len) -> isize`
///
/// Writes a CBOR-encoded list-of-multiaddrs into [outBuf]. Returns the
/// number of bytes written, or [Libp2pStatusCode.errBufferTooSmall] if the
/// buffer was too small. Callers typically size the buffer at 4 KiB.
typedef Libp2pObservedAddrsNative =
    IntPtr Function(Pointer<Void>, Pointer<Uint8>, Size);
typedef Libp2pObservedAddrsDart =
    int Function(Pointer<Void>, Pointer<Uint8>, int);

/// `lp_add_observed_addr(handle, multiaddr_ptr, len) -> c_int` — inject an
/// externally observed multiaddr (e.g., the reflexive endpoint returned by
/// a STUN-like response embedded in a `libp2p-connect-v1` signaling reply).
typedef Libp2pAddObservedAddrNative =
    Int32 Function(Pointer<Void>, Pointer<Uint8>, Size);
typedef Libp2pAddObservedAddrDart =
    int Function(Pointer<Void>, Pointer<Uint8>, int);

/// `lp_dial_direct(handle, peer_id, addrs_cbor, addrs_len, timeout_ms) -> i64`
///
/// Issues a DCUtR-aware direct dial. [addrsCbor] is a CBOR-encoded list of
/// multiaddrs (same encoding [Libp2pObservedAddrsDart] returns). Returns a
/// positive connection id on success, or a negative [Libp2pStatusCode] on
/// failure (including hole-punch failure → [Libp2pStatusCode.errDialTimeout]).
typedef Libp2pDialDirectNative =
    Int64 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>, Size, Uint32);
typedef Libp2pDialDirectDart =
    int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>, int, int);

/// `lp_open_stream(handle, conn_id, protocol_cstr) -> i64` — opens a new
/// libp2p stream for [protocol] (e.g. `/starling/sync/manifest/1`). Returns
/// a positive stream id or a negative [Libp2pStatusCode].
typedef Libp2pOpenStreamNative =
    Int64 Function(Pointer<Void>, Int64, Pointer<Utf8>);
typedef Libp2pOpenStreamDart = int Function(Pointer<Void>, int, Pointer<Utf8>);

/// `lp_stream_write(handle, stream_id, data_ptr, len, finish) -> c_int` —
/// writes one length-delimited frame. If [finish] is true, half-closes the
/// stream after this frame.
typedef Libp2pStreamWriteNative =
    Int32 Function(Pointer<Void>, Int64, Pointer<Uint8>, Size, Bool);
typedef Libp2pStreamWriteDart =
    int Function(Pointer<Void>, int, Pointer<Uint8>, int, bool);

/// `lp_stream_read(handle, stream_id, out_buf, buf_len, timeout_ms) -> isize`
///
/// Reads exactly one length-delimited frame into [outBuf]. Returns bytes
/// written, [Libp2pStatusCode.errBufferTooSmall] if the frame exceeded
/// [bufLen] (caller should resize and retry — the frame is preserved in a
/// peek slot), [Libp2pStatusCode.errStreamClosed] on graceful remote close
/// before any data, or [Libp2pStatusCode.errDialTimeout] on timeout.
typedef Libp2pStreamReadNative =
    IntPtr Function(Pointer<Void>, Int64, Pointer<Uint8>, Size, Uint32);
typedef Libp2pStreamReadDart =
    int Function(Pointer<Void>, int, Pointer<Uint8>, int, int);

/// `lp_stream_close(handle, stream_id) -> c_int` — close (both sides) and
/// release the stream id.
typedef Libp2pStreamCloseNative = Int32 Function(Pointer<Void>, Int64);
typedef Libp2pStreamCloseDart = int Function(Pointer<Void>, int);

/// `lp_set_event_port(handle, native_port) -> c_int` — register a Dart
/// `SendPort.nativePort` integer. The bridge serializes Swarm events to
/// CBOR and calls `Dart_PostCObject_DL` per event from the tokio loop.
typedef Libp2pSetEventPortNative = Int32 Function(Pointer<Void>, Int64);
typedef Libp2pSetEventPortDart = int Function(Pointer<Void>, int);

/// `lp_register_inbound_handler(handle, protocol_cstr) -> c_int` — tells
/// the bridge to accept inbound streams of [protocol] and surface them as
/// `IncomingStream` events on the native-port channel instead of resetting.
typedef Libp2pRegisterInboundHandlerNative =
    Int32 Function(Pointer<Void>, Pointer<Utf8>);
typedef Libp2pRegisterInboundHandlerDart =
    int Function(Pointer<Void>, Pointer<Utf8>);

/// `lp_local_peer_id(handle) -> *mut c_char` — base58-encoded local PeerId.
/// Caller frees with [Libp2pStringFreeDart]. Returns NULL before [init].
typedef Libp2pLocalPeerIdNative = Pointer<Utf8> Function(Pointer<Void>);
typedef Libp2pLocalPeerIdDart = Pointer<Utf8> Function(Pointer<Void>);

/// `lp_shutdown(handle) -> c_int` — stop swarm loop, close listeners,
/// drain tokio runtime. Subsequent calls on this handle return
/// [Libp2pStatusCode.errNotInitialized].
typedef Libp2pShutdownNative = Int32 Function(Pointer<Void>);
typedef Libp2pShutdownDart = int Function(Pointer<Void>);

/// `lp_last_error() -> *mut c_char` — most recent error message on the
/// calling thread. Caller frees with [Libp2pStringFreeDart].
typedef Libp2pLastErrorNative = Pointer<Utf8> Function();
typedef Libp2pLastErrorDart = Pointer<Utf8> Function();

/// `lp_string_free(ptr)` — free a string allocated by the bridge.
typedef Libp2pStringFreeNative = Void Function(Pointer<Utf8>);
typedef Libp2pStringFreeDart = void Function(Pointer<Utf8>);

/// Resolved bindings cached after first load.
class Libp2pBindings {
  Libp2pBindings._(DynamicLibrary lib)
    : init = lib.lookupFunction<Libp2pInitNative, Libp2pInitDart>('lp_init'),
      listen = lib.lookupFunction<Libp2pListenNative, Libp2pListenDart>(
        'lp_listen',
      ),
      observedAddrs = lib
          .lookupFunction<Libp2pObservedAddrsNative, Libp2pObservedAddrsDart>(
            'lp_observed_addrs',
          ),
      addObservedAddr = lib
          .lookupFunction<
            Libp2pAddObservedAddrNative,
            Libp2pAddObservedAddrDart
          >('lp_add_observed_addr'),
      dialDirect = lib
          .lookupFunction<Libp2pDialDirectNative, Libp2pDialDirectDart>(
            'lp_dial_direct',
          ),
      openStream = lib
          .lookupFunction<Libp2pOpenStreamNative, Libp2pOpenStreamDart>(
            'lp_open_stream',
          ),
      streamWrite = lib
          .lookupFunction<Libp2pStreamWriteNative, Libp2pStreamWriteDart>(
            'lp_stream_write',
          ),
      streamRead = lib
          .lookupFunction<Libp2pStreamReadNative, Libp2pStreamReadDart>(
            'lp_stream_read',
          ),
      streamClose = lib
          .lookupFunction<Libp2pStreamCloseNative, Libp2pStreamCloseDart>(
            'lp_stream_close',
          ),
      setEventPort = lib
          .lookupFunction<Libp2pSetEventPortNative, Libp2pSetEventPortDart>(
            'lp_set_event_port',
          ),
      registerInboundHandler = lib
          .lookupFunction<
            Libp2pRegisterInboundHandlerNative,
            Libp2pRegisterInboundHandlerDart
          >('lp_register_inbound_handler'),
      localPeerId = lib
          .lookupFunction<Libp2pLocalPeerIdNative, Libp2pLocalPeerIdDart>(
            'lp_local_peer_id',
          ),
      shutdown = lib.lookupFunction<Libp2pShutdownNative, Libp2pShutdownDart>(
        'lp_shutdown',
      ),
      lastError = lib
          .lookupFunction<Libp2pLastErrorNative, Libp2pLastErrorDart>(
            'lp_last_error',
          ),
      stringFree = lib
          .lookupFunction<Libp2pStringFreeNative, Libp2pStringFreeDart>(
            'lp_string_free',
          );

  final Libp2pInitDart init;
  final Libp2pListenDart listen;
  final Libp2pObservedAddrsDart observedAddrs;
  final Libp2pAddObservedAddrDart addObservedAddr;
  final Libp2pDialDirectDart dialDirect;
  final Libp2pOpenStreamDart openStream;
  final Libp2pStreamWriteDart streamWrite;
  final Libp2pStreamReadDart streamRead;
  final Libp2pStreamCloseDart streamClose;
  final Libp2pSetEventPortDart setEventPort;
  final Libp2pRegisterInboundHandlerDart registerInboundHandler;
  final Libp2pLocalPeerIdDart localPeerId;
  final Libp2pShutdownDart shutdown;
  final Libp2pLastErrorDart lastError;
  final Libp2pStringFreeDart stringFree;

  static Libp2pBindings? _instance;

  /// Resolves the platform's libp2p_bridge library and caches the bindings.
  /// Throws [UnsupportedError] on platforms where the crate isn't built
  /// (desktop) so misuse fails loudly rather than silently loading the
  /// wrong library.
  factory Libp2pBindings.load() {
    final cached = _instance;
    if (cached != null) return cached;
    final lib = _openLibrary();
    final bindings = Libp2pBindings._(lib);
    _instance = bindings;
    return bindings;
  }

  static DynamicLibrary _openLibrary() {
    if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.process();
    }
    if (Platform.isAndroid) {
      // Merged native bridge — the arti_* and lp_* FFI surfaces both live
      // in libstarling_bridge.so. See native/starling_bridge/.
      return DynamicLibrary.open('libstarling_bridge.so');
    }
    throw UnsupportedError(
      'libp2p_bridge is only built for iOS and Android in Plan 11a',
    );
  }
}
