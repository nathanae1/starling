import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:collection/collection.dart';

import 'event_kind.dart';
import 'media_ref.dart';

class Event {
  const Event({
    required this.version,
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    this.ref,
    required this.content,
    this.media = const [],
    this.extensions = const {},
    required this.sig,
    this.msgSeq,
  });

  final String version;
  final String id;
  final String pubkey;
  final int createdAt;
  final EventKind kind;
  final String? ref;
  final Uint8List content;
  final List<MediaRef> media;
  final Map<String, Uint8List> extensions;
  final Uint8List sig;
  // Local-storage-only metadata. Carries the publisher's `msg_seq` from
  // the EncryptedEvent wrapper through to disk so media decryption can
  // re-derive the per-message AEAD key. Deliberately excluded from
  // `toMap`/`toIdFields`/wire serialization — Event id/sig must remain
  // stable across the encrypt/decrypt boundary.
  final int? msgSeq;

  Map<String, dynamic> toMap() => {
    'version': version,
    'id': id,
    'pubkey': pubkey,
    'created_at': createdAt,
    'kind': kind.value,
    if (ref != null) 'ref': ref,
    'content': content,
    'media': media.map((m) => m.toMap()).toList(),
    'extensions': _extensionsToSerializable(extensions),
    'sig': sig,
  };

  /// Fields used for ID computation. Includes version and extensions.
  /// Excludes id and sig only.
  Map<String, dynamic> toIdFields() => {
    'version': version,
    'pubkey': pubkey,
    'created_at': createdAt,
    'kind': kind.value,
    if (ref != null) 'ref': ref,
    'content': content,
    'media': media.map((m) => m.toMap()).toList(),
    'extensions': _extensionsToSerializable(extensions),
  };

  Uint8List toBytes() => Uint8List.fromList(cbor.encode(toMap()));

  static Event fromMap(Map<dynamic, dynamic> map) => Event(
    version: map['version'] as String,
    id: map['id'] as String,
    pubkey: map['pubkey'] as String,
    createdAt: map['created_at'] as int,
    kind: EventKind.fromValue(map['kind'] as int),
    ref: map['ref'] as String?,
    content: _toUint8List(map['content']),
    media: (map['media'] as List<dynamic>)
        .map((item) => MediaRef.fromMap(item as Map<dynamic, dynamic>))
        .toList(),
    extensions: _extensionsFromMap(map['extensions']),
    sig: _toUint8List(map['sig']),
  );

  static Event fromBytes(Uint8List bytes) =>
      fromMap(cbor.decode(bytes) as Map<dynamic, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Event &&
          version == other.version &&
          id == other.id &&
          pubkey == other.pubkey &&
          createdAt == other.createdAt &&
          kind == other.kind &&
          ref == other.ref &&
          const ListEquality<int>().equals(content, other.content) &&
          const ListEquality<MediaRef>().equals(media, other.media) &&
          _extensionsEqual(extensions, other.extensions) &&
          const ListEquality<int>().equals(sig, other.sig);

  @override
  int get hashCode => Object.hash(version, id, pubkey, createdAt, kind, ref);

  @override
  String toString() =>
      'Event(id: $id, pubkey: $pubkey, kind: $kind, createdAt: $createdAt)';

  Event copyWith({
    String? version,
    String? id,
    String? pubkey,
    int? createdAt,
    EventKind? kind,
    String? ref,
    Uint8List? content,
    List<MediaRef>? media,
    Map<String, Uint8List>? extensions,
    Uint8List? sig,
    int? msgSeq,
  }) => Event(
    version: version ?? this.version,
    id: id ?? this.id,
    pubkey: pubkey ?? this.pubkey,
    createdAt: createdAt ?? this.createdAt,
    kind: kind ?? this.kind,
    ref: ref ?? this.ref,
    content: content ?? this.content,
    media: media ?? this.media,
    extensions: extensions ?? this.extensions,
    sig: sig ?? this.sig,
    msgSeq: msgSeq ?? this.msgSeq,
  );
}

// CBOR decode may return List<int> instead of Uint8List for byte strings.
Uint8List _toUint8List(dynamic value) {
  if (value is Uint8List) return value;
  if (value is List) return Uint8List.fromList(value.cast<int>());
  throw ArgumentError('Expected bytes, got ${value.runtimeType}');
}

Map<String, Uint8List> _extensionsFromMap(dynamic value) {
  if (value == null) return const {};
  if (value is Map) {
    return Map.unmodifiable(
      value.map((k, v) => MapEntry(k.toString(), _toUint8List(v))),
    );
  }
  return const {};
}

Map<String, dynamic> _extensionsToSerializable(Map<String, Uint8List> ext) {
  return Map<String, dynamic>.from(ext);
}

bool _extensionsEqual(Map<String, Uint8List> a, Map<String, Uint8List> b) {
  if (a.length != b.length) return false;
  const listEq = ListEquality<int>();
  for (final key in a.keys) {
    if (!b.containsKey(key)) return false;
    if (!listEq.equals(a[key]!, b[key]!)) return false;
  }
  return true;
}
