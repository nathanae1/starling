import 'dart:async';

import 'package:starling/sync/concurrency.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Pool runs at most maxConcurrent tasks at a time', () async {
    final pool = Pool(2);
    var running = 0;
    var peak = 0;

    final completers = List.generate(5, (_) => Completer<void>());
    final futures = <Future<int>>[];
    for (var i = 0; i < 5; i++) {
      futures.add(
        pool.run<int>(() async {
          running++;
          if (running > peak) peak = running;
          await completers[i].future;
          running--;
          return i;
        }),
      );
    }

    // Let the first batch enter the pool.
    await Future<void>.delayed(Duration.zero);
    expect(running, equals(2));
    expect(peak, equals(2));

    // Release the first task; the next queued task should slot in.
    completers[0].complete();
    await Future<void>.delayed(Duration.zero);
    expect(running, equals(2));

    // Drain the rest in order.
    for (var i = 1; i < 5; i++) {
      completers[i].complete();
    }
    final results = await Future.wait(futures);
    expect(results, equals(const [0, 1, 2, 3, 4]));
    expect(peak, equals(2));
  });

  test('Pool propagates task errors and frees slots', () async {
    final pool = Pool(1);
    Object? caught;
    try {
      await pool.run(() async => throw StateError('boom'));
    } catch (e) {
      caught = e;
    }
    expect(caught, isA<StateError>());

    // After the error the slot should be free again.
    final ok = await pool.run(() async => 42);
    expect(ok, equals(42));
  });
}
