import 'types.dart';

/// Abstract interface for Tor (Arti) operations.
///
/// Default implementation wraps Arti via Rust FFI (Plan 11).
/// Mock implementation simulates bootstrap and connections.
/// Bootstrap mode for [TorService.init]. The constants mirror
/// `ArtiBootstrapMode` in `tor/ffi_bindings.dart` so call sites can use
/// either without importing FFI details.
class TorBootstrapMode {
  /// Synchronous full bootstrap; [init] only returns when the client is
  /// ready for traffic. Foreground default.
  static const int full = 0;

  /// Lazy bootstrap; [init] returns immediately. Circuits build on first
  /// stream, or eagerly via [TorService.bootstrap]. Plan 14 Phase D iOS
  /// BGProcessingTask warm path.
  static const int onDemand = 1;
}

abstract class TorService {
  Future<void> init(
    String dataDir, {
    int bootstrapMode = TorBootstrapMode.full,
  });

  /// Drive bootstrap explicitly. Idempotent. Useful with
  /// [TorBootstrapMode.onDemand] when the caller wants to bound how long
  /// it waits for circuits to be ready.
  Future<void> bootstrap({Duration? timeout}) async {}

  /// Publish (or update) the device's single onion service, forwarding
  /// virtual port 80 to `127.0.0.1:[localPort]`. Idempotent on the same
  /// port. Calling again with a different port retargets the live reverse
  /// proxy in place — the `.onion` address never changes, so peers'
  /// stored connection cards stay valid across local server rebinds.
  Future<String> createOnionService(int localPort);

  Future<PeerConnection> connectToOnion(String address, int port);

  TorStatus getStatus();

  Future<void> shutdown();

  /// Cached `.onion` address from the most recent successful
  /// [createOnionService] call, or `null` if the service hasn't been
  /// published yet (or after [shutdown]).
  String? get onionAddress;

  /// Local TCP port of the in-process SOCKS5 proxy. Returns `0` until the
  /// listener is bound (i.e. before [init] completes).
  int get socksPort;

  /// Convenience: Tor is bootstrapped *and* a SOCKS proxy is listening.
  bool get isReady;
}
