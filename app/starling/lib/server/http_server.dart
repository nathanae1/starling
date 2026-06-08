import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import '../services/clock.dart';
import '../services/content_key_service.dart';
import '../services/crypto_service.dart';
import '../services/follow_service.dart';
import '../services/storage_service.dart';
import '../services/types.dart';
import 'handlers/events_handler.dart';
import 'handlers/events_push_handler.dart';
import 'handlers/follow_accept_handler.dart';
import 'handlers/follow_request_handler.dart';
import 'handlers/manifest_handler.dart';
import 'handlers/media_handler.dart';
import 'handlers/signaling_handler.dart';
import 'handlers/status_handler.dart';
import 'middleware/error_handler.dart';
import 'middleware/rate_limit.dart';

/// Embedded shelf HTTP server that exposes content to peers. Binds to a
/// random ephemeral port (49152–65535) and exposes that port via [port]
/// so mDNS (Plan 09) and Tor (Plan 11) can advertise it.
///
/// Single mode: the Owner's phone serving its own content via
/// [StarlingHttpServer.social]. The full sync API is mounted, including
/// the social-mode `POST /events` that decrypts pushes from Followers.
/// The standalone Relay (Plan 15) is a separate Rust binary; the phone
/// does not act as a relay for other Owners.
class StarlingHttpServer {
  StarlingHttpServer._({
    required Router Function() buildRouter,
    required Clock clock,
    int maxBindAttempts = 5,
    int rateLimitPerMinute = 120,
    int maxBodyBytes = 1024 * 1024,
    Random? random,
  })  : _buildRouter = buildRouter,
        _clock = clock,
        _maxBindAttempts = maxBindAttempts,
        _rateLimitPerMinute = rateLimitPerMinute,
        _maxBodyBytes = maxBodyBytes,
        _random = random ?? Random.secure();

  factory StarlingHttpServer.social({
    required StorageService storage,
    required ContentKeyService contentKey,
    required Future<Identity?> Function() identityLookup,
    required Directory appSupportDir,
    required Clock clock,
    required CryptoService crypto,
    required void Function(SignalingChannel channel) signalingInboundHandler,
    FollowService? followService,
    FollowService? Function()? followServiceLookup,
    int maxBindAttempts = 5,
    int rateLimitPerMinute = 120,
    int maxBodyBytes = 1024 * 1024,
    Random? random,
  }) {
    final lookup = followServiceLookup ?? (() => followService);
    return StarlingHttpServer._(
      buildRouter: () => _buildSocialRouter(
        storage: storage,
        contentKey: contentKey,
        identityLookup: identityLookup,
        appSupportDir: appSupportDir,
        clock: clock,
        crypto: crypto,
        signalingInboundHandler: signalingInboundHandler,
        followServiceLookup: lookup,
      ),
      clock: clock,
      maxBindAttempts: maxBindAttempts,
      rateLimitPerMinute: rateLimitPerMinute,
      maxBodyBytes: maxBodyBytes,
      random: random,
    );
  }

  static const int _portMin = 49152;
  static const int _portMax = 65535;

  final Router Function() _buildRouter;
  final Clock _clock;
  final int _maxBindAttempts;
  final int _rateLimitPerMinute;
  final int _maxBodyBytes;
  final Random _random;

  HttpServer? _server;
  RateLimiter? _rateLimiter;
  int? _port;

  int? get port => _port;
  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;
    final rateLimiter = RateLimiter(
      requestsPerMinute: _rateLimitPerMinute,
      clock: _clock,
    );
    final pipeline = const Pipeline()
        .addMiddleware(errorHandlerMiddleware())
        .addMiddleware(rateLimiter.middleware)
        .addMiddleware(bodySizeLimitMiddleware(maxBytes: _maxBodyBytes))
        .addHandler(_buildRouter().call);

    Object? lastError;
    for (var attempt = 0; attempt < _maxBindAttempts; attempt++) {
      final candidate = _portMin + _random.nextInt(_portMax - _portMin + 1);
      try {
        final server = await shelf_io.serve(
          pipeline,
          InternetAddress.anyIPv4,
          candidate,
        );
        _server = server;
        _rateLimiter = rateLimiter;
        _port = candidate;
        return;
      } on SocketException catch (e) {
        lastError = e;
      }
    }
    rateLimiter.dispose();
    throw StateError(
      'could not bind HTTP server after $_maxBindAttempts attempts: '
      '$lastError',
    );
  }

  Future<void> stop() async {
    final server = _server;
    final rateLimiter = _rateLimiter;
    _server = null;
    _rateLimiter = null;
    _port = null;
    rateLimiter?.dispose();
    if (server != null) {
      await server.close(force: true);
    }
  }
}

Router _buildSocialRouter({
  required StorageService storage,
  required ContentKeyService contentKey,
  required Future<Identity?> Function() identityLookup,
  required Directory appSupportDir,
  required Clock clock,
  required CryptoService crypto,
  required void Function(SignalingChannel channel) signalingInboundHandler,
  required FollowService? Function() followServiceLookup,
}) {
  final router = Router();
  router.get(
    '/status',
    statusHandler(
      storage: storage,
      identityLookup: identityLookup,
    ),
  );
  router.get(
    '/manifest',
    manifestHandler(
      storage: storage,
      identityLookup: identityLookup,
    ),
  );
  router.get(
    '/events',
    eventsHandler(
      storage: storage,
      contentKey: contentKey,
      identityLookup: identityLookup,
    ),
  );
  router.post(
    '/events',
    eventsPushHandler(
      storage: storage,
      contentKey: contentKey,
      clock: clock,
    ),
  );
  router.get(
    '/media/<hash>',
    mediaHandler(
      storage: storage,
      appSupportDir: appSupportDir,
    ),
  );
  router.post(
    '/follow-request',
    followRequestHandler(
      storage: storage,
      clock: clock,
    ),
  );
  router.post('/follow-accept', (Request request) async {
    final followService = followServiceLookup();
    if (followService == null) {
      return Response.notFound('follow service unavailable');
    }
    return followAcceptHandler(followService: followService)(request);
  });
  router.get(
    '/ws/signal',
    signalingHandler(
      crypto: crypto,
      onChannel: signalingInboundHandler,
    ),
  );
  return router;
}

