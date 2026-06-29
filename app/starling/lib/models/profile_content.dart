import 'dart:convert';
import 'dart:typed_data';

/// Decoded form of a kind=2 profile event's JSON `content`.
///
/// The wire contract (protocol-spec.md kind=2, plan 04) is UTF-8 JSON with
/// keys `name`, `bio`, `avatar_hash`. This codec is the single source of
/// truth for those keys so the writer ([ProfileService]) and the readers
/// ([ownProfileProvider], [followProfileProvider]) can't drift. Note the
/// model/UI field is `displayName` while the wire key is `name`.
class ProfileContent {
  const ProfileContent({required this.name, this.bio, this.avatarHash});

  /// May be empty when the source JSON omitted/blanked it — callers decide
  /// the fallback ("You" for own, a short hash for a friend).
  final String name;
  final String? bio;
  final String? avatarHash;
}

/// JSON-encode a kind=2 profile content blob. Blank optional fields are
/// omitted so a name-only profile stays `{"name":"..."}` and clearing an
/// avatar simply drops `avatar_hash`.
Uint8List encodeProfileContent({
  required String name,
  String? bio,
  String? avatarHash,
}) {
  final map = <String, dynamic>{'name': name.trim()};
  final cleanBio = bio?.trim();
  if (cleanBio != null && cleanBio.isNotEmpty) {
    map['bio'] = cleanBio;
  }
  final cleanHash = avatarHash?.trim();
  if (cleanHash != null && cleanHash.isNotEmpty) {
    map['avatar_hash'] = cleanHash;
  }
  return Uint8List.fromList(utf8.encode(jsonEncode(map)));
}

/// Decode a kind=2 profile content blob. Returns null when the bytes are not
/// valid JSON — callers fall back to a default rather than crash. A present
/// but blank field decodes to null/empty.
ProfileContent? decodeProfileContent(Uint8List content) {
  try {
    final raw = utf8.decode(content, allowMalformed: true);
    final map = jsonDecode(raw) as Map<String, dynamic>;
    String? clean(String key) {
      final v = (map[key] as String?)?.trim();
      return v != null && v.isNotEmpty ? v : null;
    }

    return ProfileContent(
      name: clean('name') ?? '',
      bio: clean('bio'),
      avatarHash: clean('avatar_hash'),
    );
  } catch (_) {
    return null;
  }
}
