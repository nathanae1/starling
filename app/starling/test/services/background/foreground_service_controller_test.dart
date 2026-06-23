import 'package:flutter_test/flutter_test.dart';
import 'package:starling/services/background/foreground_service_controller.dart';

/// Unit-tests the pure reconcile decision (Plan 16). The plugin-driving side of
/// [ForegroundServiceController] talks to static `FlutterForegroundTask` methods
/// and is covered by manual on-device verification; the decision table is what
/// determines whether a voice call gets the `microphone` foreground type.
void main() {
  group('desiredFgState', () {
    test('neither intent ⇒ no service', () {
      final s = desiredFgState(persistent: false, callActive: false);
      expect(s.running, isFalse);
      expect(s.mic, isFalse);
    });

    test('a call alone ⇒ running with microphone', () {
      final s = desiredFgState(persistent: false, callActive: true);
      expect(s.running, isTrue);
      expect(s.mic, isTrue);
    });

    test('background mode alone ⇒ running without microphone', () {
      final s = desiredFgState(persistent: true, callActive: false);
      expect(s.running, isTrue);
      expect(s.mic, isFalse);
    });

    test('both ⇒ running with microphone', () {
      final s = desiredFgState(persistent: true, callActive: true);
      expect(s.running, isTrue);
      expect(s.mic, isTrue);
    });

    test('mic is requested iff a call is active', () {
      for (final persistent in [false, true]) {
        expect(
          desiredFgState(persistent: persistent, callActive: true).mic,
          isTrue,
        );
        expect(
          desiredFgState(persistent: persistent, callActive: false).mic,
          isFalse,
        );
      }
    });
  });
}
