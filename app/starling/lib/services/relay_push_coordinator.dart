import 'dart:async';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'relay_push_service.dart';
import 'storage_service.dart';
import 'types.dart';

/// Owner-side push of content to the paired Relay (Plan 15), using the
/// "best-effort + reconcile" model:
///
/// - [backfill] runs once at pair time: pushes the Owner's full own-event
///   history + media, then flips `relayBackfillComplete`.
/// - [pushPublished] fires after each new post: a single best-effort push.
/// - [reconcile] self-heals: diffs local own-event ids against the Relay's
///   `/manifest` and re-pushes anything missing. Safe to call often — the
///   Relay's `POST /events` / `POST /media` are idempotent.
///
/// All methods no-op when no Relay is paired, and swallow/log transport
/// errors (the next reconcile retries). They never throw into callers.
class RelayPushCoordinator {
  RelayPushCoordinator({
    required RelayPushService pushService,
    required StorageService storage,
    required http.Client relayClient,
    required Future<Identity?> Function() identityLookup,
    required Future<Uint8List?> Function() ownSecretKeyLookup,
    required Future<Uint8List?> Function(String hash) mediaBytesLookup,
    Duration timeout = const Duration(seconds: 30),
  })  : _push = pushService,
        _storage = storage,
        _client = relayClient,
        _identityLookup = identityLookup,
        _ownSecretKeyLookup = ownSecretKeyLookup,
        _mediaBytesLookup = mediaBytesLookup,
        _timeout = timeout;

  final RelayPushService _push;
  final StorageService _storage;
  final http.Client _client;
  final Future<Identity?> Function() _identityLookup;
  final Future<Uint8List?> Function() _ownSecretKeyLookup;
  final Future<Uint8List?> Function(String hash) _mediaBytesLookup;
  final Duration _timeout;

  /// Push a freshly-published event (+ its media) to the paired Relay.
  Future<void> pushPublished(Event signed, Uint8List encryptedBytes) async {
    await _withRelay((ctx) async {
      await _push.pushEvents(
        relayBaseUrl: ctx.baseUrl,
        ownerPubkeyBytes: ctx.pubkeyBytes,
        ownerSecretKey: ctx.secretKey,
        items: [
          RelayPushItem(
            id: signed.id,
            encryptedEvent: EncryptedEvent.fromBytes(encryptedBytes),
          ),
        ],
      );
      await _pushMediaFor([signed], ctx);
      developer.log(
        'relay push published ${signed.id} media=${signed.media.length}',
        name: 'relay_push',
      );
    });
  }

  /// One-shot: push the Owner's full own-event + media history to the
  /// Relay, then mark the backfill complete. Idempotent on the Relay.
  Future<void> backfill() async {
    await _withRelay((ctx) async {
      final events = await _ownEventsWithPayloads(ctx.pubkey);
      if (events.items.isNotEmpty) {
        await _push.pushEvents(
          relayBaseUrl: ctx.baseUrl,
          ownerPubkeyBytes: ctx.pubkeyBytes,
          ownerSecretKey: ctx.secretKey,
          items: events.items,
        );
      }
      await _pushMediaFor(events.events, ctx);
      await _storage.markRelayBackfillComplete(ctx.relayId);
      developer.log(
        'relay backfill complete: ${events.items.length} events',
        name: 'relay_push',
      );
    });
  }

  /// Self-heal: push any own events the Relay's `/manifest` doesn't list.
  Future<void> reconcile() async {
    await _withRelay((ctx) async {
      final present = await _relayEventIds(ctx.baseUrl);
      if (present == null) return; // relay unreachable — try again next tick
      final all = await _ownEventsWithPayloads(ctx.pubkey);
      final missingEvents = <Event>[];
      final missingItems = <RelayPushItem>[];
      for (var i = 0; i < all.items.length; i++) {
        if (!present.contains(all.items[i].id)) {
          missingItems.add(all.items[i]);
          missingEvents.add(all.events[i]);
        }
      }
      if (missingItems.isEmpty) return;
      await _push.pushEvents(
        relayBaseUrl: ctx.baseUrl,
        ownerPubkeyBytes: ctx.pubkeyBytes,
        ownerSecretKey: ctx.secretKey,
        items: missingItems,
      );
      await _pushMediaFor(missingEvents, ctx);
      developer.log(
        'relay reconcile pushed ${missingItems.length} missing events',
        name: 'relay_push',
      );
    });
  }

  // --- internals ---

  /// Resolves the paired relay + identity + secret key into a [_RelayCtx]
  /// and runs [body]. No-ops (logs) when anything required is missing or
  /// the body throws — callers never see an exception.
  Future<void> _withRelay(Future<void> Function(_RelayCtx ctx) body) async {
    try {
      final relay = await _storage.getPairedRelay();
      if (relay == null) return;
      final identity = await _identityLookup();
      final secretKey = await _ownSecretKeyLookup();
      if (identity == null || secretKey == null) return;
      await body(_RelayCtx(
        relayId: relay.relayId,
        baseUrl: _baseUrl(relay.relayOnion),
        pubkey: identity.pubkey,
        pubkeyBytes: decodeStoredPubkey(identity.pubkey),
        secretKey: secretKey,
      ));
    } catch (e) {
      developer.log('relay push skipped: $e', name: 'relay_push');
    }
  }

  Future<void> _pushMediaFor(List<Event> events, _RelayCtx ctx) async {
    final seen = <String>{};
    for (final e in events) {
      for (final m in e.media) {
        if (m.hash.isEmpty || !seen.add(m.hash)) continue;
        final blob = await _mediaBytesLookup(m.hash);
        if (blob == null) continue;
        await _push.pushMedia(
          relayBaseUrl: ctx.baseUrl,
          ownerPubkeyBytes: ctx.pubkeyBytes,
          ownerSecretKey: ctx.secretKey,
          hash: m.hash,
          blob: blob,
        );
      }
    }
  }

  /// Own events paired with their stored wire-`EncryptedEvent` bytes. Own
  /// events authored before schema v2 have no stored payload and are
  /// skipped (the Relay can't serve what we can't hand it verbatim).
  Future<_OwnEvents> _ownEventsWithPayloads(String pubkey) async {
    final events = await _storage.getEvents(pubkey: pubkey);
    final items = <RelayPushItem>[];
    final kept = <Event>[];
    for (final e in events) {
      final payload = await _storage.getEncryptedPayload(e.id);
      if (payload == null) continue;
      items.add(RelayPushItem(
        id: e.id,
        encryptedEvent: EncryptedEvent.fromBytes(payload),
      ));
      kept.add(e);
    }
    return _OwnEvents(items: items, events: kept);
  }

  /// Fetches the Relay's `/manifest` and returns the set of event ids it
  /// holds, or null if the Relay is unreachable.
  Future<Set<String>?> _relayEventIds(String baseUrl) async {
    try {
      final res =
          await _client.get(Uri.parse('$baseUrl/manifest')).timeout(_timeout);
      if (res.statusCode != 200) return null;
      final decoded = cbor.decode(res.bodyBytes);
      if (decoded is! Map) return null;
      final events = decoded['events'] as List<dynamic>? ?? const [];
      return events
          .whereType<Map<dynamic, dynamic>>()
          .map((e) => e['id'])
          .whereType<String>()
          .toSet();
    } catch (_) {
      return null;
    }
  }

  String _baseUrl(String onion) =>
      onion.contains(':') ? 'http://$onion' : 'http://$onion:80';
}

class _RelayCtx {
  _RelayCtx({
    required this.relayId,
    required this.baseUrl,
    required this.pubkey,
    required this.pubkeyBytes,
    required this.secretKey,
  });
  final String relayId;
  final String baseUrl;
  final String pubkey;
  final Uint8List pubkeyBytes;
  final Uint8List secretKey;
}

class _OwnEvents {
  _OwnEvents({required this.items, required this.events});
  final List<RelayPushItem> items;
  final List<Event> events;
}
