import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/profile_content.dart';
import 'identity_provider.dart';
import 'service_providers.dart';

part 'own_profile_provider.g.dart';

/// What the "You" tab + post cards show as the device owner's identity.
/// Sourced from the latest kind=2 (profile) event when one exists.
class OwnProfileSnapshot {
  const OwnProfileSnapshot({
    required this.displayName,
    this.bio,
    this.avatarHash,
    this.avatarMsgSeq,
  });

  final String displayName;
  final String? bio;
  final String? avatarHash;

  /// `msg_seq` of the profile event that carried [avatarHash]. Combined with
  /// the owner's feed-key chain root it re-derives the AEAD key the avatar
  /// blob was encrypted under. Null when there's no avatar.
  final int? avatarMsgSeq;
}

/// Reads the latest kind=2 event for own pubkey and decodes its JSON content
/// into a profile snapshot. Falls back to "You" with no avatar when no
/// profile event has been written yet (e.g. a restore that hasn't re-synced)
/// or the content is malformed.
@riverpod
Future<OwnProfileSnapshot> ownProfile(Ref ref) async {
  final identity = await ref.watch(identityControllerProvider.future);
  if (identity == null) {
    return const OwnProfileSnapshot(displayName: 'You');
  }
  final storage = ref.watch(storageServiceProvider);
  final event = await storage.getLatestProfile(identity.pubkey);
  if (event == null) {
    return const OwnProfileSnapshot(displayName: 'You');
  }

  final profile = decodeProfileContent(event.content);
  if (profile == null) {
    // Malformed kind=2 — defensively show "You" rather than crashing the tab.
    return const OwnProfileSnapshot(displayName: 'You');
  }

  return OwnProfileSnapshot(
    displayName: profile.name.isNotEmpty ? profile.name : 'You',
    bio: profile.bio,
    avatarHash: profile.avatarHash,
    avatarMsgSeq: profile.avatarHash != null ? event.msgSeq : null,
  );
}
