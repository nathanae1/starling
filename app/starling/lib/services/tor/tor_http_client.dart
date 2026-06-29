import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'socks5_socket.dart';

/// Routes [http.BaseClient] requests through Arti's in-process SOCKS5
/// proxy. Each request opens a fresh SOCKS tunnel to the request's
/// target host (typically a `.onion` address), writes a minimal HTTP/1.1
/// request, and streams the response back as an [http.StreamedResponse].
///
/// We bypass `dart:io`'s [HttpClient] entirely. `HttpClient.connectionFactory`
/// can hand a pre-connected [Socket] to `HttpClient`, but only one that
/// hasn't been listened to yet — and we have to listen to drive the SOCKS
/// handshake. Doing the HTTP/1.1 framing ourselves over a tunnel sidesteps
/// the issue and is small (we only talk to our own Starling server, so we
/// don't need to handle every HTTP edge case).
class TorHttpClient extends http.BaseClient {
  TorHttpClient({
    required this.socksHost,
    required this.socksPort,
    this.timeout = const Duration(seconds: 30),
  });

  final String socksHost;
  final int socksPort;
  final Duration timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final uri = request.url;
    final targetPort = uri.hasPort ? uri.port : 80;
    final tunnel = await openSocks5(
      proxyHost: socksHost,
      proxyPort: socksPort,
      targetHost: uri.host,
      targetPort: targetPort,
      timeout: timeout,
    );

    final body = await request.finalize().toBytes();
    final headers = <String, String>{
      ...request.headers,
      'host': uri.hasPort ? '${uri.host}:${uri.port}' : uri.host,
      'connection': 'close',
      'accept-encoding': 'identity',
    };
    if (body.isNotEmpty || _methodHasBody(request.method)) {
      headers['content-length'] = body.length.toString();
    }

    final pathAndQuery = uri.hasQuery
        ? '${uri.path.isEmpty ? '/' : uri.path}?${uri.query}'
        : (uri.path.isEmpty ? '/' : uri.path);

    final reqHead = StringBuffer()
      ..write('${request.method} $pathAndQuery HTTP/1.1\r\n');
    headers.forEach((k, v) {
      reqHead.write('$k: $v\r\n');
    });
    reqHead.write('\r\n');

    tunnel.socket.add(utf8.encode(reqHead.toString()));
    if (body.isNotEmpty) tunnel.socket.add(body);
    await tunnel.socket.flush();

    return _readResponse(tunnel, request).timeout(timeout);
  }

  bool _methodHasBody(String method) {
    final upper = method.toUpperCase();
    return upper == 'POST' || upper == 'PUT' || upper == 'PATCH';
  }

  Future<http.StreamedResponse> _readResponse(
    SocksTunnel tunnel,
    http.BaseRequest request,
  ) async {
    final reader = _ResponseReader(tunnel.stream);
    try {
      final headerBytes = await reader.readUntilDoubleCrlf();
      final headerText = utf8.decode(headerBytes, allowMalformed: true);
      final lines = headerText.split('\r\n')..removeWhere((l) => l.isEmpty);
      if (lines.isEmpty) {
        throw const _TorHttpException('empty HTTP response');
      }
      final statusLine = lines.removeAt(0);
      final statusParts = statusLine.split(' ');
      if (statusParts.length < 2 || !statusParts[0].startsWith('HTTP/')) {
        throw _TorHttpException('bad status line: $statusLine');
      }
      final statusCode = int.tryParse(statusParts[1]);
      if (statusCode == null) {
        throw _TorHttpException('non-numeric status: $statusLine');
      }
      final reasonPhrase = statusParts.length > 2
          ? statusParts.sublist(2).join(' ')
          : null;

      final headers = <String, String>{};
      for (final line in lines) {
        final colon = line.indexOf(':');
        if (colon <= 0) continue;
        final name = line.substring(0, colon).trim().toLowerCase();
        final value = line.substring(colon + 1).trim();
        if (headers.containsKey(name)) {
          headers[name] = '${headers[name]}, $value';
        } else {
          headers[name] = value;
        }
      }

      final transferEncoding = headers['transfer-encoding']?.toLowerCase();
      final isChunked =
          transferEncoding != null &&
          transferEncoding.split(',').any((t) => t.trim() == 'chunked');
      final contentLength = int.tryParse(headers['content-length'] ?? '');

      final Stream<List<int>> bodyStream;
      if (isChunked) {
        bodyStream = reader.readChunked();
      } else if (contentLength != null) {
        bodyStream = reader.readExact(contentLength);
      } else {
        bodyStream = reader.readToEnd();
      }
      // When the body stream completes, ensure the socket is closed.
      final closingStream = bodyStream.transform(
        StreamTransformer<List<int>, List<int>>.fromHandlers(
          handleDone: (sink) {
            sink.close();
            unawaited(tunnel.close());
          },
        ),
      );

      return http.StreamedResponse(
        closingStream,
        statusCode,
        contentLength: contentLength,
        request: request,
        headers: headers,
        isRedirect: false,
        persistentConnection: false,
        reasonPhrase: reasonPhrase,
      );
    } catch (e) {
      await tunnel.close();
      rethrow;
    }
  }
}

/// Buffered reader over the SOCKS tunnel's inbound stream. Provides
/// "read until \r\n\r\n", "read N bytes", and "read to EOF" helpers
/// keyed off a single subscription.
class _ResponseReader {
  _ResponseReader(Stream<Uint8List> source)
    : _source = StreamIterator<Uint8List>(source);

  final StreamIterator<Uint8List> _source;
  final BytesBuilder _buf = BytesBuilder(copy: false);

  Future<bool> _pull() async {
    final has = await _source.moveNext();
    if (!has) return false;
    _buf.add(_source.current);
    return true;
  }

  Future<Uint8List> readUntilDoubleCrlf() async {
    while (true) {
      final snap = _buf.toBytes();
      final idx = _findDoubleCrlf(snap);
      if (idx >= 0) {
        _buf.clear();
        if (snap.length > idx + 4) {
          _buf.add(Uint8List.sublistView(snap, idx + 4));
        }
        return Uint8List.sublistView(snap, 0, idx);
      }
      final more = await _pull();
      if (!more) {
        throw const _TorHttpException('connection closed before HTTP headers');
      }
    }
  }

  Stream<List<int>> readExact(int n) async* {
    var remaining = n;
    if (_buf.isNotEmpty) {
      final snap = _buf.takeBytes();
      if (snap.length <= remaining) {
        remaining -= snap.length;
        yield snap;
      } else {
        yield Uint8List.sublistView(snap, 0, remaining);
        _buf.add(Uint8List.sublistView(snap, remaining));
        remaining = 0;
      }
    }
    while (remaining > 0) {
      final has = await _source.moveNext();
      if (!has) {
        throw _TorHttpException(
          'connection closed with $remaining bytes still expected',
        );
      }
      final chunk = _source.current;
      if (chunk.length <= remaining) {
        remaining -= chunk.length;
        yield chunk;
      } else {
        yield Uint8List.sublistView(chunk, 0, remaining);
        _buf.add(Uint8List.sublistView(chunk, remaining));
        remaining = 0;
      }
    }
  }

  Stream<List<int>> readToEnd() async* {
    if (_buf.isNotEmpty) {
      yield _buf.takeBytes();
    }
    while (await _source.moveNext()) {
      yield _source.current;
    }
  }

  Stream<List<int>> readChunked() async* {
    while (true) {
      final lineBytes = await _readLine();
      final line = utf8.decode(lineBytes, allowMalformed: true).trim();
      final semi = line.indexOf(';');
      final sizeStr = (semi >= 0 ? line.substring(0, semi) : line).trim();
      final size = int.tryParse(sizeStr, radix: 16);
      if (size == null) {
        throw _TorHttpException('bad chunk size line: $line');
      }
      if (size == 0) {
        // Drain trailers until empty line.
        while (true) {
          final trailer = await _readLine();
          if (trailer.isEmpty) return;
        }
      }
      yield* readExact(size);
      final crlf = await _readLine();
      if (crlf.isNotEmpty) {
        throw const _TorHttpException('expected CRLF after chunk');
      }
    }
  }

  Future<Uint8List> _readLine() async {
    while (true) {
      final snap = _buf.toBytes();
      final idx = _findCrlf(snap);
      if (idx >= 0) {
        _buf.clear();
        if (snap.length > idx + 2) {
          _buf.add(Uint8List.sublistView(snap, idx + 2));
        }
        return Uint8List.sublistView(snap, 0, idx);
      }
      final more = await _pull();
      if (!more) {
        throw const _TorHttpException('connection closed before CRLF');
      }
    }
  }
}

int _findDoubleCrlf(Uint8List bytes) {
  for (var i = 0; i + 3 < bytes.length; i++) {
    if (bytes[i] == 0x0d &&
        bytes[i + 1] == 0x0a &&
        bytes[i + 2] == 0x0d &&
        bytes[i + 3] == 0x0a) {
      return i;
    }
  }
  return -1;
}

int _findCrlf(Uint8List bytes) {
  for (var i = 0; i + 1 < bytes.length; i++) {
    if (bytes[i] == 0x0d && bytes[i + 1] == 0x0a) return i;
  }
  return -1;
}

class _TorHttpException implements Exception {
  const _TorHttpException(this.message);
  final String message;
  @override
  String toString() => 'TorHttpException: $message';
}
