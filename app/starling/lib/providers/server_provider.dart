import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../server/http_server.dart';
import '../services/signaling/ws_signaling_service.dart';
import '../services/storage/keychain_manager.dart';
import 'app_paths_provider.dart';
import 'follow_provider.dart';
import 'identity_provider.dart';
import 'service_providers.dart';

part 'server_provider.g.dart';

/// Lifecycle owner for the embedded [StarlingHttpServer]. The published
/// state is the bound port (or `null` while pre-onboarding / stopped),
/// so consumers like Plan 09 (mDNS) and Plan 11 (Tor) can `ref.watch` it.
@riverpod
class HttpServerController extends _$HttpServerController {
  StarlingHttpServer? _server;

  @override
  Future<int?> build() async {
    final identityAsync = ref.watch(identityControllerProvider);
    final identity = identityAsync.value;
    if (identity == null) return null;

    final storage = ref.watch(storageServiceProvider);
    final contentKey = ref.watch(contentKeyServiceProvider);
    final clock = ref.watch(clockProvider);
    final appSupportDir = await ref.watch(appSupportDirectoryProvider.future);

    final crypto = ref.watch(cryptoServiceProvider);
    final server = StarlingHttpServer.social(
      storage: storage,
      contentKey: contentKey,
      identityLookup: storage.getIdentity,
      appSupportDir: appSupportDir,
      clock: clock,
      crypto: crypto,
      // Plan 11b — every authenticated inbound /ws/signal channel is
      // handed off to the production WsSignalingService so the dispatcher
      // can decrypt + route. With the mock binding still in place
      // (pre-identity), this is a no-op.
      signalingInboundHandler: (channel) {
        final svc = ref.read(signalingServiceProvider);
        if (svc is WsSignalingService) {
          svc.handleInbound(channel);
        }
      },
      // Lazy lookup avoids a build-time cycle:
      //   ownEndpoints → httpServerController → followService → ownEndpoints.
      // followService is only needed at /follow-accept request time.
      followServiceLookup: () => ref.read(followServiceProvider),
      // Plan 17: lets POST /events unseal room keys sealed to us.
      ownSecretKeyLookup: () => KeychainManager().loadIdentitySecretKey(),
    );
    await server.start();
    _server = server;
    ref.onDispose(() async {
      await server.stop();
      _server = null;
    });
    return server.port;
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    if (server != null) {
      await server.stop();
    }
    state = const AsyncData(null);
  }

  Future<void> restart() async {
    await stop();
    ref.invalidateSelf();
  }
}
