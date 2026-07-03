// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $IdentityEntriesTable extends IdentityEntries
    with TableInfo<$IdentityEntriesTable, IdentityEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $IdentityEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pubkeyMeta = const VerificationMeta('pubkey');
  @override
  late final GeneratedColumn<String> pubkey = GeneratedColumn<String>(
    'pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _feedKeyMeta = const VerificationMeta(
    'feedKey',
  );
  @override
  late final GeneratedColumn<Uint8List> feedKey = GeneratedColumn<Uint8List>(
    'feed_key',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _feedKeyEpochMeta = const VerificationMeta(
    'feedKeyEpoch',
  );
  @override
  late final GeneratedColumn<int> feedKeyEpoch = GeneratedColumn<int>(
    'feed_key_epoch',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _feedKeyValidFromMeta = const VerificationMeta(
    'feedKeyValidFrom',
  );
  @override
  late final GeneratedColumn<int> feedKeyValidFrom = GeneratedColumn<int>(
    'feed_key_valid_from',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _msgSeqCounterMeta = const VerificationMeta(
    'msgSeqCounter',
  );
  @override
  late final GeneratedColumn<int> msgSeqCounter = GeneratedColumn<int>(
    'msg_seq_counter',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _recoveryPhraseMeta = const VerificationMeta(
    'recoveryPhrase',
  );
  @override
  late final GeneratedColumn<String> recoveryPhrase = GeneratedColumn<String>(
    'recovery_phrase',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    pubkey,
    feedKey,
    feedKeyEpoch,
    feedKeyValidFrom,
    msgSeqCounter,
    recoveryPhrase,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'identity_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<IdentityEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('pubkey')) {
      context.handle(
        _pubkeyMeta,
        pubkey.isAcceptableOrUnknown(data['pubkey']!, _pubkeyMeta),
      );
    } else if (isInserting) {
      context.missing(_pubkeyMeta);
    }
    if (data.containsKey('feed_key')) {
      context.handle(
        _feedKeyMeta,
        feedKey.isAcceptableOrUnknown(data['feed_key']!, _feedKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_feedKeyMeta);
    }
    if (data.containsKey('feed_key_epoch')) {
      context.handle(
        _feedKeyEpochMeta,
        feedKeyEpoch.isAcceptableOrUnknown(
          data['feed_key_epoch']!,
          _feedKeyEpochMeta,
        ),
      );
    }
    if (data.containsKey('feed_key_valid_from')) {
      context.handle(
        _feedKeyValidFromMeta,
        feedKeyValidFrom.isAcceptableOrUnknown(
          data['feed_key_valid_from']!,
          _feedKeyValidFromMeta,
        ),
      );
    }
    if (data.containsKey('msg_seq_counter')) {
      context.handle(
        _msgSeqCounterMeta,
        msgSeqCounter.isAcceptableOrUnknown(
          data['msg_seq_counter']!,
          _msgSeqCounterMeta,
        ),
      );
    }
    if (data.containsKey('recovery_phrase')) {
      context.handle(
        _recoveryPhraseMeta,
        recoveryPhrase.isAcceptableOrUnknown(
          data['recovery_phrase']!,
          _recoveryPhraseMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pubkey};
  @override
  IdentityEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return IdentityEntry(
      pubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pubkey'],
      )!,
      feedKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}feed_key'],
      )!,
      feedKeyEpoch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}feed_key_epoch'],
      )!,
      feedKeyValidFrom: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}feed_key_valid_from'],
      )!,
      msgSeqCounter: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}msg_seq_counter'],
      )!,
      recoveryPhrase: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recovery_phrase'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $IdentityEntriesTable createAlias(String alias) {
    return $IdentityEntriesTable(attachedDatabase, alias);
  }
}

class IdentityEntry extends DataClass implements Insertable<IdentityEntry> {
  final String pubkey;
  final Uint8List feedKey;
  final int feedKeyEpoch;
  final int feedKeyValidFrom;
  final int msgSeqCounter;
  final String? recoveryPhrase;
  final int createdAt;
  const IdentityEntry({
    required this.pubkey,
    required this.feedKey,
    required this.feedKeyEpoch,
    required this.feedKeyValidFrom,
    required this.msgSeqCounter,
    this.recoveryPhrase,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['pubkey'] = Variable<String>(pubkey);
    map['feed_key'] = Variable<Uint8List>(feedKey);
    map['feed_key_epoch'] = Variable<int>(feedKeyEpoch);
    map['feed_key_valid_from'] = Variable<int>(feedKeyValidFrom);
    map['msg_seq_counter'] = Variable<int>(msgSeqCounter);
    if (!nullToAbsent || recoveryPhrase != null) {
      map['recovery_phrase'] = Variable<String>(recoveryPhrase);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  IdentityEntriesCompanion toCompanion(bool nullToAbsent) {
    return IdentityEntriesCompanion(
      pubkey: Value(pubkey),
      feedKey: Value(feedKey),
      feedKeyEpoch: Value(feedKeyEpoch),
      feedKeyValidFrom: Value(feedKeyValidFrom),
      msgSeqCounter: Value(msgSeqCounter),
      recoveryPhrase: recoveryPhrase == null && nullToAbsent
          ? const Value.absent()
          : Value(recoveryPhrase),
      createdAt: Value(createdAt),
    );
  }

  factory IdentityEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return IdentityEntry(
      pubkey: serializer.fromJson<String>(json['pubkey']),
      feedKey: serializer.fromJson<Uint8List>(json['feedKey']),
      feedKeyEpoch: serializer.fromJson<int>(json['feedKeyEpoch']),
      feedKeyValidFrom: serializer.fromJson<int>(json['feedKeyValidFrom']),
      msgSeqCounter: serializer.fromJson<int>(json['msgSeqCounter']),
      recoveryPhrase: serializer.fromJson<String?>(json['recoveryPhrase']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pubkey': serializer.toJson<String>(pubkey),
      'feedKey': serializer.toJson<Uint8List>(feedKey),
      'feedKeyEpoch': serializer.toJson<int>(feedKeyEpoch),
      'feedKeyValidFrom': serializer.toJson<int>(feedKeyValidFrom),
      'msgSeqCounter': serializer.toJson<int>(msgSeqCounter),
      'recoveryPhrase': serializer.toJson<String?>(recoveryPhrase),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  IdentityEntry copyWith({
    String? pubkey,
    Uint8List? feedKey,
    int? feedKeyEpoch,
    int? feedKeyValidFrom,
    int? msgSeqCounter,
    Value<String?> recoveryPhrase = const Value.absent(),
    int? createdAt,
  }) => IdentityEntry(
    pubkey: pubkey ?? this.pubkey,
    feedKey: feedKey ?? this.feedKey,
    feedKeyEpoch: feedKeyEpoch ?? this.feedKeyEpoch,
    feedKeyValidFrom: feedKeyValidFrom ?? this.feedKeyValidFrom,
    msgSeqCounter: msgSeqCounter ?? this.msgSeqCounter,
    recoveryPhrase: recoveryPhrase.present
        ? recoveryPhrase.value
        : this.recoveryPhrase,
    createdAt: createdAt ?? this.createdAt,
  );
  IdentityEntry copyWithCompanion(IdentityEntriesCompanion data) {
    return IdentityEntry(
      pubkey: data.pubkey.present ? data.pubkey.value : this.pubkey,
      feedKey: data.feedKey.present ? data.feedKey.value : this.feedKey,
      feedKeyEpoch: data.feedKeyEpoch.present
          ? data.feedKeyEpoch.value
          : this.feedKeyEpoch,
      feedKeyValidFrom: data.feedKeyValidFrom.present
          ? data.feedKeyValidFrom.value
          : this.feedKeyValidFrom,
      msgSeqCounter: data.msgSeqCounter.present
          ? data.msgSeqCounter.value
          : this.msgSeqCounter,
      recoveryPhrase: data.recoveryPhrase.present
          ? data.recoveryPhrase.value
          : this.recoveryPhrase,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('IdentityEntry(')
          ..write('pubkey: $pubkey, ')
          ..write('feedKey: $feedKey, ')
          ..write('feedKeyEpoch: $feedKeyEpoch, ')
          ..write('feedKeyValidFrom: $feedKeyValidFrom, ')
          ..write('msgSeqCounter: $msgSeqCounter, ')
          ..write('recoveryPhrase: $recoveryPhrase, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    pubkey,
    $driftBlobEquality.hash(feedKey),
    feedKeyEpoch,
    feedKeyValidFrom,
    msgSeqCounter,
    recoveryPhrase,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IdentityEntry &&
          other.pubkey == this.pubkey &&
          $driftBlobEquality.equals(other.feedKey, this.feedKey) &&
          other.feedKeyEpoch == this.feedKeyEpoch &&
          other.feedKeyValidFrom == this.feedKeyValidFrom &&
          other.msgSeqCounter == this.msgSeqCounter &&
          other.recoveryPhrase == this.recoveryPhrase &&
          other.createdAt == this.createdAt);
}

class IdentityEntriesCompanion extends UpdateCompanion<IdentityEntry> {
  final Value<String> pubkey;
  final Value<Uint8List> feedKey;
  final Value<int> feedKeyEpoch;
  final Value<int> feedKeyValidFrom;
  final Value<int> msgSeqCounter;
  final Value<String?> recoveryPhrase;
  final Value<int> createdAt;
  final Value<int> rowid;
  const IdentityEntriesCompanion({
    this.pubkey = const Value.absent(),
    this.feedKey = const Value.absent(),
    this.feedKeyEpoch = const Value.absent(),
    this.feedKeyValidFrom = const Value.absent(),
    this.msgSeqCounter = const Value.absent(),
    this.recoveryPhrase = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  IdentityEntriesCompanion.insert({
    required String pubkey,
    required Uint8List feedKey,
    this.feedKeyEpoch = const Value.absent(),
    this.feedKeyValidFrom = const Value.absent(),
    this.msgSeqCounter = const Value.absent(),
    this.recoveryPhrase = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : pubkey = Value(pubkey),
       feedKey = Value(feedKey),
       createdAt = Value(createdAt);
  static Insertable<IdentityEntry> custom({
    Expression<String>? pubkey,
    Expression<Uint8List>? feedKey,
    Expression<int>? feedKeyEpoch,
    Expression<int>? feedKeyValidFrom,
    Expression<int>? msgSeqCounter,
    Expression<String>? recoveryPhrase,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pubkey != null) 'pubkey': pubkey,
      if (feedKey != null) 'feed_key': feedKey,
      if (feedKeyEpoch != null) 'feed_key_epoch': feedKeyEpoch,
      if (feedKeyValidFrom != null) 'feed_key_valid_from': feedKeyValidFrom,
      if (msgSeqCounter != null) 'msg_seq_counter': msgSeqCounter,
      if (recoveryPhrase != null) 'recovery_phrase': recoveryPhrase,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  IdentityEntriesCompanion copyWith({
    Value<String>? pubkey,
    Value<Uint8List>? feedKey,
    Value<int>? feedKeyEpoch,
    Value<int>? feedKeyValidFrom,
    Value<int>? msgSeqCounter,
    Value<String?>? recoveryPhrase,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return IdentityEntriesCompanion(
      pubkey: pubkey ?? this.pubkey,
      feedKey: feedKey ?? this.feedKey,
      feedKeyEpoch: feedKeyEpoch ?? this.feedKeyEpoch,
      feedKeyValidFrom: feedKeyValidFrom ?? this.feedKeyValidFrom,
      msgSeqCounter: msgSeqCounter ?? this.msgSeqCounter,
      recoveryPhrase: recoveryPhrase ?? this.recoveryPhrase,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pubkey.present) {
      map['pubkey'] = Variable<String>(pubkey.value);
    }
    if (feedKey.present) {
      map['feed_key'] = Variable<Uint8List>(feedKey.value);
    }
    if (feedKeyEpoch.present) {
      map['feed_key_epoch'] = Variable<int>(feedKeyEpoch.value);
    }
    if (feedKeyValidFrom.present) {
      map['feed_key_valid_from'] = Variable<int>(feedKeyValidFrom.value);
    }
    if (msgSeqCounter.present) {
      map['msg_seq_counter'] = Variable<int>(msgSeqCounter.value);
    }
    if (recoveryPhrase.present) {
      map['recovery_phrase'] = Variable<String>(recoveryPhrase.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('IdentityEntriesCompanion(')
          ..write('pubkey: $pubkey, ')
          ..write('feedKey: $feedKey, ')
          ..write('feedKeyEpoch: $feedKeyEpoch, ')
          ..write('feedKeyValidFrom: $feedKeyValidFrom, ')
          ..write('msgSeqCounter: $msgSeqCounter, ')
          ..write('recoveryPhrase: $recoveryPhrase, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FollowEntriesTable extends FollowEntries
    with TableInfo<$FollowEntriesTable, FollowEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FollowEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pubkeyMeta = const VerificationMeta('pubkey');
  @override
  late final GeneratedColumn<String> pubkey = GeneratedColumn<String>(
    'pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _connectionCardMeta = const VerificationMeta(
    'connectionCard',
  );
  @override
  late final GeneratedColumn<String> connectionCard = GeneratedColumn<String>(
    'connection_card',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _feedKeyMeta = const VerificationMeta(
    'feedKey',
  );
  @override
  late final GeneratedColumn<Uint8List> feedKey = GeneratedColumn<Uint8List>(
    'feed_key',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _feedKeyEpochMeta = const VerificationMeta(
    'feedKeyEpoch',
  );
  @override
  late final GeneratedColumn<int> feedKeyEpoch = GeneratedColumn<int>(
    'feed_key_epoch',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastSyncedAtMeta = const VerificationMeta(
    'lastSyncedAt',
  );
  @override
  late final GeneratedColumn<int> lastSyncedAt = GeneratedColumn<int>(
    'last_synced_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _lastReceivedRotationAtMeta =
      const VerificationMeta('lastReceivedRotationAt');
  @override
  late final GeneratedColumn<int> lastReceivedRotationAt = GeneratedColumn<int>(
    'last_received_rotation_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastReceivedCardAtMeta =
      const VerificationMeta('lastReceivedCardAt');
  @override
  late final GeneratedColumn<int> lastReceivedCardAt = GeneratedColumn<int>(
    'last_received_card_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastDecryptFailureAtMeta =
      const VerificationMeta('lastDecryptFailureAt');
  @override
  late final GeneratedColumn<int> lastDecryptFailureAt = GeneratedColumn<int>(
    'last_decrypt_failure_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastFullSyncAtMeta = const VerificationMeta(
    'lastFullSyncAt',
  );
  @override
  late final GeneratedColumn<int> lastFullSyncAt = GeneratedColumn<int>(
    'last_full_sync_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    pubkey,
    connectionCard,
    feedKey,
    feedKeyEpoch,
    lastSyncedAt,
    status,
    lastReceivedRotationAt,
    lastReceivedCardAt,
    lastDecryptFailureAt,
    lastFullSyncAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'follow_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<FollowEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('pubkey')) {
      context.handle(
        _pubkeyMeta,
        pubkey.isAcceptableOrUnknown(data['pubkey']!, _pubkeyMeta),
      );
    } else if (isInserting) {
      context.missing(_pubkeyMeta);
    }
    if (data.containsKey('connection_card')) {
      context.handle(
        _connectionCardMeta,
        connectionCard.isAcceptableOrUnknown(
          data['connection_card']!,
          _connectionCardMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_connectionCardMeta);
    }
    if (data.containsKey('feed_key')) {
      context.handle(
        _feedKeyMeta,
        feedKey.isAcceptableOrUnknown(data['feed_key']!, _feedKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_feedKeyMeta);
    }
    if (data.containsKey('feed_key_epoch')) {
      context.handle(
        _feedKeyEpochMeta,
        feedKeyEpoch.isAcceptableOrUnknown(
          data['feed_key_epoch']!,
          _feedKeyEpochMeta,
        ),
      );
    }
    if (data.containsKey('last_synced_at')) {
      context.handle(
        _lastSyncedAtMeta,
        lastSyncedAt.isAcceptableOrUnknown(
          data['last_synced_at']!,
          _lastSyncedAtMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('last_received_rotation_at')) {
      context.handle(
        _lastReceivedRotationAtMeta,
        lastReceivedRotationAt.isAcceptableOrUnknown(
          data['last_received_rotation_at']!,
          _lastReceivedRotationAtMeta,
        ),
      );
    }
    if (data.containsKey('last_received_card_at')) {
      context.handle(
        _lastReceivedCardAtMeta,
        lastReceivedCardAt.isAcceptableOrUnknown(
          data['last_received_card_at']!,
          _lastReceivedCardAtMeta,
        ),
      );
    }
    if (data.containsKey('last_decrypt_failure_at')) {
      context.handle(
        _lastDecryptFailureAtMeta,
        lastDecryptFailureAt.isAcceptableOrUnknown(
          data['last_decrypt_failure_at']!,
          _lastDecryptFailureAtMeta,
        ),
      );
    }
    if (data.containsKey('last_full_sync_at')) {
      context.handle(
        _lastFullSyncAtMeta,
        lastFullSyncAt.isAcceptableOrUnknown(
          data['last_full_sync_at']!,
          _lastFullSyncAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pubkey};
  @override
  FollowEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FollowEntry(
      pubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pubkey'],
      )!,
      connectionCard: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}connection_card'],
      )!,
      feedKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}feed_key'],
      )!,
      feedKeyEpoch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}feed_key_epoch'],
      )!,
      lastSyncedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_synced_at'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      lastReceivedRotationAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_received_rotation_at'],
      )!,
      lastReceivedCardAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_received_card_at'],
      )!,
      lastDecryptFailureAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_decrypt_failure_at'],
      ),
      lastFullSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_full_sync_at'],
      )!,
    );
  }

  @override
  $FollowEntriesTable createAlias(String alias) {
    return $FollowEntriesTable(attachedDatabase, alias);
  }
}

class FollowEntry extends DataClass implements Insertable<FollowEntry> {
  final String pubkey;
  final String connectionCard;
  final Uint8List feedKey;
  final int feedKeyEpoch;
  final int lastSyncedAt;
  final String status;
  final int lastReceivedRotationAt;
  final int lastReceivedCardAt;
  final int? lastDecryptFailureAt;
  final int lastFullSyncAt;
  const FollowEntry({
    required this.pubkey,
    required this.connectionCard,
    required this.feedKey,
    required this.feedKeyEpoch,
    required this.lastSyncedAt,
    required this.status,
    required this.lastReceivedRotationAt,
    required this.lastReceivedCardAt,
    this.lastDecryptFailureAt,
    required this.lastFullSyncAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['pubkey'] = Variable<String>(pubkey);
    map['connection_card'] = Variable<String>(connectionCard);
    map['feed_key'] = Variable<Uint8List>(feedKey);
    map['feed_key_epoch'] = Variable<int>(feedKeyEpoch);
    map['last_synced_at'] = Variable<int>(lastSyncedAt);
    map['status'] = Variable<String>(status);
    map['last_received_rotation_at'] = Variable<int>(lastReceivedRotationAt);
    map['last_received_card_at'] = Variable<int>(lastReceivedCardAt);
    if (!nullToAbsent || lastDecryptFailureAt != null) {
      map['last_decrypt_failure_at'] = Variable<int>(lastDecryptFailureAt);
    }
    map['last_full_sync_at'] = Variable<int>(lastFullSyncAt);
    return map;
  }

  FollowEntriesCompanion toCompanion(bool nullToAbsent) {
    return FollowEntriesCompanion(
      pubkey: Value(pubkey),
      connectionCard: Value(connectionCard),
      feedKey: Value(feedKey),
      feedKeyEpoch: Value(feedKeyEpoch),
      lastSyncedAt: Value(lastSyncedAt),
      status: Value(status),
      lastReceivedRotationAt: Value(lastReceivedRotationAt),
      lastReceivedCardAt: Value(lastReceivedCardAt),
      lastDecryptFailureAt: lastDecryptFailureAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastDecryptFailureAt),
      lastFullSyncAt: Value(lastFullSyncAt),
    );
  }

  factory FollowEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FollowEntry(
      pubkey: serializer.fromJson<String>(json['pubkey']),
      connectionCard: serializer.fromJson<String>(json['connectionCard']),
      feedKey: serializer.fromJson<Uint8List>(json['feedKey']),
      feedKeyEpoch: serializer.fromJson<int>(json['feedKeyEpoch']),
      lastSyncedAt: serializer.fromJson<int>(json['lastSyncedAt']),
      status: serializer.fromJson<String>(json['status']),
      lastReceivedRotationAt: serializer.fromJson<int>(
        json['lastReceivedRotationAt'],
      ),
      lastReceivedCardAt: serializer.fromJson<int>(json['lastReceivedCardAt']),
      lastDecryptFailureAt: serializer.fromJson<int?>(
        json['lastDecryptFailureAt'],
      ),
      lastFullSyncAt: serializer.fromJson<int>(json['lastFullSyncAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pubkey': serializer.toJson<String>(pubkey),
      'connectionCard': serializer.toJson<String>(connectionCard),
      'feedKey': serializer.toJson<Uint8List>(feedKey),
      'feedKeyEpoch': serializer.toJson<int>(feedKeyEpoch),
      'lastSyncedAt': serializer.toJson<int>(lastSyncedAt),
      'status': serializer.toJson<String>(status),
      'lastReceivedRotationAt': serializer.toJson<int>(lastReceivedRotationAt),
      'lastReceivedCardAt': serializer.toJson<int>(lastReceivedCardAt),
      'lastDecryptFailureAt': serializer.toJson<int?>(lastDecryptFailureAt),
      'lastFullSyncAt': serializer.toJson<int>(lastFullSyncAt),
    };
  }

  FollowEntry copyWith({
    String? pubkey,
    String? connectionCard,
    Uint8List? feedKey,
    int? feedKeyEpoch,
    int? lastSyncedAt,
    String? status,
    int? lastReceivedRotationAt,
    int? lastReceivedCardAt,
    Value<int?> lastDecryptFailureAt = const Value.absent(),
    int? lastFullSyncAt,
  }) => FollowEntry(
    pubkey: pubkey ?? this.pubkey,
    connectionCard: connectionCard ?? this.connectionCard,
    feedKey: feedKey ?? this.feedKey,
    feedKeyEpoch: feedKeyEpoch ?? this.feedKeyEpoch,
    lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    status: status ?? this.status,
    lastReceivedRotationAt:
        lastReceivedRotationAt ?? this.lastReceivedRotationAt,
    lastReceivedCardAt: lastReceivedCardAt ?? this.lastReceivedCardAt,
    lastDecryptFailureAt: lastDecryptFailureAt.present
        ? lastDecryptFailureAt.value
        : this.lastDecryptFailureAt,
    lastFullSyncAt: lastFullSyncAt ?? this.lastFullSyncAt,
  );
  FollowEntry copyWithCompanion(FollowEntriesCompanion data) {
    return FollowEntry(
      pubkey: data.pubkey.present ? data.pubkey.value : this.pubkey,
      connectionCard: data.connectionCard.present
          ? data.connectionCard.value
          : this.connectionCard,
      feedKey: data.feedKey.present ? data.feedKey.value : this.feedKey,
      feedKeyEpoch: data.feedKeyEpoch.present
          ? data.feedKeyEpoch.value
          : this.feedKeyEpoch,
      lastSyncedAt: data.lastSyncedAt.present
          ? data.lastSyncedAt.value
          : this.lastSyncedAt,
      status: data.status.present ? data.status.value : this.status,
      lastReceivedRotationAt: data.lastReceivedRotationAt.present
          ? data.lastReceivedRotationAt.value
          : this.lastReceivedRotationAt,
      lastReceivedCardAt: data.lastReceivedCardAt.present
          ? data.lastReceivedCardAt.value
          : this.lastReceivedCardAt,
      lastDecryptFailureAt: data.lastDecryptFailureAt.present
          ? data.lastDecryptFailureAt.value
          : this.lastDecryptFailureAt,
      lastFullSyncAt: data.lastFullSyncAt.present
          ? data.lastFullSyncAt.value
          : this.lastFullSyncAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FollowEntry(')
          ..write('pubkey: $pubkey, ')
          ..write('connectionCard: $connectionCard, ')
          ..write('feedKey: $feedKey, ')
          ..write('feedKeyEpoch: $feedKeyEpoch, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('status: $status, ')
          ..write('lastReceivedRotationAt: $lastReceivedRotationAt, ')
          ..write('lastReceivedCardAt: $lastReceivedCardAt, ')
          ..write('lastDecryptFailureAt: $lastDecryptFailureAt, ')
          ..write('lastFullSyncAt: $lastFullSyncAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    pubkey,
    connectionCard,
    $driftBlobEquality.hash(feedKey),
    feedKeyEpoch,
    lastSyncedAt,
    status,
    lastReceivedRotationAt,
    lastReceivedCardAt,
    lastDecryptFailureAt,
    lastFullSyncAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FollowEntry &&
          other.pubkey == this.pubkey &&
          other.connectionCard == this.connectionCard &&
          $driftBlobEquality.equals(other.feedKey, this.feedKey) &&
          other.feedKeyEpoch == this.feedKeyEpoch &&
          other.lastSyncedAt == this.lastSyncedAt &&
          other.status == this.status &&
          other.lastReceivedRotationAt == this.lastReceivedRotationAt &&
          other.lastReceivedCardAt == this.lastReceivedCardAt &&
          other.lastDecryptFailureAt == this.lastDecryptFailureAt &&
          other.lastFullSyncAt == this.lastFullSyncAt);
}

class FollowEntriesCompanion extends UpdateCompanion<FollowEntry> {
  final Value<String> pubkey;
  final Value<String> connectionCard;
  final Value<Uint8List> feedKey;
  final Value<int> feedKeyEpoch;
  final Value<int> lastSyncedAt;
  final Value<String> status;
  final Value<int> lastReceivedRotationAt;
  final Value<int> lastReceivedCardAt;
  final Value<int?> lastDecryptFailureAt;
  final Value<int> lastFullSyncAt;
  final Value<int> rowid;
  const FollowEntriesCompanion({
    this.pubkey = const Value.absent(),
    this.connectionCard = const Value.absent(),
    this.feedKey = const Value.absent(),
    this.feedKeyEpoch = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.status = const Value.absent(),
    this.lastReceivedRotationAt = const Value.absent(),
    this.lastReceivedCardAt = const Value.absent(),
    this.lastDecryptFailureAt = const Value.absent(),
    this.lastFullSyncAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FollowEntriesCompanion.insert({
    required String pubkey,
    required String connectionCard,
    required Uint8List feedKey,
    this.feedKeyEpoch = const Value.absent(),
    this.lastSyncedAt = const Value.absent(),
    this.status = const Value.absent(),
    this.lastReceivedRotationAt = const Value.absent(),
    this.lastReceivedCardAt = const Value.absent(),
    this.lastDecryptFailureAt = const Value.absent(),
    this.lastFullSyncAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : pubkey = Value(pubkey),
       connectionCard = Value(connectionCard),
       feedKey = Value(feedKey);
  static Insertable<FollowEntry> custom({
    Expression<String>? pubkey,
    Expression<String>? connectionCard,
    Expression<Uint8List>? feedKey,
    Expression<int>? feedKeyEpoch,
    Expression<int>? lastSyncedAt,
    Expression<String>? status,
    Expression<int>? lastReceivedRotationAt,
    Expression<int>? lastReceivedCardAt,
    Expression<int>? lastDecryptFailureAt,
    Expression<int>? lastFullSyncAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pubkey != null) 'pubkey': pubkey,
      if (connectionCard != null) 'connection_card': connectionCard,
      if (feedKey != null) 'feed_key': feedKey,
      if (feedKeyEpoch != null) 'feed_key_epoch': feedKeyEpoch,
      if (lastSyncedAt != null) 'last_synced_at': lastSyncedAt,
      if (status != null) 'status': status,
      if (lastReceivedRotationAt != null)
        'last_received_rotation_at': lastReceivedRotationAt,
      if (lastReceivedCardAt != null)
        'last_received_card_at': lastReceivedCardAt,
      if (lastDecryptFailureAt != null)
        'last_decrypt_failure_at': lastDecryptFailureAt,
      if (lastFullSyncAt != null) 'last_full_sync_at': lastFullSyncAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FollowEntriesCompanion copyWith({
    Value<String>? pubkey,
    Value<String>? connectionCard,
    Value<Uint8List>? feedKey,
    Value<int>? feedKeyEpoch,
    Value<int>? lastSyncedAt,
    Value<String>? status,
    Value<int>? lastReceivedRotationAt,
    Value<int>? lastReceivedCardAt,
    Value<int?>? lastDecryptFailureAt,
    Value<int>? lastFullSyncAt,
    Value<int>? rowid,
  }) {
    return FollowEntriesCompanion(
      pubkey: pubkey ?? this.pubkey,
      connectionCard: connectionCard ?? this.connectionCard,
      feedKey: feedKey ?? this.feedKey,
      feedKeyEpoch: feedKeyEpoch ?? this.feedKeyEpoch,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      status: status ?? this.status,
      lastReceivedRotationAt:
          lastReceivedRotationAt ?? this.lastReceivedRotationAt,
      lastReceivedCardAt: lastReceivedCardAt ?? this.lastReceivedCardAt,
      lastDecryptFailureAt: lastDecryptFailureAt ?? this.lastDecryptFailureAt,
      lastFullSyncAt: lastFullSyncAt ?? this.lastFullSyncAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pubkey.present) {
      map['pubkey'] = Variable<String>(pubkey.value);
    }
    if (connectionCard.present) {
      map['connection_card'] = Variable<String>(connectionCard.value);
    }
    if (feedKey.present) {
      map['feed_key'] = Variable<Uint8List>(feedKey.value);
    }
    if (feedKeyEpoch.present) {
      map['feed_key_epoch'] = Variable<int>(feedKeyEpoch.value);
    }
    if (lastSyncedAt.present) {
      map['last_synced_at'] = Variable<int>(lastSyncedAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (lastReceivedRotationAt.present) {
      map['last_received_rotation_at'] = Variable<int>(
        lastReceivedRotationAt.value,
      );
    }
    if (lastReceivedCardAt.present) {
      map['last_received_card_at'] = Variable<int>(lastReceivedCardAt.value);
    }
    if (lastDecryptFailureAt.present) {
      map['last_decrypt_failure_at'] = Variable<int>(
        lastDecryptFailureAt.value,
      );
    }
    if (lastFullSyncAt.present) {
      map['last_full_sync_at'] = Variable<int>(lastFullSyncAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FollowEntriesCompanion(')
          ..write('pubkey: $pubkey, ')
          ..write('connectionCard: $connectionCard, ')
          ..write('feedKey: $feedKey, ')
          ..write('feedKeyEpoch: $feedKeyEpoch, ')
          ..write('lastSyncedAt: $lastSyncedAt, ')
          ..write('status: $status, ')
          ..write('lastReceivedRotationAt: $lastReceivedRotationAt, ')
          ..write('lastReceivedCardAt: $lastReceivedCardAt, ')
          ..write('lastDecryptFailureAt: $lastDecryptFailureAt, ')
          ..write('lastFullSyncAt: $lastFullSyncAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EventEntriesTable extends EventEntries
    with TableInfo<$EventEntriesTable, EventEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pubkeyMeta = const VerificationMeta('pubkey');
  @override
  late final GeneratedColumn<String> pubkey = GeneratedColumn<String>(
    'pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<int> kind = GeneratedColumn<int>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refIdMeta = const VerificationMeta('refId');
  @override
  late final GeneratedColumn<String> refId = GeneratedColumn<String>(
    'ref_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<Uint8List> content = GeneratedColumn<Uint8List>(
    'content',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mediaRefsMeta = const VerificationMeta(
    'mediaRefs',
  );
  @override
  late final GeneratedColumn<String> mediaRefs = GeneratedColumn<String>(
    'media_refs',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sigMeta = const VerificationMeta('sig');
  @override
  late final GeneratedColumn<Uint8List> sig = GeneratedColumn<Uint8List>(
    'sig',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isOwnMeta = const VerificationMeta('isOwn');
  @override
  late final GeneratedColumn<int> isOwn = GeneratedColumn<int>(
    'is_own',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isSavedMeta = const VerificationMeta(
    'isSaved',
  );
  @override
  late final GeneratedColumn<int> isSaved = GeneratedColumn<int>(
    'is_saved',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<int> fetchedAt = GeneratedColumn<int>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastViewedMeta = const VerificationMeta(
    'lastViewed',
  );
  @override
  late final GeneratedColumn<int> lastViewed = GeneratedColumn<int>(
    'last_viewed',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<String> version = GeneratedColumn<String>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('2026-03-24'),
  );
  static const VerificationMeta _extensionsMeta = const VerificationMeta(
    'extensions',
  );
  @override
  late final GeneratedColumn<Uint8List> extensions = GeneratedColumn<Uint8List>(
    'extensions',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _msgSeqMeta = const VerificationMeta('msgSeq');
  @override
  late final GeneratedColumn<int> msgSeq = GeneratedColumn<int>(
    'msg_seq',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _encryptedPayloadMeta = const VerificationMeta(
    'encryptedPayload',
  );
  @override
  late final GeneratedColumn<Uint8List> encryptedPayload =
      GeneratedColumn<Uint8List>(
        'encrypted_payload',
        aliasedName,
        true,
        type: DriftSqlType.blob,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    pubkey,
    createdAt,
    kind,
    refId,
    content,
    mediaRefs,
    sig,
    isOwn,
    isSaved,
    fetchedAt,
    lastViewed,
    version,
    extensions,
    msgSeq,
    encryptedPayload,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'event_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<EventEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('pubkey')) {
      context.handle(
        _pubkeyMeta,
        pubkey.isAcceptableOrUnknown(data['pubkey']!, _pubkeyMeta),
      );
    } else if (isInserting) {
      context.missing(_pubkeyMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('ref_id')) {
      context.handle(
        _refIdMeta,
        refId.isAcceptableOrUnknown(data['ref_id']!, _refIdMeta),
      );
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('media_refs')) {
      context.handle(
        _mediaRefsMeta,
        mediaRefs.isAcceptableOrUnknown(data['media_refs']!, _mediaRefsMeta),
      );
    }
    if (data.containsKey('sig')) {
      context.handle(
        _sigMeta,
        sig.isAcceptableOrUnknown(data['sig']!, _sigMeta),
      );
    } else if (isInserting) {
      context.missing(_sigMeta);
    }
    if (data.containsKey('is_own')) {
      context.handle(
        _isOwnMeta,
        isOwn.isAcceptableOrUnknown(data['is_own']!, _isOwnMeta),
      );
    }
    if (data.containsKey('is_saved')) {
      context.handle(
        _isSavedMeta,
        isSaved.isAcceptableOrUnknown(data['is_saved']!, _isSavedMeta),
      );
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    if (data.containsKey('last_viewed')) {
      context.handle(
        _lastViewedMeta,
        lastViewed.isAcceptableOrUnknown(data['last_viewed']!, _lastViewedMeta),
      );
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    if (data.containsKey('extensions')) {
      context.handle(
        _extensionsMeta,
        extensions.isAcceptableOrUnknown(data['extensions']!, _extensionsMeta),
      );
    }
    if (data.containsKey('msg_seq')) {
      context.handle(
        _msgSeqMeta,
        msgSeq.isAcceptableOrUnknown(data['msg_seq']!, _msgSeqMeta),
      );
    }
    if (data.containsKey('encrypted_payload')) {
      context.handle(
        _encryptedPayloadMeta,
        encryptedPayload.isAcceptableOrUnknown(
          data['encrypted_payload']!,
          _encryptedPayloadMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  EventEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EventEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      pubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pubkey'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}kind'],
      )!,
      refId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_id'],
      ),
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}content'],
      )!,
      mediaRefs: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_refs'],
      ),
      sig: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}sig'],
      )!,
      isOwn: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_own'],
      )!,
      isSaved: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_saved'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}fetched_at'],
      )!,
      lastViewed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_viewed'],
      ),
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version'],
      )!,
      extensions: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}extensions'],
      ),
      msgSeq: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}msg_seq'],
      ),
      encryptedPayload: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}encrypted_payload'],
      ),
    );
  }

  @override
  $EventEntriesTable createAlias(String alias) {
    return $EventEntriesTable(attachedDatabase, alias);
  }
}

class EventEntry extends DataClass implements Insertable<EventEntry> {
  final String id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final String? refId;
  final Uint8List content;
  final String? mediaRefs;
  final Uint8List sig;
  final int isOwn;
  final int isSaved;
  final int fetchedAt;
  final int? lastViewed;
  final String version;
  final Uint8List? extensions;
  final int? msgSeq;
  final Uint8List? encryptedPayload;
  const EventEntry({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    this.refId,
    required this.content,
    this.mediaRefs,
    required this.sig,
    required this.isOwn,
    required this.isSaved,
    required this.fetchedAt,
    this.lastViewed,
    required this.version,
    this.extensions,
    this.msgSeq,
    this.encryptedPayload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['pubkey'] = Variable<String>(pubkey);
    map['created_at'] = Variable<int>(createdAt);
    map['kind'] = Variable<int>(kind);
    if (!nullToAbsent || refId != null) {
      map['ref_id'] = Variable<String>(refId);
    }
    map['content'] = Variable<Uint8List>(content);
    if (!nullToAbsent || mediaRefs != null) {
      map['media_refs'] = Variable<String>(mediaRefs);
    }
    map['sig'] = Variable<Uint8List>(sig);
    map['is_own'] = Variable<int>(isOwn);
    map['is_saved'] = Variable<int>(isSaved);
    map['fetched_at'] = Variable<int>(fetchedAt);
    if (!nullToAbsent || lastViewed != null) {
      map['last_viewed'] = Variable<int>(lastViewed);
    }
    map['version'] = Variable<String>(version);
    if (!nullToAbsent || extensions != null) {
      map['extensions'] = Variable<Uint8List>(extensions);
    }
    if (!nullToAbsent || msgSeq != null) {
      map['msg_seq'] = Variable<int>(msgSeq);
    }
    if (!nullToAbsent || encryptedPayload != null) {
      map['encrypted_payload'] = Variable<Uint8List>(encryptedPayload);
    }
    return map;
  }

  EventEntriesCompanion toCompanion(bool nullToAbsent) {
    return EventEntriesCompanion(
      id: Value(id),
      pubkey: Value(pubkey),
      createdAt: Value(createdAt),
      kind: Value(kind),
      refId: refId == null && nullToAbsent
          ? const Value.absent()
          : Value(refId),
      content: Value(content),
      mediaRefs: mediaRefs == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaRefs),
      sig: Value(sig),
      isOwn: Value(isOwn),
      isSaved: Value(isSaved),
      fetchedAt: Value(fetchedAt),
      lastViewed: lastViewed == null && nullToAbsent
          ? const Value.absent()
          : Value(lastViewed),
      version: Value(version),
      extensions: extensions == null && nullToAbsent
          ? const Value.absent()
          : Value(extensions),
      msgSeq: msgSeq == null && nullToAbsent
          ? const Value.absent()
          : Value(msgSeq),
      encryptedPayload: encryptedPayload == null && nullToAbsent
          ? const Value.absent()
          : Value(encryptedPayload),
    );
  }

  factory EventEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EventEntry(
      id: serializer.fromJson<String>(json['id']),
      pubkey: serializer.fromJson<String>(json['pubkey']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      kind: serializer.fromJson<int>(json['kind']),
      refId: serializer.fromJson<String?>(json['refId']),
      content: serializer.fromJson<Uint8List>(json['content']),
      mediaRefs: serializer.fromJson<String?>(json['mediaRefs']),
      sig: serializer.fromJson<Uint8List>(json['sig']),
      isOwn: serializer.fromJson<int>(json['isOwn']),
      isSaved: serializer.fromJson<int>(json['isSaved']),
      fetchedAt: serializer.fromJson<int>(json['fetchedAt']),
      lastViewed: serializer.fromJson<int?>(json['lastViewed']),
      version: serializer.fromJson<String>(json['version']),
      extensions: serializer.fromJson<Uint8List?>(json['extensions']),
      msgSeq: serializer.fromJson<int?>(json['msgSeq']),
      encryptedPayload: serializer.fromJson<Uint8List?>(
        json['encryptedPayload'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'pubkey': serializer.toJson<String>(pubkey),
      'createdAt': serializer.toJson<int>(createdAt),
      'kind': serializer.toJson<int>(kind),
      'refId': serializer.toJson<String?>(refId),
      'content': serializer.toJson<Uint8List>(content),
      'mediaRefs': serializer.toJson<String?>(mediaRefs),
      'sig': serializer.toJson<Uint8List>(sig),
      'isOwn': serializer.toJson<int>(isOwn),
      'isSaved': serializer.toJson<int>(isSaved),
      'fetchedAt': serializer.toJson<int>(fetchedAt),
      'lastViewed': serializer.toJson<int?>(lastViewed),
      'version': serializer.toJson<String>(version),
      'extensions': serializer.toJson<Uint8List?>(extensions),
      'msgSeq': serializer.toJson<int?>(msgSeq),
      'encryptedPayload': serializer.toJson<Uint8List?>(encryptedPayload),
    };
  }

  EventEntry copyWith({
    String? id,
    String? pubkey,
    int? createdAt,
    int? kind,
    Value<String?> refId = const Value.absent(),
    Uint8List? content,
    Value<String?> mediaRefs = const Value.absent(),
    Uint8List? sig,
    int? isOwn,
    int? isSaved,
    int? fetchedAt,
    Value<int?> lastViewed = const Value.absent(),
    String? version,
    Value<Uint8List?> extensions = const Value.absent(),
    Value<int?> msgSeq = const Value.absent(),
    Value<Uint8List?> encryptedPayload = const Value.absent(),
  }) => EventEntry(
    id: id ?? this.id,
    pubkey: pubkey ?? this.pubkey,
    createdAt: createdAt ?? this.createdAt,
    kind: kind ?? this.kind,
    refId: refId.present ? refId.value : this.refId,
    content: content ?? this.content,
    mediaRefs: mediaRefs.present ? mediaRefs.value : this.mediaRefs,
    sig: sig ?? this.sig,
    isOwn: isOwn ?? this.isOwn,
    isSaved: isSaved ?? this.isSaved,
    fetchedAt: fetchedAt ?? this.fetchedAt,
    lastViewed: lastViewed.present ? lastViewed.value : this.lastViewed,
    version: version ?? this.version,
    extensions: extensions.present ? extensions.value : this.extensions,
    msgSeq: msgSeq.present ? msgSeq.value : this.msgSeq,
    encryptedPayload: encryptedPayload.present
        ? encryptedPayload.value
        : this.encryptedPayload,
  );
  EventEntry copyWithCompanion(EventEntriesCompanion data) {
    return EventEntry(
      id: data.id.present ? data.id.value : this.id,
      pubkey: data.pubkey.present ? data.pubkey.value : this.pubkey,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      kind: data.kind.present ? data.kind.value : this.kind,
      refId: data.refId.present ? data.refId.value : this.refId,
      content: data.content.present ? data.content.value : this.content,
      mediaRefs: data.mediaRefs.present ? data.mediaRefs.value : this.mediaRefs,
      sig: data.sig.present ? data.sig.value : this.sig,
      isOwn: data.isOwn.present ? data.isOwn.value : this.isOwn,
      isSaved: data.isSaved.present ? data.isSaved.value : this.isSaved,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
      lastViewed: data.lastViewed.present
          ? data.lastViewed.value
          : this.lastViewed,
      version: data.version.present ? data.version.value : this.version,
      extensions: data.extensions.present
          ? data.extensions.value
          : this.extensions,
      msgSeq: data.msgSeq.present ? data.msgSeq.value : this.msgSeq,
      encryptedPayload: data.encryptedPayload.present
          ? data.encryptedPayload.value
          : this.encryptedPayload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EventEntry(')
          ..write('id: $id, ')
          ..write('pubkey: $pubkey, ')
          ..write('createdAt: $createdAt, ')
          ..write('kind: $kind, ')
          ..write('refId: $refId, ')
          ..write('content: $content, ')
          ..write('mediaRefs: $mediaRefs, ')
          ..write('sig: $sig, ')
          ..write('isOwn: $isOwn, ')
          ..write('isSaved: $isSaved, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('lastViewed: $lastViewed, ')
          ..write('version: $version, ')
          ..write('extensions: $extensions, ')
          ..write('msgSeq: $msgSeq, ')
          ..write('encryptedPayload: $encryptedPayload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    pubkey,
    createdAt,
    kind,
    refId,
    $driftBlobEquality.hash(content),
    mediaRefs,
    $driftBlobEquality.hash(sig),
    isOwn,
    isSaved,
    fetchedAt,
    lastViewed,
    version,
    $driftBlobEquality.hash(extensions),
    msgSeq,
    $driftBlobEquality.hash(encryptedPayload),
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EventEntry &&
          other.id == this.id &&
          other.pubkey == this.pubkey &&
          other.createdAt == this.createdAt &&
          other.kind == this.kind &&
          other.refId == this.refId &&
          $driftBlobEquality.equals(other.content, this.content) &&
          other.mediaRefs == this.mediaRefs &&
          $driftBlobEquality.equals(other.sig, this.sig) &&
          other.isOwn == this.isOwn &&
          other.isSaved == this.isSaved &&
          other.fetchedAt == this.fetchedAt &&
          other.lastViewed == this.lastViewed &&
          other.version == this.version &&
          $driftBlobEquality.equals(other.extensions, this.extensions) &&
          other.msgSeq == this.msgSeq &&
          $driftBlobEquality.equals(
            other.encryptedPayload,
            this.encryptedPayload,
          ));
}

class EventEntriesCompanion extends UpdateCompanion<EventEntry> {
  final Value<String> id;
  final Value<String> pubkey;
  final Value<int> createdAt;
  final Value<int> kind;
  final Value<String?> refId;
  final Value<Uint8List> content;
  final Value<String?> mediaRefs;
  final Value<Uint8List> sig;
  final Value<int> isOwn;
  final Value<int> isSaved;
  final Value<int> fetchedAt;
  final Value<int?> lastViewed;
  final Value<String> version;
  final Value<Uint8List?> extensions;
  final Value<int?> msgSeq;
  final Value<Uint8List?> encryptedPayload;
  final Value<int> rowid;
  const EventEntriesCompanion({
    this.id = const Value.absent(),
    this.pubkey = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.kind = const Value.absent(),
    this.refId = const Value.absent(),
    this.content = const Value.absent(),
    this.mediaRefs = const Value.absent(),
    this.sig = const Value.absent(),
    this.isOwn = const Value.absent(),
    this.isSaved = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.lastViewed = const Value.absent(),
    this.version = const Value.absent(),
    this.extensions = const Value.absent(),
    this.msgSeq = const Value.absent(),
    this.encryptedPayload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EventEntriesCompanion.insert({
    required String id,
    required String pubkey,
    required int createdAt,
    required int kind,
    this.refId = const Value.absent(),
    required Uint8List content,
    this.mediaRefs = const Value.absent(),
    required Uint8List sig,
    this.isOwn = const Value.absent(),
    this.isSaved = const Value.absent(),
    required int fetchedAt,
    this.lastViewed = const Value.absent(),
    this.version = const Value.absent(),
    this.extensions = const Value.absent(),
    this.msgSeq = const Value.absent(),
    this.encryptedPayload = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       pubkey = Value(pubkey),
       createdAt = Value(createdAt),
       kind = Value(kind),
       content = Value(content),
       sig = Value(sig),
       fetchedAt = Value(fetchedAt);
  static Insertable<EventEntry> custom({
    Expression<String>? id,
    Expression<String>? pubkey,
    Expression<int>? createdAt,
    Expression<int>? kind,
    Expression<String>? refId,
    Expression<Uint8List>? content,
    Expression<String>? mediaRefs,
    Expression<Uint8List>? sig,
    Expression<int>? isOwn,
    Expression<int>? isSaved,
    Expression<int>? fetchedAt,
    Expression<int>? lastViewed,
    Expression<String>? version,
    Expression<Uint8List>? extensions,
    Expression<int>? msgSeq,
    Expression<Uint8List>? encryptedPayload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (pubkey != null) 'pubkey': pubkey,
      if (createdAt != null) 'created_at': createdAt,
      if (kind != null) 'kind': kind,
      if (refId != null) 'ref_id': refId,
      if (content != null) 'content': content,
      if (mediaRefs != null) 'media_refs': mediaRefs,
      if (sig != null) 'sig': sig,
      if (isOwn != null) 'is_own': isOwn,
      if (isSaved != null) 'is_saved': isSaved,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (lastViewed != null) 'last_viewed': lastViewed,
      if (version != null) 'version': version,
      if (extensions != null) 'extensions': extensions,
      if (msgSeq != null) 'msg_seq': msgSeq,
      if (encryptedPayload != null) 'encrypted_payload': encryptedPayload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EventEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? pubkey,
    Value<int>? createdAt,
    Value<int>? kind,
    Value<String?>? refId,
    Value<Uint8List>? content,
    Value<String?>? mediaRefs,
    Value<Uint8List>? sig,
    Value<int>? isOwn,
    Value<int>? isSaved,
    Value<int>? fetchedAt,
    Value<int?>? lastViewed,
    Value<String>? version,
    Value<Uint8List?>? extensions,
    Value<int?>? msgSeq,
    Value<Uint8List?>? encryptedPayload,
    Value<int>? rowid,
  }) {
    return EventEntriesCompanion(
      id: id ?? this.id,
      pubkey: pubkey ?? this.pubkey,
      createdAt: createdAt ?? this.createdAt,
      kind: kind ?? this.kind,
      refId: refId ?? this.refId,
      content: content ?? this.content,
      mediaRefs: mediaRefs ?? this.mediaRefs,
      sig: sig ?? this.sig,
      isOwn: isOwn ?? this.isOwn,
      isSaved: isSaved ?? this.isSaved,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      lastViewed: lastViewed ?? this.lastViewed,
      version: version ?? this.version,
      extensions: extensions ?? this.extensions,
      msgSeq: msgSeq ?? this.msgSeq,
      encryptedPayload: encryptedPayload ?? this.encryptedPayload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (pubkey.present) {
      map['pubkey'] = Variable<String>(pubkey.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (kind.present) {
      map['kind'] = Variable<int>(kind.value);
    }
    if (refId.present) {
      map['ref_id'] = Variable<String>(refId.value);
    }
    if (content.present) {
      map['content'] = Variable<Uint8List>(content.value);
    }
    if (mediaRefs.present) {
      map['media_refs'] = Variable<String>(mediaRefs.value);
    }
    if (sig.present) {
      map['sig'] = Variable<Uint8List>(sig.value);
    }
    if (isOwn.present) {
      map['is_own'] = Variable<int>(isOwn.value);
    }
    if (isSaved.present) {
      map['is_saved'] = Variable<int>(isSaved.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<int>(fetchedAt.value);
    }
    if (lastViewed.present) {
      map['last_viewed'] = Variable<int>(lastViewed.value);
    }
    if (version.present) {
      map['version'] = Variable<String>(version.value);
    }
    if (extensions.present) {
      map['extensions'] = Variable<Uint8List>(extensions.value);
    }
    if (msgSeq.present) {
      map['msg_seq'] = Variable<int>(msgSeq.value);
    }
    if (encryptedPayload.present) {
      map['encrypted_payload'] = Variable<Uint8List>(encryptedPayload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventEntriesCompanion(')
          ..write('id: $id, ')
          ..write('pubkey: $pubkey, ')
          ..write('createdAt: $createdAt, ')
          ..write('kind: $kind, ')
          ..write('refId: $refId, ')
          ..write('content: $content, ')
          ..write('mediaRefs: $mediaRefs, ')
          ..write('sig: $sig, ')
          ..write('isOwn: $isOwn, ')
          ..write('isSaved: $isSaved, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('lastViewed: $lastViewed, ')
          ..write('version: $version, ')
          ..write('extensions: $extensions, ')
          ..write('msgSeq: $msgSeq, ')
          ..write('encryptedPayload: $encryptedPayload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MediaCacheEntriesTable extends MediaCacheEntries
    with TableInfo<$MediaCacheEntriesTable, MediaCacheEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaCacheEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _hashMeta = const VerificationMeta('hash');
  @override
  late final GeneratedColumn<String> hash = GeneratedColumn<String>(
    'hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastAccessedMeta = const VerificationMeta(
    'lastAccessed',
  );
  @override
  late final GeneratedColumn<int> lastAccessed = GeneratedColumn<int>(
    'last_accessed',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [hash, path, size, lastAccessed];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_cache_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaCacheEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('hash')) {
      context.handle(
        _hashMeta,
        hash.isAcceptableOrUnknown(data['hash']!, _hashMeta),
      );
    } else if (isInserting) {
      context.missing(_hashMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    if (data.containsKey('last_accessed')) {
      context.handle(
        _lastAccessedMeta,
        lastAccessed.isAcceptableOrUnknown(
          data['last_accessed']!,
          _lastAccessedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastAccessedMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {hash};
  @override
  MediaCacheEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaCacheEntry(
      hash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hash'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
      lastAccessed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_accessed'],
      )!,
    );
  }

  @override
  $MediaCacheEntriesTable createAlias(String alias) {
    return $MediaCacheEntriesTable(attachedDatabase, alias);
  }
}

class MediaCacheEntry extends DataClass implements Insertable<MediaCacheEntry> {
  final String hash;
  final String path;
  final int size;
  final int lastAccessed;
  const MediaCacheEntry({
    required this.hash,
    required this.path,
    required this.size,
    required this.lastAccessed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['hash'] = Variable<String>(hash);
    map['path'] = Variable<String>(path);
    map['size'] = Variable<int>(size);
    map['last_accessed'] = Variable<int>(lastAccessed);
    return map;
  }

  MediaCacheEntriesCompanion toCompanion(bool nullToAbsent) {
    return MediaCacheEntriesCompanion(
      hash: Value(hash),
      path: Value(path),
      size: Value(size),
      lastAccessed: Value(lastAccessed),
    );
  }

  factory MediaCacheEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaCacheEntry(
      hash: serializer.fromJson<String>(json['hash']),
      path: serializer.fromJson<String>(json['path']),
      size: serializer.fromJson<int>(json['size']),
      lastAccessed: serializer.fromJson<int>(json['lastAccessed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'hash': serializer.toJson<String>(hash),
      'path': serializer.toJson<String>(path),
      'size': serializer.toJson<int>(size),
      'lastAccessed': serializer.toJson<int>(lastAccessed),
    };
  }

  MediaCacheEntry copyWith({
    String? hash,
    String? path,
    int? size,
    int? lastAccessed,
  }) => MediaCacheEntry(
    hash: hash ?? this.hash,
    path: path ?? this.path,
    size: size ?? this.size,
    lastAccessed: lastAccessed ?? this.lastAccessed,
  );
  MediaCacheEntry copyWithCompanion(MediaCacheEntriesCompanion data) {
    return MediaCacheEntry(
      hash: data.hash.present ? data.hash.value : this.hash,
      path: data.path.present ? data.path.value : this.path,
      size: data.size.present ? data.size.value : this.size,
      lastAccessed: data.lastAccessed.present
          ? data.lastAccessed.value
          : this.lastAccessed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaCacheEntry(')
          ..write('hash: $hash, ')
          ..write('path: $path, ')
          ..write('size: $size, ')
          ..write('lastAccessed: $lastAccessed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(hash, path, size, lastAccessed);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaCacheEntry &&
          other.hash == this.hash &&
          other.path == this.path &&
          other.size == this.size &&
          other.lastAccessed == this.lastAccessed);
}

class MediaCacheEntriesCompanion extends UpdateCompanion<MediaCacheEntry> {
  final Value<String> hash;
  final Value<String> path;
  final Value<int> size;
  final Value<int> lastAccessed;
  final Value<int> rowid;
  const MediaCacheEntriesCompanion({
    this.hash = const Value.absent(),
    this.path = const Value.absent(),
    this.size = const Value.absent(),
    this.lastAccessed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaCacheEntriesCompanion.insert({
    required String hash,
    required String path,
    required int size,
    required int lastAccessed,
    this.rowid = const Value.absent(),
  }) : hash = Value(hash),
       path = Value(path),
       size = Value(size),
       lastAccessed = Value(lastAccessed);
  static Insertable<MediaCacheEntry> custom({
    Expression<String>? hash,
    Expression<String>? path,
    Expression<int>? size,
    Expression<int>? lastAccessed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (hash != null) 'hash': hash,
      if (path != null) 'path': path,
      if (size != null) 'size': size,
      if (lastAccessed != null) 'last_accessed': lastAccessed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaCacheEntriesCompanion copyWith({
    Value<String>? hash,
    Value<String>? path,
    Value<int>? size,
    Value<int>? lastAccessed,
    Value<int>? rowid,
  }) {
    return MediaCacheEntriesCompanion(
      hash: hash ?? this.hash,
      path: path ?? this.path,
      size: size ?? this.size,
      lastAccessed: lastAccessed ?? this.lastAccessed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (hash.present) {
      map['hash'] = Variable<String>(hash.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (lastAccessed.present) {
      map['last_accessed'] = Variable<int>(lastAccessed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaCacheEntriesCompanion(')
          ..write('hash: $hash, ')
          ..write('path: $path, ')
          ..write('size: $size, ')
          ..write('lastAccessed: $lastAccessed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $InboundFollowRequestEntriesTable extends InboundFollowRequestEntries
    with
        TableInfo<
          $InboundFollowRequestEntriesTable,
          InboundFollowRequestEntry
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InboundFollowRequestEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pubkeyMeta = const VerificationMeta('pubkey');
  @override
  late final GeneratedColumn<String> pubkey = GeneratedColumn<String>(
    'pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _encryptedEndpointsMeta =
      const VerificationMeta('encryptedEndpoints');
  @override
  late final GeneratedColumn<Uint8List> encryptedEndpoints =
      GeneratedColumn<Uint8List>(
        'encrypted_endpoints',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requestTimestampMeta = const VerificationMeta(
    'requestTimestamp',
  );
  @override
  late final GeneratedColumn<int> requestTimestamp = GeneratedColumn<int>(
    'request_timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    pubkey,
    encryptedEndpoints,
    createdAt,
    requestTimestamp,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'inbound_follow_request_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<InboundFollowRequestEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('pubkey')) {
      context.handle(
        _pubkeyMeta,
        pubkey.isAcceptableOrUnknown(data['pubkey']!, _pubkeyMeta),
      );
    } else if (isInserting) {
      context.missing(_pubkeyMeta);
    }
    if (data.containsKey('encrypted_endpoints')) {
      context.handle(
        _encryptedEndpointsMeta,
        encryptedEndpoints.isAcceptableOrUnknown(
          data['encrypted_endpoints']!,
          _encryptedEndpointsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptedEndpointsMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('request_timestamp')) {
      context.handle(
        _requestTimestampMeta,
        requestTimestamp.isAcceptableOrUnknown(
          data['request_timestamp']!,
          _requestTimestampMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pubkey};
  @override
  InboundFollowRequestEntry map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InboundFollowRequestEntry(
      pubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pubkey'],
      )!,
      encryptedEndpoints: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}encrypted_endpoints'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      requestTimestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}request_timestamp'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
    );
  }

  @override
  $InboundFollowRequestEntriesTable createAlias(String alias) {
    return $InboundFollowRequestEntriesTable(attachedDatabase, alias);
  }
}

class InboundFollowRequestEntry extends DataClass
    implements Insertable<InboundFollowRequestEntry> {
  final String pubkey;
  final Uint8List encryptedEndpoints;
  final int createdAt;
  final int requestTimestamp;
  final String status;
  const InboundFollowRequestEntry({
    required this.pubkey,
    required this.encryptedEndpoints,
    required this.createdAt,
    required this.requestTimestamp,
    required this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['pubkey'] = Variable<String>(pubkey);
    map['encrypted_endpoints'] = Variable<Uint8List>(encryptedEndpoints);
    map['created_at'] = Variable<int>(createdAt);
    map['request_timestamp'] = Variable<int>(requestTimestamp);
    map['status'] = Variable<String>(status);
    return map;
  }

  InboundFollowRequestEntriesCompanion toCompanion(bool nullToAbsent) {
    return InboundFollowRequestEntriesCompanion(
      pubkey: Value(pubkey),
      encryptedEndpoints: Value(encryptedEndpoints),
      createdAt: Value(createdAt),
      requestTimestamp: Value(requestTimestamp),
      status: Value(status),
    );
  }

  factory InboundFollowRequestEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InboundFollowRequestEntry(
      pubkey: serializer.fromJson<String>(json['pubkey']),
      encryptedEndpoints: serializer.fromJson<Uint8List>(
        json['encryptedEndpoints'],
      ),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      requestTimestamp: serializer.fromJson<int>(json['requestTimestamp']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pubkey': serializer.toJson<String>(pubkey),
      'encryptedEndpoints': serializer.toJson<Uint8List>(encryptedEndpoints),
      'createdAt': serializer.toJson<int>(createdAt),
      'requestTimestamp': serializer.toJson<int>(requestTimestamp),
      'status': serializer.toJson<String>(status),
    };
  }

  InboundFollowRequestEntry copyWith({
    String? pubkey,
    Uint8List? encryptedEndpoints,
    int? createdAt,
    int? requestTimestamp,
    String? status,
  }) => InboundFollowRequestEntry(
    pubkey: pubkey ?? this.pubkey,
    encryptedEndpoints: encryptedEndpoints ?? this.encryptedEndpoints,
    createdAt: createdAt ?? this.createdAt,
    requestTimestamp: requestTimestamp ?? this.requestTimestamp,
    status: status ?? this.status,
  );
  InboundFollowRequestEntry copyWithCompanion(
    InboundFollowRequestEntriesCompanion data,
  ) {
    return InboundFollowRequestEntry(
      pubkey: data.pubkey.present ? data.pubkey.value : this.pubkey,
      encryptedEndpoints: data.encryptedEndpoints.present
          ? data.encryptedEndpoints.value
          : this.encryptedEndpoints,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      requestTimestamp: data.requestTimestamp.present
          ? data.requestTimestamp.value
          : this.requestTimestamp,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InboundFollowRequestEntry(')
          ..write('pubkey: $pubkey, ')
          ..write('encryptedEndpoints: $encryptedEndpoints, ')
          ..write('createdAt: $createdAt, ')
          ..write('requestTimestamp: $requestTimestamp, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    pubkey,
    $driftBlobEquality.hash(encryptedEndpoints),
    createdAt,
    requestTimestamp,
    status,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InboundFollowRequestEntry &&
          other.pubkey == this.pubkey &&
          $driftBlobEquality.equals(
            other.encryptedEndpoints,
            this.encryptedEndpoints,
          ) &&
          other.createdAt == this.createdAt &&
          other.requestTimestamp == this.requestTimestamp &&
          other.status == this.status);
}

class InboundFollowRequestEntriesCompanion
    extends UpdateCompanion<InboundFollowRequestEntry> {
  final Value<String> pubkey;
  final Value<Uint8List> encryptedEndpoints;
  final Value<int> createdAt;
  final Value<int> requestTimestamp;
  final Value<String> status;
  final Value<int> rowid;
  const InboundFollowRequestEntriesCompanion({
    this.pubkey = const Value.absent(),
    this.encryptedEndpoints = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.requestTimestamp = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InboundFollowRequestEntriesCompanion.insert({
    required String pubkey,
    required Uint8List encryptedEndpoints,
    required int createdAt,
    this.requestTimestamp = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : pubkey = Value(pubkey),
       encryptedEndpoints = Value(encryptedEndpoints),
       createdAt = Value(createdAt);
  static Insertable<InboundFollowRequestEntry> custom({
    Expression<String>? pubkey,
    Expression<Uint8List>? encryptedEndpoints,
    Expression<int>? createdAt,
    Expression<int>? requestTimestamp,
    Expression<String>? status,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pubkey != null) 'pubkey': pubkey,
      if (encryptedEndpoints != null) 'encrypted_endpoints': encryptedEndpoints,
      if (createdAt != null) 'created_at': createdAt,
      if (requestTimestamp != null) 'request_timestamp': requestTimestamp,
      if (status != null) 'status': status,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InboundFollowRequestEntriesCompanion copyWith({
    Value<String>? pubkey,
    Value<Uint8List>? encryptedEndpoints,
    Value<int>? createdAt,
    Value<int>? requestTimestamp,
    Value<String>? status,
    Value<int>? rowid,
  }) {
    return InboundFollowRequestEntriesCompanion(
      pubkey: pubkey ?? this.pubkey,
      encryptedEndpoints: encryptedEndpoints ?? this.encryptedEndpoints,
      createdAt: createdAt ?? this.createdAt,
      requestTimestamp: requestTimestamp ?? this.requestTimestamp,
      status: status ?? this.status,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pubkey.present) {
      map['pubkey'] = Variable<String>(pubkey.value);
    }
    if (encryptedEndpoints.present) {
      map['encrypted_endpoints'] = Variable<Uint8List>(
        encryptedEndpoints.value,
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (requestTimestamp.present) {
      map['request_timestamp'] = Variable<int>(requestTimestamp.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InboundFollowRequestEntriesCompanion(')
          ..write('pubkey: $pubkey, ')
          ..write('encryptedEndpoints: $encryptedEndpoints, ')
          ..write('createdAt: $createdAt, ')
          ..write('requestTimestamp: $requestTimestamp, ')
          ..write('status: $status, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboundFollowRequestEntriesTable extends OutboundFollowRequestEntries
    with
        TableInfo<
          $OutboundFollowRequestEntriesTable,
          OutboundFollowRequestEntry
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboundFollowRequestEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _pubkeyMeta = const VerificationMeta('pubkey');
  @override
  late final GeneratedColumn<String> pubkey = GeneratedColumn<String>(
    'pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _connectionCardMeta = const VerificationMeta(
    'connectionCard',
  );
  @override
  late final GeneratedColumn<String> connectionCard = GeneratedColumn<String>(
    'connection_card',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    pubkey,
    connectionCard,
    createdAt,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbound_follow_request_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboundFollowRequestEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('pubkey')) {
      context.handle(
        _pubkeyMeta,
        pubkey.isAcceptableOrUnknown(data['pubkey']!, _pubkeyMeta),
      );
    } else if (isInserting) {
      context.missing(_pubkeyMeta);
    }
    if (data.containsKey('connection_card')) {
      context.handle(
        _connectionCardMeta,
        connectionCard.isAcceptableOrUnknown(
          data['connection_card']!,
          _connectionCardMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_connectionCardMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {pubkey};
  @override
  OutboundFollowRequestEntry map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboundFollowRequestEntry(
      pubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pubkey'],
      )!,
      connectionCard: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}connection_card'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
    );
  }

  @override
  $OutboundFollowRequestEntriesTable createAlias(String alias) {
    return $OutboundFollowRequestEntriesTable(attachedDatabase, alias);
  }
}

class OutboundFollowRequestEntry extends DataClass
    implements Insertable<OutboundFollowRequestEntry> {
  final String pubkey;
  final String connectionCard;
  final int createdAt;
  final String status;
  const OutboundFollowRequestEntry({
    required this.pubkey,
    required this.connectionCard,
    required this.createdAt,
    required this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['pubkey'] = Variable<String>(pubkey);
    map['connection_card'] = Variable<String>(connectionCard);
    map['created_at'] = Variable<int>(createdAt);
    map['status'] = Variable<String>(status);
    return map;
  }

  OutboundFollowRequestEntriesCompanion toCompanion(bool nullToAbsent) {
    return OutboundFollowRequestEntriesCompanion(
      pubkey: Value(pubkey),
      connectionCard: Value(connectionCard),
      createdAt: Value(createdAt),
      status: Value(status),
    );
  }

  factory OutboundFollowRequestEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboundFollowRequestEntry(
      pubkey: serializer.fromJson<String>(json['pubkey']),
      connectionCard: serializer.fromJson<String>(json['connectionCard']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'pubkey': serializer.toJson<String>(pubkey),
      'connectionCard': serializer.toJson<String>(connectionCard),
      'createdAt': serializer.toJson<int>(createdAt),
      'status': serializer.toJson<String>(status),
    };
  }

  OutboundFollowRequestEntry copyWith({
    String? pubkey,
    String? connectionCard,
    int? createdAt,
    String? status,
  }) => OutboundFollowRequestEntry(
    pubkey: pubkey ?? this.pubkey,
    connectionCard: connectionCard ?? this.connectionCard,
    createdAt: createdAt ?? this.createdAt,
    status: status ?? this.status,
  );
  OutboundFollowRequestEntry copyWithCompanion(
    OutboundFollowRequestEntriesCompanion data,
  ) {
    return OutboundFollowRequestEntry(
      pubkey: data.pubkey.present ? data.pubkey.value : this.pubkey,
      connectionCard: data.connectionCard.present
          ? data.connectionCard.value
          : this.connectionCard,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboundFollowRequestEntry(')
          ..write('pubkey: $pubkey, ')
          ..write('connectionCard: $connectionCard, ')
          ..write('createdAt: $createdAt, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(pubkey, connectionCard, createdAt, status);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboundFollowRequestEntry &&
          other.pubkey == this.pubkey &&
          other.connectionCard == this.connectionCard &&
          other.createdAt == this.createdAt &&
          other.status == this.status);
}

class OutboundFollowRequestEntriesCompanion
    extends UpdateCompanion<OutboundFollowRequestEntry> {
  final Value<String> pubkey;
  final Value<String> connectionCard;
  final Value<int> createdAt;
  final Value<String> status;
  final Value<int> rowid;
  const OutboundFollowRequestEntriesCompanion({
    this.pubkey = const Value.absent(),
    this.connectionCard = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutboundFollowRequestEntriesCompanion.insert({
    required String pubkey,
    required String connectionCard,
    required int createdAt,
    this.status = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : pubkey = Value(pubkey),
       connectionCard = Value(connectionCard),
       createdAt = Value(createdAt);
  static Insertable<OutboundFollowRequestEntry> custom({
    Expression<String>? pubkey,
    Expression<String>? connectionCard,
    Expression<int>? createdAt,
    Expression<String>? status,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (pubkey != null) 'pubkey': pubkey,
      if (connectionCard != null) 'connection_card': connectionCard,
      if (createdAt != null) 'created_at': createdAt,
      if (status != null) 'status': status,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutboundFollowRequestEntriesCompanion copyWith({
    Value<String>? pubkey,
    Value<String>? connectionCard,
    Value<int>? createdAt,
    Value<String>? status,
    Value<int>? rowid,
  }) {
    return OutboundFollowRequestEntriesCompanion(
      pubkey: pubkey ?? this.pubkey,
      connectionCard: connectionCard ?? this.connectionCard,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (pubkey.present) {
      map['pubkey'] = Variable<String>(pubkey.value);
    }
    if (connectionCard.present) {
      map['connection_card'] = Variable<String>(connectionCard.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboundFollowRequestEntriesCompanion(')
          ..write('pubkey: $pubkey, ')
          ..write('connectionCard: $connectionCard, ')
          ..write('createdAt: $createdAt, ')
          ..write('status: $status, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutboundQueueEntriesTable extends OutboundQueueEntries
    with TableInfo<$OutboundQueueEntriesTable, OutboundQueueEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutboundQueueEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _targetPubkeyMeta = const VerificationMeta(
    'targetPubkey',
  );
  @override
  late final GeneratedColumn<String> targetPubkey = GeneratedColumn<String>(
    'target_pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventBlobMeta = const VerificationMeta(
    'eventBlob',
  );
  @override
  late final GeneratedColumn<Uint8List> eventBlob = GeneratedColumn<Uint8List>(
    'event_blob',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _retryCountMeta = const VerificationMeta(
    'retryCount',
  );
  @override
  late final GeneratedColumn<int> retryCount = GeneratedColumn<int>(
    'retry_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _itemTypeMeta = const VerificationMeta(
    'itemType',
  );
  @override
  late final GeneratedColumn<String> itemType = GeneratedColumn<String>(
    'item_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    targetPubkey,
    eventBlob,
    createdAt,
    retryCount,
    itemType,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outbound_queue_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutboundQueueEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('target_pubkey')) {
      context.handle(
        _targetPubkeyMeta,
        targetPubkey.isAcceptableOrUnknown(
          data['target_pubkey']!,
          _targetPubkeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetPubkeyMeta);
    }
    if (data.containsKey('event_blob')) {
      context.handle(
        _eventBlobMeta,
        eventBlob.isAcceptableOrUnknown(data['event_blob']!, _eventBlobMeta),
      );
    } else if (isInserting) {
      context.missing(_eventBlobMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('retry_count')) {
      context.handle(
        _retryCountMeta,
        retryCount.isAcceptableOrUnknown(data['retry_count']!, _retryCountMeta),
      );
    }
    if (data.containsKey('item_type')) {
      context.handle(
        _itemTypeMeta,
        itemType.isAcceptableOrUnknown(data['item_type']!, _itemTypeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutboundQueueEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutboundQueueEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      targetPubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_pubkey'],
      )!,
      eventBlob: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}event_blob'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      retryCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}retry_count'],
      )!,
      itemType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_type'],
      ),
    );
  }

  @override
  $OutboundQueueEntriesTable createAlias(String alias) {
    return $OutboundQueueEntriesTable(attachedDatabase, alias);
  }
}

class OutboundQueueEntry extends DataClass
    implements Insertable<OutboundQueueEntry> {
  final int id;
  final String targetPubkey;
  final Uint8List eventBlob;
  final int createdAt;
  final int retryCount;

  /// Plan 17: the EnvelopeItem `type` this row ships as when drained. Null ⇒
  /// `'event'` (back-compat with all pre-Plan-17 rows). Chatroom fan-out sets
  /// `'room-key'` / `'room-event'`.
  final String? itemType;
  const OutboundQueueEntry({
    required this.id,
    required this.targetPubkey,
    required this.eventBlob,
    required this.createdAt,
    required this.retryCount,
    this.itemType,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['target_pubkey'] = Variable<String>(targetPubkey);
    map['event_blob'] = Variable<Uint8List>(eventBlob);
    map['created_at'] = Variable<int>(createdAt);
    map['retry_count'] = Variable<int>(retryCount);
    if (!nullToAbsent || itemType != null) {
      map['item_type'] = Variable<String>(itemType);
    }
    return map;
  }

  OutboundQueueEntriesCompanion toCompanion(bool nullToAbsent) {
    return OutboundQueueEntriesCompanion(
      id: Value(id),
      targetPubkey: Value(targetPubkey),
      eventBlob: Value(eventBlob),
      createdAt: Value(createdAt),
      retryCount: Value(retryCount),
      itemType: itemType == null && nullToAbsent
          ? const Value.absent()
          : Value(itemType),
    );
  }

  factory OutboundQueueEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutboundQueueEntry(
      id: serializer.fromJson<int>(json['id']),
      targetPubkey: serializer.fromJson<String>(json['targetPubkey']),
      eventBlob: serializer.fromJson<Uint8List>(json['eventBlob']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      retryCount: serializer.fromJson<int>(json['retryCount']),
      itemType: serializer.fromJson<String?>(json['itemType']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'targetPubkey': serializer.toJson<String>(targetPubkey),
      'eventBlob': serializer.toJson<Uint8List>(eventBlob),
      'createdAt': serializer.toJson<int>(createdAt),
      'retryCount': serializer.toJson<int>(retryCount),
      'itemType': serializer.toJson<String?>(itemType),
    };
  }

  OutboundQueueEntry copyWith({
    int? id,
    String? targetPubkey,
    Uint8List? eventBlob,
    int? createdAt,
    int? retryCount,
    Value<String?> itemType = const Value.absent(),
  }) => OutboundQueueEntry(
    id: id ?? this.id,
    targetPubkey: targetPubkey ?? this.targetPubkey,
    eventBlob: eventBlob ?? this.eventBlob,
    createdAt: createdAt ?? this.createdAt,
    retryCount: retryCount ?? this.retryCount,
    itemType: itemType.present ? itemType.value : this.itemType,
  );
  OutboundQueueEntry copyWithCompanion(OutboundQueueEntriesCompanion data) {
    return OutboundQueueEntry(
      id: data.id.present ? data.id.value : this.id,
      targetPubkey: data.targetPubkey.present
          ? data.targetPubkey.value
          : this.targetPubkey,
      eventBlob: data.eventBlob.present ? data.eventBlob.value : this.eventBlob,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      retryCount: data.retryCount.present
          ? data.retryCount.value
          : this.retryCount,
      itemType: data.itemType.present ? data.itemType.value : this.itemType,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutboundQueueEntry(')
          ..write('id: $id, ')
          ..write('targetPubkey: $targetPubkey, ')
          ..write('eventBlob: $eventBlob, ')
          ..write('createdAt: $createdAt, ')
          ..write('retryCount: $retryCount, ')
          ..write('itemType: $itemType')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    targetPubkey,
    $driftBlobEquality.hash(eventBlob),
    createdAt,
    retryCount,
    itemType,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutboundQueueEntry &&
          other.id == this.id &&
          other.targetPubkey == this.targetPubkey &&
          $driftBlobEquality.equals(other.eventBlob, this.eventBlob) &&
          other.createdAt == this.createdAt &&
          other.retryCount == this.retryCount &&
          other.itemType == this.itemType);
}

class OutboundQueueEntriesCompanion
    extends UpdateCompanion<OutboundQueueEntry> {
  final Value<int> id;
  final Value<String> targetPubkey;
  final Value<Uint8List> eventBlob;
  final Value<int> createdAt;
  final Value<int> retryCount;
  final Value<String?> itemType;
  const OutboundQueueEntriesCompanion({
    this.id = const Value.absent(),
    this.targetPubkey = const Value.absent(),
    this.eventBlob = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.retryCount = const Value.absent(),
    this.itemType = const Value.absent(),
  });
  OutboundQueueEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String targetPubkey,
    required Uint8List eventBlob,
    required int createdAt,
    this.retryCount = const Value.absent(),
    this.itemType = const Value.absent(),
  }) : targetPubkey = Value(targetPubkey),
       eventBlob = Value(eventBlob),
       createdAt = Value(createdAt);
  static Insertable<OutboundQueueEntry> custom({
    Expression<int>? id,
    Expression<String>? targetPubkey,
    Expression<Uint8List>? eventBlob,
    Expression<int>? createdAt,
    Expression<int>? retryCount,
    Expression<String>? itemType,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (targetPubkey != null) 'target_pubkey': targetPubkey,
      if (eventBlob != null) 'event_blob': eventBlob,
      if (createdAt != null) 'created_at': createdAt,
      if (retryCount != null) 'retry_count': retryCount,
      if (itemType != null) 'item_type': itemType,
    });
  }

  OutboundQueueEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? targetPubkey,
    Value<Uint8List>? eventBlob,
    Value<int>? createdAt,
    Value<int>? retryCount,
    Value<String?>? itemType,
  }) {
    return OutboundQueueEntriesCompanion(
      id: id ?? this.id,
      targetPubkey: targetPubkey ?? this.targetPubkey,
      eventBlob: eventBlob ?? this.eventBlob,
      createdAt: createdAt ?? this.createdAt,
      retryCount: retryCount ?? this.retryCount,
      itemType: itemType ?? this.itemType,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (targetPubkey.present) {
      map['target_pubkey'] = Variable<String>(targetPubkey.value);
    }
    if (eventBlob.present) {
      map['event_blob'] = Variable<Uint8List>(eventBlob.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (retryCount.present) {
      map['retry_count'] = Variable<int>(retryCount.value);
    }
    if (itemType.present) {
      map['item_type'] = Variable<String>(itemType.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OutboundQueueEntriesCompanion(')
          ..write('id: $id, ')
          ..write('targetPubkey: $targetPubkey, ')
          ..write('eventBlob: $eventBlob, ')
          ..write('createdAt: $createdAt, ')
          ..write('retryCount: $retryCount, ')
          ..write('itemType: $itemType')
          ..write(')'))
        .toString();
  }
}

class $UnknownEnvelopeItemEntriesTable extends UnknownEnvelopeItemEntries
    with TableInfo<$UnknownEnvelopeItemEntriesTable, UnknownEnvelopeItemEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UnknownEnvelopeItemEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sourcePubkeyMeta = const VerificationMeta(
    'sourcePubkey',
  );
  @override
  late final GeneratedColumn<String> sourcePubkey = GeneratedColumn<String>(
    'source_pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _envelopeVersionMeta = const VerificationMeta(
    'envelopeVersion',
  );
  @override
  late final GeneratedColumn<String> envelopeVersion = GeneratedColumn<String>(
    'envelope_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<Uint8List> payload = GeneratedColumn<Uint8List>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _extensionsMeta = const VerificationMeta(
    'extensions',
  );
  @override
  late final GeneratedColumn<Uint8List> extensions = GeneratedColumn<Uint8List>(
    'extensions',
    aliasedName,
    true,
    type: DriftSqlType.blob,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _receivedAtMeta = const VerificationMeta(
    'receivedAt',
  );
  @override
  late final GeneratedColumn<int> receivedAt = GeneratedColumn<int>(
    'received_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sourcePubkey,
    envelopeVersion,
    type,
    payload,
    extensions,
    receivedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'unknown_envelope_item_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<UnknownEnvelopeItemEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('source_pubkey')) {
      context.handle(
        _sourcePubkeyMeta,
        sourcePubkey.isAcceptableOrUnknown(
          data['source_pubkey']!,
          _sourcePubkeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sourcePubkeyMeta);
    }
    if (data.containsKey('envelope_version')) {
      context.handle(
        _envelopeVersionMeta,
        envelopeVersion.isAcceptableOrUnknown(
          data['envelope_version']!,
          _envelopeVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_envelopeVersionMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('extensions')) {
      context.handle(
        _extensionsMeta,
        extensions.isAcceptableOrUnknown(data['extensions']!, _extensionsMeta),
      );
    }
    if (data.containsKey('received_at')) {
      context.handle(
        _receivedAtMeta,
        receivedAt.isAcceptableOrUnknown(data['received_at']!, _receivedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_receivedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UnknownEnvelopeItemEntry map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UnknownEnvelopeItemEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sourcePubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_pubkey'],
      )!,
      envelopeVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}envelope_version'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}payload'],
      )!,
      extensions: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}extensions'],
      ),
      receivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}received_at'],
      )!,
    );
  }

  @override
  $UnknownEnvelopeItemEntriesTable createAlias(String alias) {
    return $UnknownEnvelopeItemEntriesTable(attachedDatabase, alias);
  }
}

class UnknownEnvelopeItemEntry extends DataClass
    implements Insertable<UnknownEnvelopeItemEntry> {
  final int id;

  /// The peer pubkey we received this item from. Lets us scope retention /
  /// purge by source if a peer turns hostile.
  final String sourcePubkey;

  /// `Envelope.version` at receive time — useful when we eventually decide
  /// whether to forward the item back during sync.
  final String envelopeVersion;

  /// The unknown `type` string, e.g. `"commit"` or `"receipt"`.
  final String type;

  /// Raw payload bytes. We never decode these.
  final Uint8List payload;

  /// Item-level extensions, raw CBOR (or null if absent).
  final Uint8List? extensions;
  final int receivedAt;
  const UnknownEnvelopeItemEntry({
    required this.id,
    required this.sourcePubkey,
    required this.envelopeVersion,
    required this.type,
    required this.payload,
    this.extensions,
    required this.receivedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['source_pubkey'] = Variable<String>(sourcePubkey);
    map['envelope_version'] = Variable<String>(envelopeVersion);
    map['type'] = Variable<String>(type);
    map['payload'] = Variable<Uint8List>(payload);
    if (!nullToAbsent || extensions != null) {
      map['extensions'] = Variable<Uint8List>(extensions);
    }
    map['received_at'] = Variable<int>(receivedAt);
    return map;
  }

  UnknownEnvelopeItemEntriesCompanion toCompanion(bool nullToAbsent) {
    return UnknownEnvelopeItemEntriesCompanion(
      id: Value(id),
      sourcePubkey: Value(sourcePubkey),
      envelopeVersion: Value(envelopeVersion),
      type: Value(type),
      payload: Value(payload),
      extensions: extensions == null && nullToAbsent
          ? const Value.absent()
          : Value(extensions),
      receivedAt: Value(receivedAt),
    );
  }

  factory UnknownEnvelopeItemEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UnknownEnvelopeItemEntry(
      id: serializer.fromJson<int>(json['id']),
      sourcePubkey: serializer.fromJson<String>(json['sourcePubkey']),
      envelopeVersion: serializer.fromJson<String>(json['envelopeVersion']),
      type: serializer.fromJson<String>(json['type']),
      payload: serializer.fromJson<Uint8List>(json['payload']),
      extensions: serializer.fromJson<Uint8List?>(json['extensions']),
      receivedAt: serializer.fromJson<int>(json['receivedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sourcePubkey': serializer.toJson<String>(sourcePubkey),
      'envelopeVersion': serializer.toJson<String>(envelopeVersion),
      'type': serializer.toJson<String>(type),
      'payload': serializer.toJson<Uint8List>(payload),
      'extensions': serializer.toJson<Uint8List?>(extensions),
      'receivedAt': serializer.toJson<int>(receivedAt),
    };
  }

  UnknownEnvelopeItemEntry copyWith({
    int? id,
    String? sourcePubkey,
    String? envelopeVersion,
    String? type,
    Uint8List? payload,
    Value<Uint8List?> extensions = const Value.absent(),
    int? receivedAt,
  }) => UnknownEnvelopeItemEntry(
    id: id ?? this.id,
    sourcePubkey: sourcePubkey ?? this.sourcePubkey,
    envelopeVersion: envelopeVersion ?? this.envelopeVersion,
    type: type ?? this.type,
    payload: payload ?? this.payload,
    extensions: extensions.present ? extensions.value : this.extensions,
    receivedAt: receivedAt ?? this.receivedAt,
  );
  UnknownEnvelopeItemEntry copyWithCompanion(
    UnknownEnvelopeItemEntriesCompanion data,
  ) {
    return UnknownEnvelopeItemEntry(
      id: data.id.present ? data.id.value : this.id,
      sourcePubkey: data.sourcePubkey.present
          ? data.sourcePubkey.value
          : this.sourcePubkey,
      envelopeVersion: data.envelopeVersion.present
          ? data.envelopeVersion.value
          : this.envelopeVersion,
      type: data.type.present ? data.type.value : this.type,
      payload: data.payload.present ? data.payload.value : this.payload,
      extensions: data.extensions.present
          ? data.extensions.value
          : this.extensions,
      receivedAt: data.receivedAt.present
          ? data.receivedAt.value
          : this.receivedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('UnknownEnvelopeItemEntry(')
          ..write('id: $id, ')
          ..write('sourcePubkey: $sourcePubkey, ')
          ..write('envelopeVersion: $envelopeVersion, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('extensions: $extensions, ')
          ..write('receivedAt: $receivedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sourcePubkey,
    envelopeVersion,
    type,
    $driftBlobEquality.hash(payload),
    $driftBlobEquality.hash(extensions),
    receivedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UnknownEnvelopeItemEntry &&
          other.id == this.id &&
          other.sourcePubkey == this.sourcePubkey &&
          other.envelopeVersion == this.envelopeVersion &&
          other.type == this.type &&
          $driftBlobEquality.equals(other.payload, this.payload) &&
          $driftBlobEquality.equals(other.extensions, this.extensions) &&
          other.receivedAt == this.receivedAt);
}

class UnknownEnvelopeItemEntriesCompanion
    extends UpdateCompanion<UnknownEnvelopeItemEntry> {
  final Value<int> id;
  final Value<String> sourcePubkey;
  final Value<String> envelopeVersion;
  final Value<String> type;
  final Value<Uint8List> payload;
  final Value<Uint8List?> extensions;
  final Value<int> receivedAt;
  const UnknownEnvelopeItemEntriesCompanion({
    this.id = const Value.absent(),
    this.sourcePubkey = const Value.absent(),
    this.envelopeVersion = const Value.absent(),
    this.type = const Value.absent(),
    this.payload = const Value.absent(),
    this.extensions = const Value.absent(),
    this.receivedAt = const Value.absent(),
  });
  UnknownEnvelopeItemEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String sourcePubkey,
    required String envelopeVersion,
    required String type,
    required Uint8List payload,
    this.extensions = const Value.absent(),
    required int receivedAt,
  }) : sourcePubkey = Value(sourcePubkey),
       envelopeVersion = Value(envelopeVersion),
       type = Value(type),
       payload = Value(payload),
       receivedAt = Value(receivedAt);
  static Insertable<UnknownEnvelopeItemEntry> custom({
    Expression<int>? id,
    Expression<String>? sourcePubkey,
    Expression<String>? envelopeVersion,
    Expression<String>? type,
    Expression<Uint8List>? payload,
    Expression<Uint8List>? extensions,
    Expression<int>? receivedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sourcePubkey != null) 'source_pubkey': sourcePubkey,
      if (envelopeVersion != null) 'envelope_version': envelopeVersion,
      if (type != null) 'type': type,
      if (payload != null) 'payload': payload,
      if (extensions != null) 'extensions': extensions,
      if (receivedAt != null) 'received_at': receivedAt,
    });
  }

  UnknownEnvelopeItemEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? sourcePubkey,
    Value<String>? envelopeVersion,
    Value<String>? type,
    Value<Uint8List>? payload,
    Value<Uint8List?>? extensions,
    Value<int>? receivedAt,
  }) {
    return UnknownEnvelopeItemEntriesCompanion(
      id: id ?? this.id,
      sourcePubkey: sourcePubkey ?? this.sourcePubkey,
      envelopeVersion: envelopeVersion ?? this.envelopeVersion,
      type: type ?? this.type,
      payload: payload ?? this.payload,
      extensions: extensions ?? this.extensions,
      receivedAt: receivedAt ?? this.receivedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sourcePubkey.present) {
      map['source_pubkey'] = Variable<String>(sourcePubkey.value);
    }
    if (envelopeVersion.present) {
      map['envelope_version'] = Variable<String>(envelopeVersion.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (payload.present) {
      map['payload'] = Variable<Uint8List>(payload.value);
    }
    if (extensions.present) {
      map['extensions'] = Variable<Uint8List>(extensions.value);
    }
    if (receivedAt.present) {
      map['received_at'] = Variable<int>(receivedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UnknownEnvelopeItemEntriesCompanion(')
          ..write('id: $id, ')
          ..write('sourcePubkey: $sourcePubkey, ')
          ..write('envelopeVersion: $envelopeVersion, ')
          ..write('type: $type, ')
          ..write('payload: $payload, ')
          ..write('extensions: $extensions, ')
          ..write('receivedAt: $receivedAt')
          ..write(')'))
        .toString();
  }
}

class $FeedKeyHistoryEntriesTable extends FeedKeyHistoryEntries
    with TableInfo<$FeedKeyHistoryEntriesTable, FeedKeyHistoryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FeedKeyHistoryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _feedKeyMeta = const VerificationMeta(
    'feedKey',
  );
  @override
  late final GeneratedColumn<Uint8List> feedKey = GeneratedColumn<Uint8List>(
    'feed_key',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _feedKeyEpochMeta = const VerificationMeta(
    'feedKeyEpoch',
  );
  @override
  late final GeneratedColumn<int> feedKeyEpoch = GeneratedColumn<int>(
    'feed_key_epoch',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _validFromMeta = const VerificationMeta(
    'validFrom',
  );
  @override
  late final GeneratedColumn<int> validFrom = GeneratedColumn<int>(
    'valid_from',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _validUntilMeta = const VerificationMeta(
    'validUntil',
  );
  @override
  late final GeneratedColumn<int> validUntil = GeneratedColumn<int>(
    'valid_until',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    feedKey,
    feedKeyEpoch,
    validFrom,
    validUntil,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'feed_key_history_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<FeedKeyHistoryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('feed_key')) {
      context.handle(
        _feedKeyMeta,
        feedKey.isAcceptableOrUnknown(data['feed_key']!, _feedKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_feedKeyMeta);
    }
    if (data.containsKey('feed_key_epoch')) {
      context.handle(
        _feedKeyEpochMeta,
        feedKeyEpoch.isAcceptableOrUnknown(
          data['feed_key_epoch']!,
          _feedKeyEpochMeta,
        ),
      );
    }
    if (data.containsKey('valid_from')) {
      context.handle(
        _validFromMeta,
        validFrom.isAcceptableOrUnknown(data['valid_from']!, _validFromMeta),
      );
    } else if (isInserting) {
      context.missing(_validFromMeta);
    }
    if (data.containsKey('valid_until')) {
      context.handle(
        _validUntilMeta,
        validUntil.isAcceptableOrUnknown(data['valid_until']!, _validUntilMeta),
      );
    } else if (isInserting) {
      context.missing(_validUntilMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FeedKeyHistoryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FeedKeyHistoryEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      feedKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}feed_key'],
      )!,
      feedKeyEpoch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}feed_key_epoch'],
      )!,
      validFrom: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}valid_from'],
      )!,
      validUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}valid_until'],
      )!,
    );
  }

  @override
  $FeedKeyHistoryEntriesTable createAlias(String alias) {
    return $FeedKeyHistoryEntriesTable(attachedDatabase, alias);
  }
}

class FeedKeyHistoryEntry extends DataClass
    implements Insertable<FeedKeyHistoryEntry> {
  final int id;
  final Uint8List feedKey;
  final int feedKeyEpoch;
  final int validFrom;
  final int validUntil;
  const FeedKeyHistoryEntry({
    required this.id,
    required this.feedKey,
    required this.feedKeyEpoch,
    required this.validFrom,
    required this.validUntil,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['feed_key'] = Variable<Uint8List>(feedKey);
    map['feed_key_epoch'] = Variable<int>(feedKeyEpoch);
    map['valid_from'] = Variable<int>(validFrom);
    map['valid_until'] = Variable<int>(validUntil);
    return map;
  }

  FeedKeyHistoryEntriesCompanion toCompanion(bool nullToAbsent) {
    return FeedKeyHistoryEntriesCompanion(
      id: Value(id),
      feedKey: Value(feedKey),
      feedKeyEpoch: Value(feedKeyEpoch),
      validFrom: Value(validFrom),
      validUntil: Value(validUntil),
    );
  }

  factory FeedKeyHistoryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FeedKeyHistoryEntry(
      id: serializer.fromJson<int>(json['id']),
      feedKey: serializer.fromJson<Uint8List>(json['feedKey']),
      feedKeyEpoch: serializer.fromJson<int>(json['feedKeyEpoch']),
      validFrom: serializer.fromJson<int>(json['validFrom']),
      validUntil: serializer.fromJson<int>(json['validUntil']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'feedKey': serializer.toJson<Uint8List>(feedKey),
      'feedKeyEpoch': serializer.toJson<int>(feedKeyEpoch),
      'validFrom': serializer.toJson<int>(validFrom),
      'validUntil': serializer.toJson<int>(validUntil),
    };
  }

  FeedKeyHistoryEntry copyWith({
    int? id,
    Uint8List? feedKey,
    int? feedKeyEpoch,
    int? validFrom,
    int? validUntil,
  }) => FeedKeyHistoryEntry(
    id: id ?? this.id,
    feedKey: feedKey ?? this.feedKey,
    feedKeyEpoch: feedKeyEpoch ?? this.feedKeyEpoch,
    validFrom: validFrom ?? this.validFrom,
    validUntil: validUntil ?? this.validUntil,
  );
  FeedKeyHistoryEntry copyWithCompanion(FeedKeyHistoryEntriesCompanion data) {
    return FeedKeyHistoryEntry(
      id: data.id.present ? data.id.value : this.id,
      feedKey: data.feedKey.present ? data.feedKey.value : this.feedKey,
      feedKeyEpoch: data.feedKeyEpoch.present
          ? data.feedKeyEpoch.value
          : this.feedKeyEpoch,
      validFrom: data.validFrom.present ? data.validFrom.value : this.validFrom,
      validUntil: data.validUntil.present
          ? data.validUntil.value
          : this.validUntil,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FeedKeyHistoryEntry(')
          ..write('id: $id, ')
          ..write('feedKey: $feedKey, ')
          ..write('feedKeyEpoch: $feedKeyEpoch, ')
          ..write('validFrom: $validFrom, ')
          ..write('validUntil: $validUntil')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    $driftBlobEquality.hash(feedKey),
    feedKeyEpoch,
    validFrom,
    validUntil,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FeedKeyHistoryEntry &&
          other.id == this.id &&
          $driftBlobEquality.equals(other.feedKey, this.feedKey) &&
          other.feedKeyEpoch == this.feedKeyEpoch &&
          other.validFrom == this.validFrom &&
          other.validUntil == this.validUntil);
}

class FeedKeyHistoryEntriesCompanion
    extends UpdateCompanion<FeedKeyHistoryEntry> {
  final Value<int> id;
  final Value<Uint8List> feedKey;
  final Value<int> feedKeyEpoch;
  final Value<int> validFrom;
  final Value<int> validUntil;
  const FeedKeyHistoryEntriesCompanion({
    this.id = const Value.absent(),
    this.feedKey = const Value.absent(),
    this.feedKeyEpoch = const Value.absent(),
    this.validFrom = const Value.absent(),
    this.validUntil = const Value.absent(),
  });
  FeedKeyHistoryEntriesCompanion.insert({
    this.id = const Value.absent(),
    required Uint8List feedKey,
    this.feedKeyEpoch = const Value.absent(),
    required int validFrom,
    required int validUntil,
  }) : feedKey = Value(feedKey),
       validFrom = Value(validFrom),
       validUntil = Value(validUntil);
  static Insertable<FeedKeyHistoryEntry> custom({
    Expression<int>? id,
    Expression<Uint8List>? feedKey,
    Expression<int>? feedKeyEpoch,
    Expression<int>? validFrom,
    Expression<int>? validUntil,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (feedKey != null) 'feed_key': feedKey,
      if (feedKeyEpoch != null) 'feed_key_epoch': feedKeyEpoch,
      if (validFrom != null) 'valid_from': validFrom,
      if (validUntil != null) 'valid_until': validUntil,
    });
  }

  FeedKeyHistoryEntriesCompanion copyWith({
    Value<int>? id,
    Value<Uint8List>? feedKey,
    Value<int>? feedKeyEpoch,
    Value<int>? validFrom,
    Value<int>? validUntil,
  }) {
    return FeedKeyHistoryEntriesCompanion(
      id: id ?? this.id,
      feedKey: feedKey ?? this.feedKey,
      feedKeyEpoch: feedKeyEpoch ?? this.feedKeyEpoch,
      validFrom: validFrom ?? this.validFrom,
      validUntil: validUntil ?? this.validUntil,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (feedKey.present) {
      map['feed_key'] = Variable<Uint8List>(feedKey.value);
    }
    if (feedKeyEpoch.present) {
      map['feed_key_epoch'] = Variable<int>(feedKeyEpoch.value);
    }
    if (validFrom.present) {
      map['valid_from'] = Variable<int>(validFrom.value);
    }
    if (validUntil.present) {
      map['valid_until'] = Variable<int>(validUntil.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FeedKeyHistoryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('feedKey: $feedKey, ')
          ..write('feedKeyEpoch: $feedKeyEpoch, ')
          ..write('validFrom: $validFrom, ')
          ..write('validUntil: $validUntil')
          ..write(')'))
        .toString();
  }
}

class $FollowFeedKeyHistoryEntriesTable extends FollowFeedKeyHistoryEntries
    with
        TableInfo<
          $FollowFeedKeyHistoryEntriesTable,
          FollowFeedKeyHistoryEntry
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FollowFeedKeyHistoryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _followPubkeyMeta = const VerificationMeta(
    'followPubkey',
  );
  @override
  late final GeneratedColumn<String> followPubkey = GeneratedColumn<String>(
    'follow_pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _feedKeyMeta = const VerificationMeta(
    'feedKey',
  );
  @override
  late final GeneratedColumn<Uint8List> feedKey = GeneratedColumn<Uint8List>(
    'feed_key',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _feedKeyEpochMeta = const VerificationMeta(
    'feedKeyEpoch',
  );
  @override
  late final GeneratedColumn<int> feedKeyEpoch = GeneratedColumn<int>(
    'feed_key_epoch',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _validFromMeta = const VerificationMeta(
    'validFrom',
  );
  @override
  late final GeneratedColumn<int> validFrom = GeneratedColumn<int>(
    'valid_from',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _validUntilMeta = const VerificationMeta(
    'validUntil',
  );
  @override
  late final GeneratedColumn<int> validUntil = GeneratedColumn<int>(
    'valid_until',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    followPubkey,
    feedKey,
    feedKeyEpoch,
    validFrom,
    validUntil,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'follow_feed_key_history_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<FollowFeedKeyHistoryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('follow_pubkey')) {
      context.handle(
        _followPubkeyMeta,
        followPubkey.isAcceptableOrUnknown(
          data['follow_pubkey']!,
          _followPubkeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_followPubkeyMeta);
    }
    if (data.containsKey('feed_key')) {
      context.handle(
        _feedKeyMeta,
        feedKey.isAcceptableOrUnknown(data['feed_key']!, _feedKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_feedKeyMeta);
    }
    if (data.containsKey('feed_key_epoch')) {
      context.handle(
        _feedKeyEpochMeta,
        feedKeyEpoch.isAcceptableOrUnknown(
          data['feed_key_epoch']!,
          _feedKeyEpochMeta,
        ),
      );
    }
    if (data.containsKey('valid_from')) {
      context.handle(
        _validFromMeta,
        validFrom.isAcceptableOrUnknown(data['valid_from']!, _validFromMeta),
      );
    } else if (isInserting) {
      context.missing(_validFromMeta);
    }
    if (data.containsKey('valid_until')) {
      context.handle(
        _validUntilMeta,
        validUntil.isAcceptableOrUnknown(data['valid_until']!, _validUntilMeta),
      );
    } else if (isInserting) {
      context.missing(_validUntilMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FollowFeedKeyHistoryEntry map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FollowFeedKeyHistoryEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      followPubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}follow_pubkey'],
      )!,
      feedKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}feed_key'],
      )!,
      feedKeyEpoch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}feed_key_epoch'],
      )!,
      validFrom: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}valid_from'],
      )!,
      validUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}valid_until'],
      )!,
    );
  }

  @override
  $FollowFeedKeyHistoryEntriesTable createAlias(String alias) {
    return $FollowFeedKeyHistoryEntriesTable(attachedDatabase, alias);
  }
}

class FollowFeedKeyHistoryEntry extends DataClass
    implements Insertable<FollowFeedKeyHistoryEntry> {
  final int id;
  final String followPubkey;
  final Uint8List feedKey;
  final int feedKeyEpoch;
  final int validFrom;
  final int validUntil;
  const FollowFeedKeyHistoryEntry({
    required this.id,
    required this.followPubkey,
    required this.feedKey,
    required this.feedKeyEpoch,
    required this.validFrom,
    required this.validUntil,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['follow_pubkey'] = Variable<String>(followPubkey);
    map['feed_key'] = Variable<Uint8List>(feedKey);
    map['feed_key_epoch'] = Variable<int>(feedKeyEpoch);
    map['valid_from'] = Variable<int>(validFrom);
    map['valid_until'] = Variable<int>(validUntil);
    return map;
  }

  FollowFeedKeyHistoryEntriesCompanion toCompanion(bool nullToAbsent) {
    return FollowFeedKeyHistoryEntriesCompanion(
      id: Value(id),
      followPubkey: Value(followPubkey),
      feedKey: Value(feedKey),
      feedKeyEpoch: Value(feedKeyEpoch),
      validFrom: Value(validFrom),
      validUntil: Value(validUntil),
    );
  }

  factory FollowFeedKeyHistoryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FollowFeedKeyHistoryEntry(
      id: serializer.fromJson<int>(json['id']),
      followPubkey: serializer.fromJson<String>(json['followPubkey']),
      feedKey: serializer.fromJson<Uint8List>(json['feedKey']),
      feedKeyEpoch: serializer.fromJson<int>(json['feedKeyEpoch']),
      validFrom: serializer.fromJson<int>(json['validFrom']),
      validUntil: serializer.fromJson<int>(json['validUntil']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'followPubkey': serializer.toJson<String>(followPubkey),
      'feedKey': serializer.toJson<Uint8List>(feedKey),
      'feedKeyEpoch': serializer.toJson<int>(feedKeyEpoch),
      'validFrom': serializer.toJson<int>(validFrom),
      'validUntil': serializer.toJson<int>(validUntil),
    };
  }

  FollowFeedKeyHistoryEntry copyWith({
    int? id,
    String? followPubkey,
    Uint8List? feedKey,
    int? feedKeyEpoch,
    int? validFrom,
    int? validUntil,
  }) => FollowFeedKeyHistoryEntry(
    id: id ?? this.id,
    followPubkey: followPubkey ?? this.followPubkey,
    feedKey: feedKey ?? this.feedKey,
    feedKeyEpoch: feedKeyEpoch ?? this.feedKeyEpoch,
    validFrom: validFrom ?? this.validFrom,
    validUntil: validUntil ?? this.validUntil,
  );
  FollowFeedKeyHistoryEntry copyWithCompanion(
    FollowFeedKeyHistoryEntriesCompanion data,
  ) {
    return FollowFeedKeyHistoryEntry(
      id: data.id.present ? data.id.value : this.id,
      followPubkey: data.followPubkey.present
          ? data.followPubkey.value
          : this.followPubkey,
      feedKey: data.feedKey.present ? data.feedKey.value : this.feedKey,
      feedKeyEpoch: data.feedKeyEpoch.present
          ? data.feedKeyEpoch.value
          : this.feedKeyEpoch,
      validFrom: data.validFrom.present ? data.validFrom.value : this.validFrom,
      validUntil: data.validUntil.present
          ? data.validUntil.value
          : this.validUntil,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FollowFeedKeyHistoryEntry(')
          ..write('id: $id, ')
          ..write('followPubkey: $followPubkey, ')
          ..write('feedKey: $feedKey, ')
          ..write('feedKeyEpoch: $feedKeyEpoch, ')
          ..write('validFrom: $validFrom, ')
          ..write('validUntil: $validUntil')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    followPubkey,
    $driftBlobEquality.hash(feedKey),
    feedKeyEpoch,
    validFrom,
    validUntil,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FollowFeedKeyHistoryEntry &&
          other.id == this.id &&
          other.followPubkey == this.followPubkey &&
          $driftBlobEquality.equals(other.feedKey, this.feedKey) &&
          other.feedKeyEpoch == this.feedKeyEpoch &&
          other.validFrom == this.validFrom &&
          other.validUntil == this.validUntil);
}

class FollowFeedKeyHistoryEntriesCompanion
    extends UpdateCompanion<FollowFeedKeyHistoryEntry> {
  final Value<int> id;
  final Value<String> followPubkey;
  final Value<Uint8List> feedKey;
  final Value<int> feedKeyEpoch;
  final Value<int> validFrom;
  final Value<int> validUntil;
  const FollowFeedKeyHistoryEntriesCompanion({
    this.id = const Value.absent(),
    this.followPubkey = const Value.absent(),
    this.feedKey = const Value.absent(),
    this.feedKeyEpoch = const Value.absent(),
    this.validFrom = const Value.absent(),
    this.validUntil = const Value.absent(),
  });
  FollowFeedKeyHistoryEntriesCompanion.insert({
    this.id = const Value.absent(),
    required String followPubkey,
    required Uint8List feedKey,
    this.feedKeyEpoch = const Value.absent(),
    required int validFrom,
    required int validUntil,
  }) : followPubkey = Value(followPubkey),
       feedKey = Value(feedKey),
       validFrom = Value(validFrom),
       validUntil = Value(validUntil);
  static Insertable<FollowFeedKeyHistoryEntry> custom({
    Expression<int>? id,
    Expression<String>? followPubkey,
    Expression<Uint8List>? feedKey,
    Expression<int>? feedKeyEpoch,
    Expression<int>? validFrom,
    Expression<int>? validUntil,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (followPubkey != null) 'follow_pubkey': followPubkey,
      if (feedKey != null) 'feed_key': feedKey,
      if (feedKeyEpoch != null) 'feed_key_epoch': feedKeyEpoch,
      if (validFrom != null) 'valid_from': validFrom,
      if (validUntil != null) 'valid_until': validUntil,
    });
  }

  FollowFeedKeyHistoryEntriesCompanion copyWith({
    Value<int>? id,
    Value<String>? followPubkey,
    Value<Uint8List>? feedKey,
    Value<int>? feedKeyEpoch,
    Value<int>? validFrom,
    Value<int>? validUntil,
  }) {
    return FollowFeedKeyHistoryEntriesCompanion(
      id: id ?? this.id,
      followPubkey: followPubkey ?? this.followPubkey,
      feedKey: feedKey ?? this.feedKey,
      feedKeyEpoch: feedKeyEpoch ?? this.feedKeyEpoch,
      validFrom: validFrom ?? this.validFrom,
      validUntil: validUntil ?? this.validUntil,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (followPubkey.present) {
      map['follow_pubkey'] = Variable<String>(followPubkey.value);
    }
    if (feedKey.present) {
      map['feed_key'] = Variable<Uint8List>(feedKey.value);
    }
    if (feedKeyEpoch.present) {
      map['feed_key_epoch'] = Variable<int>(feedKeyEpoch.value);
    }
    if (validFrom.present) {
      map['valid_from'] = Variable<int>(validFrom.value);
    }
    if (validUntil.present) {
      map['valid_until'] = Variable<int>(validUntil.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FollowFeedKeyHistoryEntriesCompanion(')
          ..write('id: $id, ')
          ..write('followPubkey: $followPubkey, ')
          ..write('feedKey: $feedKey, ')
          ..write('feedKeyEpoch: $feedKeyEpoch, ')
          ..write('validFrom: $validFrom, ')
          ..write('validUntil: $validUntil')
          ..write(')'))
        .toString();
  }
}

class $PendingKeyDistributionEntriesTable extends PendingKeyDistributionEntries
    with
        TableInfo<
          $PendingKeyDistributionEntriesTable,
          PendingKeyDistributionEntry
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingKeyDistributionEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _targetPubkeyMeta = const VerificationMeta(
    'targetPubkey',
  );
  @override
  late final GeneratedColumn<String> targetPubkey = GeneratedColumn<String>(
    'target_pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _encryptedFeedKeyMeta = const VerificationMeta(
    'encryptedFeedKey',
  );
  @override
  late final GeneratedColumn<Uint8List> encryptedFeedKey =
      GeneratedColumn<Uint8List>(
        'encrypted_feed_key',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _nonceMeta = const VerificationMeta('nonce');
  @override
  late final GeneratedColumn<Uint8List> nonce = GeneratedColumn<Uint8List>(
    'nonce',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _distributedMeta = const VerificationMeta(
    'distributed',
  );
  @override
  late final GeneratedColumn<int> distributed = GeneratedColumn<int>(
    'distributed',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    targetPubkey,
    encryptedFeedKey,
    nonce,
    createdAt,
    distributed,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_key_distribution_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingKeyDistributionEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('target_pubkey')) {
      context.handle(
        _targetPubkeyMeta,
        targetPubkey.isAcceptableOrUnknown(
          data['target_pubkey']!,
          _targetPubkeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetPubkeyMeta);
    }
    if (data.containsKey('encrypted_feed_key')) {
      context.handle(
        _encryptedFeedKeyMeta,
        encryptedFeedKey.isAcceptableOrUnknown(
          data['encrypted_feed_key']!,
          _encryptedFeedKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptedFeedKeyMeta);
    }
    if (data.containsKey('nonce')) {
      context.handle(
        _nonceMeta,
        nonce.isAcceptableOrUnknown(data['nonce']!, _nonceMeta),
      );
    } else if (isInserting) {
      context.missing(_nonceMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('distributed')) {
      context.handle(
        _distributedMeta,
        distributed.isAcceptableOrUnknown(
          data['distributed']!,
          _distributedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {targetPubkey, createdAt};
  @override
  PendingKeyDistributionEntry map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingKeyDistributionEntry(
      targetPubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_pubkey'],
      )!,
      encryptedFeedKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}encrypted_feed_key'],
      )!,
      nonce: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}nonce'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      distributed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}distributed'],
      )!,
    );
  }

  @override
  $PendingKeyDistributionEntriesTable createAlias(String alias) {
    return $PendingKeyDistributionEntriesTable(attachedDatabase, alias);
  }
}

class PendingKeyDistributionEntry extends DataClass
    implements Insertable<PendingKeyDistributionEntry> {
  final String targetPubkey;
  final Uint8List encryptedFeedKey;
  final Uint8List nonce;
  final int createdAt;
  final int distributed;
  const PendingKeyDistributionEntry({
    required this.targetPubkey,
    required this.encryptedFeedKey,
    required this.nonce,
    required this.createdAt,
    required this.distributed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['target_pubkey'] = Variable<String>(targetPubkey);
    map['encrypted_feed_key'] = Variable<Uint8List>(encryptedFeedKey);
    map['nonce'] = Variable<Uint8List>(nonce);
    map['created_at'] = Variable<int>(createdAt);
    map['distributed'] = Variable<int>(distributed);
    return map;
  }

  PendingKeyDistributionEntriesCompanion toCompanion(bool nullToAbsent) {
    return PendingKeyDistributionEntriesCompanion(
      targetPubkey: Value(targetPubkey),
      encryptedFeedKey: Value(encryptedFeedKey),
      nonce: Value(nonce),
      createdAt: Value(createdAt),
      distributed: Value(distributed),
    );
  }

  factory PendingKeyDistributionEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingKeyDistributionEntry(
      targetPubkey: serializer.fromJson<String>(json['targetPubkey']),
      encryptedFeedKey: serializer.fromJson<Uint8List>(
        json['encryptedFeedKey'],
      ),
      nonce: serializer.fromJson<Uint8List>(json['nonce']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      distributed: serializer.fromJson<int>(json['distributed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'targetPubkey': serializer.toJson<String>(targetPubkey),
      'encryptedFeedKey': serializer.toJson<Uint8List>(encryptedFeedKey),
      'nonce': serializer.toJson<Uint8List>(nonce),
      'createdAt': serializer.toJson<int>(createdAt),
      'distributed': serializer.toJson<int>(distributed),
    };
  }

  PendingKeyDistributionEntry copyWith({
    String? targetPubkey,
    Uint8List? encryptedFeedKey,
    Uint8List? nonce,
    int? createdAt,
    int? distributed,
  }) => PendingKeyDistributionEntry(
    targetPubkey: targetPubkey ?? this.targetPubkey,
    encryptedFeedKey: encryptedFeedKey ?? this.encryptedFeedKey,
    nonce: nonce ?? this.nonce,
    createdAt: createdAt ?? this.createdAt,
    distributed: distributed ?? this.distributed,
  );
  PendingKeyDistributionEntry copyWithCompanion(
    PendingKeyDistributionEntriesCompanion data,
  ) {
    return PendingKeyDistributionEntry(
      targetPubkey: data.targetPubkey.present
          ? data.targetPubkey.value
          : this.targetPubkey,
      encryptedFeedKey: data.encryptedFeedKey.present
          ? data.encryptedFeedKey.value
          : this.encryptedFeedKey,
      nonce: data.nonce.present ? data.nonce.value : this.nonce,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      distributed: data.distributed.present
          ? data.distributed.value
          : this.distributed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingKeyDistributionEntry(')
          ..write('targetPubkey: $targetPubkey, ')
          ..write('encryptedFeedKey: $encryptedFeedKey, ')
          ..write('nonce: $nonce, ')
          ..write('createdAt: $createdAt, ')
          ..write('distributed: $distributed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    targetPubkey,
    $driftBlobEquality.hash(encryptedFeedKey),
    $driftBlobEquality.hash(nonce),
    createdAt,
    distributed,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingKeyDistributionEntry &&
          other.targetPubkey == this.targetPubkey &&
          $driftBlobEquality.equals(
            other.encryptedFeedKey,
            this.encryptedFeedKey,
          ) &&
          $driftBlobEquality.equals(other.nonce, this.nonce) &&
          other.createdAt == this.createdAt &&
          other.distributed == this.distributed);
}

class PendingKeyDistributionEntriesCompanion
    extends UpdateCompanion<PendingKeyDistributionEntry> {
  final Value<String> targetPubkey;
  final Value<Uint8List> encryptedFeedKey;
  final Value<Uint8List> nonce;
  final Value<int> createdAt;
  final Value<int> distributed;
  final Value<int> rowid;
  const PendingKeyDistributionEntriesCompanion({
    this.targetPubkey = const Value.absent(),
    this.encryptedFeedKey = const Value.absent(),
    this.nonce = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.distributed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingKeyDistributionEntriesCompanion.insert({
    required String targetPubkey,
    required Uint8List encryptedFeedKey,
    required Uint8List nonce,
    required int createdAt,
    this.distributed = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : targetPubkey = Value(targetPubkey),
       encryptedFeedKey = Value(encryptedFeedKey),
       nonce = Value(nonce),
       createdAt = Value(createdAt);
  static Insertable<PendingKeyDistributionEntry> custom({
    Expression<String>? targetPubkey,
    Expression<Uint8List>? encryptedFeedKey,
    Expression<Uint8List>? nonce,
    Expression<int>? createdAt,
    Expression<int>? distributed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (targetPubkey != null) 'target_pubkey': targetPubkey,
      if (encryptedFeedKey != null) 'encrypted_feed_key': encryptedFeedKey,
      if (nonce != null) 'nonce': nonce,
      if (createdAt != null) 'created_at': createdAt,
      if (distributed != null) 'distributed': distributed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingKeyDistributionEntriesCompanion copyWith({
    Value<String>? targetPubkey,
    Value<Uint8List>? encryptedFeedKey,
    Value<Uint8List>? nonce,
    Value<int>? createdAt,
    Value<int>? distributed,
    Value<int>? rowid,
  }) {
    return PendingKeyDistributionEntriesCompanion(
      targetPubkey: targetPubkey ?? this.targetPubkey,
      encryptedFeedKey: encryptedFeedKey ?? this.encryptedFeedKey,
      nonce: nonce ?? this.nonce,
      createdAt: createdAt ?? this.createdAt,
      distributed: distributed ?? this.distributed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (targetPubkey.present) {
      map['target_pubkey'] = Variable<String>(targetPubkey.value);
    }
    if (encryptedFeedKey.present) {
      map['encrypted_feed_key'] = Variable<Uint8List>(encryptedFeedKey.value);
    }
    if (nonce.present) {
      map['nonce'] = Variable<Uint8List>(nonce.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (distributed.present) {
      map['distributed'] = Variable<int>(distributed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingKeyDistributionEntriesCompanion(')
          ..write('targetPubkey: $targetPubkey, ')
          ..write('encryptedFeedKey: $encryptedFeedKey, ')
          ..write('nonce: $nonce, ')
          ..write('createdAt: $createdAt, ')
          ..write('distributed: $distributed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PairedRelayEntriesTable extends PairedRelayEntries
    with TableInfo<$PairedRelayEntriesTable, PairedRelayEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PairedRelayEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _relayIdMeta = const VerificationMeta(
    'relayId',
  );
  @override
  late final GeneratedColumn<String> relayId = GeneratedColumn<String>(
    'relay_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relayOnionMeta = const VerificationMeta(
    'relayOnion',
  );
  @override
  late final GeneratedColumn<String> relayOnion = GeneratedColumn<String>(
    'relay_onion',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pairedAtMeta = const VerificationMeta(
    'pairedAt',
  );
  @override
  late final GeneratedColumn<int> pairedAt = GeneratedColumn<int>(
    'paired_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relayBackfillCompleteMeta =
      const VerificationMeta('relayBackfillComplete');
  @override
  late final GeneratedColumn<int> relayBackfillComplete = GeneratedColumn<int>(
    'relay_backfill_complete',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _relayPruneBeforeMeta = const VerificationMeta(
    'relayPruneBefore',
  );
  @override
  late final GeneratedColumn<int> relayPruneBefore = GeneratedColumn<int>(
    'relay_prune_before',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastPushAtMeta = const VerificationMeta(
    'lastPushAt',
  );
  @override
  late final GeneratedColumn<int> lastPushAt = GeneratedColumn<int>(
    'last_push_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    relayId,
    relayOnion,
    pairedAt,
    relayBackfillComplete,
    relayPruneBefore,
    lastPushAt,
    lastError,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'paired_relay_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<PairedRelayEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('relay_id')) {
      context.handle(
        _relayIdMeta,
        relayId.isAcceptableOrUnknown(data['relay_id']!, _relayIdMeta),
      );
    } else if (isInserting) {
      context.missing(_relayIdMeta);
    }
    if (data.containsKey('relay_onion')) {
      context.handle(
        _relayOnionMeta,
        relayOnion.isAcceptableOrUnknown(data['relay_onion']!, _relayOnionMeta),
      );
    } else if (isInserting) {
      context.missing(_relayOnionMeta);
    }
    if (data.containsKey('paired_at')) {
      context.handle(
        _pairedAtMeta,
        pairedAt.isAcceptableOrUnknown(data['paired_at']!, _pairedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_pairedAtMeta);
    }
    if (data.containsKey('relay_backfill_complete')) {
      context.handle(
        _relayBackfillCompleteMeta,
        relayBackfillComplete.isAcceptableOrUnknown(
          data['relay_backfill_complete']!,
          _relayBackfillCompleteMeta,
        ),
      );
    }
    if (data.containsKey('relay_prune_before')) {
      context.handle(
        _relayPruneBeforeMeta,
        relayPruneBefore.isAcceptableOrUnknown(
          data['relay_prune_before']!,
          _relayPruneBeforeMeta,
        ),
      );
    }
    if (data.containsKey('last_push_at')) {
      context.handle(
        _lastPushAtMeta,
        lastPushAt.isAcceptableOrUnknown(
          data['last_push_at']!,
          _lastPushAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {relayId};
  @override
  PairedRelayEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PairedRelayEntry(
      relayId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relay_id'],
      )!,
      relayOnion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relay_onion'],
      )!,
      pairedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}paired_at'],
      )!,
      relayBackfillComplete: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}relay_backfill_complete'],
      )!,
      relayPruneBefore: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}relay_prune_before'],
      )!,
      lastPushAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_push_at'],
      )!,
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
    );
  }

  @override
  $PairedRelayEntriesTable createAlias(String alias) {
    return $PairedRelayEntriesTable(attachedDatabase, alias);
  }
}

class PairedRelayEntry extends DataClass
    implements Insertable<PairedRelayEntry> {
  final String relayId;
  final String relayOnion;
  final int pairedAt;
  final int relayBackfillComplete;
  final int relayPruneBefore;
  final int lastPushAt;
  final String? lastError;
  const PairedRelayEntry({
    required this.relayId,
    required this.relayOnion,
    required this.pairedAt,
    required this.relayBackfillComplete,
    required this.relayPruneBefore,
    required this.lastPushAt,
    this.lastError,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['relay_id'] = Variable<String>(relayId);
    map['relay_onion'] = Variable<String>(relayOnion);
    map['paired_at'] = Variable<int>(pairedAt);
    map['relay_backfill_complete'] = Variable<int>(relayBackfillComplete);
    map['relay_prune_before'] = Variable<int>(relayPruneBefore);
    map['last_push_at'] = Variable<int>(lastPushAt);
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    return map;
  }

  PairedRelayEntriesCompanion toCompanion(bool nullToAbsent) {
    return PairedRelayEntriesCompanion(
      relayId: Value(relayId),
      relayOnion: Value(relayOnion),
      pairedAt: Value(pairedAt),
      relayBackfillComplete: Value(relayBackfillComplete),
      relayPruneBefore: Value(relayPruneBefore),
      lastPushAt: Value(lastPushAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
    );
  }

  factory PairedRelayEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PairedRelayEntry(
      relayId: serializer.fromJson<String>(json['relayId']),
      relayOnion: serializer.fromJson<String>(json['relayOnion']),
      pairedAt: serializer.fromJson<int>(json['pairedAt']),
      relayBackfillComplete: serializer.fromJson<int>(
        json['relayBackfillComplete'],
      ),
      relayPruneBefore: serializer.fromJson<int>(json['relayPruneBefore']),
      lastPushAt: serializer.fromJson<int>(json['lastPushAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'relayId': serializer.toJson<String>(relayId),
      'relayOnion': serializer.toJson<String>(relayOnion),
      'pairedAt': serializer.toJson<int>(pairedAt),
      'relayBackfillComplete': serializer.toJson<int>(relayBackfillComplete),
      'relayPruneBefore': serializer.toJson<int>(relayPruneBefore),
      'lastPushAt': serializer.toJson<int>(lastPushAt),
      'lastError': serializer.toJson<String?>(lastError),
    };
  }

  PairedRelayEntry copyWith({
    String? relayId,
    String? relayOnion,
    int? pairedAt,
    int? relayBackfillComplete,
    int? relayPruneBefore,
    int? lastPushAt,
    Value<String?> lastError = const Value.absent(),
  }) => PairedRelayEntry(
    relayId: relayId ?? this.relayId,
    relayOnion: relayOnion ?? this.relayOnion,
    pairedAt: pairedAt ?? this.pairedAt,
    relayBackfillComplete: relayBackfillComplete ?? this.relayBackfillComplete,
    relayPruneBefore: relayPruneBefore ?? this.relayPruneBefore,
    lastPushAt: lastPushAt ?? this.lastPushAt,
    lastError: lastError.present ? lastError.value : this.lastError,
  );
  PairedRelayEntry copyWithCompanion(PairedRelayEntriesCompanion data) {
    return PairedRelayEntry(
      relayId: data.relayId.present ? data.relayId.value : this.relayId,
      relayOnion: data.relayOnion.present
          ? data.relayOnion.value
          : this.relayOnion,
      pairedAt: data.pairedAt.present ? data.pairedAt.value : this.pairedAt,
      relayBackfillComplete: data.relayBackfillComplete.present
          ? data.relayBackfillComplete.value
          : this.relayBackfillComplete,
      relayPruneBefore: data.relayPruneBefore.present
          ? data.relayPruneBefore.value
          : this.relayPruneBefore,
      lastPushAt: data.lastPushAt.present
          ? data.lastPushAt.value
          : this.lastPushAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PairedRelayEntry(')
          ..write('relayId: $relayId, ')
          ..write('relayOnion: $relayOnion, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('relayBackfillComplete: $relayBackfillComplete, ')
          ..write('relayPruneBefore: $relayPruneBefore, ')
          ..write('lastPushAt: $lastPushAt, ')
          ..write('lastError: $lastError')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    relayId,
    relayOnion,
    pairedAt,
    relayBackfillComplete,
    relayPruneBefore,
    lastPushAt,
    lastError,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PairedRelayEntry &&
          other.relayId == this.relayId &&
          other.relayOnion == this.relayOnion &&
          other.pairedAt == this.pairedAt &&
          other.relayBackfillComplete == this.relayBackfillComplete &&
          other.relayPruneBefore == this.relayPruneBefore &&
          other.lastPushAt == this.lastPushAt &&
          other.lastError == this.lastError);
}

class PairedRelayEntriesCompanion extends UpdateCompanion<PairedRelayEntry> {
  final Value<String> relayId;
  final Value<String> relayOnion;
  final Value<int> pairedAt;
  final Value<int> relayBackfillComplete;
  final Value<int> relayPruneBefore;
  final Value<int> lastPushAt;
  final Value<String?> lastError;
  final Value<int> rowid;
  const PairedRelayEntriesCompanion({
    this.relayId = const Value.absent(),
    this.relayOnion = const Value.absent(),
    this.pairedAt = const Value.absent(),
    this.relayBackfillComplete = const Value.absent(),
    this.relayPruneBefore = const Value.absent(),
    this.lastPushAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PairedRelayEntriesCompanion.insert({
    required String relayId,
    required String relayOnion,
    required int pairedAt,
    this.relayBackfillComplete = const Value.absent(),
    this.relayPruneBefore = const Value.absent(),
    this.lastPushAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : relayId = Value(relayId),
       relayOnion = Value(relayOnion),
       pairedAt = Value(pairedAt);
  static Insertable<PairedRelayEntry> custom({
    Expression<String>? relayId,
    Expression<String>? relayOnion,
    Expression<int>? pairedAt,
    Expression<int>? relayBackfillComplete,
    Expression<int>? relayPruneBefore,
    Expression<int>? lastPushAt,
    Expression<String>? lastError,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (relayId != null) 'relay_id': relayId,
      if (relayOnion != null) 'relay_onion': relayOnion,
      if (pairedAt != null) 'paired_at': pairedAt,
      if (relayBackfillComplete != null)
        'relay_backfill_complete': relayBackfillComplete,
      if (relayPruneBefore != null) 'relay_prune_before': relayPruneBefore,
      if (lastPushAt != null) 'last_push_at': lastPushAt,
      if (lastError != null) 'last_error': lastError,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PairedRelayEntriesCompanion copyWith({
    Value<String>? relayId,
    Value<String>? relayOnion,
    Value<int>? pairedAt,
    Value<int>? relayBackfillComplete,
    Value<int>? relayPruneBefore,
    Value<int>? lastPushAt,
    Value<String?>? lastError,
    Value<int>? rowid,
  }) {
    return PairedRelayEntriesCompanion(
      relayId: relayId ?? this.relayId,
      relayOnion: relayOnion ?? this.relayOnion,
      pairedAt: pairedAt ?? this.pairedAt,
      relayBackfillComplete:
          relayBackfillComplete ?? this.relayBackfillComplete,
      relayPruneBefore: relayPruneBefore ?? this.relayPruneBefore,
      lastPushAt: lastPushAt ?? this.lastPushAt,
      lastError: lastError ?? this.lastError,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (relayId.present) {
      map['relay_id'] = Variable<String>(relayId.value);
    }
    if (relayOnion.present) {
      map['relay_onion'] = Variable<String>(relayOnion.value);
    }
    if (pairedAt.present) {
      map['paired_at'] = Variable<int>(pairedAt.value);
    }
    if (relayBackfillComplete.present) {
      map['relay_backfill_complete'] = Variable<int>(
        relayBackfillComplete.value,
      );
    }
    if (relayPruneBefore.present) {
      map['relay_prune_before'] = Variable<int>(relayPruneBefore.value);
    }
    if (lastPushAt.present) {
      map['last_push_at'] = Variable<int>(lastPushAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PairedRelayEntriesCompanion(')
          ..write('relayId: $relayId, ')
          ..write('relayOnion: $relayOnion, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('relayBackfillComplete: $relayBackfillComplete, ')
          ..write('relayPruneBefore: $relayPruneBefore, ')
          ..write('lastPushAt: $lastPushAt, ')
          ..write('lastError: $lastError, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PendingCardDistributionEntriesTable
    extends PendingCardDistributionEntries
    with
        TableInfo<
          $PendingCardDistributionEntriesTable,
          PendingCardDistributionEntry
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingCardDistributionEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _targetPubkeyMeta = const VerificationMeta(
    'targetPubkey',
  );
  @override
  late final GeneratedColumn<String> targetPubkey = GeneratedColumn<String>(
    'target_pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _encryptedCardMeta = const VerificationMeta(
    'encryptedCard',
  );
  @override
  late final GeneratedColumn<Uint8List> encryptedCard =
      GeneratedColumn<Uint8List>(
        'encrypted_card',
        aliasedName,
        false,
        type: DriftSqlType.blob,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _nonceMeta = const VerificationMeta('nonce');
  @override
  late final GeneratedColumn<Uint8List> nonce = GeneratedColumn<Uint8List>(
    'nonce',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _distributedMeta = const VerificationMeta(
    'distributed',
  );
  @override
  late final GeneratedColumn<int> distributed = GeneratedColumn<int>(
    'distributed',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    targetPubkey,
    encryptedCard,
    nonce,
    createdAt,
    distributed,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_card_distribution_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<PendingCardDistributionEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('target_pubkey')) {
      context.handle(
        _targetPubkeyMeta,
        targetPubkey.isAcceptableOrUnknown(
          data['target_pubkey']!,
          _targetPubkeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_targetPubkeyMeta);
    }
    if (data.containsKey('encrypted_card')) {
      context.handle(
        _encryptedCardMeta,
        encryptedCard.isAcceptableOrUnknown(
          data['encrypted_card']!,
          _encryptedCardMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_encryptedCardMeta);
    }
    if (data.containsKey('nonce')) {
      context.handle(
        _nonceMeta,
        nonce.isAcceptableOrUnknown(data['nonce']!, _nonceMeta),
      );
    } else if (isInserting) {
      context.missing(_nonceMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('distributed')) {
      context.handle(
        _distributedMeta,
        distributed.isAcceptableOrUnknown(
          data['distributed']!,
          _distributedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {targetPubkey, createdAt};
  @override
  PendingCardDistributionEntry map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingCardDistributionEntry(
      targetPubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target_pubkey'],
      )!,
      encryptedCard: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}encrypted_card'],
      )!,
      nonce: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}nonce'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      distributed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}distributed'],
      )!,
    );
  }

  @override
  $PendingCardDistributionEntriesTable createAlias(String alias) {
    return $PendingCardDistributionEntriesTable(attachedDatabase, alias);
  }
}

class PendingCardDistributionEntry extends DataClass
    implements Insertable<PendingCardDistributionEntry> {
  final String targetPubkey;
  final Uint8List encryptedCard;
  final Uint8List nonce;
  final int createdAt;
  final int distributed;
  const PendingCardDistributionEntry({
    required this.targetPubkey,
    required this.encryptedCard,
    required this.nonce,
    required this.createdAt,
    required this.distributed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['target_pubkey'] = Variable<String>(targetPubkey);
    map['encrypted_card'] = Variable<Uint8List>(encryptedCard);
    map['nonce'] = Variable<Uint8List>(nonce);
    map['created_at'] = Variable<int>(createdAt);
    map['distributed'] = Variable<int>(distributed);
    return map;
  }

  PendingCardDistributionEntriesCompanion toCompanion(bool nullToAbsent) {
    return PendingCardDistributionEntriesCompanion(
      targetPubkey: Value(targetPubkey),
      encryptedCard: Value(encryptedCard),
      nonce: Value(nonce),
      createdAt: Value(createdAt),
      distributed: Value(distributed),
    );
  }

  factory PendingCardDistributionEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingCardDistributionEntry(
      targetPubkey: serializer.fromJson<String>(json['targetPubkey']),
      encryptedCard: serializer.fromJson<Uint8List>(json['encryptedCard']),
      nonce: serializer.fromJson<Uint8List>(json['nonce']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      distributed: serializer.fromJson<int>(json['distributed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'targetPubkey': serializer.toJson<String>(targetPubkey),
      'encryptedCard': serializer.toJson<Uint8List>(encryptedCard),
      'nonce': serializer.toJson<Uint8List>(nonce),
      'createdAt': serializer.toJson<int>(createdAt),
      'distributed': serializer.toJson<int>(distributed),
    };
  }

  PendingCardDistributionEntry copyWith({
    String? targetPubkey,
    Uint8List? encryptedCard,
    Uint8List? nonce,
    int? createdAt,
    int? distributed,
  }) => PendingCardDistributionEntry(
    targetPubkey: targetPubkey ?? this.targetPubkey,
    encryptedCard: encryptedCard ?? this.encryptedCard,
    nonce: nonce ?? this.nonce,
    createdAt: createdAt ?? this.createdAt,
    distributed: distributed ?? this.distributed,
  );
  PendingCardDistributionEntry copyWithCompanion(
    PendingCardDistributionEntriesCompanion data,
  ) {
    return PendingCardDistributionEntry(
      targetPubkey: data.targetPubkey.present
          ? data.targetPubkey.value
          : this.targetPubkey,
      encryptedCard: data.encryptedCard.present
          ? data.encryptedCard.value
          : this.encryptedCard,
      nonce: data.nonce.present ? data.nonce.value : this.nonce,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      distributed: data.distributed.present
          ? data.distributed.value
          : this.distributed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingCardDistributionEntry(')
          ..write('targetPubkey: $targetPubkey, ')
          ..write('encryptedCard: $encryptedCard, ')
          ..write('nonce: $nonce, ')
          ..write('createdAt: $createdAt, ')
          ..write('distributed: $distributed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    targetPubkey,
    $driftBlobEquality.hash(encryptedCard),
    $driftBlobEquality.hash(nonce),
    createdAt,
    distributed,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingCardDistributionEntry &&
          other.targetPubkey == this.targetPubkey &&
          $driftBlobEquality.equals(other.encryptedCard, this.encryptedCard) &&
          $driftBlobEquality.equals(other.nonce, this.nonce) &&
          other.createdAt == this.createdAt &&
          other.distributed == this.distributed);
}

class PendingCardDistributionEntriesCompanion
    extends UpdateCompanion<PendingCardDistributionEntry> {
  final Value<String> targetPubkey;
  final Value<Uint8List> encryptedCard;
  final Value<Uint8List> nonce;
  final Value<int> createdAt;
  final Value<int> distributed;
  final Value<int> rowid;
  const PendingCardDistributionEntriesCompanion({
    this.targetPubkey = const Value.absent(),
    this.encryptedCard = const Value.absent(),
    this.nonce = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.distributed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingCardDistributionEntriesCompanion.insert({
    required String targetPubkey,
    required Uint8List encryptedCard,
    required Uint8List nonce,
    required int createdAt,
    this.distributed = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : targetPubkey = Value(targetPubkey),
       encryptedCard = Value(encryptedCard),
       nonce = Value(nonce),
       createdAt = Value(createdAt);
  static Insertable<PendingCardDistributionEntry> custom({
    Expression<String>? targetPubkey,
    Expression<Uint8List>? encryptedCard,
    Expression<Uint8List>? nonce,
    Expression<int>? createdAt,
    Expression<int>? distributed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (targetPubkey != null) 'target_pubkey': targetPubkey,
      if (encryptedCard != null) 'encrypted_card': encryptedCard,
      if (nonce != null) 'nonce': nonce,
      if (createdAt != null) 'created_at': createdAt,
      if (distributed != null) 'distributed': distributed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingCardDistributionEntriesCompanion copyWith({
    Value<String>? targetPubkey,
    Value<Uint8List>? encryptedCard,
    Value<Uint8List>? nonce,
    Value<int>? createdAt,
    Value<int>? distributed,
    Value<int>? rowid,
  }) {
    return PendingCardDistributionEntriesCompanion(
      targetPubkey: targetPubkey ?? this.targetPubkey,
      encryptedCard: encryptedCard ?? this.encryptedCard,
      nonce: nonce ?? this.nonce,
      createdAt: createdAt ?? this.createdAt,
      distributed: distributed ?? this.distributed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (targetPubkey.present) {
      map['target_pubkey'] = Variable<String>(targetPubkey.value);
    }
    if (encryptedCard.present) {
      map['encrypted_card'] = Variable<Uint8List>(encryptedCard.value);
    }
    if (nonce.present) {
      map['nonce'] = Variable<Uint8List>(nonce.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (distributed.present) {
      map['distributed'] = Variable<int>(distributed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingCardDistributionEntriesCompanion(')
          ..write('targetPubkey: $targetPubkey, ')
          ..write('encryptedCard: $encryptedCard, ')
          ..write('nonce: $nonce, ')
          ..write('createdAt: $createdAt, ')
          ..write('distributed: $distributed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RelayFanoutStateEntriesTable extends RelayFanoutStateEntries
    with TableInfo<$RelayFanoutStateEntriesTable, RelayFanoutStateEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RelayFanoutStateEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _pendingCardFanoutMeta = const VerificationMeta(
    'pendingCardFanout',
  );
  @override
  late final GeneratedColumn<int> pendingCardFanout = GeneratedColumn<int>(
    'pending_card_fanout',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _pendingUnpairOnionMeta =
      const VerificationMeta('pendingUnpairOnion');
  @override
  late final GeneratedColumn<String> pendingUnpairOnion =
      GeneratedColumn<String>(
        'pending_unpair_onion',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _unpairNotifyAttemptsMeta =
      const VerificationMeta('unpairNotifyAttempts');
  @override
  late final GeneratedColumn<int> unpairNotifyAttempts = GeneratedColumn<int>(
    'unpair_notify_attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    pendingCardFanout,
    pendingUnpairOnion,
    unpairNotifyAttempts,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'relay_fanout_state_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<RelayFanoutStateEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('pending_card_fanout')) {
      context.handle(
        _pendingCardFanoutMeta,
        pendingCardFanout.isAcceptableOrUnknown(
          data['pending_card_fanout']!,
          _pendingCardFanoutMeta,
        ),
      );
    }
    if (data.containsKey('pending_unpair_onion')) {
      context.handle(
        _pendingUnpairOnionMeta,
        pendingUnpairOnion.isAcceptableOrUnknown(
          data['pending_unpair_onion']!,
          _pendingUnpairOnionMeta,
        ),
      );
    }
    if (data.containsKey('unpair_notify_attempts')) {
      context.handle(
        _unpairNotifyAttemptsMeta,
        unpairNotifyAttempts.isAcceptableOrUnknown(
          data['unpair_notify_attempts']!,
          _unpairNotifyAttemptsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RelayFanoutStateEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RelayFanoutStateEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      pendingCardFanout: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}pending_card_fanout'],
      )!,
      pendingUnpairOnion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pending_unpair_onion'],
      ),
      unpairNotifyAttempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unpair_notify_attempts'],
      )!,
    );
  }

  @override
  $RelayFanoutStateEntriesTable createAlias(String alias) {
    return $RelayFanoutStateEntriesTable(attachedDatabase, alias);
  }
}

class RelayFanoutStateEntry extends DataClass
    implements Insertable<RelayFanoutStateEntry> {
  /// Always 1 — a one-row table.
  final int id;
  final int pendingCardFanout;
  final String? pendingUnpairOnion;
  final int unpairNotifyAttempts;
  const RelayFanoutStateEntry({
    required this.id,
    required this.pendingCardFanout,
    this.pendingUnpairOnion,
    required this.unpairNotifyAttempts,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['pending_card_fanout'] = Variable<int>(pendingCardFanout);
    if (!nullToAbsent || pendingUnpairOnion != null) {
      map['pending_unpair_onion'] = Variable<String>(pendingUnpairOnion);
    }
    map['unpair_notify_attempts'] = Variable<int>(unpairNotifyAttempts);
    return map;
  }

  RelayFanoutStateEntriesCompanion toCompanion(bool nullToAbsent) {
    return RelayFanoutStateEntriesCompanion(
      id: Value(id),
      pendingCardFanout: Value(pendingCardFanout),
      pendingUnpairOnion: pendingUnpairOnion == null && nullToAbsent
          ? const Value.absent()
          : Value(pendingUnpairOnion),
      unpairNotifyAttempts: Value(unpairNotifyAttempts),
    );
  }

  factory RelayFanoutStateEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RelayFanoutStateEntry(
      id: serializer.fromJson<int>(json['id']),
      pendingCardFanout: serializer.fromJson<int>(json['pendingCardFanout']),
      pendingUnpairOnion: serializer.fromJson<String?>(
        json['pendingUnpairOnion'],
      ),
      unpairNotifyAttempts: serializer.fromJson<int>(
        json['unpairNotifyAttempts'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'pendingCardFanout': serializer.toJson<int>(pendingCardFanout),
      'pendingUnpairOnion': serializer.toJson<String?>(pendingUnpairOnion),
      'unpairNotifyAttempts': serializer.toJson<int>(unpairNotifyAttempts),
    };
  }

  RelayFanoutStateEntry copyWith({
    int? id,
    int? pendingCardFanout,
    Value<String?> pendingUnpairOnion = const Value.absent(),
    int? unpairNotifyAttempts,
  }) => RelayFanoutStateEntry(
    id: id ?? this.id,
    pendingCardFanout: pendingCardFanout ?? this.pendingCardFanout,
    pendingUnpairOnion: pendingUnpairOnion.present
        ? pendingUnpairOnion.value
        : this.pendingUnpairOnion,
    unpairNotifyAttempts: unpairNotifyAttempts ?? this.unpairNotifyAttempts,
  );
  RelayFanoutStateEntry copyWithCompanion(
    RelayFanoutStateEntriesCompanion data,
  ) {
    return RelayFanoutStateEntry(
      id: data.id.present ? data.id.value : this.id,
      pendingCardFanout: data.pendingCardFanout.present
          ? data.pendingCardFanout.value
          : this.pendingCardFanout,
      pendingUnpairOnion: data.pendingUnpairOnion.present
          ? data.pendingUnpairOnion.value
          : this.pendingUnpairOnion,
      unpairNotifyAttempts: data.unpairNotifyAttempts.present
          ? data.unpairNotifyAttempts.value
          : this.unpairNotifyAttempts,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RelayFanoutStateEntry(')
          ..write('id: $id, ')
          ..write('pendingCardFanout: $pendingCardFanout, ')
          ..write('pendingUnpairOnion: $pendingUnpairOnion, ')
          ..write('unpairNotifyAttempts: $unpairNotifyAttempts')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    pendingCardFanout,
    pendingUnpairOnion,
    unpairNotifyAttempts,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RelayFanoutStateEntry &&
          other.id == this.id &&
          other.pendingCardFanout == this.pendingCardFanout &&
          other.pendingUnpairOnion == this.pendingUnpairOnion &&
          other.unpairNotifyAttempts == this.unpairNotifyAttempts);
}

class RelayFanoutStateEntriesCompanion
    extends UpdateCompanion<RelayFanoutStateEntry> {
  final Value<int> id;
  final Value<int> pendingCardFanout;
  final Value<String?> pendingUnpairOnion;
  final Value<int> unpairNotifyAttempts;
  const RelayFanoutStateEntriesCompanion({
    this.id = const Value.absent(),
    this.pendingCardFanout = const Value.absent(),
    this.pendingUnpairOnion = const Value.absent(),
    this.unpairNotifyAttempts = const Value.absent(),
  });
  RelayFanoutStateEntriesCompanion.insert({
    this.id = const Value.absent(),
    this.pendingCardFanout = const Value.absent(),
    this.pendingUnpairOnion = const Value.absent(),
    this.unpairNotifyAttempts = const Value.absent(),
  });
  static Insertable<RelayFanoutStateEntry> custom({
    Expression<int>? id,
    Expression<int>? pendingCardFanout,
    Expression<String>? pendingUnpairOnion,
    Expression<int>? unpairNotifyAttempts,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (pendingCardFanout != null) 'pending_card_fanout': pendingCardFanout,
      if (pendingUnpairOnion != null)
        'pending_unpair_onion': pendingUnpairOnion,
      if (unpairNotifyAttempts != null)
        'unpair_notify_attempts': unpairNotifyAttempts,
    });
  }

  RelayFanoutStateEntriesCompanion copyWith({
    Value<int>? id,
    Value<int>? pendingCardFanout,
    Value<String?>? pendingUnpairOnion,
    Value<int>? unpairNotifyAttempts,
  }) {
    return RelayFanoutStateEntriesCompanion(
      id: id ?? this.id,
      pendingCardFanout: pendingCardFanout ?? this.pendingCardFanout,
      pendingUnpairOnion: pendingUnpairOnion ?? this.pendingUnpairOnion,
      unpairNotifyAttempts: unpairNotifyAttempts ?? this.unpairNotifyAttempts,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (pendingCardFanout.present) {
      map['pending_card_fanout'] = Variable<int>(pendingCardFanout.value);
    }
    if (pendingUnpairOnion.present) {
      map['pending_unpair_onion'] = Variable<String>(pendingUnpairOnion.value);
    }
    if (unpairNotifyAttempts.present) {
      map['unpair_notify_attempts'] = Variable<int>(unpairNotifyAttempts.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RelayFanoutStateEntriesCompanion(')
          ..write('id: $id, ')
          ..write('pendingCardFanout: $pendingCardFanout, ')
          ..write('pendingUnpairOnion: $pendingUnpairOnion, ')
          ..write('unpairNotifyAttempts: $unpairNotifyAttempts')
          ..write(')'))
        .toString();
  }
}

class $VoiceRoomEntriesTable extends VoiceRoomEntries
    with TableInfo<$VoiceRoomEntriesTable, VoiceRoomEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VoiceRoomEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _creatorPubkeyMeta = const VerificationMeta(
    'creatorPubkey',
  );
  @override
  late final GeneratedColumn<String> creatorPubkey = GeneratedColumn<String>(
    'creator_pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<int> endedAt = GeneratedColumn<int>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _participantCountMeta = const VerificationMeta(
    'participantCount',
  );
  @override
  late final GeneratedColumn<int> participantCount = GeneratedColumn<int>(
    'participant_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _missedMeta = const VerificationMeta('missed');
  @override
  late final GeneratedColumn<bool> missed = GeneratedColumn<bool>(
    'missed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("missed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    creatorPubkey,
    createdAt,
    endedAt,
    participantCount,
    missed,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'voice_room_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<VoiceRoomEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('creator_pubkey')) {
      context.handle(
        _creatorPubkeyMeta,
        creatorPubkey.isAcceptableOrUnknown(
          data['creator_pubkey']!,
          _creatorPubkeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_creatorPubkeyMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    if (data.containsKey('participant_count')) {
      context.handle(
        _participantCountMeta,
        participantCount.isAcceptableOrUnknown(
          data['participant_count']!,
          _participantCountMeta,
        ),
      );
    }
    if (data.containsKey('missed')) {
      context.handle(
        _missedMeta,
        missed.isAcceptableOrUnknown(data['missed']!, _missedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VoiceRoomEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VoiceRoomEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      creatorPubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}creator_pubkey'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ended_at'],
      ),
      participantCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}participant_count'],
      )!,
      missed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}missed'],
      )!,
    );
  }

  @override
  $VoiceRoomEntriesTable createAlias(String alias) {
    return $VoiceRoomEntriesTable(attachedDatabase, alias);
  }
}

class VoiceRoomEntry extends DataClass implements Insertable<VoiceRoomEntry> {
  final String id;
  final String name;
  final String creatorPubkey;
  final int createdAt;
  final int? endedAt;
  final int participantCount;

  /// Invitee-side: the call rang (or auto-declined busy) and was never
  /// answered — renders "Missed" in the recent list. Answering a later
  /// retry upserts the row back to false.
  final bool missed;
  const VoiceRoomEntry({
    required this.id,
    required this.name,
    required this.creatorPubkey,
    required this.createdAt,
    this.endedAt,
    required this.participantCount,
    required this.missed,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['creator_pubkey'] = Variable<String>(creatorPubkey);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<int>(endedAt);
    }
    map['participant_count'] = Variable<int>(participantCount);
    map['missed'] = Variable<bool>(missed);
    return map;
  }

  VoiceRoomEntriesCompanion toCompanion(bool nullToAbsent) {
    return VoiceRoomEntriesCompanion(
      id: Value(id),
      name: Value(name),
      creatorPubkey: Value(creatorPubkey),
      createdAt: Value(createdAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      participantCount: Value(participantCount),
      missed: Value(missed),
    );
  }

  factory VoiceRoomEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VoiceRoomEntry(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      creatorPubkey: serializer.fromJson<String>(json['creatorPubkey']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      endedAt: serializer.fromJson<int?>(json['endedAt']),
      participantCount: serializer.fromJson<int>(json['participantCount']),
      missed: serializer.fromJson<bool>(json['missed']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'creatorPubkey': serializer.toJson<String>(creatorPubkey),
      'createdAt': serializer.toJson<int>(createdAt),
      'endedAt': serializer.toJson<int?>(endedAt),
      'participantCount': serializer.toJson<int>(participantCount),
      'missed': serializer.toJson<bool>(missed),
    };
  }

  VoiceRoomEntry copyWith({
    String? id,
    String? name,
    String? creatorPubkey,
    int? createdAt,
    Value<int?> endedAt = const Value.absent(),
    int? participantCount,
    bool? missed,
  }) => VoiceRoomEntry(
    id: id ?? this.id,
    name: name ?? this.name,
    creatorPubkey: creatorPubkey ?? this.creatorPubkey,
    createdAt: createdAt ?? this.createdAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    participantCount: participantCount ?? this.participantCount,
    missed: missed ?? this.missed,
  );
  VoiceRoomEntry copyWithCompanion(VoiceRoomEntriesCompanion data) {
    return VoiceRoomEntry(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      creatorPubkey: data.creatorPubkey.present
          ? data.creatorPubkey.value
          : this.creatorPubkey,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      participantCount: data.participantCount.present
          ? data.participantCount.value
          : this.participantCount,
      missed: data.missed.present ? data.missed.value : this.missed,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VoiceRoomEntry(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('creatorPubkey: $creatorPubkey, ')
          ..write('createdAt: $createdAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('participantCount: $participantCount, ')
          ..write('missed: $missed')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    creatorPubkey,
    createdAt,
    endedAt,
    participantCount,
    missed,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VoiceRoomEntry &&
          other.id == this.id &&
          other.name == this.name &&
          other.creatorPubkey == this.creatorPubkey &&
          other.createdAt == this.createdAt &&
          other.endedAt == this.endedAt &&
          other.participantCount == this.participantCount &&
          other.missed == this.missed);
}

class VoiceRoomEntriesCompanion extends UpdateCompanion<VoiceRoomEntry> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> creatorPubkey;
  final Value<int> createdAt;
  final Value<int?> endedAt;
  final Value<int> participantCount;
  final Value<bool> missed;
  final Value<int> rowid;
  const VoiceRoomEntriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.creatorPubkey = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.participantCount = const Value.absent(),
    this.missed = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VoiceRoomEntriesCompanion.insert({
    required String id,
    required String name,
    required String creatorPubkey,
    required int createdAt,
    this.endedAt = const Value.absent(),
    this.participantCount = const Value.absent(),
    this.missed = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       creatorPubkey = Value(creatorPubkey),
       createdAt = Value(createdAt);
  static Insertable<VoiceRoomEntry> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? creatorPubkey,
    Expression<int>? createdAt,
    Expression<int>? endedAt,
    Expression<int>? participantCount,
    Expression<bool>? missed,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (creatorPubkey != null) 'creator_pubkey': creatorPubkey,
      if (createdAt != null) 'created_at': createdAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (participantCount != null) 'participant_count': participantCount,
      if (missed != null) 'missed': missed,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VoiceRoomEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? creatorPubkey,
    Value<int>? createdAt,
    Value<int?>? endedAt,
    Value<int>? participantCount,
    Value<bool>? missed,
    Value<int>? rowid,
  }) {
    return VoiceRoomEntriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      creatorPubkey: creatorPubkey ?? this.creatorPubkey,
      createdAt: createdAt ?? this.createdAt,
      endedAt: endedAt ?? this.endedAt,
      participantCount: participantCount ?? this.participantCount,
      missed: missed ?? this.missed,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (creatorPubkey.present) {
      map['creator_pubkey'] = Variable<String>(creatorPubkey.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<int>(endedAt.value);
    }
    if (participantCount.present) {
      map['participant_count'] = Variable<int>(participantCount.value);
    }
    if (missed.present) {
      map['missed'] = Variable<bool>(missed.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VoiceRoomEntriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('creatorPubkey: $creatorPubkey, ')
          ..write('createdAt: $createdAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('participantCount: $participantCount, ')
          ..write('missed: $missed, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VoiceRoomParticipantEntriesTable extends VoiceRoomParticipantEntries
    with
        TableInfo<
          $VoiceRoomParticipantEntriesTable,
          VoiceRoomParticipantEntry
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VoiceRoomParticipantEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _roomIdMeta = const VerificationMeta('roomId');
  @override
  late final GeneratedColumn<String> roomId = GeneratedColumn<String>(
    'room_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pubkeyMeta = const VerificationMeta('pubkey');
  @override
  late final GeneratedColumn<String> pubkey = GeneratedColumn<String>(
    'pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _joinedAtMeta = const VerificationMeta(
    'joinedAt',
  );
  @override
  late final GeneratedColumn<int> joinedAt = GeneratedColumn<int>(
    'joined_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _leftAtMeta = const VerificationMeta('leftAt');
  @override
  late final GeneratedColumn<int> leftAt = GeneratedColumn<int>(
    'left_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    roomId,
    pubkey,
    displayName,
    joinedAt,
    leftAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'voice_room_participant_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<VoiceRoomParticipantEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('room_id')) {
      context.handle(
        _roomIdMeta,
        roomId.isAcceptableOrUnknown(data['room_id']!, _roomIdMeta),
      );
    } else if (isInserting) {
      context.missing(_roomIdMeta);
    }
    if (data.containsKey('pubkey')) {
      context.handle(
        _pubkeyMeta,
        pubkey.isAcceptableOrUnknown(data['pubkey']!, _pubkeyMeta),
      );
    } else if (isInserting) {
      context.missing(_pubkeyMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('joined_at')) {
      context.handle(
        _joinedAtMeta,
        joinedAt.isAcceptableOrUnknown(data['joined_at']!, _joinedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_joinedAtMeta);
    }
    if (data.containsKey('left_at')) {
      context.handle(
        _leftAtMeta,
        leftAt.isAcceptableOrUnknown(data['left_at']!, _leftAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {roomId, pubkey};
  @override
  VoiceRoomParticipantEntry map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VoiceRoomParticipantEntry(
      roomId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room_id'],
      )!,
      pubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pubkey'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      ),
      joinedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}joined_at'],
      )!,
      leftAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}left_at'],
      ),
    );
  }

  @override
  $VoiceRoomParticipantEntriesTable createAlias(String alias) {
    return $VoiceRoomParticipantEntriesTable(attachedDatabase, alias);
  }
}

class VoiceRoomParticipantEntry extends DataClass
    implements Insertable<VoiceRoomParticipantEntry> {
  final String roomId;
  final String pubkey;
  final String? displayName;
  final int joinedAt;
  final int? leftAt;
  const VoiceRoomParticipantEntry({
    required this.roomId,
    required this.pubkey,
    this.displayName,
    required this.joinedAt,
    this.leftAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['room_id'] = Variable<String>(roomId);
    map['pubkey'] = Variable<String>(pubkey);
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    map['joined_at'] = Variable<int>(joinedAt);
    if (!nullToAbsent || leftAt != null) {
      map['left_at'] = Variable<int>(leftAt);
    }
    return map;
  }

  VoiceRoomParticipantEntriesCompanion toCompanion(bool nullToAbsent) {
    return VoiceRoomParticipantEntriesCompanion(
      roomId: Value(roomId),
      pubkey: Value(pubkey),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      joinedAt: Value(joinedAt),
      leftAt: leftAt == null && nullToAbsent
          ? const Value.absent()
          : Value(leftAt),
    );
  }

  factory VoiceRoomParticipantEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VoiceRoomParticipantEntry(
      roomId: serializer.fromJson<String>(json['roomId']),
      pubkey: serializer.fromJson<String>(json['pubkey']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      joinedAt: serializer.fromJson<int>(json['joinedAt']),
      leftAt: serializer.fromJson<int?>(json['leftAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'roomId': serializer.toJson<String>(roomId),
      'pubkey': serializer.toJson<String>(pubkey),
      'displayName': serializer.toJson<String?>(displayName),
      'joinedAt': serializer.toJson<int>(joinedAt),
      'leftAt': serializer.toJson<int?>(leftAt),
    };
  }

  VoiceRoomParticipantEntry copyWith({
    String? roomId,
    String? pubkey,
    Value<String?> displayName = const Value.absent(),
    int? joinedAt,
    Value<int?> leftAt = const Value.absent(),
  }) => VoiceRoomParticipantEntry(
    roomId: roomId ?? this.roomId,
    pubkey: pubkey ?? this.pubkey,
    displayName: displayName.present ? displayName.value : this.displayName,
    joinedAt: joinedAt ?? this.joinedAt,
    leftAt: leftAt.present ? leftAt.value : this.leftAt,
  );
  VoiceRoomParticipantEntry copyWithCompanion(
    VoiceRoomParticipantEntriesCompanion data,
  ) {
    return VoiceRoomParticipantEntry(
      roomId: data.roomId.present ? data.roomId.value : this.roomId,
      pubkey: data.pubkey.present ? data.pubkey.value : this.pubkey,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      joinedAt: data.joinedAt.present ? data.joinedAt.value : this.joinedAt,
      leftAt: data.leftAt.present ? data.leftAt.value : this.leftAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VoiceRoomParticipantEntry(')
          ..write('roomId: $roomId, ')
          ..write('pubkey: $pubkey, ')
          ..write('displayName: $displayName, ')
          ..write('joinedAt: $joinedAt, ')
          ..write('leftAt: $leftAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(roomId, pubkey, displayName, joinedAt, leftAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VoiceRoomParticipantEntry &&
          other.roomId == this.roomId &&
          other.pubkey == this.pubkey &&
          other.displayName == this.displayName &&
          other.joinedAt == this.joinedAt &&
          other.leftAt == this.leftAt);
}

class VoiceRoomParticipantEntriesCompanion
    extends UpdateCompanion<VoiceRoomParticipantEntry> {
  final Value<String> roomId;
  final Value<String> pubkey;
  final Value<String?> displayName;
  final Value<int> joinedAt;
  final Value<int?> leftAt;
  final Value<int> rowid;
  const VoiceRoomParticipantEntriesCompanion({
    this.roomId = const Value.absent(),
    this.pubkey = const Value.absent(),
    this.displayName = const Value.absent(),
    this.joinedAt = const Value.absent(),
    this.leftAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VoiceRoomParticipantEntriesCompanion.insert({
    required String roomId,
    required String pubkey,
    this.displayName = const Value.absent(),
    required int joinedAt,
    this.leftAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : roomId = Value(roomId),
       pubkey = Value(pubkey),
       joinedAt = Value(joinedAt);
  static Insertable<VoiceRoomParticipantEntry> custom({
    Expression<String>? roomId,
    Expression<String>? pubkey,
    Expression<String>? displayName,
    Expression<int>? joinedAt,
    Expression<int>? leftAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (roomId != null) 'room_id': roomId,
      if (pubkey != null) 'pubkey': pubkey,
      if (displayName != null) 'display_name': displayName,
      if (joinedAt != null) 'joined_at': joinedAt,
      if (leftAt != null) 'left_at': leftAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VoiceRoomParticipantEntriesCompanion copyWith({
    Value<String>? roomId,
    Value<String>? pubkey,
    Value<String?>? displayName,
    Value<int>? joinedAt,
    Value<int?>? leftAt,
    Value<int>? rowid,
  }) {
    return VoiceRoomParticipantEntriesCompanion(
      roomId: roomId ?? this.roomId,
      pubkey: pubkey ?? this.pubkey,
      displayName: displayName ?? this.displayName,
      joinedAt: joinedAt ?? this.joinedAt,
      leftAt: leftAt ?? this.leftAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (roomId.present) {
      map['room_id'] = Variable<String>(roomId.value);
    }
    if (pubkey.present) {
      map['pubkey'] = Variable<String>(pubkey.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (joinedAt.present) {
      map['joined_at'] = Variable<int>(joinedAt.value);
    }
    if (leftAt.present) {
      map['left_at'] = Variable<int>(leftAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VoiceRoomParticipantEntriesCompanion(')
          ..write('roomId: $roomId, ')
          ..write('pubkey: $pubkey, ')
          ..write('displayName: $displayName, ')
          ..write('joinedAt: $joinedAt, ')
          ..write('leftAt: $leftAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RoomEntriesTable extends RoomEntries
    with TableInfo<$RoomEntriesTable, RoomEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoomEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _creatorPubkeyMeta = const VerificationMeta(
    'creatorPubkey',
  );
  @override
  late final GeneratedColumn<String> creatorPubkey = GeneratedColumn<String>(
    'creator_pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastActivityAtMeta = const VerificationMeta(
    'lastActivityAt',
  );
  @override
  late final GeneratedColumn<int> lastActivityAt = GeneratedColumn<int>(
    'last_activity_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roomKeyMeta = const VerificationMeta(
    'roomKey',
  );
  @override
  late final GeneratedColumn<Uint8List> roomKey = GeneratedColumn<Uint8List>(
    'room_key',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roomKeyEpochMeta = const VerificationMeta(
    'roomKeyEpoch',
  );
  @override
  late final GeneratedColumn<int> roomKeyEpoch = GeneratedColumn<int>(
    'room_key_epoch',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _roomKeyValidFromMeta = const VerificationMeta(
    'roomKeyValidFrom',
  );
  @override
  late final GeneratedColumn<int> roomKeyValidFrom = GeneratedColumn<int>(
    'room_key_valid_from',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _roomMsgSeqCounterMeta = const VerificationMeta(
    'roomMsgSeqCounter',
  );
  @override
  late final GeneratedColumn<int> roomMsgSeqCounter = GeneratedColumn<int>(
    'room_msg_seq_counter',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _membershipEpochMeta = const VerificationMeta(
    'membershipEpoch',
  );
  @override
  late final GeneratedColumn<int> membershipEpoch = GeneratedColumn<int>(
    'membership_epoch',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _isMemberMeta = const VerificationMeta(
    'isMember',
  );
  @override
  late final GeneratedColumn<int> isMember = GeneratedColumn<int>(
    'is_member',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _lastReadAtMeta = const VerificationMeta(
    'lastReadAt',
  );
  @override
  late final GeneratedColumn<int> lastReadAt = GeneratedColumn<int>(
    'last_read_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    creatorPubkey,
    createdAt,
    lastActivityAt,
    roomKey,
    roomKeyEpoch,
    roomKeyValidFrom,
    roomMsgSeqCounter,
    membershipEpoch,
    isMember,
    lastReadAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'room_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<RoomEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('creator_pubkey')) {
      context.handle(
        _creatorPubkeyMeta,
        creatorPubkey.isAcceptableOrUnknown(
          data['creator_pubkey']!,
          _creatorPubkeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_creatorPubkeyMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('last_activity_at')) {
      context.handle(
        _lastActivityAtMeta,
        lastActivityAt.isAcceptableOrUnknown(
          data['last_activity_at']!,
          _lastActivityAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lastActivityAtMeta);
    }
    if (data.containsKey('room_key')) {
      context.handle(
        _roomKeyMeta,
        roomKey.isAcceptableOrUnknown(data['room_key']!, _roomKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_roomKeyMeta);
    }
    if (data.containsKey('room_key_epoch')) {
      context.handle(
        _roomKeyEpochMeta,
        roomKeyEpoch.isAcceptableOrUnknown(
          data['room_key_epoch']!,
          _roomKeyEpochMeta,
        ),
      );
    }
    if (data.containsKey('room_key_valid_from')) {
      context.handle(
        _roomKeyValidFromMeta,
        roomKeyValidFrom.isAcceptableOrUnknown(
          data['room_key_valid_from']!,
          _roomKeyValidFromMeta,
        ),
      );
    }
    if (data.containsKey('room_msg_seq_counter')) {
      context.handle(
        _roomMsgSeqCounterMeta,
        roomMsgSeqCounter.isAcceptableOrUnknown(
          data['room_msg_seq_counter']!,
          _roomMsgSeqCounterMeta,
        ),
      );
    }
    if (data.containsKey('membership_epoch')) {
      context.handle(
        _membershipEpochMeta,
        membershipEpoch.isAcceptableOrUnknown(
          data['membership_epoch']!,
          _membershipEpochMeta,
        ),
      );
    }
    if (data.containsKey('is_member')) {
      context.handle(
        _isMemberMeta,
        isMember.isAcceptableOrUnknown(data['is_member']!, _isMemberMeta),
      );
    }
    if (data.containsKey('last_read_at')) {
      context.handle(
        _lastReadAtMeta,
        lastReadAt.isAcceptableOrUnknown(
          data['last_read_at']!,
          _lastReadAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RoomEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoomEntry(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      creatorPubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}creator_pubkey'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      lastActivityAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_activity_at'],
      )!,
      roomKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}room_key'],
      )!,
      roomKeyEpoch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}room_key_epoch'],
      )!,
      roomKeyValidFrom: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}room_key_valid_from'],
      )!,
      roomMsgSeqCounter: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}room_msg_seq_counter'],
      )!,
      membershipEpoch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}membership_epoch'],
      )!,
      isMember: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}is_member'],
      )!,
      lastReadAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_read_at'],
      )!,
    );
  }

  @override
  $RoomEntriesTable createAlias(String alias) {
    return $RoomEntriesTable(attachedDatabase, alias);
  }
}

class RoomEntry extends DataClass implements Insertable<RoomEntry> {
  /// roomId = the id of the genesis `roomCreate` event.
  final String id;
  final String name;
  final String creatorPubkey;
  final int createdAt;

  /// Retention key: last time a message/membership/call event touched the
  /// room. NOT createdAt — a long-lived room stays alive on activity.
  final int lastActivityAt;

  /// Current room key (chain root), its epoch, and the time it took effect.
  final Uint8List roomKey;
  final int roomKeyEpoch;
  final int roomKeyValidFrom;

  /// Next msg_seq to allocate under the current room key.
  final int roomMsgSeqCounter;

  /// Monotonic membership version — a `roomMembership` is applied only if
  /// its epoch is newer than this.
  final int membershipEpoch;

  /// 1 while the local user is a member; 0 after leaving/removal. Drives
  /// retention (left rooms are evictable) and the room list.
  final int isMember;

  /// Local-only read cursor (unix seconds) for the unread badge.
  final int lastReadAt;
  const RoomEntry({
    required this.id,
    required this.name,
    required this.creatorPubkey,
    required this.createdAt,
    required this.lastActivityAt,
    required this.roomKey,
    required this.roomKeyEpoch,
    required this.roomKeyValidFrom,
    required this.roomMsgSeqCounter,
    required this.membershipEpoch,
    required this.isMember,
    required this.lastReadAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['creator_pubkey'] = Variable<String>(creatorPubkey);
    map['created_at'] = Variable<int>(createdAt);
    map['last_activity_at'] = Variable<int>(lastActivityAt);
    map['room_key'] = Variable<Uint8List>(roomKey);
    map['room_key_epoch'] = Variable<int>(roomKeyEpoch);
    map['room_key_valid_from'] = Variable<int>(roomKeyValidFrom);
    map['room_msg_seq_counter'] = Variable<int>(roomMsgSeqCounter);
    map['membership_epoch'] = Variable<int>(membershipEpoch);
    map['is_member'] = Variable<int>(isMember);
    map['last_read_at'] = Variable<int>(lastReadAt);
    return map;
  }

  RoomEntriesCompanion toCompanion(bool nullToAbsent) {
    return RoomEntriesCompanion(
      id: Value(id),
      name: Value(name),
      creatorPubkey: Value(creatorPubkey),
      createdAt: Value(createdAt),
      lastActivityAt: Value(lastActivityAt),
      roomKey: Value(roomKey),
      roomKeyEpoch: Value(roomKeyEpoch),
      roomKeyValidFrom: Value(roomKeyValidFrom),
      roomMsgSeqCounter: Value(roomMsgSeqCounter),
      membershipEpoch: Value(membershipEpoch),
      isMember: Value(isMember),
      lastReadAt: Value(lastReadAt),
    );
  }

  factory RoomEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoomEntry(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      creatorPubkey: serializer.fromJson<String>(json['creatorPubkey']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      lastActivityAt: serializer.fromJson<int>(json['lastActivityAt']),
      roomKey: serializer.fromJson<Uint8List>(json['roomKey']),
      roomKeyEpoch: serializer.fromJson<int>(json['roomKeyEpoch']),
      roomKeyValidFrom: serializer.fromJson<int>(json['roomKeyValidFrom']),
      roomMsgSeqCounter: serializer.fromJson<int>(json['roomMsgSeqCounter']),
      membershipEpoch: serializer.fromJson<int>(json['membershipEpoch']),
      isMember: serializer.fromJson<int>(json['isMember']),
      lastReadAt: serializer.fromJson<int>(json['lastReadAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'creatorPubkey': serializer.toJson<String>(creatorPubkey),
      'createdAt': serializer.toJson<int>(createdAt),
      'lastActivityAt': serializer.toJson<int>(lastActivityAt),
      'roomKey': serializer.toJson<Uint8List>(roomKey),
      'roomKeyEpoch': serializer.toJson<int>(roomKeyEpoch),
      'roomKeyValidFrom': serializer.toJson<int>(roomKeyValidFrom),
      'roomMsgSeqCounter': serializer.toJson<int>(roomMsgSeqCounter),
      'membershipEpoch': serializer.toJson<int>(membershipEpoch),
      'isMember': serializer.toJson<int>(isMember),
      'lastReadAt': serializer.toJson<int>(lastReadAt),
    };
  }

  RoomEntry copyWith({
    String? id,
    String? name,
    String? creatorPubkey,
    int? createdAt,
    int? lastActivityAt,
    Uint8List? roomKey,
    int? roomKeyEpoch,
    int? roomKeyValidFrom,
    int? roomMsgSeqCounter,
    int? membershipEpoch,
    int? isMember,
    int? lastReadAt,
  }) => RoomEntry(
    id: id ?? this.id,
    name: name ?? this.name,
    creatorPubkey: creatorPubkey ?? this.creatorPubkey,
    createdAt: createdAt ?? this.createdAt,
    lastActivityAt: lastActivityAt ?? this.lastActivityAt,
    roomKey: roomKey ?? this.roomKey,
    roomKeyEpoch: roomKeyEpoch ?? this.roomKeyEpoch,
    roomKeyValidFrom: roomKeyValidFrom ?? this.roomKeyValidFrom,
    roomMsgSeqCounter: roomMsgSeqCounter ?? this.roomMsgSeqCounter,
    membershipEpoch: membershipEpoch ?? this.membershipEpoch,
    isMember: isMember ?? this.isMember,
    lastReadAt: lastReadAt ?? this.lastReadAt,
  );
  RoomEntry copyWithCompanion(RoomEntriesCompanion data) {
    return RoomEntry(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      creatorPubkey: data.creatorPubkey.present
          ? data.creatorPubkey.value
          : this.creatorPubkey,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastActivityAt: data.lastActivityAt.present
          ? data.lastActivityAt.value
          : this.lastActivityAt,
      roomKey: data.roomKey.present ? data.roomKey.value : this.roomKey,
      roomKeyEpoch: data.roomKeyEpoch.present
          ? data.roomKeyEpoch.value
          : this.roomKeyEpoch,
      roomKeyValidFrom: data.roomKeyValidFrom.present
          ? data.roomKeyValidFrom.value
          : this.roomKeyValidFrom,
      roomMsgSeqCounter: data.roomMsgSeqCounter.present
          ? data.roomMsgSeqCounter.value
          : this.roomMsgSeqCounter,
      membershipEpoch: data.membershipEpoch.present
          ? data.membershipEpoch.value
          : this.membershipEpoch,
      isMember: data.isMember.present ? data.isMember.value : this.isMember,
      lastReadAt: data.lastReadAt.present
          ? data.lastReadAt.value
          : this.lastReadAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoomEntry(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('creatorPubkey: $creatorPubkey, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastActivityAt: $lastActivityAt, ')
          ..write('roomKey: $roomKey, ')
          ..write('roomKeyEpoch: $roomKeyEpoch, ')
          ..write('roomKeyValidFrom: $roomKeyValidFrom, ')
          ..write('roomMsgSeqCounter: $roomMsgSeqCounter, ')
          ..write('membershipEpoch: $membershipEpoch, ')
          ..write('isMember: $isMember, ')
          ..write('lastReadAt: $lastReadAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    creatorPubkey,
    createdAt,
    lastActivityAt,
    $driftBlobEquality.hash(roomKey),
    roomKeyEpoch,
    roomKeyValidFrom,
    roomMsgSeqCounter,
    membershipEpoch,
    isMember,
    lastReadAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoomEntry &&
          other.id == this.id &&
          other.name == this.name &&
          other.creatorPubkey == this.creatorPubkey &&
          other.createdAt == this.createdAt &&
          other.lastActivityAt == this.lastActivityAt &&
          $driftBlobEquality.equals(other.roomKey, this.roomKey) &&
          other.roomKeyEpoch == this.roomKeyEpoch &&
          other.roomKeyValidFrom == this.roomKeyValidFrom &&
          other.roomMsgSeqCounter == this.roomMsgSeqCounter &&
          other.membershipEpoch == this.membershipEpoch &&
          other.isMember == this.isMember &&
          other.lastReadAt == this.lastReadAt);
}

class RoomEntriesCompanion extends UpdateCompanion<RoomEntry> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> creatorPubkey;
  final Value<int> createdAt;
  final Value<int> lastActivityAt;
  final Value<Uint8List> roomKey;
  final Value<int> roomKeyEpoch;
  final Value<int> roomKeyValidFrom;
  final Value<int> roomMsgSeqCounter;
  final Value<int> membershipEpoch;
  final Value<int> isMember;
  final Value<int> lastReadAt;
  final Value<int> rowid;
  const RoomEntriesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.creatorPubkey = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastActivityAt = const Value.absent(),
    this.roomKey = const Value.absent(),
    this.roomKeyEpoch = const Value.absent(),
    this.roomKeyValidFrom = const Value.absent(),
    this.roomMsgSeqCounter = const Value.absent(),
    this.membershipEpoch = const Value.absent(),
    this.isMember = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RoomEntriesCompanion.insert({
    required String id,
    required String name,
    required String creatorPubkey,
    required int createdAt,
    required int lastActivityAt,
    required Uint8List roomKey,
    this.roomKeyEpoch = const Value.absent(),
    this.roomKeyValidFrom = const Value.absent(),
    this.roomMsgSeqCounter = const Value.absent(),
    this.membershipEpoch = const Value.absent(),
    this.isMember = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       creatorPubkey = Value(creatorPubkey),
       createdAt = Value(createdAt),
       lastActivityAt = Value(lastActivityAt),
       roomKey = Value(roomKey);
  static Insertable<RoomEntry> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? creatorPubkey,
    Expression<int>? createdAt,
    Expression<int>? lastActivityAt,
    Expression<Uint8List>? roomKey,
    Expression<int>? roomKeyEpoch,
    Expression<int>? roomKeyValidFrom,
    Expression<int>? roomMsgSeqCounter,
    Expression<int>? membershipEpoch,
    Expression<int>? isMember,
    Expression<int>? lastReadAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (creatorPubkey != null) 'creator_pubkey': creatorPubkey,
      if (createdAt != null) 'created_at': createdAt,
      if (lastActivityAt != null) 'last_activity_at': lastActivityAt,
      if (roomKey != null) 'room_key': roomKey,
      if (roomKeyEpoch != null) 'room_key_epoch': roomKeyEpoch,
      if (roomKeyValidFrom != null) 'room_key_valid_from': roomKeyValidFrom,
      if (roomMsgSeqCounter != null) 'room_msg_seq_counter': roomMsgSeqCounter,
      if (membershipEpoch != null) 'membership_epoch': membershipEpoch,
      if (isMember != null) 'is_member': isMember,
      if (lastReadAt != null) 'last_read_at': lastReadAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RoomEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? creatorPubkey,
    Value<int>? createdAt,
    Value<int>? lastActivityAt,
    Value<Uint8List>? roomKey,
    Value<int>? roomKeyEpoch,
    Value<int>? roomKeyValidFrom,
    Value<int>? roomMsgSeqCounter,
    Value<int>? membershipEpoch,
    Value<int>? isMember,
    Value<int>? lastReadAt,
    Value<int>? rowid,
  }) {
    return RoomEntriesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      creatorPubkey: creatorPubkey ?? this.creatorPubkey,
      createdAt: createdAt ?? this.createdAt,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      roomKey: roomKey ?? this.roomKey,
      roomKeyEpoch: roomKeyEpoch ?? this.roomKeyEpoch,
      roomKeyValidFrom: roomKeyValidFrom ?? this.roomKeyValidFrom,
      roomMsgSeqCounter: roomMsgSeqCounter ?? this.roomMsgSeqCounter,
      membershipEpoch: membershipEpoch ?? this.membershipEpoch,
      isMember: isMember ?? this.isMember,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (creatorPubkey.present) {
      map['creator_pubkey'] = Variable<String>(creatorPubkey.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (lastActivityAt.present) {
      map['last_activity_at'] = Variable<int>(lastActivityAt.value);
    }
    if (roomKey.present) {
      map['room_key'] = Variable<Uint8List>(roomKey.value);
    }
    if (roomKeyEpoch.present) {
      map['room_key_epoch'] = Variable<int>(roomKeyEpoch.value);
    }
    if (roomKeyValidFrom.present) {
      map['room_key_valid_from'] = Variable<int>(roomKeyValidFrom.value);
    }
    if (roomMsgSeqCounter.present) {
      map['room_msg_seq_counter'] = Variable<int>(roomMsgSeqCounter.value);
    }
    if (membershipEpoch.present) {
      map['membership_epoch'] = Variable<int>(membershipEpoch.value);
    }
    if (isMember.present) {
      map['is_member'] = Variable<int>(isMember.value);
    }
    if (lastReadAt.present) {
      map['last_read_at'] = Variable<int>(lastReadAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoomEntriesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('creatorPubkey: $creatorPubkey, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastActivityAt: $lastActivityAt, ')
          ..write('roomKey: $roomKey, ')
          ..write('roomKeyEpoch: $roomKeyEpoch, ')
          ..write('roomKeyValidFrom: $roomKeyValidFrom, ')
          ..write('roomMsgSeqCounter: $roomMsgSeqCounter, ')
          ..write('membershipEpoch: $membershipEpoch, ')
          ..write('isMember: $isMember, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RoomMemberEntriesTable extends RoomMemberEntries
    with TableInfo<$RoomMemberEntriesTable, RoomMemberEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoomMemberEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _roomIdMeta = const VerificationMeta('roomId');
  @override
  late final GeneratedColumn<String> roomId = GeneratedColumn<String>(
    'room_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pubkeyMeta = const VerificationMeta('pubkey');
  @override
  late final GeneratedColumn<String> pubkey = GeneratedColumn<String>(
    'pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<int> addedAt = GeneratedColumn<int>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _removedAtMeta = const VerificationMeta(
    'removedAt',
  );
  @override
  late final GeneratedColumn<int> removedAt = GeneratedColumn<int>(
    'removed_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _roleMeta = const VerificationMeta('role');
  @override
  late final GeneratedColumn<String> role = GeneratedColumn<String>(
    'role',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('member'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    roomId,
    pubkey,
    displayName,
    addedAt,
    removedAt,
    role,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'room_member_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<RoomMemberEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('room_id')) {
      context.handle(
        _roomIdMeta,
        roomId.isAcceptableOrUnknown(data['room_id']!, _roomIdMeta),
      );
    } else if (isInserting) {
      context.missing(_roomIdMeta);
    }
    if (data.containsKey('pubkey')) {
      context.handle(
        _pubkeyMeta,
        pubkey.isAcceptableOrUnknown(data['pubkey']!, _pubkeyMeta),
      );
    } else if (isInserting) {
      context.missing(_pubkeyMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    if (data.containsKey('removed_at')) {
      context.handle(
        _removedAtMeta,
        removedAt.isAcceptableOrUnknown(data['removed_at']!, _removedAtMeta),
      );
    }
    if (data.containsKey('role')) {
      context.handle(
        _roleMeta,
        role.isAcceptableOrUnknown(data['role']!, _roleMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {roomId, pubkey};
  @override
  RoomMemberEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoomMemberEntry(
      roomId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room_id'],
      )!,
      pubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pubkey'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}added_at'],
      )!,
      removedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}removed_at'],
      ),
      role: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}role'],
      )!,
    );
  }

  @override
  $RoomMemberEntriesTable createAlias(String alias) {
    return $RoomMemberEntriesTable(attachedDatabase, alias);
  }
}

class RoomMemberEntry extends DataClass implements Insertable<RoomMemberEntry> {
  final String roomId;
  final String pubkey;
  final String? displayName;
  final int addedAt;
  final int? removedAt;
  final String role;
  const RoomMemberEntry({
    required this.roomId,
    required this.pubkey,
    this.displayName,
    required this.addedAt,
    this.removedAt,
    required this.role,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['room_id'] = Variable<String>(roomId);
    map['pubkey'] = Variable<String>(pubkey);
    if (!nullToAbsent || displayName != null) {
      map['display_name'] = Variable<String>(displayName);
    }
    map['added_at'] = Variable<int>(addedAt);
    if (!nullToAbsent || removedAt != null) {
      map['removed_at'] = Variable<int>(removedAt);
    }
    map['role'] = Variable<String>(role);
    return map;
  }

  RoomMemberEntriesCompanion toCompanion(bool nullToAbsent) {
    return RoomMemberEntriesCompanion(
      roomId: Value(roomId),
      pubkey: Value(pubkey),
      displayName: displayName == null && nullToAbsent
          ? const Value.absent()
          : Value(displayName),
      addedAt: Value(addedAt),
      removedAt: removedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(removedAt),
      role: Value(role),
    );
  }

  factory RoomMemberEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoomMemberEntry(
      roomId: serializer.fromJson<String>(json['roomId']),
      pubkey: serializer.fromJson<String>(json['pubkey']),
      displayName: serializer.fromJson<String?>(json['displayName']),
      addedAt: serializer.fromJson<int>(json['addedAt']),
      removedAt: serializer.fromJson<int?>(json['removedAt']),
      role: serializer.fromJson<String>(json['role']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'roomId': serializer.toJson<String>(roomId),
      'pubkey': serializer.toJson<String>(pubkey),
      'displayName': serializer.toJson<String?>(displayName),
      'addedAt': serializer.toJson<int>(addedAt),
      'removedAt': serializer.toJson<int?>(removedAt),
      'role': serializer.toJson<String>(role),
    };
  }

  RoomMemberEntry copyWith({
    String? roomId,
    String? pubkey,
    Value<String?> displayName = const Value.absent(),
    int? addedAt,
    Value<int?> removedAt = const Value.absent(),
    String? role,
  }) => RoomMemberEntry(
    roomId: roomId ?? this.roomId,
    pubkey: pubkey ?? this.pubkey,
    displayName: displayName.present ? displayName.value : this.displayName,
    addedAt: addedAt ?? this.addedAt,
    removedAt: removedAt.present ? removedAt.value : this.removedAt,
    role: role ?? this.role,
  );
  RoomMemberEntry copyWithCompanion(RoomMemberEntriesCompanion data) {
    return RoomMemberEntry(
      roomId: data.roomId.present ? data.roomId.value : this.roomId,
      pubkey: data.pubkey.present ? data.pubkey.value : this.pubkey,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      removedAt: data.removedAt.present ? data.removedAt.value : this.removedAt,
      role: data.role.present ? data.role.value : this.role,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoomMemberEntry(')
          ..write('roomId: $roomId, ')
          ..write('pubkey: $pubkey, ')
          ..write('displayName: $displayName, ')
          ..write('addedAt: $addedAt, ')
          ..write('removedAt: $removedAt, ')
          ..write('role: $role')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(roomId, pubkey, displayName, addedAt, removedAt, role);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoomMemberEntry &&
          other.roomId == this.roomId &&
          other.pubkey == this.pubkey &&
          other.displayName == this.displayName &&
          other.addedAt == this.addedAt &&
          other.removedAt == this.removedAt &&
          other.role == this.role);
}

class RoomMemberEntriesCompanion extends UpdateCompanion<RoomMemberEntry> {
  final Value<String> roomId;
  final Value<String> pubkey;
  final Value<String?> displayName;
  final Value<int> addedAt;
  final Value<int?> removedAt;
  final Value<String> role;
  final Value<int> rowid;
  const RoomMemberEntriesCompanion({
    this.roomId = const Value.absent(),
    this.pubkey = const Value.absent(),
    this.displayName = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.removedAt = const Value.absent(),
    this.role = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RoomMemberEntriesCompanion.insert({
    required String roomId,
    required String pubkey,
    this.displayName = const Value.absent(),
    required int addedAt,
    this.removedAt = const Value.absent(),
    this.role = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : roomId = Value(roomId),
       pubkey = Value(pubkey),
       addedAt = Value(addedAt);
  static Insertable<RoomMemberEntry> custom({
    Expression<String>? roomId,
    Expression<String>? pubkey,
    Expression<String>? displayName,
    Expression<int>? addedAt,
    Expression<int>? removedAt,
    Expression<String>? role,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (roomId != null) 'room_id': roomId,
      if (pubkey != null) 'pubkey': pubkey,
      if (displayName != null) 'display_name': displayName,
      if (addedAt != null) 'added_at': addedAt,
      if (removedAt != null) 'removed_at': removedAt,
      if (role != null) 'role': role,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RoomMemberEntriesCompanion copyWith({
    Value<String>? roomId,
    Value<String>? pubkey,
    Value<String?>? displayName,
    Value<int>? addedAt,
    Value<int?>? removedAt,
    Value<String>? role,
    Value<int>? rowid,
  }) {
    return RoomMemberEntriesCompanion(
      roomId: roomId ?? this.roomId,
      pubkey: pubkey ?? this.pubkey,
      displayName: displayName ?? this.displayName,
      addedAt: addedAt ?? this.addedAt,
      removedAt: removedAt ?? this.removedAt,
      role: role ?? this.role,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (roomId.present) {
      map['room_id'] = Variable<String>(roomId.value);
    }
    if (pubkey.present) {
      map['pubkey'] = Variable<String>(pubkey.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<int>(addedAt.value);
    }
    if (removedAt.present) {
      map['removed_at'] = Variable<int>(removedAt.value);
    }
    if (role.present) {
      map['role'] = Variable<String>(role.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoomMemberEntriesCompanion(')
          ..write('roomId: $roomId, ')
          ..write('pubkey: $pubkey, ')
          ..write('displayName: $displayName, ')
          ..write('addedAt: $addedAt, ')
          ..write('removedAt: $removedAt, ')
          ..write('role: $role, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RoomKeyHistoryEntriesTable extends RoomKeyHistoryEntries
    with TableInfo<$RoomKeyHistoryEntriesTable, RoomKeyHistoryEntry> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoomKeyHistoryEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _roomIdMeta = const VerificationMeta('roomId');
  @override
  late final GeneratedColumn<String> roomId = GeneratedColumn<String>(
    'room_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _epochMeta = const VerificationMeta('epoch');
  @override
  late final GeneratedColumn<int> epoch = GeneratedColumn<int>(
    'epoch',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roomKeyMeta = const VerificationMeta(
    'roomKey',
  );
  @override
  late final GeneratedColumn<Uint8List> roomKey = GeneratedColumn<Uint8List>(
    'room_key',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _validFromMeta = const VerificationMeta(
    'validFrom',
  );
  @override
  late final GeneratedColumn<int> validFrom = GeneratedColumn<int>(
    'valid_from',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _validUntilMeta = const VerificationMeta(
    'validUntil',
  );
  @override
  late final GeneratedColumn<int> validUntil = GeneratedColumn<int>(
    'valid_until',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    roomId,
    epoch,
    roomKey,
    validFrom,
    validUntil,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'room_key_history_entries';
  @override
  VerificationContext validateIntegrity(
    Insertable<RoomKeyHistoryEntry> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('room_id')) {
      context.handle(
        _roomIdMeta,
        roomId.isAcceptableOrUnknown(data['room_id']!, _roomIdMeta),
      );
    } else if (isInserting) {
      context.missing(_roomIdMeta);
    }
    if (data.containsKey('epoch')) {
      context.handle(
        _epochMeta,
        epoch.isAcceptableOrUnknown(data['epoch']!, _epochMeta),
      );
    } else if (isInserting) {
      context.missing(_epochMeta);
    }
    if (data.containsKey('room_key')) {
      context.handle(
        _roomKeyMeta,
        roomKey.isAcceptableOrUnknown(data['room_key']!, _roomKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_roomKeyMeta);
    }
    if (data.containsKey('valid_from')) {
      context.handle(
        _validFromMeta,
        validFrom.isAcceptableOrUnknown(data['valid_from']!, _validFromMeta),
      );
    } else if (isInserting) {
      context.missing(_validFromMeta);
    }
    if (data.containsKey('valid_until')) {
      context.handle(
        _validUntilMeta,
        validUntil.isAcceptableOrUnknown(data['valid_until']!, _validUntilMeta),
      );
    } else if (isInserting) {
      context.missing(_validUntilMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {roomId, epoch};
  @override
  RoomKeyHistoryEntry map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoomKeyHistoryEntry(
      roomId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room_id'],
      )!,
      epoch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}epoch'],
      )!,
      roomKey: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}room_key'],
      )!,
      validFrom: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}valid_from'],
      )!,
      validUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}valid_until'],
      )!,
    );
  }

  @override
  $RoomKeyHistoryEntriesTable createAlias(String alias) {
    return $RoomKeyHistoryEntriesTable(attachedDatabase, alias);
  }
}

class RoomKeyHistoryEntry extends DataClass
    implements Insertable<RoomKeyHistoryEntry> {
  final String roomId;
  final int epoch;
  final Uint8List roomKey;
  final int validFrom;
  final int validUntil;
  const RoomKeyHistoryEntry({
    required this.roomId,
    required this.epoch,
    required this.roomKey,
    required this.validFrom,
    required this.validUntil,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['room_id'] = Variable<String>(roomId);
    map['epoch'] = Variable<int>(epoch);
    map['room_key'] = Variable<Uint8List>(roomKey);
    map['valid_from'] = Variable<int>(validFrom);
    map['valid_until'] = Variable<int>(validUntil);
    return map;
  }

  RoomKeyHistoryEntriesCompanion toCompanion(bool nullToAbsent) {
    return RoomKeyHistoryEntriesCompanion(
      roomId: Value(roomId),
      epoch: Value(epoch),
      roomKey: Value(roomKey),
      validFrom: Value(validFrom),
      validUntil: Value(validUntil),
    );
  }

  factory RoomKeyHistoryEntry.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoomKeyHistoryEntry(
      roomId: serializer.fromJson<String>(json['roomId']),
      epoch: serializer.fromJson<int>(json['epoch']),
      roomKey: serializer.fromJson<Uint8List>(json['roomKey']),
      validFrom: serializer.fromJson<int>(json['validFrom']),
      validUntil: serializer.fromJson<int>(json['validUntil']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'roomId': serializer.toJson<String>(roomId),
      'epoch': serializer.toJson<int>(epoch),
      'roomKey': serializer.toJson<Uint8List>(roomKey),
      'validFrom': serializer.toJson<int>(validFrom),
      'validUntil': serializer.toJson<int>(validUntil),
    };
  }

  RoomKeyHistoryEntry copyWith({
    String? roomId,
    int? epoch,
    Uint8List? roomKey,
    int? validFrom,
    int? validUntil,
  }) => RoomKeyHistoryEntry(
    roomId: roomId ?? this.roomId,
    epoch: epoch ?? this.epoch,
    roomKey: roomKey ?? this.roomKey,
    validFrom: validFrom ?? this.validFrom,
    validUntil: validUntil ?? this.validUntil,
  );
  RoomKeyHistoryEntry copyWithCompanion(RoomKeyHistoryEntriesCompanion data) {
    return RoomKeyHistoryEntry(
      roomId: data.roomId.present ? data.roomId.value : this.roomId,
      epoch: data.epoch.present ? data.epoch.value : this.epoch,
      roomKey: data.roomKey.present ? data.roomKey.value : this.roomKey,
      validFrom: data.validFrom.present ? data.validFrom.value : this.validFrom,
      validUntil: data.validUntil.present
          ? data.validUntil.value
          : this.validUntil,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoomKeyHistoryEntry(')
          ..write('roomId: $roomId, ')
          ..write('epoch: $epoch, ')
          ..write('roomKey: $roomKey, ')
          ..write('validFrom: $validFrom, ')
          ..write('validUntil: $validUntil')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    roomId,
    epoch,
    $driftBlobEquality.hash(roomKey),
    validFrom,
    validUntil,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoomKeyHistoryEntry &&
          other.roomId == this.roomId &&
          other.epoch == this.epoch &&
          $driftBlobEquality.equals(other.roomKey, this.roomKey) &&
          other.validFrom == this.validFrom &&
          other.validUntil == this.validUntil);
}

class RoomKeyHistoryEntriesCompanion
    extends UpdateCompanion<RoomKeyHistoryEntry> {
  final Value<String> roomId;
  final Value<int> epoch;
  final Value<Uint8List> roomKey;
  final Value<int> validFrom;
  final Value<int> validUntil;
  final Value<int> rowid;
  const RoomKeyHistoryEntriesCompanion({
    this.roomId = const Value.absent(),
    this.epoch = const Value.absent(),
    this.roomKey = const Value.absent(),
    this.validFrom = const Value.absent(),
    this.validUntil = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RoomKeyHistoryEntriesCompanion.insert({
    required String roomId,
    required int epoch,
    required Uint8List roomKey,
    required int validFrom,
    required int validUntil,
    this.rowid = const Value.absent(),
  }) : roomId = Value(roomId),
       epoch = Value(epoch),
       roomKey = Value(roomKey),
       validFrom = Value(validFrom),
       validUntil = Value(validUntil);
  static Insertable<RoomKeyHistoryEntry> custom({
    Expression<String>? roomId,
    Expression<int>? epoch,
    Expression<Uint8List>? roomKey,
    Expression<int>? validFrom,
    Expression<int>? validUntil,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (roomId != null) 'room_id': roomId,
      if (epoch != null) 'epoch': epoch,
      if (roomKey != null) 'room_key': roomKey,
      if (validFrom != null) 'valid_from': validFrom,
      if (validUntil != null) 'valid_until': validUntil,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RoomKeyHistoryEntriesCompanion copyWith({
    Value<String>? roomId,
    Value<int>? epoch,
    Value<Uint8List>? roomKey,
    Value<int>? validFrom,
    Value<int>? validUntil,
    Value<int>? rowid,
  }) {
    return RoomKeyHistoryEntriesCompanion(
      roomId: roomId ?? this.roomId,
      epoch: epoch ?? this.epoch,
      roomKey: roomKey ?? this.roomKey,
      validFrom: validFrom ?? this.validFrom,
      validUntil: validUntil ?? this.validUntil,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (roomId.present) {
      map['room_id'] = Variable<String>(roomId.value);
    }
    if (epoch.present) {
      map['epoch'] = Variable<int>(epoch.value);
    }
    if (roomKey.present) {
      map['room_key'] = Variable<Uint8List>(roomKey.value);
    }
    if (validFrom.present) {
      map['valid_from'] = Variable<int>(validFrom.value);
    }
    if (validUntil.present) {
      map['valid_until'] = Variable<int>(validUntil.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoomKeyHistoryEntriesCompanion(')
          ..write('roomId: $roomId, ')
          ..write('epoch: $epoch, ')
          ..write('roomKey: $roomKey, ')
          ..write('validFrom: $validFrom, ')
          ..write('validUntil: $validUntil, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $IdentityEntriesTable identityEntries = $IdentityEntriesTable(
    this,
  );
  late final $FollowEntriesTable followEntries = $FollowEntriesTable(this);
  late final $EventEntriesTable eventEntries = $EventEntriesTable(this);
  late final $MediaCacheEntriesTable mediaCacheEntries =
      $MediaCacheEntriesTable(this);
  late final $InboundFollowRequestEntriesTable inboundFollowRequestEntries =
      $InboundFollowRequestEntriesTable(this);
  late final $OutboundFollowRequestEntriesTable outboundFollowRequestEntries =
      $OutboundFollowRequestEntriesTable(this);
  late final $OutboundQueueEntriesTable outboundQueueEntries =
      $OutboundQueueEntriesTable(this);
  late final $UnknownEnvelopeItemEntriesTable unknownEnvelopeItemEntries =
      $UnknownEnvelopeItemEntriesTable(this);
  late final $FeedKeyHistoryEntriesTable feedKeyHistoryEntries =
      $FeedKeyHistoryEntriesTable(this);
  late final $FollowFeedKeyHistoryEntriesTable followFeedKeyHistoryEntries =
      $FollowFeedKeyHistoryEntriesTable(this);
  late final $PendingKeyDistributionEntriesTable pendingKeyDistributionEntries =
      $PendingKeyDistributionEntriesTable(this);
  late final $PairedRelayEntriesTable pairedRelayEntries =
      $PairedRelayEntriesTable(this);
  late final $PendingCardDistributionEntriesTable
  pendingCardDistributionEntries = $PendingCardDistributionEntriesTable(this);
  late final $RelayFanoutStateEntriesTable relayFanoutStateEntries =
      $RelayFanoutStateEntriesTable(this);
  late final $VoiceRoomEntriesTable voiceRoomEntries = $VoiceRoomEntriesTable(
    this,
  );
  late final $VoiceRoomParticipantEntriesTable voiceRoomParticipantEntries =
      $VoiceRoomParticipantEntriesTable(this);
  late final $RoomEntriesTable roomEntries = $RoomEntriesTable(this);
  late final $RoomMemberEntriesTable roomMemberEntries =
      $RoomMemberEntriesTable(this);
  late final $RoomKeyHistoryEntriesTable roomKeyHistoryEntries =
      $RoomKeyHistoryEntriesTable(this);
  late final IdentityDao identityDao = IdentityDao(this as AppDatabase);
  late final FollowsDao followsDao = FollowsDao(this as AppDatabase);
  late final EventsDao eventsDao = EventsDao(this as AppDatabase);
  late final MediaCacheDao mediaCacheDao = MediaCacheDao(this as AppDatabase);
  late final FollowRequestsDao followRequestsDao = FollowRequestsDao(
    this as AppDatabase,
  );
  late final OutboundQueueDao outboundQueueDao = OutboundQueueDao(
    this as AppDatabase,
  );
  late final UnknownItemsDao unknownItemsDao = UnknownItemsDao(
    this as AppDatabase,
  );
  late final KeyRotationDao keyRotationDao = KeyRotationDao(
    this as AppDatabase,
  );
  late final PairedRelayDao pairedRelayDao = PairedRelayDao(
    this as AppDatabase,
  );
  late final VoiceRoomsDao voiceRoomsDao = VoiceRoomsDao(this as AppDatabase);
  late final RoomsDao roomsDao = RoomsDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    identityEntries,
    followEntries,
    eventEntries,
    mediaCacheEntries,
    inboundFollowRequestEntries,
    outboundFollowRequestEntries,
    outboundQueueEntries,
    unknownEnvelopeItemEntries,
    feedKeyHistoryEntries,
    followFeedKeyHistoryEntries,
    pendingKeyDistributionEntries,
    pairedRelayEntries,
    pendingCardDistributionEntries,
    relayFanoutStateEntries,
    voiceRoomEntries,
    voiceRoomParticipantEntries,
    roomEntries,
    roomMemberEntries,
    roomKeyHistoryEntries,
  ];
}

typedef $$IdentityEntriesTableCreateCompanionBuilder =
    IdentityEntriesCompanion Function({
      required String pubkey,
      required Uint8List feedKey,
      Value<int> feedKeyEpoch,
      Value<int> feedKeyValidFrom,
      Value<int> msgSeqCounter,
      Value<String?> recoveryPhrase,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$IdentityEntriesTableUpdateCompanionBuilder =
    IdentityEntriesCompanion Function({
      Value<String> pubkey,
      Value<Uint8List> feedKey,
      Value<int> feedKeyEpoch,
      Value<int> feedKeyValidFrom,
      Value<int> msgSeqCounter,
      Value<String?> recoveryPhrase,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$IdentityEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $IdentityEntriesTable> {
  $$IdentityEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get feedKey => $composableBuilder(
    column: $table.feedKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get feedKeyEpoch => $composableBuilder(
    column: $table.feedKeyEpoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get feedKeyValidFrom => $composableBuilder(
    column: $table.feedKeyValidFrom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get msgSeqCounter => $composableBuilder(
    column: $table.msgSeqCounter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recoveryPhrase => $composableBuilder(
    column: $table.recoveryPhrase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$IdentityEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $IdentityEntriesTable> {
  $$IdentityEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get feedKey => $composableBuilder(
    column: $table.feedKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get feedKeyEpoch => $composableBuilder(
    column: $table.feedKeyEpoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get feedKeyValidFrom => $composableBuilder(
    column: $table.feedKeyValidFrom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get msgSeqCounter => $composableBuilder(
    column: $table.msgSeqCounter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recoveryPhrase => $composableBuilder(
    column: $table.recoveryPhrase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$IdentityEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $IdentityEntriesTable> {
  $$IdentityEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pubkey =>
      $composableBuilder(column: $table.pubkey, builder: (column) => column);

  GeneratedColumn<Uint8List> get feedKey =>
      $composableBuilder(column: $table.feedKey, builder: (column) => column);

  GeneratedColumn<int> get feedKeyEpoch => $composableBuilder(
    column: $table.feedKeyEpoch,
    builder: (column) => column,
  );

  GeneratedColumn<int> get feedKeyValidFrom => $composableBuilder(
    column: $table.feedKeyValidFrom,
    builder: (column) => column,
  );

  GeneratedColumn<int> get msgSeqCounter => $composableBuilder(
    column: $table.msgSeqCounter,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recoveryPhrase => $composableBuilder(
    column: $table.recoveryPhrase,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$IdentityEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $IdentityEntriesTable,
          IdentityEntry,
          $$IdentityEntriesTableFilterComposer,
          $$IdentityEntriesTableOrderingComposer,
          $$IdentityEntriesTableAnnotationComposer,
          $$IdentityEntriesTableCreateCompanionBuilder,
          $$IdentityEntriesTableUpdateCompanionBuilder,
          (
            IdentityEntry,
            BaseReferences<_$AppDatabase, $IdentityEntriesTable, IdentityEntry>,
          ),
          IdentityEntry,
          PrefetchHooks Function()
        > {
  $$IdentityEntriesTableTableManager(
    _$AppDatabase db,
    $IdentityEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$IdentityEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$IdentityEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$IdentityEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> pubkey = const Value.absent(),
                Value<Uint8List> feedKey = const Value.absent(),
                Value<int> feedKeyEpoch = const Value.absent(),
                Value<int> feedKeyValidFrom = const Value.absent(),
                Value<int> msgSeqCounter = const Value.absent(),
                Value<String?> recoveryPhrase = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => IdentityEntriesCompanion(
                pubkey: pubkey,
                feedKey: feedKey,
                feedKeyEpoch: feedKeyEpoch,
                feedKeyValidFrom: feedKeyValidFrom,
                msgSeqCounter: msgSeqCounter,
                recoveryPhrase: recoveryPhrase,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String pubkey,
                required Uint8List feedKey,
                Value<int> feedKeyEpoch = const Value.absent(),
                Value<int> feedKeyValidFrom = const Value.absent(),
                Value<int> msgSeqCounter = const Value.absent(),
                Value<String?> recoveryPhrase = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => IdentityEntriesCompanion.insert(
                pubkey: pubkey,
                feedKey: feedKey,
                feedKeyEpoch: feedKeyEpoch,
                feedKeyValidFrom: feedKeyValidFrom,
                msgSeqCounter: msgSeqCounter,
                recoveryPhrase: recoveryPhrase,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$IdentityEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $IdentityEntriesTable,
      IdentityEntry,
      $$IdentityEntriesTableFilterComposer,
      $$IdentityEntriesTableOrderingComposer,
      $$IdentityEntriesTableAnnotationComposer,
      $$IdentityEntriesTableCreateCompanionBuilder,
      $$IdentityEntriesTableUpdateCompanionBuilder,
      (
        IdentityEntry,
        BaseReferences<_$AppDatabase, $IdentityEntriesTable, IdentityEntry>,
      ),
      IdentityEntry,
      PrefetchHooks Function()
    >;
typedef $$FollowEntriesTableCreateCompanionBuilder =
    FollowEntriesCompanion Function({
      required String pubkey,
      required String connectionCard,
      required Uint8List feedKey,
      Value<int> feedKeyEpoch,
      Value<int> lastSyncedAt,
      Value<String> status,
      Value<int> lastReceivedRotationAt,
      Value<int> lastReceivedCardAt,
      Value<int?> lastDecryptFailureAt,
      Value<int> lastFullSyncAt,
      Value<int> rowid,
    });
typedef $$FollowEntriesTableUpdateCompanionBuilder =
    FollowEntriesCompanion Function({
      Value<String> pubkey,
      Value<String> connectionCard,
      Value<Uint8List> feedKey,
      Value<int> feedKeyEpoch,
      Value<int> lastSyncedAt,
      Value<String> status,
      Value<int> lastReceivedRotationAt,
      Value<int> lastReceivedCardAt,
      Value<int?> lastDecryptFailureAt,
      Value<int> lastFullSyncAt,
      Value<int> rowid,
    });

class $$FollowEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $FollowEntriesTable> {
  $$FollowEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get connectionCard => $composableBuilder(
    column: $table.connectionCard,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get feedKey => $composableBuilder(
    column: $table.feedKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get feedKeyEpoch => $composableBuilder(
    column: $table.feedKeyEpoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReceivedRotationAt => $composableBuilder(
    column: $table.lastReceivedRotationAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReceivedCardAt => $composableBuilder(
    column: $table.lastReceivedCardAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastDecryptFailureAt => $composableBuilder(
    column: $table.lastDecryptFailureAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastFullSyncAt => $composableBuilder(
    column: $table.lastFullSyncAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FollowEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $FollowEntriesTable> {
  $$FollowEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get connectionCard => $composableBuilder(
    column: $table.connectionCard,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get feedKey => $composableBuilder(
    column: $table.feedKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get feedKeyEpoch => $composableBuilder(
    column: $table.feedKeyEpoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReceivedRotationAt => $composableBuilder(
    column: $table.lastReceivedRotationAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReceivedCardAt => $composableBuilder(
    column: $table.lastReceivedCardAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastDecryptFailureAt => $composableBuilder(
    column: $table.lastDecryptFailureAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastFullSyncAt => $composableBuilder(
    column: $table.lastFullSyncAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FollowEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FollowEntriesTable> {
  $$FollowEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pubkey =>
      $composableBuilder(column: $table.pubkey, builder: (column) => column);

  GeneratedColumn<String> get connectionCard => $composableBuilder(
    column: $table.connectionCard,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get feedKey =>
      $composableBuilder(column: $table.feedKey, builder: (column) => column);

  GeneratedColumn<int> get feedKeyEpoch => $composableBuilder(
    column: $table.feedKeyEpoch,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastSyncedAt => $composableBuilder(
    column: $table.lastSyncedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get lastReceivedRotationAt => $composableBuilder(
    column: $table.lastReceivedRotationAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastReceivedCardAt => $composableBuilder(
    column: $table.lastReceivedCardAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastDecryptFailureAt => $composableBuilder(
    column: $table.lastDecryptFailureAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastFullSyncAt => $composableBuilder(
    column: $table.lastFullSyncAt,
    builder: (column) => column,
  );
}

class $$FollowEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FollowEntriesTable,
          FollowEntry,
          $$FollowEntriesTableFilterComposer,
          $$FollowEntriesTableOrderingComposer,
          $$FollowEntriesTableAnnotationComposer,
          $$FollowEntriesTableCreateCompanionBuilder,
          $$FollowEntriesTableUpdateCompanionBuilder,
          (
            FollowEntry,
            BaseReferences<_$AppDatabase, $FollowEntriesTable, FollowEntry>,
          ),
          FollowEntry,
          PrefetchHooks Function()
        > {
  $$FollowEntriesTableTableManager(_$AppDatabase db, $FollowEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FollowEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FollowEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FollowEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> pubkey = const Value.absent(),
                Value<String> connectionCard = const Value.absent(),
                Value<Uint8List> feedKey = const Value.absent(),
                Value<int> feedKeyEpoch = const Value.absent(),
                Value<int> lastSyncedAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> lastReceivedRotationAt = const Value.absent(),
                Value<int> lastReceivedCardAt = const Value.absent(),
                Value<int?> lastDecryptFailureAt = const Value.absent(),
                Value<int> lastFullSyncAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FollowEntriesCompanion(
                pubkey: pubkey,
                connectionCard: connectionCard,
                feedKey: feedKey,
                feedKeyEpoch: feedKeyEpoch,
                lastSyncedAt: lastSyncedAt,
                status: status,
                lastReceivedRotationAt: lastReceivedRotationAt,
                lastReceivedCardAt: lastReceivedCardAt,
                lastDecryptFailureAt: lastDecryptFailureAt,
                lastFullSyncAt: lastFullSyncAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String pubkey,
                required String connectionCard,
                required Uint8List feedKey,
                Value<int> feedKeyEpoch = const Value.absent(),
                Value<int> lastSyncedAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> lastReceivedRotationAt = const Value.absent(),
                Value<int> lastReceivedCardAt = const Value.absent(),
                Value<int?> lastDecryptFailureAt = const Value.absent(),
                Value<int> lastFullSyncAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FollowEntriesCompanion.insert(
                pubkey: pubkey,
                connectionCard: connectionCard,
                feedKey: feedKey,
                feedKeyEpoch: feedKeyEpoch,
                lastSyncedAt: lastSyncedAt,
                status: status,
                lastReceivedRotationAt: lastReceivedRotationAt,
                lastReceivedCardAt: lastReceivedCardAt,
                lastDecryptFailureAt: lastDecryptFailureAt,
                lastFullSyncAt: lastFullSyncAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FollowEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FollowEntriesTable,
      FollowEntry,
      $$FollowEntriesTableFilterComposer,
      $$FollowEntriesTableOrderingComposer,
      $$FollowEntriesTableAnnotationComposer,
      $$FollowEntriesTableCreateCompanionBuilder,
      $$FollowEntriesTableUpdateCompanionBuilder,
      (
        FollowEntry,
        BaseReferences<_$AppDatabase, $FollowEntriesTable, FollowEntry>,
      ),
      FollowEntry,
      PrefetchHooks Function()
    >;
typedef $$EventEntriesTableCreateCompanionBuilder =
    EventEntriesCompanion Function({
      required String id,
      required String pubkey,
      required int createdAt,
      required int kind,
      Value<String?> refId,
      required Uint8List content,
      Value<String?> mediaRefs,
      required Uint8List sig,
      Value<int> isOwn,
      Value<int> isSaved,
      required int fetchedAt,
      Value<int?> lastViewed,
      Value<String> version,
      Value<Uint8List?> extensions,
      Value<int?> msgSeq,
      Value<Uint8List?> encryptedPayload,
      Value<int> rowid,
    });
typedef $$EventEntriesTableUpdateCompanionBuilder =
    EventEntriesCompanion Function({
      Value<String> id,
      Value<String> pubkey,
      Value<int> createdAt,
      Value<int> kind,
      Value<String?> refId,
      Value<Uint8List> content,
      Value<String?> mediaRefs,
      Value<Uint8List> sig,
      Value<int> isOwn,
      Value<int> isSaved,
      Value<int> fetchedAt,
      Value<int?> lastViewed,
      Value<String> version,
      Value<Uint8List?> extensions,
      Value<int?> msgSeq,
      Value<Uint8List?> encryptedPayload,
      Value<int> rowid,
    });

class $$EventEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $EventEntriesTable> {
  $$EventEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaRefs => $composableBuilder(
    column: $table.mediaRefs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get sig => $composableBuilder(
    column: $table.sig,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get isOwn => $composableBuilder(
    column: $table.isOwn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get isSaved => $composableBuilder(
    column: $table.isSaved,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastViewed => $composableBuilder(
    column: $table.lastViewed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get extensions => $composableBuilder(
    column: $table.extensions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get msgSeq => $composableBuilder(
    column: $table.msgSeq,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get encryptedPayload => $composableBuilder(
    column: $table.encryptedPayload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EventEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $EventEntriesTable> {
  $$EventEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaRefs => $composableBuilder(
    column: $table.mediaRefs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get sig => $composableBuilder(
    column: $table.sig,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get isOwn => $composableBuilder(
    column: $table.isOwn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get isSaved => $composableBuilder(
    column: $table.isSaved,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastViewed => $composableBuilder(
    column: $table.lastViewed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get extensions => $composableBuilder(
    column: $table.extensions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get msgSeq => $composableBuilder(
    column: $table.msgSeq,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get encryptedPayload => $composableBuilder(
    column: $table.encryptedPayload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EventEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $EventEntriesTable> {
  $$EventEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get pubkey =>
      $composableBuilder(column: $table.pubkey, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get refId =>
      $composableBuilder(column: $table.refId, builder: (column) => column);

  GeneratedColumn<Uint8List> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get mediaRefs =>
      $composableBuilder(column: $table.mediaRefs, builder: (column) => column);

  GeneratedColumn<Uint8List> get sig =>
      $composableBuilder(column: $table.sig, builder: (column) => column);

  GeneratedColumn<int> get isOwn =>
      $composableBuilder(column: $table.isOwn, builder: (column) => column);

  GeneratedColumn<int> get isSaved =>
      $composableBuilder(column: $table.isSaved, builder: (column) => column);

  GeneratedColumn<int> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);

  GeneratedColumn<int> get lastViewed => $composableBuilder(
    column: $table.lastViewed,
    builder: (column) => column,
  );

  GeneratedColumn<String> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<Uint8List> get extensions => $composableBuilder(
    column: $table.extensions,
    builder: (column) => column,
  );

  GeneratedColumn<int> get msgSeq =>
      $composableBuilder(column: $table.msgSeq, builder: (column) => column);

  GeneratedColumn<Uint8List> get encryptedPayload => $composableBuilder(
    column: $table.encryptedPayload,
    builder: (column) => column,
  );
}

class $$EventEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EventEntriesTable,
          EventEntry,
          $$EventEntriesTableFilterComposer,
          $$EventEntriesTableOrderingComposer,
          $$EventEntriesTableAnnotationComposer,
          $$EventEntriesTableCreateCompanionBuilder,
          $$EventEntriesTableUpdateCompanionBuilder,
          (
            EventEntry,
            BaseReferences<_$AppDatabase, $EventEntriesTable, EventEntry>,
          ),
          EventEntry,
          PrefetchHooks Function()
        > {
  $$EventEntriesTableTableManager(_$AppDatabase db, $EventEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> pubkey = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> kind = const Value.absent(),
                Value<String?> refId = const Value.absent(),
                Value<Uint8List> content = const Value.absent(),
                Value<String?> mediaRefs = const Value.absent(),
                Value<Uint8List> sig = const Value.absent(),
                Value<int> isOwn = const Value.absent(),
                Value<int> isSaved = const Value.absent(),
                Value<int> fetchedAt = const Value.absent(),
                Value<int?> lastViewed = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<Uint8List?> extensions = const Value.absent(),
                Value<int?> msgSeq = const Value.absent(),
                Value<Uint8List?> encryptedPayload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventEntriesCompanion(
                id: id,
                pubkey: pubkey,
                createdAt: createdAt,
                kind: kind,
                refId: refId,
                content: content,
                mediaRefs: mediaRefs,
                sig: sig,
                isOwn: isOwn,
                isSaved: isSaved,
                fetchedAt: fetchedAt,
                lastViewed: lastViewed,
                version: version,
                extensions: extensions,
                msgSeq: msgSeq,
                encryptedPayload: encryptedPayload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String pubkey,
                required int createdAt,
                required int kind,
                Value<String?> refId = const Value.absent(),
                required Uint8List content,
                Value<String?> mediaRefs = const Value.absent(),
                required Uint8List sig,
                Value<int> isOwn = const Value.absent(),
                Value<int> isSaved = const Value.absent(),
                required int fetchedAt,
                Value<int?> lastViewed = const Value.absent(),
                Value<String> version = const Value.absent(),
                Value<Uint8List?> extensions = const Value.absent(),
                Value<int?> msgSeq = const Value.absent(),
                Value<Uint8List?> encryptedPayload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventEntriesCompanion.insert(
                id: id,
                pubkey: pubkey,
                createdAt: createdAt,
                kind: kind,
                refId: refId,
                content: content,
                mediaRefs: mediaRefs,
                sig: sig,
                isOwn: isOwn,
                isSaved: isSaved,
                fetchedAt: fetchedAt,
                lastViewed: lastViewed,
                version: version,
                extensions: extensions,
                msgSeq: msgSeq,
                encryptedPayload: encryptedPayload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EventEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EventEntriesTable,
      EventEntry,
      $$EventEntriesTableFilterComposer,
      $$EventEntriesTableOrderingComposer,
      $$EventEntriesTableAnnotationComposer,
      $$EventEntriesTableCreateCompanionBuilder,
      $$EventEntriesTableUpdateCompanionBuilder,
      (
        EventEntry,
        BaseReferences<_$AppDatabase, $EventEntriesTable, EventEntry>,
      ),
      EventEntry,
      PrefetchHooks Function()
    >;
typedef $$MediaCacheEntriesTableCreateCompanionBuilder =
    MediaCacheEntriesCompanion Function({
      required String hash,
      required String path,
      required int size,
      required int lastAccessed,
      Value<int> rowid,
    });
typedef $$MediaCacheEntriesTableUpdateCompanionBuilder =
    MediaCacheEntriesCompanion Function({
      Value<String> hash,
      Value<String> path,
      Value<int> size,
      Value<int> lastAccessed,
      Value<int> rowid,
    });

class $$MediaCacheEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $MediaCacheEntriesTable> {
  $$MediaCacheEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get hash => $composableBuilder(
    column: $table.hash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastAccessed => $composableBuilder(
    column: $table.lastAccessed,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MediaCacheEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaCacheEntriesTable> {
  $$MediaCacheEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get hash => $composableBuilder(
    column: $table.hash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastAccessed => $composableBuilder(
    column: $table.lastAccessed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MediaCacheEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaCacheEntriesTable> {
  $$MediaCacheEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get hash =>
      $composableBuilder(column: $table.hash, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);

  GeneratedColumn<int> get lastAccessed => $composableBuilder(
    column: $table.lastAccessed,
    builder: (column) => column,
  );
}

class $$MediaCacheEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MediaCacheEntriesTable,
          MediaCacheEntry,
          $$MediaCacheEntriesTableFilterComposer,
          $$MediaCacheEntriesTableOrderingComposer,
          $$MediaCacheEntriesTableAnnotationComposer,
          $$MediaCacheEntriesTableCreateCompanionBuilder,
          $$MediaCacheEntriesTableUpdateCompanionBuilder,
          (
            MediaCacheEntry,
            BaseReferences<
              _$AppDatabase,
              $MediaCacheEntriesTable,
              MediaCacheEntry
            >,
          ),
          MediaCacheEntry,
          PrefetchHooks Function()
        > {
  $$MediaCacheEntriesTableTableManager(
    _$AppDatabase db,
    $MediaCacheEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaCacheEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaCacheEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaCacheEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> hash = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<int> lastAccessed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaCacheEntriesCompanion(
                hash: hash,
                path: path,
                size: size,
                lastAccessed: lastAccessed,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String hash,
                required String path,
                required int size,
                required int lastAccessed,
                Value<int> rowid = const Value.absent(),
              }) => MediaCacheEntriesCompanion.insert(
                hash: hash,
                path: path,
                size: size,
                lastAccessed: lastAccessed,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MediaCacheEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MediaCacheEntriesTable,
      MediaCacheEntry,
      $$MediaCacheEntriesTableFilterComposer,
      $$MediaCacheEntriesTableOrderingComposer,
      $$MediaCacheEntriesTableAnnotationComposer,
      $$MediaCacheEntriesTableCreateCompanionBuilder,
      $$MediaCacheEntriesTableUpdateCompanionBuilder,
      (
        MediaCacheEntry,
        BaseReferences<_$AppDatabase, $MediaCacheEntriesTable, MediaCacheEntry>,
      ),
      MediaCacheEntry,
      PrefetchHooks Function()
    >;
typedef $$InboundFollowRequestEntriesTableCreateCompanionBuilder =
    InboundFollowRequestEntriesCompanion Function({
      required String pubkey,
      required Uint8List encryptedEndpoints,
      required int createdAt,
      Value<int> requestTimestamp,
      Value<String> status,
      Value<int> rowid,
    });
typedef $$InboundFollowRequestEntriesTableUpdateCompanionBuilder =
    InboundFollowRequestEntriesCompanion Function({
      Value<String> pubkey,
      Value<Uint8List> encryptedEndpoints,
      Value<int> createdAt,
      Value<int> requestTimestamp,
      Value<String> status,
      Value<int> rowid,
    });

class $$InboundFollowRequestEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $InboundFollowRequestEntriesTable> {
  $$InboundFollowRequestEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get encryptedEndpoints => $composableBuilder(
    column: $table.encryptedEndpoints,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get requestTimestamp => $composableBuilder(
    column: $table.requestTimestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InboundFollowRequestEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $InboundFollowRequestEntriesTable> {
  $$InboundFollowRequestEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get encryptedEndpoints => $composableBuilder(
    column: $table.encryptedEndpoints,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get requestTimestamp => $composableBuilder(
    column: $table.requestTimestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InboundFollowRequestEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $InboundFollowRequestEntriesTable> {
  $$InboundFollowRequestEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pubkey =>
      $composableBuilder(column: $table.pubkey, builder: (column) => column);

  GeneratedColumn<Uint8List> get encryptedEndpoints => $composableBuilder(
    column: $table.encryptedEndpoints,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get requestTimestamp => $composableBuilder(
    column: $table.requestTimestamp,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$InboundFollowRequestEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $InboundFollowRequestEntriesTable,
          InboundFollowRequestEntry,
          $$InboundFollowRequestEntriesTableFilterComposer,
          $$InboundFollowRequestEntriesTableOrderingComposer,
          $$InboundFollowRequestEntriesTableAnnotationComposer,
          $$InboundFollowRequestEntriesTableCreateCompanionBuilder,
          $$InboundFollowRequestEntriesTableUpdateCompanionBuilder,
          (
            InboundFollowRequestEntry,
            BaseReferences<
              _$AppDatabase,
              $InboundFollowRequestEntriesTable,
              InboundFollowRequestEntry
            >,
          ),
          InboundFollowRequestEntry,
          PrefetchHooks Function()
        > {
  $$InboundFollowRequestEntriesTableTableManager(
    _$AppDatabase db,
    $InboundFollowRequestEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InboundFollowRequestEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$InboundFollowRequestEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$InboundFollowRequestEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> pubkey = const Value.absent(),
                Value<Uint8List> encryptedEndpoints = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> requestTimestamp = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InboundFollowRequestEntriesCompanion(
                pubkey: pubkey,
                encryptedEndpoints: encryptedEndpoints,
                createdAt: createdAt,
                requestTimestamp: requestTimestamp,
                status: status,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String pubkey,
                required Uint8List encryptedEndpoints,
                required int createdAt,
                Value<int> requestTimestamp = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InboundFollowRequestEntriesCompanion.insert(
                pubkey: pubkey,
                encryptedEndpoints: encryptedEndpoints,
                createdAt: createdAt,
                requestTimestamp: requestTimestamp,
                status: status,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InboundFollowRequestEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $InboundFollowRequestEntriesTable,
      InboundFollowRequestEntry,
      $$InboundFollowRequestEntriesTableFilterComposer,
      $$InboundFollowRequestEntriesTableOrderingComposer,
      $$InboundFollowRequestEntriesTableAnnotationComposer,
      $$InboundFollowRequestEntriesTableCreateCompanionBuilder,
      $$InboundFollowRequestEntriesTableUpdateCompanionBuilder,
      (
        InboundFollowRequestEntry,
        BaseReferences<
          _$AppDatabase,
          $InboundFollowRequestEntriesTable,
          InboundFollowRequestEntry
        >,
      ),
      InboundFollowRequestEntry,
      PrefetchHooks Function()
    >;
typedef $$OutboundFollowRequestEntriesTableCreateCompanionBuilder =
    OutboundFollowRequestEntriesCompanion Function({
      required String pubkey,
      required String connectionCard,
      required int createdAt,
      Value<String> status,
      Value<int> rowid,
    });
typedef $$OutboundFollowRequestEntriesTableUpdateCompanionBuilder =
    OutboundFollowRequestEntriesCompanion Function({
      Value<String> pubkey,
      Value<String> connectionCard,
      Value<int> createdAt,
      Value<String> status,
      Value<int> rowid,
    });

class $$OutboundFollowRequestEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $OutboundFollowRequestEntriesTable> {
  $$OutboundFollowRequestEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get connectionCard => $composableBuilder(
    column: $table.connectionCard,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboundFollowRequestEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboundFollowRequestEntriesTable> {
  $$OutboundFollowRequestEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get connectionCard => $composableBuilder(
    column: $table.connectionCard,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboundFollowRequestEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboundFollowRequestEntriesTable> {
  $$OutboundFollowRequestEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get pubkey =>
      $composableBuilder(column: $table.pubkey, builder: (column) => column);

  GeneratedColumn<String> get connectionCard => $composableBuilder(
    column: $table.connectionCard,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);
}

class $$OutboundFollowRequestEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboundFollowRequestEntriesTable,
          OutboundFollowRequestEntry,
          $$OutboundFollowRequestEntriesTableFilterComposer,
          $$OutboundFollowRequestEntriesTableOrderingComposer,
          $$OutboundFollowRequestEntriesTableAnnotationComposer,
          $$OutboundFollowRequestEntriesTableCreateCompanionBuilder,
          $$OutboundFollowRequestEntriesTableUpdateCompanionBuilder,
          (
            OutboundFollowRequestEntry,
            BaseReferences<
              _$AppDatabase,
              $OutboundFollowRequestEntriesTable,
              OutboundFollowRequestEntry
            >,
          ),
          OutboundFollowRequestEntry,
          PrefetchHooks Function()
        > {
  $$OutboundFollowRequestEntriesTableTableManager(
    _$AppDatabase db,
    $OutboundFollowRequestEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboundFollowRequestEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$OutboundFollowRequestEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$OutboundFollowRequestEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> pubkey = const Value.absent(),
                Value<String> connectionCard = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboundFollowRequestEntriesCompanion(
                pubkey: pubkey,
                connectionCard: connectionCard,
                createdAt: createdAt,
                status: status,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String pubkey,
                required String connectionCard,
                required int createdAt,
                Value<String> status = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutboundFollowRequestEntriesCompanion.insert(
                pubkey: pubkey,
                connectionCard: connectionCard,
                createdAt: createdAt,
                status: status,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboundFollowRequestEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboundFollowRequestEntriesTable,
      OutboundFollowRequestEntry,
      $$OutboundFollowRequestEntriesTableFilterComposer,
      $$OutboundFollowRequestEntriesTableOrderingComposer,
      $$OutboundFollowRequestEntriesTableAnnotationComposer,
      $$OutboundFollowRequestEntriesTableCreateCompanionBuilder,
      $$OutboundFollowRequestEntriesTableUpdateCompanionBuilder,
      (
        OutboundFollowRequestEntry,
        BaseReferences<
          _$AppDatabase,
          $OutboundFollowRequestEntriesTable,
          OutboundFollowRequestEntry
        >,
      ),
      OutboundFollowRequestEntry,
      PrefetchHooks Function()
    >;
typedef $$OutboundQueueEntriesTableCreateCompanionBuilder =
    OutboundQueueEntriesCompanion Function({
      Value<int> id,
      required String targetPubkey,
      required Uint8List eventBlob,
      required int createdAt,
      Value<int> retryCount,
      Value<String?> itemType,
    });
typedef $$OutboundQueueEntriesTableUpdateCompanionBuilder =
    OutboundQueueEntriesCompanion Function({
      Value<int> id,
      Value<String> targetPubkey,
      Value<Uint8List> eventBlob,
      Value<int> createdAt,
      Value<int> retryCount,
      Value<String?> itemType,
    });

class $$OutboundQueueEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $OutboundQueueEntriesTable> {
  $$OutboundQueueEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get targetPubkey => $composableBuilder(
    column: $table.targetPubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get eventBlob => $composableBuilder(
    column: $table.eventBlob,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemType => $composableBuilder(
    column: $table.itemType,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutboundQueueEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $OutboundQueueEntriesTable> {
  $$OutboundQueueEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get targetPubkey => $composableBuilder(
    column: $table.targetPubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get eventBlob => $composableBuilder(
    column: $table.eventBlob,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemType => $composableBuilder(
    column: $table.itemType,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutboundQueueEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutboundQueueEntriesTable> {
  $$OutboundQueueEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get targetPubkey => $composableBuilder(
    column: $table.targetPubkey,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get eventBlob =>
      $composableBuilder(column: $table.eventBlob, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get retryCount => $composableBuilder(
    column: $table.retryCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get itemType =>
      $composableBuilder(column: $table.itemType, builder: (column) => column);
}

class $$OutboundQueueEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutboundQueueEntriesTable,
          OutboundQueueEntry,
          $$OutboundQueueEntriesTableFilterComposer,
          $$OutboundQueueEntriesTableOrderingComposer,
          $$OutboundQueueEntriesTableAnnotationComposer,
          $$OutboundQueueEntriesTableCreateCompanionBuilder,
          $$OutboundQueueEntriesTableUpdateCompanionBuilder,
          (
            OutboundQueueEntry,
            BaseReferences<
              _$AppDatabase,
              $OutboundQueueEntriesTable,
              OutboundQueueEntry
            >,
          ),
          OutboundQueueEntry,
          PrefetchHooks Function()
        > {
  $$OutboundQueueEntriesTableTableManager(
    _$AppDatabase db,
    $OutboundQueueEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutboundQueueEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutboundQueueEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$OutboundQueueEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> targetPubkey = const Value.absent(),
                Value<Uint8List> eventBlob = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> retryCount = const Value.absent(),
                Value<String?> itemType = const Value.absent(),
              }) => OutboundQueueEntriesCompanion(
                id: id,
                targetPubkey: targetPubkey,
                eventBlob: eventBlob,
                createdAt: createdAt,
                retryCount: retryCount,
                itemType: itemType,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String targetPubkey,
                required Uint8List eventBlob,
                required int createdAt,
                Value<int> retryCount = const Value.absent(),
                Value<String?> itemType = const Value.absent(),
              }) => OutboundQueueEntriesCompanion.insert(
                id: id,
                targetPubkey: targetPubkey,
                eventBlob: eventBlob,
                createdAt: createdAt,
                retryCount: retryCount,
                itemType: itemType,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OutboundQueueEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutboundQueueEntriesTable,
      OutboundQueueEntry,
      $$OutboundQueueEntriesTableFilterComposer,
      $$OutboundQueueEntriesTableOrderingComposer,
      $$OutboundQueueEntriesTableAnnotationComposer,
      $$OutboundQueueEntriesTableCreateCompanionBuilder,
      $$OutboundQueueEntriesTableUpdateCompanionBuilder,
      (
        OutboundQueueEntry,
        BaseReferences<
          _$AppDatabase,
          $OutboundQueueEntriesTable,
          OutboundQueueEntry
        >,
      ),
      OutboundQueueEntry,
      PrefetchHooks Function()
    >;
typedef $$UnknownEnvelopeItemEntriesTableCreateCompanionBuilder =
    UnknownEnvelopeItemEntriesCompanion Function({
      Value<int> id,
      required String sourcePubkey,
      required String envelopeVersion,
      required String type,
      required Uint8List payload,
      Value<Uint8List?> extensions,
      required int receivedAt,
    });
typedef $$UnknownEnvelopeItemEntriesTableUpdateCompanionBuilder =
    UnknownEnvelopeItemEntriesCompanion Function({
      Value<int> id,
      Value<String> sourcePubkey,
      Value<String> envelopeVersion,
      Value<String> type,
      Value<Uint8List> payload,
      Value<Uint8List?> extensions,
      Value<int> receivedAt,
    });

class $$UnknownEnvelopeItemEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $UnknownEnvelopeItemEntriesTable> {
  $$UnknownEnvelopeItemEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourcePubkey => $composableBuilder(
    column: $table.sourcePubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get envelopeVersion => $composableBuilder(
    column: $table.envelopeVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get extensions => $composableBuilder(
    column: $table.extensions,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UnknownEnvelopeItemEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $UnknownEnvelopeItemEntriesTable> {
  $$UnknownEnvelopeItemEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourcePubkey => $composableBuilder(
    column: $table.sourcePubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get envelopeVersion => $composableBuilder(
    column: $table.envelopeVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get extensions => $composableBuilder(
    column: $table.extensions,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UnknownEnvelopeItemEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $UnknownEnvelopeItemEntriesTable> {
  $$UnknownEnvelopeItemEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sourcePubkey => $composableBuilder(
    column: $table.sourcePubkey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get envelopeVersion => $composableBuilder(
    column: $table.envelopeVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<Uint8List> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<Uint8List> get extensions => $composableBuilder(
    column: $table.extensions,
    builder: (column) => column,
  );

  GeneratedColumn<int> get receivedAt => $composableBuilder(
    column: $table.receivedAt,
    builder: (column) => column,
  );
}

class $$UnknownEnvelopeItemEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UnknownEnvelopeItemEntriesTable,
          UnknownEnvelopeItemEntry,
          $$UnknownEnvelopeItemEntriesTableFilterComposer,
          $$UnknownEnvelopeItemEntriesTableOrderingComposer,
          $$UnknownEnvelopeItemEntriesTableAnnotationComposer,
          $$UnknownEnvelopeItemEntriesTableCreateCompanionBuilder,
          $$UnknownEnvelopeItemEntriesTableUpdateCompanionBuilder,
          (
            UnknownEnvelopeItemEntry,
            BaseReferences<
              _$AppDatabase,
              $UnknownEnvelopeItemEntriesTable,
              UnknownEnvelopeItemEntry
            >,
          ),
          UnknownEnvelopeItemEntry,
          PrefetchHooks Function()
        > {
  $$UnknownEnvelopeItemEntriesTableTableManager(
    _$AppDatabase db,
    $UnknownEnvelopeItemEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UnknownEnvelopeItemEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$UnknownEnvelopeItemEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$UnknownEnvelopeItemEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> sourcePubkey = const Value.absent(),
                Value<String> envelopeVersion = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<Uint8List> payload = const Value.absent(),
                Value<Uint8List?> extensions = const Value.absent(),
                Value<int> receivedAt = const Value.absent(),
              }) => UnknownEnvelopeItemEntriesCompanion(
                id: id,
                sourcePubkey: sourcePubkey,
                envelopeVersion: envelopeVersion,
                type: type,
                payload: payload,
                extensions: extensions,
                receivedAt: receivedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String sourcePubkey,
                required String envelopeVersion,
                required String type,
                required Uint8List payload,
                Value<Uint8List?> extensions = const Value.absent(),
                required int receivedAt,
              }) => UnknownEnvelopeItemEntriesCompanion.insert(
                id: id,
                sourcePubkey: sourcePubkey,
                envelopeVersion: envelopeVersion,
                type: type,
                payload: payload,
                extensions: extensions,
                receivedAt: receivedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$UnknownEnvelopeItemEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UnknownEnvelopeItemEntriesTable,
      UnknownEnvelopeItemEntry,
      $$UnknownEnvelopeItemEntriesTableFilterComposer,
      $$UnknownEnvelopeItemEntriesTableOrderingComposer,
      $$UnknownEnvelopeItemEntriesTableAnnotationComposer,
      $$UnknownEnvelopeItemEntriesTableCreateCompanionBuilder,
      $$UnknownEnvelopeItemEntriesTableUpdateCompanionBuilder,
      (
        UnknownEnvelopeItemEntry,
        BaseReferences<
          _$AppDatabase,
          $UnknownEnvelopeItemEntriesTable,
          UnknownEnvelopeItemEntry
        >,
      ),
      UnknownEnvelopeItemEntry,
      PrefetchHooks Function()
    >;
typedef $$FeedKeyHistoryEntriesTableCreateCompanionBuilder =
    FeedKeyHistoryEntriesCompanion Function({
      Value<int> id,
      required Uint8List feedKey,
      Value<int> feedKeyEpoch,
      required int validFrom,
      required int validUntil,
    });
typedef $$FeedKeyHistoryEntriesTableUpdateCompanionBuilder =
    FeedKeyHistoryEntriesCompanion Function({
      Value<int> id,
      Value<Uint8List> feedKey,
      Value<int> feedKeyEpoch,
      Value<int> validFrom,
      Value<int> validUntil,
    });

class $$FeedKeyHistoryEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $FeedKeyHistoryEntriesTable> {
  $$FeedKeyHistoryEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get feedKey => $composableBuilder(
    column: $table.feedKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get feedKeyEpoch => $composableBuilder(
    column: $table.feedKeyEpoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get validFrom => $composableBuilder(
    column: $table.validFrom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get validUntil => $composableBuilder(
    column: $table.validUntil,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FeedKeyHistoryEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $FeedKeyHistoryEntriesTable> {
  $$FeedKeyHistoryEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get feedKey => $composableBuilder(
    column: $table.feedKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get feedKeyEpoch => $composableBuilder(
    column: $table.feedKeyEpoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get validFrom => $composableBuilder(
    column: $table.validFrom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get validUntil => $composableBuilder(
    column: $table.validUntil,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FeedKeyHistoryEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FeedKeyHistoryEntriesTable> {
  $$FeedKeyHistoryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<Uint8List> get feedKey =>
      $composableBuilder(column: $table.feedKey, builder: (column) => column);

  GeneratedColumn<int> get feedKeyEpoch => $composableBuilder(
    column: $table.feedKeyEpoch,
    builder: (column) => column,
  );

  GeneratedColumn<int> get validFrom =>
      $composableBuilder(column: $table.validFrom, builder: (column) => column);

  GeneratedColumn<int> get validUntil => $composableBuilder(
    column: $table.validUntil,
    builder: (column) => column,
  );
}

class $$FeedKeyHistoryEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FeedKeyHistoryEntriesTable,
          FeedKeyHistoryEntry,
          $$FeedKeyHistoryEntriesTableFilterComposer,
          $$FeedKeyHistoryEntriesTableOrderingComposer,
          $$FeedKeyHistoryEntriesTableAnnotationComposer,
          $$FeedKeyHistoryEntriesTableCreateCompanionBuilder,
          $$FeedKeyHistoryEntriesTableUpdateCompanionBuilder,
          (
            FeedKeyHistoryEntry,
            BaseReferences<
              _$AppDatabase,
              $FeedKeyHistoryEntriesTable,
              FeedKeyHistoryEntry
            >,
          ),
          FeedKeyHistoryEntry,
          PrefetchHooks Function()
        > {
  $$FeedKeyHistoryEntriesTableTableManager(
    _$AppDatabase db,
    $FeedKeyHistoryEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FeedKeyHistoryEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$FeedKeyHistoryEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$FeedKeyHistoryEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<Uint8List> feedKey = const Value.absent(),
                Value<int> feedKeyEpoch = const Value.absent(),
                Value<int> validFrom = const Value.absent(),
                Value<int> validUntil = const Value.absent(),
              }) => FeedKeyHistoryEntriesCompanion(
                id: id,
                feedKey: feedKey,
                feedKeyEpoch: feedKeyEpoch,
                validFrom: validFrom,
                validUntil: validUntil,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required Uint8List feedKey,
                Value<int> feedKeyEpoch = const Value.absent(),
                required int validFrom,
                required int validUntil,
              }) => FeedKeyHistoryEntriesCompanion.insert(
                id: id,
                feedKey: feedKey,
                feedKeyEpoch: feedKeyEpoch,
                validFrom: validFrom,
                validUntil: validUntil,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FeedKeyHistoryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FeedKeyHistoryEntriesTable,
      FeedKeyHistoryEntry,
      $$FeedKeyHistoryEntriesTableFilterComposer,
      $$FeedKeyHistoryEntriesTableOrderingComposer,
      $$FeedKeyHistoryEntriesTableAnnotationComposer,
      $$FeedKeyHistoryEntriesTableCreateCompanionBuilder,
      $$FeedKeyHistoryEntriesTableUpdateCompanionBuilder,
      (
        FeedKeyHistoryEntry,
        BaseReferences<
          _$AppDatabase,
          $FeedKeyHistoryEntriesTable,
          FeedKeyHistoryEntry
        >,
      ),
      FeedKeyHistoryEntry,
      PrefetchHooks Function()
    >;
typedef $$FollowFeedKeyHistoryEntriesTableCreateCompanionBuilder =
    FollowFeedKeyHistoryEntriesCompanion Function({
      Value<int> id,
      required String followPubkey,
      required Uint8List feedKey,
      Value<int> feedKeyEpoch,
      required int validFrom,
      required int validUntil,
    });
typedef $$FollowFeedKeyHistoryEntriesTableUpdateCompanionBuilder =
    FollowFeedKeyHistoryEntriesCompanion Function({
      Value<int> id,
      Value<String> followPubkey,
      Value<Uint8List> feedKey,
      Value<int> feedKeyEpoch,
      Value<int> validFrom,
      Value<int> validUntil,
    });

class $$FollowFeedKeyHistoryEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $FollowFeedKeyHistoryEntriesTable> {
  $$FollowFeedKeyHistoryEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get followPubkey => $composableBuilder(
    column: $table.followPubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get feedKey => $composableBuilder(
    column: $table.feedKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get feedKeyEpoch => $composableBuilder(
    column: $table.feedKeyEpoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get validFrom => $composableBuilder(
    column: $table.validFrom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get validUntil => $composableBuilder(
    column: $table.validUntil,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FollowFeedKeyHistoryEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $FollowFeedKeyHistoryEntriesTable> {
  $$FollowFeedKeyHistoryEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get followPubkey => $composableBuilder(
    column: $table.followPubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get feedKey => $composableBuilder(
    column: $table.feedKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get feedKeyEpoch => $composableBuilder(
    column: $table.feedKeyEpoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get validFrom => $composableBuilder(
    column: $table.validFrom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get validUntil => $composableBuilder(
    column: $table.validUntil,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FollowFeedKeyHistoryEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $FollowFeedKeyHistoryEntriesTable> {
  $$FollowFeedKeyHistoryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get followPubkey => $composableBuilder(
    column: $table.followPubkey,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get feedKey =>
      $composableBuilder(column: $table.feedKey, builder: (column) => column);

  GeneratedColumn<int> get feedKeyEpoch => $composableBuilder(
    column: $table.feedKeyEpoch,
    builder: (column) => column,
  );

  GeneratedColumn<int> get validFrom =>
      $composableBuilder(column: $table.validFrom, builder: (column) => column);

  GeneratedColumn<int> get validUntil => $composableBuilder(
    column: $table.validUntil,
    builder: (column) => column,
  );
}

class $$FollowFeedKeyHistoryEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FollowFeedKeyHistoryEntriesTable,
          FollowFeedKeyHistoryEntry,
          $$FollowFeedKeyHistoryEntriesTableFilterComposer,
          $$FollowFeedKeyHistoryEntriesTableOrderingComposer,
          $$FollowFeedKeyHistoryEntriesTableAnnotationComposer,
          $$FollowFeedKeyHistoryEntriesTableCreateCompanionBuilder,
          $$FollowFeedKeyHistoryEntriesTableUpdateCompanionBuilder,
          (
            FollowFeedKeyHistoryEntry,
            BaseReferences<
              _$AppDatabase,
              $FollowFeedKeyHistoryEntriesTable,
              FollowFeedKeyHistoryEntry
            >,
          ),
          FollowFeedKeyHistoryEntry,
          PrefetchHooks Function()
        > {
  $$FollowFeedKeyHistoryEntriesTableTableManager(
    _$AppDatabase db,
    $FollowFeedKeyHistoryEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FollowFeedKeyHistoryEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$FollowFeedKeyHistoryEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$FollowFeedKeyHistoryEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> followPubkey = const Value.absent(),
                Value<Uint8List> feedKey = const Value.absent(),
                Value<int> feedKeyEpoch = const Value.absent(),
                Value<int> validFrom = const Value.absent(),
                Value<int> validUntil = const Value.absent(),
              }) => FollowFeedKeyHistoryEntriesCompanion(
                id: id,
                followPubkey: followPubkey,
                feedKey: feedKey,
                feedKeyEpoch: feedKeyEpoch,
                validFrom: validFrom,
                validUntil: validUntil,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String followPubkey,
                required Uint8List feedKey,
                Value<int> feedKeyEpoch = const Value.absent(),
                required int validFrom,
                required int validUntil,
              }) => FollowFeedKeyHistoryEntriesCompanion.insert(
                id: id,
                followPubkey: followPubkey,
                feedKey: feedKey,
                feedKeyEpoch: feedKeyEpoch,
                validFrom: validFrom,
                validUntil: validUntil,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FollowFeedKeyHistoryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FollowFeedKeyHistoryEntriesTable,
      FollowFeedKeyHistoryEntry,
      $$FollowFeedKeyHistoryEntriesTableFilterComposer,
      $$FollowFeedKeyHistoryEntriesTableOrderingComposer,
      $$FollowFeedKeyHistoryEntriesTableAnnotationComposer,
      $$FollowFeedKeyHistoryEntriesTableCreateCompanionBuilder,
      $$FollowFeedKeyHistoryEntriesTableUpdateCompanionBuilder,
      (
        FollowFeedKeyHistoryEntry,
        BaseReferences<
          _$AppDatabase,
          $FollowFeedKeyHistoryEntriesTable,
          FollowFeedKeyHistoryEntry
        >,
      ),
      FollowFeedKeyHistoryEntry,
      PrefetchHooks Function()
    >;
typedef $$PendingKeyDistributionEntriesTableCreateCompanionBuilder =
    PendingKeyDistributionEntriesCompanion Function({
      required String targetPubkey,
      required Uint8List encryptedFeedKey,
      required Uint8List nonce,
      required int createdAt,
      Value<int> distributed,
      Value<int> rowid,
    });
typedef $$PendingKeyDistributionEntriesTableUpdateCompanionBuilder =
    PendingKeyDistributionEntriesCompanion Function({
      Value<String> targetPubkey,
      Value<Uint8List> encryptedFeedKey,
      Value<Uint8List> nonce,
      Value<int> createdAt,
      Value<int> distributed,
      Value<int> rowid,
    });

class $$PendingKeyDistributionEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $PendingKeyDistributionEntriesTable> {
  $$PendingKeyDistributionEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get targetPubkey => $composableBuilder(
    column: $table.targetPubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get encryptedFeedKey => $composableBuilder(
    column: $table.encryptedFeedKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get nonce => $composableBuilder(
    column: $table.nonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get distributed => $composableBuilder(
    column: $table.distributed,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingKeyDistributionEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingKeyDistributionEntriesTable> {
  $$PendingKeyDistributionEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get targetPubkey => $composableBuilder(
    column: $table.targetPubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get encryptedFeedKey => $composableBuilder(
    column: $table.encryptedFeedKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get nonce => $composableBuilder(
    column: $table.nonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get distributed => $composableBuilder(
    column: $table.distributed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingKeyDistributionEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingKeyDistributionEntriesTable> {
  $$PendingKeyDistributionEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get targetPubkey => $composableBuilder(
    column: $table.targetPubkey,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get encryptedFeedKey => $composableBuilder(
    column: $table.encryptedFeedKey,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get nonce =>
      $composableBuilder(column: $table.nonce, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get distributed => $composableBuilder(
    column: $table.distributed,
    builder: (column) => column,
  );
}

class $$PendingKeyDistributionEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingKeyDistributionEntriesTable,
          PendingKeyDistributionEntry,
          $$PendingKeyDistributionEntriesTableFilterComposer,
          $$PendingKeyDistributionEntriesTableOrderingComposer,
          $$PendingKeyDistributionEntriesTableAnnotationComposer,
          $$PendingKeyDistributionEntriesTableCreateCompanionBuilder,
          $$PendingKeyDistributionEntriesTableUpdateCompanionBuilder,
          (
            PendingKeyDistributionEntry,
            BaseReferences<
              _$AppDatabase,
              $PendingKeyDistributionEntriesTable,
              PendingKeyDistributionEntry
            >,
          ),
          PendingKeyDistributionEntry,
          PrefetchHooks Function()
        > {
  $$PendingKeyDistributionEntriesTableTableManager(
    _$AppDatabase db,
    $PendingKeyDistributionEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingKeyDistributionEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$PendingKeyDistributionEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PendingKeyDistributionEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> targetPubkey = const Value.absent(),
                Value<Uint8List> encryptedFeedKey = const Value.absent(),
                Value<Uint8List> nonce = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> distributed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingKeyDistributionEntriesCompanion(
                targetPubkey: targetPubkey,
                encryptedFeedKey: encryptedFeedKey,
                nonce: nonce,
                createdAt: createdAt,
                distributed: distributed,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String targetPubkey,
                required Uint8List encryptedFeedKey,
                required Uint8List nonce,
                required int createdAt,
                Value<int> distributed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingKeyDistributionEntriesCompanion.insert(
                targetPubkey: targetPubkey,
                encryptedFeedKey: encryptedFeedKey,
                nonce: nonce,
                createdAt: createdAt,
                distributed: distributed,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingKeyDistributionEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingKeyDistributionEntriesTable,
      PendingKeyDistributionEntry,
      $$PendingKeyDistributionEntriesTableFilterComposer,
      $$PendingKeyDistributionEntriesTableOrderingComposer,
      $$PendingKeyDistributionEntriesTableAnnotationComposer,
      $$PendingKeyDistributionEntriesTableCreateCompanionBuilder,
      $$PendingKeyDistributionEntriesTableUpdateCompanionBuilder,
      (
        PendingKeyDistributionEntry,
        BaseReferences<
          _$AppDatabase,
          $PendingKeyDistributionEntriesTable,
          PendingKeyDistributionEntry
        >,
      ),
      PendingKeyDistributionEntry,
      PrefetchHooks Function()
    >;
typedef $$PairedRelayEntriesTableCreateCompanionBuilder =
    PairedRelayEntriesCompanion Function({
      required String relayId,
      required String relayOnion,
      required int pairedAt,
      Value<int> relayBackfillComplete,
      Value<int> relayPruneBefore,
      Value<int> lastPushAt,
      Value<String?> lastError,
      Value<int> rowid,
    });
typedef $$PairedRelayEntriesTableUpdateCompanionBuilder =
    PairedRelayEntriesCompanion Function({
      Value<String> relayId,
      Value<String> relayOnion,
      Value<int> pairedAt,
      Value<int> relayBackfillComplete,
      Value<int> relayPruneBefore,
      Value<int> lastPushAt,
      Value<String?> lastError,
      Value<int> rowid,
    });

class $$PairedRelayEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $PairedRelayEntriesTable> {
  $$PairedRelayEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get relayId => $composableBuilder(
    column: $table.relayId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relayOnion => $composableBuilder(
    column: $table.relayOnion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get relayBackfillComplete => $composableBuilder(
    column: $table.relayBackfillComplete,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get relayPruneBefore => $composableBuilder(
    column: $table.relayPruneBefore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastPushAt => $composableBuilder(
    column: $table.lastPushAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PairedRelayEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $PairedRelayEntriesTable> {
  $$PairedRelayEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get relayId => $composableBuilder(
    column: $table.relayId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relayOnion => $composableBuilder(
    column: $table.relayOnion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get relayBackfillComplete => $composableBuilder(
    column: $table.relayBackfillComplete,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get relayPruneBefore => $composableBuilder(
    column: $table.relayPruneBefore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastPushAt => $composableBuilder(
    column: $table.lastPushAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PairedRelayEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PairedRelayEntriesTable> {
  $$PairedRelayEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get relayId =>
      $composableBuilder(column: $table.relayId, builder: (column) => column);

  GeneratedColumn<String> get relayOnion => $composableBuilder(
    column: $table.relayOnion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get pairedAt =>
      $composableBuilder(column: $table.pairedAt, builder: (column) => column);

  GeneratedColumn<int> get relayBackfillComplete => $composableBuilder(
    column: $table.relayBackfillComplete,
    builder: (column) => column,
  );

  GeneratedColumn<int> get relayPruneBefore => $composableBuilder(
    column: $table.relayPruneBefore,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastPushAt => $composableBuilder(
    column: $table.lastPushAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);
}

class $$PairedRelayEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PairedRelayEntriesTable,
          PairedRelayEntry,
          $$PairedRelayEntriesTableFilterComposer,
          $$PairedRelayEntriesTableOrderingComposer,
          $$PairedRelayEntriesTableAnnotationComposer,
          $$PairedRelayEntriesTableCreateCompanionBuilder,
          $$PairedRelayEntriesTableUpdateCompanionBuilder,
          (
            PairedRelayEntry,
            BaseReferences<
              _$AppDatabase,
              $PairedRelayEntriesTable,
              PairedRelayEntry
            >,
          ),
          PairedRelayEntry,
          PrefetchHooks Function()
        > {
  $$PairedRelayEntriesTableTableManager(
    _$AppDatabase db,
    $PairedRelayEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PairedRelayEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PairedRelayEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PairedRelayEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> relayId = const Value.absent(),
                Value<String> relayOnion = const Value.absent(),
                Value<int> pairedAt = const Value.absent(),
                Value<int> relayBackfillComplete = const Value.absent(),
                Value<int> relayPruneBefore = const Value.absent(),
                Value<int> lastPushAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PairedRelayEntriesCompanion(
                relayId: relayId,
                relayOnion: relayOnion,
                pairedAt: pairedAt,
                relayBackfillComplete: relayBackfillComplete,
                relayPruneBefore: relayPruneBefore,
                lastPushAt: lastPushAt,
                lastError: lastError,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String relayId,
                required String relayOnion,
                required int pairedAt,
                Value<int> relayBackfillComplete = const Value.absent(),
                Value<int> relayPruneBefore = const Value.absent(),
                Value<int> lastPushAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PairedRelayEntriesCompanion.insert(
                relayId: relayId,
                relayOnion: relayOnion,
                pairedAt: pairedAt,
                relayBackfillComplete: relayBackfillComplete,
                relayPruneBefore: relayPruneBefore,
                lastPushAt: lastPushAt,
                lastError: lastError,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PairedRelayEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PairedRelayEntriesTable,
      PairedRelayEntry,
      $$PairedRelayEntriesTableFilterComposer,
      $$PairedRelayEntriesTableOrderingComposer,
      $$PairedRelayEntriesTableAnnotationComposer,
      $$PairedRelayEntriesTableCreateCompanionBuilder,
      $$PairedRelayEntriesTableUpdateCompanionBuilder,
      (
        PairedRelayEntry,
        BaseReferences<
          _$AppDatabase,
          $PairedRelayEntriesTable,
          PairedRelayEntry
        >,
      ),
      PairedRelayEntry,
      PrefetchHooks Function()
    >;
typedef $$PendingCardDistributionEntriesTableCreateCompanionBuilder =
    PendingCardDistributionEntriesCompanion Function({
      required String targetPubkey,
      required Uint8List encryptedCard,
      required Uint8List nonce,
      required int createdAt,
      Value<int> distributed,
      Value<int> rowid,
    });
typedef $$PendingCardDistributionEntriesTableUpdateCompanionBuilder =
    PendingCardDistributionEntriesCompanion Function({
      Value<String> targetPubkey,
      Value<Uint8List> encryptedCard,
      Value<Uint8List> nonce,
      Value<int> createdAt,
      Value<int> distributed,
      Value<int> rowid,
    });

class $$PendingCardDistributionEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $PendingCardDistributionEntriesTable> {
  $$PendingCardDistributionEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get targetPubkey => $composableBuilder(
    column: $table.targetPubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get encryptedCard => $composableBuilder(
    column: $table.encryptedCard,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get nonce => $composableBuilder(
    column: $table.nonce,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get distributed => $composableBuilder(
    column: $table.distributed,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PendingCardDistributionEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $PendingCardDistributionEntriesTable> {
  $$PendingCardDistributionEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get targetPubkey => $composableBuilder(
    column: $table.targetPubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get encryptedCard => $composableBuilder(
    column: $table.encryptedCard,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get nonce => $composableBuilder(
    column: $table.nonce,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get distributed => $composableBuilder(
    column: $table.distributed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PendingCardDistributionEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PendingCardDistributionEntriesTable> {
  $$PendingCardDistributionEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get targetPubkey => $composableBuilder(
    column: $table.targetPubkey,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get encryptedCard => $composableBuilder(
    column: $table.encryptedCard,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get nonce =>
      $composableBuilder(column: $table.nonce, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get distributed => $composableBuilder(
    column: $table.distributed,
    builder: (column) => column,
  );
}

class $$PendingCardDistributionEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PendingCardDistributionEntriesTable,
          PendingCardDistributionEntry,
          $$PendingCardDistributionEntriesTableFilterComposer,
          $$PendingCardDistributionEntriesTableOrderingComposer,
          $$PendingCardDistributionEntriesTableAnnotationComposer,
          $$PendingCardDistributionEntriesTableCreateCompanionBuilder,
          $$PendingCardDistributionEntriesTableUpdateCompanionBuilder,
          (
            PendingCardDistributionEntry,
            BaseReferences<
              _$AppDatabase,
              $PendingCardDistributionEntriesTable,
              PendingCardDistributionEntry
            >,
          ),
          PendingCardDistributionEntry,
          PrefetchHooks Function()
        > {
  $$PendingCardDistributionEntriesTableTableManager(
    _$AppDatabase db,
    $PendingCardDistributionEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingCardDistributionEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$PendingCardDistributionEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PendingCardDistributionEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> targetPubkey = const Value.absent(),
                Value<Uint8List> encryptedCard = const Value.absent(),
                Value<Uint8List> nonce = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> distributed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingCardDistributionEntriesCompanion(
                targetPubkey: targetPubkey,
                encryptedCard: encryptedCard,
                nonce: nonce,
                createdAt: createdAt,
                distributed: distributed,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String targetPubkey,
                required Uint8List encryptedCard,
                required Uint8List nonce,
                required int createdAt,
                Value<int> distributed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PendingCardDistributionEntriesCompanion.insert(
                targetPubkey: targetPubkey,
                encryptedCard: encryptedCard,
                nonce: nonce,
                createdAt: createdAt,
                distributed: distributed,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PendingCardDistributionEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PendingCardDistributionEntriesTable,
      PendingCardDistributionEntry,
      $$PendingCardDistributionEntriesTableFilterComposer,
      $$PendingCardDistributionEntriesTableOrderingComposer,
      $$PendingCardDistributionEntriesTableAnnotationComposer,
      $$PendingCardDistributionEntriesTableCreateCompanionBuilder,
      $$PendingCardDistributionEntriesTableUpdateCompanionBuilder,
      (
        PendingCardDistributionEntry,
        BaseReferences<
          _$AppDatabase,
          $PendingCardDistributionEntriesTable,
          PendingCardDistributionEntry
        >,
      ),
      PendingCardDistributionEntry,
      PrefetchHooks Function()
    >;
typedef $$RelayFanoutStateEntriesTableCreateCompanionBuilder =
    RelayFanoutStateEntriesCompanion Function({
      Value<int> id,
      Value<int> pendingCardFanout,
      Value<String?> pendingUnpairOnion,
      Value<int> unpairNotifyAttempts,
    });
typedef $$RelayFanoutStateEntriesTableUpdateCompanionBuilder =
    RelayFanoutStateEntriesCompanion Function({
      Value<int> id,
      Value<int> pendingCardFanout,
      Value<String?> pendingUnpairOnion,
      Value<int> unpairNotifyAttempts,
    });

class $$RelayFanoutStateEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $RelayFanoutStateEntriesTable> {
  $$RelayFanoutStateEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get pendingCardFanout => $composableBuilder(
    column: $table.pendingCardFanout,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pendingUnpairOnion => $composableBuilder(
    column: $table.pendingUnpairOnion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get unpairNotifyAttempts => $composableBuilder(
    column: $table.unpairNotifyAttempts,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RelayFanoutStateEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $RelayFanoutStateEntriesTable> {
  $$RelayFanoutStateEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get pendingCardFanout => $composableBuilder(
    column: $table.pendingCardFanout,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pendingUnpairOnion => $composableBuilder(
    column: $table.pendingUnpairOnion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get unpairNotifyAttempts => $composableBuilder(
    column: $table.unpairNotifyAttempts,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RelayFanoutStateEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RelayFanoutStateEntriesTable> {
  $$RelayFanoutStateEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get pendingCardFanout => $composableBuilder(
    column: $table.pendingCardFanout,
    builder: (column) => column,
  );

  GeneratedColumn<String> get pendingUnpairOnion => $composableBuilder(
    column: $table.pendingUnpairOnion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get unpairNotifyAttempts => $composableBuilder(
    column: $table.unpairNotifyAttempts,
    builder: (column) => column,
  );
}

class $$RelayFanoutStateEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RelayFanoutStateEntriesTable,
          RelayFanoutStateEntry,
          $$RelayFanoutStateEntriesTableFilterComposer,
          $$RelayFanoutStateEntriesTableOrderingComposer,
          $$RelayFanoutStateEntriesTableAnnotationComposer,
          $$RelayFanoutStateEntriesTableCreateCompanionBuilder,
          $$RelayFanoutStateEntriesTableUpdateCompanionBuilder,
          (
            RelayFanoutStateEntry,
            BaseReferences<
              _$AppDatabase,
              $RelayFanoutStateEntriesTable,
              RelayFanoutStateEntry
            >,
          ),
          RelayFanoutStateEntry,
          PrefetchHooks Function()
        > {
  $$RelayFanoutStateEntriesTableTableManager(
    _$AppDatabase db,
    $RelayFanoutStateEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RelayFanoutStateEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$RelayFanoutStateEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RelayFanoutStateEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> pendingCardFanout = const Value.absent(),
                Value<String?> pendingUnpairOnion = const Value.absent(),
                Value<int> unpairNotifyAttempts = const Value.absent(),
              }) => RelayFanoutStateEntriesCompanion(
                id: id,
                pendingCardFanout: pendingCardFanout,
                pendingUnpairOnion: pendingUnpairOnion,
                unpairNotifyAttempts: unpairNotifyAttempts,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> pendingCardFanout = const Value.absent(),
                Value<String?> pendingUnpairOnion = const Value.absent(),
                Value<int> unpairNotifyAttempts = const Value.absent(),
              }) => RelayFanoutStateEntriesCompanion.insert(
                id: id,
                pendingCardFanout: pendingCardFanout,
                pendingUnpairOnion: pendingUnpairOnion,
                unpairNotifyAttempts: unpairNotifyAttempts,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RelayFanoutStateEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RelayFanoutStateEntriesTable,
      RelayFanoutStateEntry,
      $$RelayFanoutStateEntriesTableFilterComposer,
      $$RelayFanoutStateEntriesTableOrderingComposer,
      $$RelayFanoutStateEntriesTableAnnotationComposer,
      $$RelayFanoutStateEntriesTableCreateCompanionBuilder,
      $$RelayFanoutStateEntriesTableUpdateCompanionBuilder,
      (
        RelayFanoutStateEntry,
        BaseReferences<
          _$AppDatabase,
          $RelayFanoutStateEntriesTable,
          RelayFanoutStateEntry
        >,
      ),
      RelayFanoutStateEntry,
      PrefetchHooks Function()
    >;
typedef $$VoiceRoomEntriesTableCreateCompanionBuilder =
    VoiceRoomEntriesCompanion Function({
      required String id,
      required String name,
      required String creatorPubkey,
      required int createdAt,
      Value<int?> endedAt,
      Value<int> participantCount,
      Value<bool> missed,
      Value<int> rowid,
    });
typedef $$VoiceRoomEntriesTableUpdateCompanionBuilder =
    VoiceRoomEntriesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> creatorPubkey,
      Value<int> createdAt,
      Value<int?> endedAt,
      Value<int> participantCount,
      Value<bool> missed,
      Value<int> rowid,
    });

class $$VoiceRoomEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $VoiceRoomEntriesTable> {
  $$VoiceRoomEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get creatorPubkey => $composableBuilder(
    column: $table.creatorPubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get participantCount => $composableBuilder(
    column: $table.participantCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get missed => $composableBuilder(
    column: $table.missed,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VoiceRoomEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $VoiceRoomEntriesTable> {
  $$VoiceRoomEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get creatorPubkey => $composableBuilder(
    column: $table.creatorPubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get participantCount => $composableBuilder(
    column: $table.participantCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get missed => $composableBuilder(
    column: $table.missed,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VoiceRoomEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $VoiceRoomEntriesTable> {
  $$VoiceRoomEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get creatorPubkey => $composableBuilder(
    column: $table.creatorPubkey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<int> get participantCount => $composableBuilder(
    column: $table.participantCount,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get missed =>
      $composableBuilder(column: $table.missed, builder: (column) => column);
}

class $$VoiceRoomEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VoiceRoomEntriesTable,
          VoiceRoomEntry,
          $$VoiceRoomEntriesTableFilterComposer,
          $$VoiceRoomEntriesTableOrderingComposer,
          $$VoiceRoomEntriesTableAnnotationComposer,
          $$VoiceRoomEntriesTableCreateCompanionBuilder,
          $$VoiceRoomEntriesTableUpdateCompanionBuilder,
          (
            VoiceRoomEntry,
            BaseReferences<
              _$AppDatabase,
              $VoiceRoomEntriesTable,
              VoiceRoomEntry
            >,
          ),
          VoiceRoomEntry,
          PrefetchHooks Function()
        > {
  $$VoiceRoomEntriesTableTableManager(
    _$AppDatabase db,
    $VoiceRoomEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VoiceRoomEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VoiceRoomEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VoiceRoomEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> creatorPubkey = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int?> endedAt = const Value.absent(),
                Value<int> participantCount = const Value.absent(),
                Value<bool> missed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VoiceRoomEntriesCompanion(
                id: id,
                name: name,
                creatorPubkey: creatorPubkey,
                createdAt: createdAt,
                endedAt: endedAt,
                participantCount: participantCount,
                missed: missed,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String creatorPubkey,
                required int createdAt,
                Value<int?> endedAt = const Value.absent(),
                Value<int> participantCount = const Value.absent(),
                Value<bool> missed = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VoiceRoomEntriesCompanion.insert(
                id: id,
                name: name,
                creatorPubkey: creatorPubkey,
                createdAt: createdAt,
                endedAt: endedAt,
                participantCount: participantCount,
                missed: missed,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VoiceRoomEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VoiceRoomEntriesTable,
      VoiceRoomEntry,
      $$VoiceRoomEntriesTableFilterComposer,
      $$VoiceRoomEntriesTableOrderingComposer,
      $$VoiceRoomEntriesTableAnnotationComposer,
      $$VoiceRoomEntriesTableCreateCompanionBuilder,
      $$VoiceRoomEntriesTableUpdateCompanionBuilder,
      (
        VoiceRoomEntry,
        BaseReferences<_$AppDatabase, $VoiceRoomEntriesTable, VoiceRoomEntry>,
      ),
      VoiceRoomEntry,
      PrefetchHooks Function()
    >;
typedef $$VoiceRoomParticipantEntriesTableCreateCompanionBuilder =
    VoiceRoomParticipantEntriesCompanion Function({
      required String roomId,
      required String pubkey,
      Value<String?> displayName,
      required int joinedAt,
      Value<int?> leftAt,
      Value<int> rowid,
    });
typedef $$VoiceRoomParticipantEntriesTableUpdateCompanionBuilder =
    VoiceRoomParticipantEntriesCompanion Function({
      Value<String> roomId,
      Value<String> pubkey,
      Value<String?> displayName,
      Value<int> joinedAt,
      Value<int?> leftAt,
      Value<int> rowid,
    });

class $$VoiceRoomParticipantEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $VoiceRoomParticipantEntriesTable> {
  $$VoiceRoomParticipantEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get joinedAt => $composableBuilder(
    column: $table.joinedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get leftAt => $composableBuilder(
    column: $table.leftAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$VoiceRoomParticipantEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $VoiceRoomParticipantEntriesTable> {
  $$VoiceRoomParticipantEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get joinedAt => $composableBuilder(
    column: $table.joinedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get leftAt => $composableBuilder(
    column: $table.leftAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$VoiceRoomParticipantEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $VoiceRoomParticipantEntriesTable> {
  $$VoiceRoomParticipantEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get roomId =>
      $composableBuilder(column: $table.roomId, builder: (column) => column);

  GeneratedColumn<String> get pubkey =>
      $composableBuilder(column: $table.pubkey, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get joinedAt =>
      $composableBuilder(column: $table.joinedAt, builder: (column) => column);

  GeneratedColumn<int> get leftAt =>
      $composableBuilder(column: $table.leftAt, builder: (column) => column);
}

class $$VoiceRoomParticipantEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $VoiceRoomParticipantEntriesTable,
          VoiceRoomParticipantEntry,
          $$VoiceRoomParticipantEntriesTableFilterComposer,
          $$VoiceRoomParticipantEntriesTableOrderingComposer,
          $$VoiceRoomParticipantEntriesTableAnnotationComposer,
          $$VoiceRoomParticipantEntriesTableCreateCompanionBuilder,
          $$VoiceRoomParticipantEntriesTableUpdateCompanionBuilder,
          (
            VoiceRoomParticipantEntry,
            BaseReferences<
              _$AppDatabase,
              $VoiceRoomParticipantEntriesTable,
              VoiceRoomParticipantEntry
            >,
          ),
          VoiceRoomParticipantEntry,
          PrefetchHooks Function()
        > {
  $$VoiceRoomParticipantEntriesTableTableManager(
    _$AppDatabase db,
    $VoiceRoomParticipantEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VoiceRoomParticipantEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$VoiceRoomParticipantEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$VoiceRoomParticipantEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> roomId = const Value.absent(),
                Value<String> pubkey = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<int> joinedAt = const Value.absent(),
                Value<int?> leftAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VoiceRoomParticipantEntriesCompanion(
                roomId: roomId,
                pubkey: pubkey,
                displayName: displayName,
                joinedAt: joinedAt,
                leftAt: leftAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String roomId,
                required String pubkey,
                Value<String?> displayName = const Value.absent(),
                required int joinedAt,
                Value<int?> leftAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => VoiceRoomParticipantEntriesCompanion.insert(
                roomId: roomId,
                pubkey: pubkey,
                displayName: displayName,
                joinedAt: joinedAt,
                leftAt: leftAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$VoiceRoomParticipantEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $VoiceRoomParticipantEntriesTable,
      VoiceRoomParticipantEntry,
      $$VoiceRoomParticipantEntriesTableFilterComposer,
      $$VoiceRoomParticipantEntriesTableOrderingComposer,
      $$VoiceRoomParticipantEntriesTableAnnotationComposer,
      $$VoiceRoomParticipantEntriesTableCreateCompanionBuilder,
      $$VoiceRoomParticipantEntriesTableUpdateCompanionBuilder,
      (
        VoiceRoomParticipantEntry,
        BaseReferences<
          _$AppDatabase,
          $VoiceRoomParticipantEntriesTable,
          VoiceRoomParticipantEntry
        >,
      ),
      VoiceRoomParticipantEntry,
      PrefetchHooks Function()
    >;
typedef $$RoomEntriesTableCreateCompanionBuilder =
    RoomEntriesCompanion Function({
      required String id,
      required String name,
      required String creatorPubkey,
      required int createdAt,
      required int lastActivityAt,
      required Uint8List roomKey,
      Value<int> roomKeyEpoch,
      Value<int> roomKeyValidFrom,
      Value<int> roomMsgSeqCounter,
      Value<int> membershipEpoch,
      Value<int> isMember,
      Value<int> lastReadAt,
      Value<int> rowid,
    });
typedef $$RoomEntriesTableUpdateCompanionBuilder =
    RoomEntriesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> creatorPubkey,
      Value<int> createdAt,
      Value<int> lastActivityAt,
      Value<Uint8List> roomKey,
      Value<int> roomKeyEpoch,
      Value<int> roomKeyValidFrom,
      Value<int> roomMsgSeqCounter,
      Value<int> membershipEpoch,
      Value<int> isMember,
      Value<int> lastReadAt,
      Value<int> rowid,
    });

class $$RoomEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $RoomEntriesTable> {
  $$RoomEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get creatorPubkey => $composableBuilder(
    column: $table.creatorPubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastActivityAt => $composableBuilder(
    column: $table.lastActivityAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get roomKey => $composableBuilder(
    column: $table.roomKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get roomKeyEpoch => $composableBuilder(
    column: $table.roomKeyEpoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get roomKeyValidFrom => $composableBuilder(
    column: $table.roomKeyValidFrom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get roomMsgSeqCounter => $composableBuilder(
    column: $table.roomMsgSeqCounter,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get membershipEpoch => $composableBuilder(
    column: $table.membershipEpoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get isMember => $composableBuilder(
    column: $table.isMember,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RoomEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $RoomEntriesTable> {
  $$RoomEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get creatorPubkey => $composableBuilder(
    column: $table.creatorPubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastActivityAt => $composableBuilder(
    column: $table.lastActivityAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get roomKey => $composableBuilder(
    column: $table.roomKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get roomKeyEpoch => $composableBuilder(
    column: $table.roomKeyEpoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get roomKeyValidFrom => $composableBuilder(
    column: $table.roomKeyValidFrom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get roomMsgSeqCounter => $composableBuilder(
    column: $table.roomMsgSeqCounter,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get membershipEpoch => $composableBuilder(
    column: $table.membershipEpoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get isMember => $composableBuilder(
    column: $table.isMember,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RoomEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RoomEntriesTable> {
  $$RoomEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get creatorPubkey => $composableBuilder(
    column: $table.creatorPubkey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get lastActivityAt => $composableBuilder(
    column: $table.lastActivityAt,
    builder: (column) => column,
  );

  GeneratedColumn<Uint8List> get roomKey =>
      $composableBuilder(column: $table.roomKey, builder: (column) => column);

  GeneratedColumn<int> get roomKeyEpoch => $composableBuilder(
    column: $table.roomKeyEpoch,
    builder: (column) => column,
  );

  GeneratedColumn<int> get roomKeyValidFrom => $composableBuilder(
    column: $table.roomKeyValidFrom,
    builder: (column) => column,
  );

  GeneratedColumn<int> get roomMsgSeqCounter => $composableBuilder(
    column: $table.roomMsgSeqCounter,
    builder: (column) => column,
  );

  GeneratedColumn<int> get membershipEpoch => $composableBuilder(
    column: $table.membershipEpoch,
    builder: (column) => column,
  );

  GeneratedColumn<int> get isMember =>
      $composableBuilder(column: $table.isMember, builder: (column) => column);

  GeneratedColumn<int> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => column,
  );
}

class $$RoomEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RoomEntriesTable,
          RoomEntry,
          $$RoomEntriesTableFilterComposer,
          $$RoomEntriesTableOrderingComposer,
          $$RoomEntriesTableAnnotationComposer,
          $$RoomEntriesTableCreateCompanionBuilder,
          $$RoomEntriesTableUpdateCompanionBuilder,
          (
            RoomEntry,
            BaseReferences<_$AppDatabase, $RoomEntriesTable, RoomEntry>,
          ),
          RoomEntry,
          PrefetchHooks Function()
        > {
  $$RoomEntriesTableTableManager(_$AppDatabase db, $RoomEntriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoomEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoomEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RoomEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> creatorPubkey = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> lastActivityAt = const Value.absent(),
                Value<Uint8List> roomKey = const Value.absent(),
                Value<int> roomKeyEpoch = const Value.absent(),
                Value<int> roomKeyValidFrom = const Value.absent(),
                Value<int> roomMsgSeqCounter = const Value.absent(),
                Value<int> membershipEpoch = const Value.absent(),
                Value<int> isMember = const Value.absent(),
                Value<int> lastReadAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RoomEntriesCompanion(
                id: id,
                name: name,
                creatorPubkey: creatorPubkey,
                createdAt: createdAt,
                lastActivityAt: lastActivityAt,
                roomKey: roomKey,
                roomKeyEpoch: roomKeyEpoch,
                roomKeyValidFrom: roomKeyValidFrom,
                roomMsgSeqCounter: roomMsgSeqCounter,
                membershipEpoch: membershipEpoch,
                isMember: isMember,
                lastReadAt: lastReadAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String creatorPubkey,
                required int createdAt,
                required int lastActivityAt,
                required Uint8List roomKey,
                Value<int> roomKeyEpoch = const Value.absent(),
                Value<int> roomKeyValidFrom = const Value.absent(),
                Value<int> roomMsgSeqCounter = const Value.absent(),
                Value<int> membershipEpoch = const Value.absent(),
                Value<int> isMember = const Value.absent(),
                Value<int> lastReadAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RoomEntriesCompanion.insert(
                id: id,
                name: name,
                creatorPubkey: creatorPubkey,
                createdAt: createdAt,
                lastActivityAt: lastActivityAt,
                roomKey: roomKey,
                roomKeyEpoch: roomKeyEpoch,
                roomKeyValidFrom: roomKeyValidFrom,
                roomMsgSeqCounter: roomMsgSeqCounter,
                membershipEpoch: membershipEpoch,
                isMember: isMember,
                lastReadAt: lastReadAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RoomEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RoomEntriesTable,
      RoomEntry,
      $$RoomEntriesTableFilterComposer,
      $$RoomEntriesTableOrderingComposer,
      $$RoomEntriesTableAnnotationComposer,
      $$RoomEntriesTableCreateCompanionBuilder,
      $$RoomEntriesTableUpdateCompanionBuilder,
      (RoomEntry, BaseReferences<_$AppDatabase, $RoomEntriesTable, RoomEntry>),
      RoomEntry,
      PrefetchHooks Function()
    >;
typedef $$RoomMemberEntriesTableCreateCompanionBuilder =
    RoomMemberEntriesCompanion Function({
      required String roomId,
      required String pubkey,
      Value<String?> displayName,
      required int addedAt,
      Value<int?> removedAt,
      Value<String> role,
      Value<int> rowid,
    });
typedef $$RoomMemberEntriesTableUpdateCompanionBuilder =
    RoomMemberEntriesCompanion Function({
      Value<String> roomId,
      Value<String> pubkey,
      Value<String?> displayName,
      Value<int> addedAt,
      Value<int?> removedAt,
      Value<String> role,
      Value<int> rowid,
    });

class $$RoomMemberEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $RoomMemberEntriesTable> {
  $$RoomMemberEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get removedAt => $composableBuilder(
    column: $table.removedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RoomMemberEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $RoomMemberEntriesTable> {
  $$RoomMemberEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get removedAt => $composableBuilder(
    column: $table.removedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get role => $composableBuilder(
    column: $table.role,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RoomMemberEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RoomMemberEntriesTable> {
  $$RoomMemberEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get roomId =>
      $composableBuilder(column: $table.roomId, builder: (column) => column);

  GeneratedColumn<String> get pubkey =>
      $composableBuilder(column: $table.pubkey, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<int> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<int> get removedAt =>
      $composableBuilder(column: $table.removedAt, builder: (column) => column);

  GeneratedColumn<String> get role =>
      $composableBuilder(column: $table.role, builder: (column) => column);
}

class $$RoomMemberEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RoomMemberEntriesTable,
          RoomMemberEntry,
          $$RoomMemberEntriesTableFilterComposer,
          $$RoomMemberEntriesTableOrderingComposer,
          $$RoomMemberEntriesTableAnnotationComposer,
          $$RoomMemberEntriesTableCreateCompanionBuilder,
          $$RoomMemberEntriesTableUpdateCompanionBuilder,
          (
            RoomMemberEntry,
            BaseReferences<
              _$AppDatabase,
              $RoomMemberEntriesTable,
              RoomMemberEntry
            >,
          ),
          RoomMemberEntry,
          PrefetchHooks Function()
        > {
  $$RoomMemberEntriesTableTableManager(
    _$AppDatabase db,
    $RoomMemberEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoomMemberEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoomMemberEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RoomMemberEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> roomId = const Value.absent(),
                Value<String> pubkey = const Value.absent(),
                Value<String?> displayName = const Value.absent(),
                Value<int> addedAt = const Value.absent(),
                Value<int?> removedAt = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RoomMemberEntriesCompanion(
                roomId: roomId,
                pubkey: pubkey,
                displayName: displayName,
                addedAt: addedAt,
                removedAt: removedAt,
                role: role,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String roomId,
                required String pubkey,
                Value<String?> displayName = const Value.absent(),
                required int addedAt,
                Value<int?> removedAt = const Value.absent(),
                Value<String> role = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RoomMemberEntriesCompanion.insert(
                roomId: roomId,
                pubkey: pubkey,
                displayName: displayName,
                addedAt: addedAt,
                removedAt: removedAt,
                role: role,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RoomMemberEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RoomMemberEntriesTable,
      RoomMemberEntry,
      $$RoomMemberEntriesTableFilterComposer,
      $$RoomMemberEntriesTableOrderingComposer,
      $$RoomMemberEntriesTableAnnotationComposer,
      $$RoomMemberEntriesTableCreateCompanionBuilder,
      $$RoomMemberEntriesTableUpdateCompanionBuilder,
      (
        RoomMemberEntry,
        BaseReferences<_$AppDatabase, $RoomMemberEntriesTable, RoomMemberEntry>,
      ),
      RoomMemberEntry,
      PrefetchHooks Function()
    >;
typedef $$RoomKeyHistoryEntriesTableCreateCompanionBuilder =
    RoomKeyHistoryEntriesCompanion Function({
      required String roomId,
      required int epoch,
      required Uint8List roomKey,
      required int validFrom,
      required int validUntil,
      Value<int> rowid,
    });
typedef $$RoomKeyHistoryEntriesTableUpdateCompanionBuilder =
    RoomKeyHistoryEntriesCompanion Function({
      Value<String> roomId,
      Value<int> epoch,
      Value<Uint8List> roomKey,
      Value<int> validFrom,
      Value<int> validUntil,
      Value<int> rowid,
    });

class $$RoomKeyHistoryEntriesTableFilterComposer
    extends Composer<_$AppDatabase, $RoomKeyHistoryEntriesTable> {
  $$RoomKeyHistoryEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get epoch => $composableBuilder(
    column: $table.epoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get roomKey => $composableBuilder(
    column: $table.roomKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get validFrom => $composableBuilder(
    column: $table.validFrom,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get validUntil => $composableBuilder(
    column: $table.validUntil,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RoomKeyHistoryEntriesTableOrderingComposer
    extends Composer<_$AppDatabase, $RoomKeyHistoryEntriesTable> {
  $$RoomKeyHistoryEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get epoch => $composableBuilder(
    column: $table.epoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get roomKey => $composableBuilder(
    column: $table.roomKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get validFrom => $composableBuilder(
    column: $table.validFrom,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get validUntil => $composableBuilder(
    column: $table.validUntil,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RoomKeyHistoryEntriesTableAnnotationComposer
    extends Composer<_$AppDatabase, $RoomKeyHistoryEntriesTable> {
  $$RoomKeyHistoryEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get roomId =>
      $composableBuilder(column: $table.roomId, builder: (column) => column);

  GeneratedColumn<int> get epoch =>
      $composableBuilder(column: $table.epoch, builder: (column) => column);

  GeneratedColumn<Uint8List> get roomKey =>
      $composableBuilder(column: $table.roomKey, builder: (column) => column);

  GeneratedColumn<int> get validFrom =>
      $composableBuilder(column: $table.validFrom, builder: (column) => column);

  GeneratedColumn<int> get validUntil => $composableBuilder(
    column: $table.validUntil,
    builder: (column) => column,
  );
}

class $$RoomKeyHistoryEntriesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RoomKeyHistoryEntriesTable,
          RoomKeyHistoryEntry,
          $$RoomKeyHistoryEntriesTableFilterComposer,
          $$RoomKeyHistoryEntriesTableOrderingComposer,
          $$RoomKeyHistoryEntriesTableAnnotationComposer,
          $$RoomKeyHistoryEntriesTableCreateCompanionBuilder,
          $$RoomKeyHistoryEntriesTableUpdateCompanionBuilder,
          (
            RoomKeyHistoryEntry,
            BaseReferences<
              _$AppDatabase,
              $RoomKeyHistoryEntriesTable,
              RoomKeyHistoryEntry
            >,
          ),
          RoomKeyHistoryEntry,
          PrefetchHooks Function()
        > {
  $$RoomKeyHistoryEntriesTableTableManager(
    _$AppDatabase db,
    $RoomKeyHistoryEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoomKeyHistoryEntriesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$RoomKeyHistoryEntriesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$RoomKeyHistoryEntriesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> roomId = const Value.absent(),
                Value<int> epoch = const Value.absent(),
                Value<Uint8List> roomKey = const Value.absent(),
                Value<int> validFrom = const Value.absent(),
                Value<int> validUntil = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RoomKeyHistoryEntriesCompanion(
                roomId: roomId,
                epoch: epoch,
                roomKey: roomKey,
                validFrom: validFrom,
                validUntil: validUntil,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String roomId,
                required int epoch,
                required Uint8List roomKey,
                required int validFrom,
                required int validUntil,
                Value<int> rowid = const Value.absent(),
              }) => RoomKeyHistoryEntriesCompanion.insert(
                roomId: roomId,
                epoch: epoch,
                roomKey: roomKey,
                validFrom: validFrom,
                validUntil: validUntil,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RoomKeyHistoryEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RoomKeyHistoryEntriesTable,
      RoomKeyHistoryEntry,
      $$RoomKeyHistoryEntriesTableFilterComposer,
      $$RoomKeyHistoryEntriesTableOrderingComposer,
      $$RoomKeyHistoryEntriesTableAnnotationComposer,
      $$RoomKeyHistoryEntriesTableCreateCompanionBuilder,
      $$RoomKeyHistoryEntriesTableUpdateCompanionBuilder,
      (
        RoomKeyHistoryEntry,
        BaseReferences<
          _$AppDatabase,
          $RoomKeyHistoryEntriesTable,
          RoomKeyHistoryEntry
        >,
      ),
      RoomKeyHistoryEntry,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$IdentityEntriesTableTableManager get identityEntries =>
      $$IdentityEntriesTableTableManager(_db, _db.identityEntries);
  $$FollowEntriesTableTableManager get followEntries =>
      $$FollowEntriesTableTableManager(_db, _db.followEntries);
  $$EventEntriesTableTableManager get eventEntries =>
      $$EventEntriesTableTableManager(_db, _db.eventEntries);
  $$MediaCacheEntriesTableTableManager get mediaCacheEntries =>
      $$MediaCacheEntriesTableTableManager(_db, _db.mediaCacheEntries);
  $$InboundFollowRequestEntriesTableTableManager
  get inboundFollowRequestEntries =>
      $$InboundFollowRequestEntriesTableTableManager(
        _db,
        _db.inboundFollowRequestEntries,
      );
  $$OutboundFollowRequestEntriesTableTableManager
  get outboundFollowRequestEntries =>
      $$OutboundFollowRequestEntriesTableTableManager(
        _db,
        _db.outboundFollowRequestEntries,
      );
  $$OutboundQueueEntriesTableTableManager get outboundQueueEntries =>
      $$OutboundQueueEntriesTableTableManager(_db, _db.outboundQueueEntries);
  $$UnknownEnvelopeItemEntriesTableTableManager
  get unknownEnvelopeItemEntries =>
      $$UnknownEnvelopeItemEntriesTableTableManager(
        _db,
        _db.unknownEnvelopeItemEntries,
      );
  $$FeedKeyHistoryEntriesTableTableManager get feedKeyHistoryEntries =>
      $$FeedKeyHistoryEntriesTableTableManager(_db, _db.feedKeyHistoryEntries);
  $$FollowFeedKeyHistoryEntriesTableTableManager
  get followFeedKeyHistoryEntries =>
      $$FollowFeedKeyHistoryEntriesTableTableManager(
        _db,
        _db.followFeedKeyHistoryEntries,
      );
  $$PendingKeyDistributionEntriesTableTableManager
  get pendingKeyDistributionEntries =>
      $$PendingKeyDistributionEntriesTableTableManager(
        _db,
        _db.pendingKeyDistributionEntries,
      );
  $$PairedRelayEntriesTableTableManager get pairedRelayEntries =>
      $$PairedRelayEntriesTableTableManager(_db, _db.pairedRelayEntries);
  $$PendingCardDistributionEntriesTableTableManager
  get pendingCardDistributionEntries =>
      $$PendingCardDistributionEntriesTableTableManager(
        _db,
        _db.pendingCardDistributionEntries,
      );
  $$RelayFanoutStateEntriesTableTableManager get relayFanoutStateEntries =>
      $$RelayFanoutStateEntriesTableTableManager(
        _db,
        _db.relayFanoutStateEntries,
      );
  $$VoiceRoomEntriesTableTableManager get voiceRoomEntries =>
      $$VoiceRoomEntriesTableTableManager(_db, _db.voiceRoomEntries);
  $$VoiceRoomParticipantEntriesTableTableManager
  get voiceRoomParticipantEntries =>
      $$VoiceRoomParticipantEntriesTableTableManager(
        _db,
        _db.voiceRoomParticipantEntries,
      );
  $$RoomEntriesTableTableManager get roomEntries =>
      $$RoomEntriesTableTableManager(_db, _db.roomEntries);
  $$RoomMemberEntriesTableTableManager get roomMemberEntries =>
      $$RoomMemberEntriesTableTableManager(_db, _db.roomMemberEntries);
  $$RoomKeyHistoryEntriesTableTableManager get roomKeyHistoryEntries =>
      $$RoomKeyHistoryEntriesTableTableManager(_db, _db.roomKeyHistoryEntries);
}
