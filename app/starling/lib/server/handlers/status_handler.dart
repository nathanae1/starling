import 'dart:convert';

import 'package:shelf/shelf.dart';

import '../../models/protocol_version.dart';
import '../../services/storage_service.dart';
import '../../services/types.dart';

/// `GET /status` — JSON view of who this server speaks for, what protocol
/// version it implements, and rough storage stats. No auth.
Handler statusHandler({
  required StorageService storage,
  required Future<Identity?> Function() identityLookup,
}) {
  return (Request request) async {
    final identity = await identityLookup();
    if (identity == null) {
      return Response(503, body: 'not ready');
    }
    final ownEvents = await storage.getEvents(pubkey: identity.pubkey);
    final mediaUsed = await storage.getMediaCacheSize();
    // Exclude chatroom kinds (100-103) from the public event count so a
    // peer can't infer room activity from /status (Plan 17).
    final feedEventCount = ownEvents.where((e) => !e.kind.isRoomScoped).length;
    final body = jsonEncode({
      'pubkey': identity.pubkey,
      'version': kStarlingProtocolVersion,
      'event_count': feedEventCount,
      'media_storage_used': mediaUsed,
    });
    return Response.ok(
      body,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  };
}
