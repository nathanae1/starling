import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:starling/models/profile_content.dart';

void main() {
  test('encode/decode round-trips name + bio + avatar_hash', () {
    final pc = decodeProfileContent(
      encodeProfileContent(name: 'Sam', bio: 'hi there', avatarHash: 'abc123'),
    )!;
    expect(pc.name, 'Sam');
    expect(pc.bio, 'hi there');
    expect(pc.avatarHash, 'abc123');
  });

  test('emits the exact wire keys name/bio/avatar_hash', () {
    final map =
        jsonDecode(
              utf8.decode(
                encodeProfileContent(name: 'Sam', bio: 'hi', avatarHash: 'h'),
              ),
            )
            as Map<String, dynamic>;
    expect(map.keys.toSet(), {'name', 'bio', 'avatar_hash'});
  });

  test('omits blank/null optional fields', () {
    final map =
        jsonDecode(
              utf8.decode(
                encodeProfileContent(name: 'Sam', bio: '   ', avatarHash: null),
              ),
            )
            as Map<String, dynamic>;
    expect(map.keys.toSet(), {'name'});
  });

  test('trims values on encode + decode', () {
    final pc = decodeProfileContent(encodeProfileContent(name: '  Sam  '))!;
    expect(pc.name, 'Sam');
  });

  test('decode returns null on malformed (non-JSON) bytes', () {
    expect(
      decodeProfileContent(Uint8List.fromList([0xff, 0x00, 0x12])),
      isNull,
    );
  });

  test('blank name decodes to empty so callers apply their own fallback', () {
    final pc = decodeProfileContent(
      Uint8List.fromList(utf8.encode('{"name":"   "}')),
    )!;
    expect(pc.name, '');
    expect(pc.avatarHash, isNull);
  });
}
