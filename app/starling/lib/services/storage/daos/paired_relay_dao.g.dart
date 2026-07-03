// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'paired_relay_dao.dart';

// ignore_for_file: type=lint
mixin _$PairedRelayDaoMixin on DatabaseAccessor<AppDatabase> {
  $PairedRelayEntriesTable get pairedRelayEntries =>
      attachedDatabase.pairedRelayEntries;
  $PendingCardDistributionEntriesTable get pendingCardDistributionEntries =>
      attachedDatabase.pendingCardDistributionEntries;
  $RelayFanoutStateEntriesTable get relayFanoutStateEntries =>
      attachedDatabase.relayFanoutStateEntries;
  PairedRelayDaoManager get managers => PairedRelayDaoManager(this);
}

class PairedRelayDaoManager {
  final _$PairedRelayDaoMixin _db;
  PairedRelayDaoManager(this._db);
  $$PairedRelayEntriesTableTableManager get pairedRelayEntries =>
      $$PairedRelayEntriesTableTableManager(
        _db.attachedDatabase,
        _db.pairedRelayEntries,
      );
  $$PendingCardDistributionEntriesTableTableManager
  get pendingCardDistributionEntries =>
      $$PendingCardDistributionEntriesTableTableManager(
        _db.attachedDatabase,
        _db.pendingCardDistributionEntries,
      );
  $$RelayFanoutStateEntriesTableTableManager get relayFanoutStateEntries =>
      $$RelayFanoutStateEntriesTableTableManager(
        _db.attachedDatabase,
        _db.relayFanoutStateEntries,
      );
}
