import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/types.dart';
import 'service_providers.dart';

part 'follow_requests_provider.g.dart';

/// Live pending inbound follow requests for the Friends tab banner.
@riverpod
Stream<List<FollowRequest>> inboundRequestsStream(Ref ref) {
  final storage = ref.watch(storageServiceProvider);
  return storage.watchInboundRequests();
}

/// Live actioned inbound rows (status != 'pending') — peers who scanned
/// our QR and whom we've already accepted (or are still trying to deliver
/// the accept to). The friends list shows these as "Follows you" rows
/// when we don't follow them back yet.
@riverpod
Stream<List<FollowRequest>> inboundFollowersStream(Ref ref) {
  final storage = ref.watch(storageServiceProvider);
  return storage.watchInboundFollowers();
}

/// Live outbound follow requests (any status) for the Friends tab "Pending"
/// rows.
@riverpod
Stream<List<FollowRequest>> outboundRequestsStream(Ref ref) {
  final storage = ref.watch(storageServiceProvider);
  return storage.watchOutboundRequests();
}
