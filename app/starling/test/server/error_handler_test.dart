import 'dart:async';
import 'dart:typed_data';

import 'package:starling/server/middleware/error_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

void main() {
  group('errorHandlerMiddleware', () {
    test('FormatException → 400', () async {
      final handler = errorHandlerMiddleware()(
        (Request _) async => throw const FormatException('bad'),
      );
      final res = await handler(Request('GET', Uri.parse('http://localhost/')));
      expect(res.statusCode, 400);
    });

    test('ArgumentError → 400', () async {
      final handler = errorHandlerMiddleware()(
        (Request _) async => throw ArgumentError('bad'),
      );
      final res = await handler(Request('GET', Uri.parse('http://localhost/')));
      expect(res.statusCode, 400);
    });

    test('uncaught throw → 500 without leaking message', () async {
      final handler = errorHandlerMiddleware()(
        (Request _) async => throw Exception('SECRET-LEAK'),
      );
      final res = await handler(Request('GET', Uri.parse('http://localhost/')));
      expect(res.statusCode, 500);
      final body = await res.readAsString();
      expect(body.contains('SECRET-LEAK'), isFalse);
      expect(body, contains('internal error'));
    });
  });

  group('bodySizeLimitMiddleware', () {
    test('passes through GET requests untouched', () async {
      final handler = bodySizeLimitMiddleware(maxBytes: 4)(
        (Request _) async => Response.ok('done'),
      );
      final res = await handler(Request('GET', Uri.parse('http://localhost/')));
      expect(res.statusCode, 200);
    });

    test('rejects POST with content-length over the cap', () async {
      var bodyRead = false;
      final handler = bodySizeLimitMiddleware(maxBytes: 4)((
        Request request,
      ) async {
        await request.read().drain<void>();
        bodyRead = true;
        return Response.ok('done');
      });
      final res = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/'),
          body: Uint8List.fromList(List.filled(10, 1)),
        ),
      );
      expect(res.statusCode, 413);
      expect(
        bodyRead,
        isFalse,
        reason: 'middleware should reject before invoking the inner handler',
      );
    });

    test('rejects POST with chunked over-cap stream', () async {
      // Build a stream with an unknown content length whose total exceeds the
      // cap: the wrapping stream throws _BodyTooLarge once the cap is crossed.
      final chunks = Stream<List<int>>.fromIterable([
        List<int>.filled(3, 0),
        List<int>.filled(5, 0),
      ]);
      final handler = bodySizeLimitMiddleware(maxBytes: 4)((
        Request request,
      ) async {
        await request.read().drain<void>();
        return Response.ok('done');
      });
      final res = await handler(
        Request('POST', Uri.parse('http://localhost/'), body: chunks),
      );
      expect(res.statusCode, 413);
    });

    test('passes through POST under the cap', () async {
      final handler = bodySizeLimitMiddleware(maxBytes: 1024)((
        Request request,
      ) async {
        final bytes = await request.read().fold<BytesBuilder>(
          BytesBuilder(),
          (b, c) => b..add(c),
        );
        return Response.ok('${bytes.length}');
      });
      final res = await handler(
        Request(
          'POST',
          Uri.parse('http://localhost/'),
          body: Uint8List.fromList(List.filled(100, 0)),
        ),
      );
      expect(res.statusCode, 200);
      expect(await res.readAsString(), '100');
    });
  });
}
