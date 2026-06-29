import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/profile_content.dart';
import '../utils/pubkey_format.dart';
import 'identity_provider.dart';
import 'own_profile_provider.dart';
import 'service_providers.dart';

part 'follow_profile_provider.g.dart';

/// Display name + bio + avatar for an arbitrary pubkey, used by post cards
/// and other-profile screens. For own pubkey, dispatches to
/// [ownProfileProvider]; otherwise reads the friend's latest synced kind=2
/// profile event (the `follows` row carries no live name/avatar).
class FollowProfileSnapshot {
  const FollowProfileSnapshot({
    required this.displayName,
    this.bio,
    this.avatarHash,
    this.avatarMsgSeq,
  });

  final String displayName;
  final String? bio;
  final String? avatarHash;

  /// `msg_seq` of the profile event that carried [avatarHash], needed to
  /// re-derive the avatar blob's AEAD key. Null when there's no avatar.
  final int? avatarMsgSeq;
}

@riverpod
Future<FollowProfileSnapshot> followProfile(Ref ref, String pubkey) async {
  // Subscribe synchronously before any await — using `ref` after an await
  // is illegal if the provider was invalidated during the await.
  final identityFuture = ref.watch(identityControllerProvider.future);
  final ownProfileFuture = ref.watch(ownProfileProvider.future);
  final storage = ref.watch(storageServiceProvider);

  final identity = await identityFuture;
  if (identity != null && identity.pubkey == pubkey) {
    final own = await ownProfileFuture;
    return FollowProfileSnapshot(
      displayName: own.displayName,
      bio: own.bio,
      avatarHash: own.avatarHash,
      avatarMsgSeq: own.avatarMsgSeq,
    );
  }

  // Read the friend's latest kind=2 event directly (it syncs like any other
  // event and carries the msg_seq the avatar blob was encrypted under).
  final event = await storage.getLatestProfile(pubkey);
  final profile = event == null ? null : decodeProfileContent(event.content);
  final name = profile != null && profile.name.isNotEmpty
      ? profile.name
      : shortPubkey(pubkey);
  return FollowProfileSnapshot(
    displayName: name,
    bio: profile?.bio,
    avatarHash: profile?.avatarHash,
    avatarMsgSeq: profile?.avatarHash != null ? event?.msgSeq : null,
  );
}

/// First name for display (everything before the first whitespace).
String firstNameOf(String displayName) {
  final trimmed = displayName.trim();
  if (trimmed.isEmpty) return 'Friend';
  final ws = trimmed.indexOf(RegExp(r'\s'));
  return ws == -1 ? trimmed : trimmed.substring(0, ws);
}
