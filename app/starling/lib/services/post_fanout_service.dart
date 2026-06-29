import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import '../models/envelope.dart';
import '../models/protocol_version.dart';
import '../sync/peer_reachability_monitor.dart';
import '../sync/sync_engine.dart';
import 'storage_service.dart';

/// Best-effort push of a freshly-published encrypted event to every
/// accepted follower whose connection is currently reachable. Followers
/// who are unreachable get the event later via their own periodic pull —
/// no retry/queue here.
abstract class PostFanoutService {
  Future<void> fanout(Uint8List encryptedEventBytes);

  /// Test/seam helper — drops every push on the floor.
  static const PostFanoutService noop = _NoopPostFanoutService();
}

class _NoopPostFanoutService implements PostFanoutService {
  const _NoopPostFanoutService();

  @override
  Future<void> fanout(Uint8List encryptedEventBytes) async {}
}

class DefaultPostFanoutService implements PostFanoutService {
  DefaultPostFanoutService({
    required StorageService storage,
    required SyncTransport transport,
    required PeerReachabilityMonitor reachability,
  }) : _storage = storage,
       _transport = transport,
       _reachability = reachability;

  final StorageService _storage;
  final SyncTransport _transport;
  final PeerReachabilityMonitor _reachability;

  @override
  Future<void> fanout(Uint8List encryptedEventBytes) async {
    final List<String> followers;
    try {
      followers = await _storage.getAcceptedFollowerPubkeys();
    } catch (e) {
      developer.log('fanout: follower lookup failed: $e', name: 'post_fanout');
      return;
    }
    if (followers.isEmpty) return;

    final envelope = Envelope(
      version: kStarlingProtocolVersion,
      items: [EnvelopeItem(type: 'event', payload: encryptedEventBytes)],
    );

    await Future.wait(
      followers.map((p) => _pushOne(p, envelope)),
      eagerError: false,
    );
  }

  Future<void> _pushOne(String pubkey, Envelope envelope) async {
    try {
      final conn = await _reachability.bestConnectionFor(pubkey);
      if (conn == null) {
        developer.log(
          'fanout: $pubkey unreachable — skipped',
          name: 'post_fanout',
        );
        return;
      }
      await _transport.pushEnvelope(conn, envelope);
      developer.log(
        'fanout: pushed to $pubkey via ${conn.transport.name}',
        name: 'post_fanout',
      );
    } catch (e) {
      developer.log('fanout: push to $pubkey failed: $e', name: 'post_fanout');
    }
  }
}
