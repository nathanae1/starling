import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'minute_ticker_provider.g.dart';

/// Shared 60 s heartbeat for relative-time labels ("synced 4m ago", post
/// timestamps, friend last-seen). Widgets watch this next to `clockProvider`
/// so their labels re-compute each minute without every widget owning its
/// own `Timer`. Auto-disposes when no relative-time label is on screen.
@riverpod
Stream<int> minuteTicker(Ref ref) =>
    Stream<int>.periodic(const Duration(minutes: 1), (i) => i);
