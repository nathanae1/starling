import 'dart:async';
import 'dart:io';

import '../services/follow_service.dart';
import '../services/lan_network_service.dart';
import '../services/tor/arti_tor_service.dart';
import 'debug_log.dart';

/// Human copy for a caught error. Users never see raw
/// `Exception`/`StateError` strings — known failure types map to plain
/// language here, everything else falls back to a generic line, and the raw
/// detail always goes to [debugLog] under [tag] so it stays diagnosable.
String friendlyError(Object error, {String tag = 'error'}) {
  debugLog(tag, 'friendlyError: $error');
  return switch (error) {
    FollowFailure(:final kind) => switch (kind) {
      FollowFailureKind.noEndpoints =>
        "We couldn't reach this person — they have no endpoints yet.",
      FollowFailureKind.network =>
        "Couldn't connect. Check your connection and try again.",
      FollowFailureKind.unknownRequester =>
        "Couldn't load your identity. Try again.",
      FollowFailureKind.decryptFailed =>
        'Something went wrong preparing the request.',
    },
    TorServiceException() =>
      'The network connection is still starting up — try again in a moment.',
    TimeoutException() =>
      'That took too long. Check your connection and try again.',
    SocketException() || NetworkException() =>
      "Couldn't connect. Check your connection and try again.",
    _ => 'Something went wrong. Try again.',
  };
}
