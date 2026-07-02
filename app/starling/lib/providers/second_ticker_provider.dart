import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'second_ticker_provider.g.dart';

/// A shared 1-second heartbeat for ticking call-duration displays (mm:ss).
/// The minute ticker is too coarse for that; keep this one scoped to
/// in-call UI so the app isn't rebuilding every second at rest —
/// auto-disposes when the last watcher (the call screens) unmounts.
@riverpod
Stream<int> secondTicker(Ref ref) =>
    Stream<int>.periodic(const Duration(seconds: 1), (i) => i);
