import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'publish_activity_provider.g.dart';

/// Number of in-flight publish operations (compose → immediate fanout). Fresh
/// posts fan out on a separate path from the sync engine, so this is what lets
/// the sync indicator show "Publishing…" (vs "Loading feeds…"). A counter, not
/// a bool, so overlapping publishes don't clear the indicator early; read as
/// `> 0`. keepAlive so the count is stable across listener churn.
@Riverpod(keepAlive: true)
class PublishActivity extends _$PublishActivity {
  @override
  int build() => 0;

  void begin() => state = state + 1;

  void end() => state = state > 0 ? state - 1 : 0;
}
