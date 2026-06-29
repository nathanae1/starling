import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/profile.dart';

part 'profile_provider.g.dart';

/// Transient onboarding profile state — name + avatar the user is entering on
/// the Setup screen before anything is persisted. Cleared once onboarding
/// completes. The durable profile (loaded from the latest kind=2 event) will
/// live on a separate provider once Plan 05 lands.
@riverpod
class OnboardingProfileController extends _$OnboardingProfileController {
  @override
  Profile build() => const Profile(displayName: '');

  void setDisplayName(String name) {
    state = state.copyWith(displayName: name);
  }

  void setAvatarBytes(Uint8List bytes) {
    state = state.copyWith(avatarBytes: bytes);
  }

  void clearAvatar() {
    state = Profile(displayName: state.displayName, bio: state.bio);
  }

  void reset() => state = const Profile(displayName: '');
}
