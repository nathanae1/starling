import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:cbor/simple.dart';

import '../models/envelope.dart';
import '../server/handlers/events_handler.dart';
import '../server/handlers/events_push_handler.dart';
import '../server/handlers/follow_accept_handler.dart';
import '../server/handlers/follow_request_handler.dart';
import '../server/handlers/manifest_handler.dart';
import '../server/handlers/media_handler.dart';
import '../server/handlers/ping_handler.dart';
import 'clock.dart';
import 'content_key_service.dart';
import 'crypto_service.dart';
import 'follow_service.dart';
import 'libp2p/libp2p_service.dart';
import 'storage_service.dart';
import 'types.dart';

/// Inbound side of `Libp2pNetworkService`. Plan 11a — registers a handler
/// for each `/starling/sync/<route>/1` protocol with the underlying
/// [Libp2pService], reads one CBOR request frame per stream, dispatches to
/// the same pure handler functions the shelf HTTP server uses, writes a
/// single CBOR response frame, and closes.
///
/// Wire format is byte-identical to what `Libp2pNetworkService` (the
/// initiator side) sends — see that file for the exact CBOR shape per
/// protocol. The shelf handlers in `lib/server/handlers/` were refactored
/// in Plan 11a §16 to expose `build*Response`/`ingest*` pure functions for
/// this purpose.
class Libp2pStreamServer {
  Libp2pStreamServer({
    required Libp2pService libp2p,
    required StorageService storage,
    required ContentKeyService contentKey,
    required CryptoService crypto,
    required Clock clock,
    required Directory appSupportDir,
    required Future<Identity?> Function() identityLookup,
    required FollowService Function() followServiceLookup,
  })  : _libp2p = libp2p,
        _storage = storage,
        _contentKey = contentKey,
        _crypto = crypto,
        _clock = clock,
        _appSupportDir = appSupportDir,
        _identityLookup = identityLookup,
        _followServiceLookup = followServiceLookup;

  final Libp2pService _libp2p;
  final StorageService _storage;
  final ContentKeyService _contentKey;
  final CryptoService _crypto;
  final Clock _clock;
  final Directory _appSupportDir;
  final Future<Identity?> Function() _identityLookup;
  final FollowService Function() _followServiceLookup;

  bool _started = false;

  static const _pManifest = '/starling/sync/manifest/1';
  static const _pEvents = '/starling/sync/events/1';
  static const _pEventsPush = '/starling/sync/events-push/1';
  static const _pMedia = '/starling/sync/media/1';
  static const _pFollowRequest = '/starling/sync/follow-request/1';
  static const _pFollowAccept = '/starling/sync/follow-accept/1';
  static const _pPing = '/starling/sync/ping/1';

  /// Idempotent. Registers an inbound handler per protocol. Safe to call
  /// before [Libp2pService.listen] completes — the bridge buffers the
  /// registrations until its event loop is up.
  void start() {
    if (_started) return;
    _started = true;
    _libp2p.registerInboundHandler(_pManifest, _handleStream(_handleManifest));
    _libp2p.registerInboundHandler(_pEvents, _handleStream(_handleEvents));
    _libp2p.registerInboundHandler(
        _pEventsPush, _handleStream(_handleEventsPush));
    _libp2p.registerInboundHandler(_pMedia, _handleStream(_handleMedia));
    _libp2p.registerInboundHandler(
        _pFollowRequest, _handleStream(_handleFollowRequest));
    _libp2p.registerInboundHandler(
        _pFollowAccept, _handleStream(_handleFollowAccept));
    _libp2p.registerInboundHandler(_pPing, _handleStream(_handlePing));
  }

  /// No-op currently — Libp2pService doesn't have an unregister surface,
  /// and shutting the bridge down tears every handler registration with
  /// it. Provided so lifecycle code can `_server?.stop()` symmetrically.
  Future<void> stop() async {
    _started = false;
  }

  // --- per-protocol bodies. Each takes the request frame, returns the
  //     response frame (empty Uint8List for fire-and-forget protocols). ---

  Future<Uint8List> _handleManifest(Uint8List req) async {
    final identity = await _identityLookup();
    if (identity == null) {
      throw StateError('manifest: identity not loaded');
    }
    final decoded = cbor.decode(req);
    int? since;
    int? until;
    String? untilId;
    String? requesterPubkey;
    int? ackRotationAt;
    int? cardSeenAt;
    Uint8List? ackSig;
    if (decoded is Map) {
      since = decoded['since'] as int?;
      until = decoded['until'] as int?;
      untilId = decoded['until_id'] as String?;
      requesterPubkey = decoded['requester_pubkey'] as String?;
      ackRotationAt = decoded['ack_rotation_at'] as int?;
      cardSeenAt = decoded['card_seen_at'] as int?;
      ackSig = _asBytes(decoded['ack_sig']);
    }
    return buildManifestResponseBytes(
      storage: _storage,
      crypto: _crypto,
      identity: identity,
      since: since,
      until: until,
      untilId: untilId,
      requesterPubkey: requesterPubkey,
      ackRotationAt: ackRotationAt,
      cardSeenAt: cardSeenAt,
      ackSig: ackSig,
    );
  }

  Future<Uint8List> _handleEvents(Uint8List req) async {
    final identity = await _identityLookup();
    if (identity == null) {
      throw StateError('events: identity not loaded');
    }
    int? since;
    if (req.isNotEmpty) {
      final decoded = cbor.decode(req);
      if (decoded is Map) since = decoded['since'] as int?;
    }
    final envelope = await buildEventsEnvelope(
      storage: _storage,
      contentKey: _contentKey,
      identity: identity,
      since: since,
    );
    return envelope.toBytes();
  }

  Future<Uint8List> _handleEventsPush(Uint8List req) async {
    if (req.isEmpty) return Uint8List(0);
    final envelope = Envelope.fromBytes(req);
    await ingestPushedEnvelope(
      storage: _storage,
      contentKey: _contentKey,
      clock: _clock,
      envelope: envelope,
    );
    return Uint8List(0);
  }

  Future<Uint8List> _handleMedia(Uint8List req) async {
    final decoded = cbor.decode(req);
    if (decoded is! Map) return Uint8List(0);
    final hash = decoded['hash'] as String?;
    if (hash == null) return Uint8List(0);
    final bytes = await readMediaBytes(
      storage: _storage,
      appSupportDir: _appSupportDir,
      hash: hash,
    );
    return bytes ?? Uint8List(0);
  }

  Future<Uint8List> _handleFollowRequest(Uint8List req) async {
    final decoded = cbor.decode(req);
    if (decoded is! Map) return Uint8List(0);
    final payload = decoded['payload'];
    final bodyBytes = _asBytes(payload);
    if (bodyBytes == null) return Uint8List(0);
    await ingestFollowRequestBytes(
      storage: _storage,
      clock: _clock,
      bodyBytes: bodyBytes,
    );
    return Uint8List(0);
  }

  Future<Uint8List> _handleFollowAccept(Uint8List req) async {
    final decoded = cbor.decode(req);
    if (decoded is! Map) return Uint8List(0);
    final payload = decoded['payload'];
    final bodyBytes = _asBytes(payload);
    if (bodyBytes == null) return Uint8List(0);
    await ingestFollowAcceptBytes(
      followService: _followServiceLookup(),
      bodyBytes: bodyBytes,
    );
    return Uint8List(0);
  }

  Future<Uint8List> _handlePing(Uint8List req) async {
    return buildPingResponseBytes(req);
  }

  /// Adapts a `(Uint8List) -> Future<Uint8List>` per-protocol body into the
  /// `void Function(Libp2pStream)` shape `Libp2pService` expects. Reads one
  /// frame, runs the body, writes the response frame with `finish: true`,
  /// then closes. Failures are logged and the stream is closed — the
  /// underlying QUIC stream's reset surfaces to the initiator as a read
  /// error, mirroring the HTTP 500 path.
  void Function(Libp2pStream) _handleStream(
    Future<Uint8List> Function(Uint8List request) body,
  ) {
    return (Libp2pStream stream) {
      unawaited(() async {
        try {
          final req = await stream.read();
          final resp = await body(req);
          await stream.write(resp, finish: true);
        } catch (e, st) {
          developer.log(
            '${stream.protocol} handler failed: $e\n$st',
            name: 'libp2p_stream_server',
          );
        } finally {
          await stream.close();
        }
      }());
    };
  }
}

Uint8List? _asBytes(dynamic value) {
  if (value is Uint8List) return value;
  if (value is List<int>) return Uint8List.fromList(value);
  return null;
}
