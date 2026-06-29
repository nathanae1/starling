import 'dart:async';
import 'dart:typed_data';

import 'libp2p_service.dart';

/// Stub [Libp2pService] used while the `native/libp2p_bridge` Rust crate
/// is unfinished and behind `kLibp2pEnabled=false`. Every call reports the
/// service as unavailable.
///
/// Replaced by `Libp2pBridge` (the real FFI-backed impl) once the Rust
/// side ships. Until then this lets DI wiring and tests proceed without
/// the bridge being built.
class Libp2pBridgeStub implements Libp2pService {
  final _eventCtrl = StreamController<Libp2pEvent>.broadcast();

  @override
  bool get isReady => false;

  @override
  String get localPeerId => '';

  @override
  Stream<Libp2pEvent> get events => _eventCtrl.stream;

  Never _unavailable() => throw const Libp2pUnavailableException(
    'libp2p bridge not built — kLibp2pEnabled is false or the native '
    'crate has not been cross-compiled for this target.',
  );

  @override
  Future<void> init(String dataDir, Uint8List ed25519Seed) async {
    // No-op; deliberately doesn't throw so providers can construct the stub
    // unconditionally. Network methods do throw.
  }

  @override
  Future<void> listen() async {
    // No-op for the same reason as [init].
  }

  @override
  Future<List<Uint8List>> observedAddrs() async => const [];

  @override
  Future<void> addObservedAddr(Uint8List multiaddr) async {}

  @override
  Future<void> dialDirect(
    String remotePeerId,
    List<Uint8List> remoteAddrs, {
    Duration timeout = const Duration(seconds: 8),
  }) async => _unavailable();

  @override
  Future<Libp2pStream> openStream(String remotePeerId, String protocol) async =>
      _unavailable();

  @override
  void registerInboundHandler(
    String protocol,
    void Function(Libp2pStream stream) handler,
  ) {
    // No-op; the stub never delivers inbound streams.
  }

  @override
  Future<void> shutdown() async {
    if (!_eventCtrl.isClosed) await _eventCtrl.close();
  }
}
