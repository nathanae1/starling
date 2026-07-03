// Diff-asserting vector regeneration (Phase 4 vector hygiene).
//
// This test rebuilds every pinned vector from the production encoders and
// FAILS if `index.json` no longer matches — so an encoder change can't
// land without consciously regenerating the pinned bytes (and waking the
// Rust side via `wire_vectors.rs`, which reads the same file).
//
// To regenerate after an intentional protocol change:
//
//   STARLING_WRITE_VECTORS=1 flutter test test/vectors/vectors_gen.dart
//
// then re-run the Dart + Rust vector suites and commit the diff.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'vectors_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('index.json matches freshly-generated protocol vectors', () async {
    final vectors = await buildProtocolVectors();
    final file = File('test/vectors/index.json');

    if (Platform.environment['STARLING_WRITE_VECTORS'] == '1') {
      file.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(vectors)}\n',
      );
    }

    expect(file.existsSync(), isTrue, reason: 'run with STARLING_WRITE_VECTORS=1 to create it');
    expect(
      jsonDecode(file.readAsStringSync()),
      equals(vectors),
      reason:
          'test/vectors/index.json is stale. If the wire change is '
          'intentional, regenerate with STARLING_WRITE_VECTORS=1 '
          'flutter test test/vectors/vectors_gen.dart and re-run the Rust '
          'wire_vectors tests.',
    );
  });
}
