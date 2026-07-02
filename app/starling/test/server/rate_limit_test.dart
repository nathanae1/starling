import 'package:starling/server/middleware/rate_limit.dart';
import 'package:starling/services/mocks/mock_clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';

void main() {
  late MockClock clock;
  late RateLimiter limiter;

  setUp(() {
    clock = MockClock();
    limiter = RateLimiter(
      requestsPerMinute: 5,
      window: const Duration(seconds: 60),
      clock: clock,
    );
  });

  tearDown(() => limiter.dispose());

  Handler buildHandler() =>
      limiter.middleware((Request _) async => Response.ok('ok'));

  Request requestFrom(String address) => Request(
    'GET',
    Uri.parse('http://localhost/'),
    context: {'starling.test.remote_address': address},
  );

  test('allows up to the configured limit, then 429', () async {
    final handler = buildHandler();
    for (var i = 0; i < 5; i++) {
      final res = await handler(requestFrom('1.1.1.1'));
      expect(res.statusCode, 200);
    }
    final blocked = await handler(requestFrom('1.1.1.1'));
    expect(blocked.statusCode, 429);
    expect(blocked.headers['retry-after'], '60');
  });

  test('separate addresses have separate buckets', () async {
    final handler = buildHandler();
    for (var i = 0; i < 5; i++) {
      final res = await handler(requestFrom('1.1.1.1'));
      expect(res.statusCode, 200);
    }
    final fromOther = await handler(requestFrom('2.2.2.2'));
    expect(fromOther.statusCode, 200);
  });

  test('counter resets once the window elapses', () async {
    final handler = buildHandler();
    for (var i = 0; i < 5; i++) {
      await handler(requestFrom('1.1.1.1'));
    }
    final blocked = await handler(requestFrom('1.1.1.1'));
    expect(blocked.statusCode, 429);

    clock.advance(61);
    final after = await handler(requestFrom('1.1.1.1'));
    expect(after.statusCode, 200);
  });
}
