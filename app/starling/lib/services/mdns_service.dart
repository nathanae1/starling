import 'dart:async';

import 'package:flutter/services.dart';

import 'types.dart';

/// Bespoke mDNS advertise + resolve for the `_starling._tcp` service. The
/// native plugins (Swift `MdnsPlugin` on iOS, Kotlin `MdnsPlugin` on
/// Android) wrap NWListener+NWBrowser and NsdManager respectively. Native
/// code stays narrow: register a service, browse for services, emit
/// `peer-found` / `peer-lost` events. All filtering, scheduling, and
/// follows-list cross-checking lives in Dart.
abstract class MdnsService {
  /// Begins advertising `_starling._tcp` with TXT record `pubkey={pubkey}`
  /// `port={port}`, and starts browsing for other peers. Idempotent —
  /// subsequent calls reconfigure the active record.
  Future<void> register({required String pubkey, required int port});

  /// Stops advertising and clears the resolver. Safe to call when not
  /// running. Empties the live peer cache.
  Future<void> deregister();

  /// Live cache of currently visible peers, keyed by short pubkey
  /// (the value of the `pubkey` TXT key). Emits a fresh map each time the
  /// cache changes. Late subscribers receive the current snapshot.
  Stream<Map<String, LanPeer>> get peers;

  /// One-shot snapshot of the current cache. Useful when the consumer
  /// just needs "what do I see right now?" without subscribing.
  Map<String, LanPeer> currentPeers();

  /// Forces a fresh browse cycle. The resolver runs continuously, so this
  /// is mainly useful for pull-to-refresh: drop the current cache and
  /// rebuild it from native events.
  Future<void> rescan();
}

class MdnsException implements Exception {
  const MdnsException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'MdnsException($code): $message';
}

/// Method-channel-backed implementation. Channel names are kept in sync
/// with `MdnsPlugin.swift` and `MdnsPlugin.kt`.
class MethodChannelMdnsService implements MdnsService {
  MethodChannelMdnsService({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  }) : _methodChannel =
           methodChannel ?? const MethodChannel('dev.starling.mdns'),
       _eventChannel =
           eventChannel ?? const EventChannel('dev.starling.mdns/peers');

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;

  final Map<String, LanPeer> _cache = {};
  final StreamController<Map<String, LanPeer>> _controller =
      StreamController<Map<String, LanPeer>>.broadcast();
  StreamSubscription<dynamic>? _eventSub;

  void _ensureSubscribed() {
    if (_eventSub != null) return;
    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      _onNativeEvent,
      onError: (_) {
        // Native stream errors are non-fatal; the resolver will
        // re-emit on the next discovery tick.
      },
    );
  }

  void _onNativeEvent(dynamic raw) {
    if (raw is! Map) return;
    final event = raw['event'] as String?;
    final pubkey = raw['pubkey'] as String?;
    if (event == null || pubkey == null) return;

    if (event == 'peer-found') {
      final host = raw['host'] as String?;
      final port = raw['port'] as int?;
      if (host == null || port == null) return;
      _cache[pubkey] = LanPeer(pubkey: pubkey, host: host, port: port);
      _emitSnapshot();
    } else if (event == 'peer-lost') {
      if (_cache.remove(pubkey) != null) {
        _emitSnapshot();
      }
    } else if (event == 'cleared') {
      if (_cache.isNotEmpty) {
        _cache.clear();
        _emitSnapshot();
      }
    }
  }

  void _emitSnapshot() => _controller.add(Map.unmodifiable(_cache));

  @override
  Future<void> register({required String pubkey, required int port}) async {
    _ensureSubscribed();
    try {
      await _methodChannel.invokeMethod<void>('register', {
        'pubkey': pubkey,
        'port': port,
      });
    } on PlatformException catch (e) {
      throw MdnsException(e.code, e.message ?? 'mdns register failed');
    }
  }

  @override
  Future<void> deregister() async {
    try {
      await _methodChannel.invokeMethod<void>('deregister');
    } on PlatformException catch (e) {
      throw MdnsException(e.code, e.message ?? 'mdns deregister failed');
    }
    if (_cache.isNotEmpty) {
      _cache.clear();
      _emitSnapshot();
    }
  }

  @override
  Stream<Map<String, LanPeer>> get peers async* {
    _ensureSubscribed();
    yield Map.unmodifiable(_cache);
    yield* _controller.stream;
  }

  @override
  Map<String, LanPeer> currentPeers() => Map.unmodifiable(_cache);

  @override
  Future<void> rescan() async {
    try {
      await _methodChannel.invokeMethod<void>('rescan');
    } on PlatformException catch (e) {
      throw MdnsException(e.code, e.message ?? 'mdns rescan failed');
    }
  }

  /// Releases the broadcast subscription. Tests should call this in
  /// `tearDown`.
  Future<void> dispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    await _controller.close();
  }
}
