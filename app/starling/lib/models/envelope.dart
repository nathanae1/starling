import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:collection/collection.dart';

/// A typed item inside an Envelope. Each item carries its own integrity
/// mechanism defined by its type. The Envelope itself is untrusted.
///
/// Defined types (v1):
///   "event" — payload is a serialized EncryptedEvent, integrity via Ed25519 signature
///
/// Unknown types MUST be preserved and forwarded, not dropped.
class EnvelopeItem {
  const EnvelopeItem({
    required this.type,
    required this.payload,
    this.extensions = const {},
  });

  final String type;
  final Uint8List payload;
  final Map<String, Uint8List> extensions;

  Map<String, dynamic> toMap() => {
    'type': type,
    'payload': payload,
    'extensions': Map<String, dynamic>.from(extensions),
  };

  static EnvelopeItem fromMap(Map<dynamic, dynamic> map) {
    final extensions = <String, Uint8List>{};
    final rawExtensions = map['extensions'];
    if (rawExtensions is Map) {
      for (final entry in rawExtensions.entries) {
        extensions[entry.key.toString()] = _toUint8List(entry.value);
      }
    }

    return EnvelopeItem(
      type: map['type'] as String,
      payload: _toUint8List(map['payload']),
      extensions: Map.unmodifiable(extensions),
    );
  }

  Uint8List toBytes() => Uint8List.fromList(cbor.encode(toMap()));

  static EnvelopeItem fromBytes(Uint8List bytes) =>
      fromMap(cbor.decode(bytes) as Map<dynamic, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EnvelopeItem &&
          type == other.type &&
          const ListEquality<int>().equals(payload, other.payload) &&
          _mapsEqual(extensions, other.extensions);

  @override
  int get hashCode => Object.hash(type, payload.length);

  @override
  String toString() =>
      'EnvelopeItem(type: $type, payloadSize: ${payload.length})';
}

/// The transport unit. All sync and push operations move Envelopes,
/// not bare EncryptedEvents.
///
/// The Envelope itself is NOT signed and is NOT trusted. A receiver treats
/// it as an untrusted container: parse, extract items, verify each item
/// independently using the item type's integrity mechanism, discard envelope.
///
/// Envelope-level extensions are explicitly untrusted. Security-relevant data
/// must be promoted to a proper item type with its own signing scheme.
class Envelope {
  const Envelope({
    required this.version,
    required this.items,
    this.extensions = const {},
  });

  final String version;
  final List<EnvelopeItem> items;
  final Map<String, Uint8List> extensions;

  Map<String, dynamic> toMap() => {
    'version': version,
    'items': items.map((i) => i.toMap()).toList(),
    'extensions': Map<String, dynamic>.from(extensions),
  };

  Uint8List toBytes() => Uint8List.fromList(cbor.encode(toMap()));

  static Envelope fromMap(Map<dynamic, dynamic> map) {
    final extensions = <String, Uint8List>{};
    final rawExtensions = map['extensions'];
    if (rawExtensions is Map) {
      for (final entry in rawExtensions.entries) {
        extensions[entry.key.toString()] = _toUint8List(entry.value);
      }
    }

    return Envelope(
      version: map['version'] as String,
      items: (map['items'] as List<dynamic>)
          .map((item) => EnvelopeItem.fromMap(item as Map<dynamic, dynamic>))
          .toList(),
      extensions: Map.unmodifiable(extensions),
    );
  }

  static Envelope fromBytes(Uint8List bytes) =>
      fromMap(cbor.decode(bytes) as Map<dynamic, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Envelope &&
          version == other.version &&
          const ListEquality<EnvelopeItem>().equals(items, other.items) &&
          _mapsEqual(extensions, other.extensions);

  @override
  int get hashCode => Object.hash(version, items.length);

  @override
  String toString() => 'Envelope(version: $version, items: ${items.length})';
}

Uint8List _toUint8List(dynamic value) {
  if (value is Uint8List) return value;
  if (value is List) return Uint8List.fromList(value.cast<int>());
  throw ArgumentError('Expected bytes, got ${value.runtimeType}');
}

bool _mapsEqual(Map<String, Uint8List> a, Map<String, Uint8List> b) {
  if (a.length != b.length) return false;
  const listEq = ListEquality<int>();
  for (final key in a.keys) {
    if (!b.containsKey(key)) return false;
    if (!listEq.equals(a[key]!, b[key]!)) return false;
  }
  return true;
}
