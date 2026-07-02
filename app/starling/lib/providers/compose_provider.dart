import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../utils/debug_log.dart';

part 'compose_provider.g.dart';

enum ComposePhase {
  /// No photo chosen, no picker open.
  idle,

  /// The native picker or camera sheet is open.
  picking,

  /// A photo is selected and ready to preview / publish.
  ready,

  /// The publish pipeline is running.
  publishing,
}

class ComposeState {
  const ComposeState({
    this.photoBytes,
    this.mimeType,
    this.caption = '',
    this.phase = ComposePhase.idle,
    this.errorMessage,
  });

  final Uint8List? photoBytes;
  final String? mimeType;
  final String caption;
  final ComposePhase phase;
  final String? errorMessage;

  bool get canAdvanceToPreview =>
      photoBytes != null &&
      phase != ComposePhase.publishing &&
      phase != ComposePhase.picking;

  ComposeState copyWith({
    Uint8List? photoBytes,
    bool clearPhoto = false,
    String? mimeType,
    String? caption,
    ComposePhase? phase,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ComposeState(
      photoBytes: clearPhoto ? null : (photoBytes ?? this.photoBytes),
      mimeType: clearPhoto ? null : (mimeType ?? this.mimeType),
      caption: caption ?? this.caption,
      phase: phase ?? this.phase,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Compose-screen scratch state. Lives across Compose → Preview → back-to-edit
/// so the photo and caption survive the sub-route push. Invalidate on modal
/// close (either ✕ or successful publish).
///
/// `keepAlive: true` so the state survives the transient gap between the ✕
/// icon popping Compose and any listener re-subscribing — and so that tests
/// that seed state via [ComposeController.debugSeedState] before the
/// widget tree mounts don't lose it to auto-dispose.
@Riverpod(keepAlive: true)
class ComposeController extends _$ComposeController {
  ImagePicker? _pickerOverride;

  @override
  ComposeState build() => const ComposeState();

  /// Test hook: inject a stub `ImagePicker` to avoid platform-channel calls.
  // ignore: use_setters_to_change_properties
  void debugSetPicker(ImagePicker picker) => _pickerOverride = picker;

  /// Test hook: replace the current state wholesale. Not part of the public
  /// API — widget tests use this to put the screen into an arbitrary phase
  /// without driving the native picker.
  @visibleForTesting
  // ignore: use_setters_to_change_properties
  void debugSeedState(ComposeState next) => state = next;

  ImagePicker get _picker => _pickerOverride ?? ImagePicker();

  Future<void> pickFromGallery() => _pick(ImageSource.gallery);
  Future<void> pickFromCamera() => _pick(ImageSource.camera);

  Future<void> _pick(ImageSource source) async {
    if (state.phase == ComposePhase.publishing) return;
    state = state.copyWith(phase: ComposePhase.picking, clearError: true);
    try {
      final file = await _picker.pickImage(source: source, imageQuality: 100);
      if (file == null) {
        state = state.copyWith(
          phase: state.photoBytes == null
              ? ComposePhase.idle
              : ComposePhase.ready,
        );
        return;
      }
      final bytes = await file.readAsBytes();
      state = state.copyWith(
        photoBytes: bytes,
        mimeType: file.mimeType ?? 'image/jpeg',
        phase: ComposePhase.ready,
        clearError: true,
      );
    } on Object catch (e) {
      debugLog('compose', 'photo pick failed: $e');
      state = state.copyWith(
        phase: state.photoBytes == null
            ? ComposePhase.idle
            : ComposePhase.ready,
        errorMessage: "Couldn't open that photo. Try another.",
      );
    }
  }

  void clearPhoto() {
    state = state.copyWith(
      clearPhoto: true,
      phase: ComposePhase.idle,
      clearError: true,
    );
  }

  void setCaption(String text) {
    state = state.copyWith(caption: text);
  }

  void markPublishing() {
    state = state.copyWith(phase: ComposePhase.publishing, clearError: true);
  }

  void markPublishFailed(String message) {
    state = state.copyWith(phase: ComposePhase.ready, errorMessage: message);
  }
}
