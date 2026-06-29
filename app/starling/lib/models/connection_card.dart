import 'dart:typed_data';

import 'package:cbor/simple.dart';
import 'package:collection/collection.dart';

class Endpoint {
  const Endpoint({required this.type, required this.address});

  final String type; // "onion" or "relay"
  final String address;

  Map<String, dynamic> toMap() => {'type': type, 'address': address};

  static Endpoint fromMap(Map<dynamic, dynamic> map) =>
      Endpoint(type: map['type'] as String, address: map['address'] as String);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Endpoint && type == other.type && address == other.address;

  @override
  int get hashCode => Object.hash(type, address);

  @override
  String toString() => 'Endpoint(type: $type, address: $address)';
}

class ConnectionCard {
  const ConnectionCard({
    required this.pubkey,
    this.endpoints = const [],
    this.capabilities = const ['pairwise-v1', 'libp2p-direct-v1'],
  });

  final String pubkey;
  final List<Endpoint> endpoints;
  final List<String> capabilities;

  Map<String, dynamic> toMap() => {
    'pubkey': pubkey,
    'endpoints': endpoints.map((e) => e.toMap()).toList(),
    'capabilities': capabilities,
  };

  Uint8List toBytes() => Uint8List.fromList(cbor.encode(toMap()));

  static ConnectionCard fromMap(Map<dynamic, dynamic> map) => ConnectionCard(
    pubkey: map['pubkey'] as String,
    endpoints: (map['endpoints'] as List<dynamic>)
        .map((item) => Endpoint.fromMap(item as Map<dynamic, dynamic>))
        .toList(),
    capabilities:
        (map['capabilities'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const ['pairwise-v1'],
  );

  static ConnectionCard fromBytes(Uint8List bytes) =>
      fromMap(cbor.decode(bytes) as Map<dynamic, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConnectionCard &&
          pubkey == other.pubkey &&
          const ListEquality<Endpoint>().equals(endpoints, other.endpoints) &&
          const ListEquality<String>().equals(capabilities, other.capabilities);

  @override
  int get hashCode =>
      Object.hash(pubkey, endpoints.length, capabilities.length);

  @override
  String toString() =>
      'ConnectionCard(pubkey: $pubkey, endpoints: ${endpoints.length}, '
      'capabilities: $capabilities)';

  ConnectionCard copyWith({
    String? pubkey,
    List<Endpoint>? endpoints,
    List<String>? capabilities,
  }) => ConnectionCard(
    pubkey: pubkey ?? this.pubkey,
    endpoints: endpoints ?? this.endpoints,
    capabilities: capabilities ?? this.capabilities,
  );
}
