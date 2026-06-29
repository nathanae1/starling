import 'package:drift/drift.dart';

class InboundFollowRequestEntries extends Table {
  TextColumn get pubkey => text()();
  BlobColumn get encryptedEndpoints => blob()();
  IntColumn get createdAt => integer()();
  // Wire timestamp echoed by the requester. Distinct from createdAt because
  // createdAt is the time we received the request, while requestTimestamp is
  // the time the requester signed into the outer CBOR for shared-key
  // derivation. Both sides must derive the shared key from the same value.
  IntColumn get requestTimestamp => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {pubkey};
}
