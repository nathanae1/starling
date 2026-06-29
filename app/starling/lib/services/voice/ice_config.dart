/// Plan 16 — WebRTC ICE configuration.
///
/// Serverless by default: [customServers] is empty, so WebRTC gathers only
/// `host` candidates (LAN + native IPv6), the connectivity bet inherited from
/// Plan 11c. The opt-in escape hatch lets a user paste their own
/// `stun:`/`turn:` servers (e.g. a self-hosted coturn) — off by default and
/// understood to leave Starling's no-third-party-servers guarantee.
class IceConfig {
  const IceConfig({this.customServers = const []});

  /// `iceServers` entries in WebRTC's expected shape, e.g.
  /// `{'urls': 'turn:host:3478', 'username': 'u', 'credential': 'p'}`.
  final List<Map<String, dynamic>> customServers;

  /// Build the `RTCConfiguration` map for `createPeerConnection`.
  ///
  /// Invariants (Plan 16 §Connectivity): never set `iceTransportPolicy:
  /// relay` (that would force a TURN we don't run by default), and never
  /// disable IPv6 — the v6 host candidate is the WAN workhorse.
  Map<String, dynamic> toRtcConfiguration() => {
    'iceServers': customServers,
    'sdpSemantics': 'unified-plan',
    'iceTransportPolicy': 'all',
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require',
  };

  /// Parse a user-pasted block into `iceServers` entries. One server per
  /// line; blank lines and `#` comments ignored. Accepted forms:
  ///
  /// ```
  /// stun:stun.example.org:3478
  /// turn:turn.example.org:3478 | username | credential
  /// turns:turn.example.org:5349|username|credential
  /// ```
  ///
  /// Malformed lines are skipped (best-effort; the field is advanced/opt-in).
  static List<Map<String, dynamic>> parseServers(String raw) {
    final out = <Map<String, dynamic>>[];
    for (final line in raw.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final parts = trimmed.split('|').map((p) => p.trim()).toList();
      final url = parts.first;
      if (!_looksLikeIceUrl(url)) continue;
      final entry = <String, dynamic>{'urls': url};
      if (parts.length >= 3) {
        if (parts[1].isNotEmpty) entry['username'] = parts[1];
        if (parts[2].isNotEmpty) entry['credential'] = parts[2];
      }
      out.add(entry);
    }
    return out;
  }

  static bool _looksLikeIceUrl(String url) =>
      url.startsWith('stun:') ||
      url.startsWith('stuns:') ||
      url.startsWith('turn:') ||
      url.startsWith('turns:');
}
