import 'package:cbor/simple.dart';
import 'package:starling/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaRef CBOR serialization', () {
    test('round-trips through CBOR', () {
      const ref = MediaRef(hash: 'abc123', mimeType: 'image/jpeg', size: 1024);
      final bytes = cbor.encode(ref.toMap());
      final decoded = MediaRef.fromMap(
        cbor.decode(bytes) as Map<dynamic, dynamic>,
      );
      expect(decoded, equals(ref));
    });

    test('equal MediaRefs are equal', () {
      const a = MediaRef(hash: 'abc', mimeType: 'image/png', size: 512);
      const b = MediaRef(hash: 'abc', mimeType: 'image/png', size: 512);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different MediaRefs are not equal', () {
      const a = MediaRef(hash: 'abc', mimeType: 'image/png', size: 512);
      const b = MediaRef(hash: 'def', mimeType: 'image/png', size: 512);
      expect(a, isNot(equals(b)));
    });
  });
}
