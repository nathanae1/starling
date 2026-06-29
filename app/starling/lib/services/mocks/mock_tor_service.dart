import '../tor_service.dart';
import '../types.dart';

/// Simulated TorService for testing without a real Tor client.
class MockTorService implements TorService {
  bool _isReady = false;
  String? _onionAddress;

  /// Test hook: while > 0, each [createOnionService] call throws and
  /// decrements this, simulating transient onion-publish failures. Used to
  /// exercise the publish-retry path (OnionPublisher) and as a debug-mode
  /// failure injector.
  int failCreateOnionCount = 0;

  @override
  Future<void> init(
    String dataDir, {
    int bootstrapMode = TorBootstrapMode.full,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    _isReady = bootstrapMode == TorBootstrapMode.full;
  }

  @override
  Future<void> bootstrap({Duration? timeout}) async {
    _isReady = true;
  }

  @override
  Future<String> createOnionService(int localPort) async {
    if (failCreateOnionCount > 0) {
      failCreateOnionCount--;
      throw StateError('injected onion publish failure (port=$localPort)');
    }
    _onionAddress = 'mockabcdef1234567890abcdef1234567890abcdef12345678.onion';
    return _onionAddress!;
  }

  @override
  Future<PeerConnection> connectToOnion(String address, int port) async {
    return PeerConnection(
      pubkey: 'mock-peer',
      baseUrl: 'http://$address:$port',
      transport: PeerTransport.tor,
    );
  }

  @override
  TorStatus getStatus() => TorStatus(
    bootstrapPercent: _isReady ? 100 : 0,
    circuitCount: _isReady ? 3 : 0,
    isReady: _isReady,
    onionAddress: _onionAddress,
  );

  @override
  Future<void> shutdown() async {
    _isReady = false;
    _onionAddress = null;
  }

  @override
  String? get onionAddress => _onionAddress;

  @override
  int get socksPort => _isReady ? 9999 : 0;

  @override
  bool get isReady => _isReady;
}
