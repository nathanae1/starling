import 'package:app_links/app_links.dart';

import 'connection_card_parser.dart';

/// Wraps the platform deep-link stream and parses incoming
/// `starling://connect?card=...` (friend invite) and
/// `starling-relay://pair?card=...` (relay pairing, Plan 15) URIs into
/// [ParsedInvite] events. URIs that don't match a known scheme/host are
/// dropped silently.
class DeepLinkHandler {
  DeepLinkHandler({AppLinks? appLinks}) : _appLinks = appLinks ?? AppLinks();

  final AppLinks _appLinks;

  /// Stream of parsed invites from cold-start and runtime deep-link events.
  Stream<ParsedInvite> get invites async* {
    final initial = await _appLinks.getInitialLink();
    if (initial != null) {
      final parsed = _parse(initial);
      if (parsed != null) yield parsed;
    }
    yield* _appLinks.uriLinkStream
        .map(_parse)
        .where((event) => event != null)
        .cast<ParsedInvite>();
  }

  ParsedInvite? _parse(Uri uri) {
    final isFriendInvite = uri.scheme == 'starling' && uri.host == 'connect';
    final isRelayPair = uri.scheme == 'starling-relay' && uri.host == 'pair';
    if (!isFriendInvite && !isRelayPair) return null;
    return parseInvite(uri.toString());
  }
}
