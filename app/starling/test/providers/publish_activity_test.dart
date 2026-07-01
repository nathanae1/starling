import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:starling/providers/publish_activity_provider.dart';

void main() {
  test('begin/end tracks overlapping publishes as a counter', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(publishActivityProvider), 0);

    final notifier = container.read(publishActivityProvider.notifier);
    notifier.begin();
    expect(container.read(publishActivityProvider), 1);
    // Overlapping publish — the count, not a bool, keeps "Publishing…" on
    // until BOTH finish.
    notifier.begin();
    expect(container.read(publishActivityProvider), 2);
    notifier.end();
    expect(container.read(publishActivityProvider), 1);
    notifier.end();
    expect(container.read(publishActivityProvider), 0);
    // Never underflows.
    notifier.end();
    expect(container.read(publishActivityProvider), 0);
  });
}
