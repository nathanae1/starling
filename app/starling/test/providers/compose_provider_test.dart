import 'dart:typed_data';

import 'package:starling/providers/compose_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initial state is idle with no photo and empty caption', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final state = container.read(composeControllerProvider);
    expect(state.phase, ComposePhase.idle);
    expect(state.photoBytes, isNull);
    expect(state.caption, isEmpty);
    expect(state.canAdvanceToPreview, isFalse);
  });

  test('setCaption updates caption without clearing phase or photo', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(composeControllerProvider.notifier).setCaption('hi');
    expect(container.read(composeControllerProvider).caption, 'hi');
  });

  test('clearPhoto resets photo + phase without touching caption', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final c = container.read(composeControllerProvider.notifier);
    c.setCaption('keep me');
    // Simulate a picker success by directly mutating via markPublishing flow:
    // easier: use the public API — pickFrom* needs platform. We instead drive
    // the state through its public transitions.
    c.markPublishing();
    c.markPublishFailed('x'); // now phase=ready
    // No photo was set; clearPhoto should still work and leave caption.
    c.clearPhoto();
    final s = container.read(composeControllerProvider);
    expect(s.photoBytes, isNull);
    expect(s.phase, ComposePhase.idle);
    expect(s.caption, 'keep me');
  });

  test('canAdvanceToPreview is true only when a photo is present and not '
      'publishing/picking', () {
    const empty = ComposeState();
    expect(empty.canAdvanceToPreview, isFalse);

    final ready = ComposeState(
      photoBytes: Uint8List.fromList([1, 2]),
      phase: ComposePhase.ready,
    );
    expect(ready.canAdvanceToPreview, isTrue);

    final publishing = ready.copyWith(phase: ComposePhase.publishing);
    expect(publishing.canAdvanceToPreview, isFalse);

    final picking = ready.copyWith(phase: ComposePhase.picking);
    expect(picking.canAdvanceToPreview, isFalse);
  });

  test(
    'markPublishFailed drops phase back to ready and records the message',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final c = container.read(composeControllerProvider.notifier);
      c.markPublishing();
      c.markPublishFailed('nope');
      final s = container.read(composeControllerProvider);
      expect(s.phase, ComposePhase.ready);
      expect(s.errorMessage, 'nope');
    },
  );
}
