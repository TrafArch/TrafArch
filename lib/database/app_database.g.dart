// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SavedCardsTable extends SavedCards
    with TableInfo<$SavedCardsTable, SavedCard> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavedCardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cardFingerprintMeta = const VerificationMeta(
    'cardFingerprint',
  );
  @override
  late final GeneratedColumn<String> cardFingerprint = GeneratedColumn<String>(
    'card_fingerprint',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _cardTypeMeta = const VerificationMeta(
    'cardType',
  );
  @override
  late final GeneratedColumn<String> cardType = GeneratedColumn<String>(
    'card_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _officialNameMeta = const VerificationMeta(
    'officialName',
  );
  @override
  late final GeneratedColumn<String> officialName = GeneratedColumn<String>(
    'official_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _customNameMeta = const VerificationMeta(
    'customName',
  );
  @override
  late final GeneratedColumn<String> customName = GeneratedColumn<String>(
    'custom_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _issuerNameMeta = const VerificationMeta(
    'issuerName',
  );
  @override
  late final GeneratedColumn<String> issuerName = GeneratedColumn<String>(
    'issuer_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cityNameMeta = const VerificationMeta(
    'cityName',
  );
  @override
  late final GeneratedColumn<String> cityName = GeneratedColumn<String>(
    'city_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _identificationSourceMeta =
      const VerificationMeta('identificationSource');
  @override
  late final GeneratedColumn<String> identificationSource =
      GeneratedColumn<String>(
        'identification_source',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('unknown'),
      );
  static const VerificationMeta _identificationConfidenceMeta =
      const VerificationMeta('identificationConfidence');
  @override
  late final GeneratedColumn<double> identificationConfidence =
      GeneratedColumn<double>(
        'identification_confidence',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _cardNumberMeta = const VerificationMeta(
    'cardNumber',
  );
  @override
  late final GeneratedColumn<String> cardNumber = GeneratedColumn<String>(
    'card_number',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cardNumberMaskedMeta = const VerificationMeta(
    'cardNumberMasked',
  );
  @override
  late final GeneratedColumn<String> cardNumberMasked = GeneratedColumn<String>(
    'card_number_masked',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _balanceFenMeta = const VerificationMeta(
    'balanceFen',
  );
  @override
  late final GeneratedColumn<int> balanceFen = GeneratedColumn<int>(
    'balance_fen',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _currencyCodeMeta = const VerificationMeta(
    'currencyCode',
  );
  @override
  late final GeneratedColumn<String> currencyCode = GeneratedColumn<String>(
    'currency_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _transactionCountMeta = const VerificationMeta(
    'transactionCount',
  );
  @override
  late final GeneratedColumn<int> transactionCount = GeneratedColumn<int>(
    'transaction_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sessionDataJsonMeta = const VerificationMeta(
    'sessionDataJson',
  );
  @override
  late final GeneratedColumn<String> sessionDataJson = GeneratedColumn<String>(
    'session_data_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cardImagePathMeta = const VerificationMeta(
    'cardImagePath',
  );
  @override
  late final GeneratedColumn<String> cardImagePath = GeneratedColumn<String>(
    'card_image_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastReadAtMeta = const VerificationMeta(
    'lastReadAt',
  );
  @override
  late final GeneratedColumn<int> lastReadAt = GeneratedColumn<int>(
    'last_read_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
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
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    cardFingerprint,
    cardType,
    officialName,
    customName,
    issuerName,
    cityName,
    identificationSource,
    identificationConfidence,
    cardNumber,
    cardNumberMasked,
    balanceFen,
    currencyCode,
    transactionCount,
    sessionDataJson,
    cardImagePath,
    lastReadAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'saved_cards';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavedCard> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('card_fingerprint')) {
      context.handle(
        _cardFingerprintMeta,
        cardFingerprint.isAcceptableOrUnknown(
          data['card_fingerprint']!,
          _cardFingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cardFingerprintMeta);
    }
    if (data.containsKey('card_type')) {
      context.handle(
        _cardTypeMeta,
        cardType.isAcceptableOrUnknown(data['card_type']!, _cardTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_cardTypeMeta);
    }
    if (data.containsKey('official_name')) {
      context.handle(
        _officialNameMeta,
        officialName.isAcceptableOrUnknown(
          data['official_name']!,
          _officialNameMeta,
        ),
      );
    }
    if (data.containsKey('custom_name')) {
      context.handle(
        _customNameMeta,
        customName.isAcceptableOrUnknown(data['custom_name']!, _customNameMeta),
      );
    }
    if (data.containsKey('issuer_name')) {
      context.handle(
        _issuerNameMeta,
        issuerName.isAcceptableOrUnknown(data['issuer_name']!, _issuerNameMeta),
      );
    }
    if (data.containsKey('city_name')) {
      context.handle(
        _cityNameMeta,
        cityName.isAcceptableOrUnknown(data['city_name']!, _cityNameMeta),
      );
    }
    if (data.containsKey('identification_source')) {
      context.handle(
        _identificationSourceMeta,
        identificationSource.isAcceptableOrUnknown(
          data['identification_source']!,
          _identificationSourceMeta,
        ),
      );
    }
    if (data.containsKey('identification_confidence')) {
      context.handle(
        _identificationConfidenceMeta,
        identificationConfidence.isAcceptableOrUnknown(
          data['identification_confidence']!,
          _identificationConfidenceMeta,
        ),
      );
    }
    if (data.containsKey('card_number')) {
      context.handle(
        _cardNumberMeta,
        cardNumber.isAcceptableOrUnknown(data['card_number']!, _cardNumberMeta),
      );
    }
    if (data.containsKey('card_number_masked')) {
      context.handle(
        _cardNumberMaskedMeta,
        cardNumberMasked.isAcceptableOrUnknown(
          data['card_number_masked']!,
          _cardNumberMaskedMeta,
        ),
      );
    }
    if (data.containsKey('balance_fen')) {
      context.handle(
        _balanceFenMeta,
        balanceFen.isAcceptableOrUnknown(data['balance_fen']!, _balanceFenMeta),
      );
    }
    if (data.containsKey('currency_code')) {
      context.handle(
        _currencyCodeMeta,
        currencyCode.isAcceptableOrUnknown(
          data['currency_code']!,
          _currencyCodeMeta,
        ),
      );
    }
    if (data.containsKey('transaction_count')) {
      context.handle(
        _transactionCountMeta,
        transactionCount.isAcceptableOrUnknown(
          data['transaction_count']!,
          _transactionCountMeta,
        ),
      );
    }
    if (data.containsKey('session_data_json')) {
      context.handle(
        _sessionDataJsonMeta,
        sessionDataJson.isAcceptableOrUnknown(
          data['session_data_json']!,
          _sessionDataJsonMeta,
        ),
      );
    }
    if (data.containsKey('card_image_path')) {
      context.handle(
        _cardImagePathMeta,
        cardImagePath.isAcceptableOrUnknown(
          data['card_image_path']!,
          _cardImagePathMeta,
        ),
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
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavedCard map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavedCard(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      cardFingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_fingerprint'],
      )!,
      cardType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_type'],
      )!,
      officialName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}official_name'],
      ),
      customName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}custom_name'],
      ),
      issuerName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}issuer_name'],
      ),
      cityName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}city_name'],
      ),
      identificationSource: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identification_source'],
      )!,
      identificationConfidence: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}identification_confidence'],
      ),
      cardNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_number'],
      ),
      cardNumberMasked: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_number_masked'],
      ),
      balanceFen: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}balance_fen'],
      ),
      currencyCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency_code'],
      ),
      transactionCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}transaction_count'],
      ),
      sessionDataJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_data_json'],
      ),
      cardImagePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_image_path'],
      ),
      lastReadAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_read_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SavedCardsTable createAlias(String alias) {
    return $SavedCardsTable(attachedDatabase, alias);
  }
}

class SavedCard extends DataClass implements Insertable<SavedCard> {
  /// App 内部卡片 ID（uuid v4）。
  final String id;

  /// 稳定的本地卡片指纹（唯一，关联同一张卡的历次读取）。
  final String cardFingerprint;

  /// 卡型（CardTypes 常量：china_tunion / city_union / octopus_tunion / …）。
  final String cardType;

  /// 自动识别的正式卡名（如「福路通」）；无可靠证据时为 NULL。
  final String? officialName;

  /// 用户自定义名称；为空时展示层回退正式卡名。
  final String? customName;

  /// 发卡机构或运营方。
  final String? issuerName;

  /// 已确认的城市或地区。
  final String? cityName;

  /// 名称的识别依据（CardIdentificationSources 常量）。
  final String identificationSource;

  /// 识别置信度（仅有明确规则依据时记录）。
  final double? identificationConfidence;

  /// 卡号（完整存储，不做脱敏）：交通联合为逻辑卡号（应用序列号去前导 0），
  /// 城市一卡通为 0x15 公共应用基本信息的应用序列号；未读到卡号时为 NULL。
  final String? cardNumber;

  /// 脱敏卡号（保留末 4 位，其余以 * 代替）；未读到卡号时为 NULL。
  final String? cardNumberMasked;

  /// 最近一次读取的余额快照（分）；未读到余额时为 NULL（不猜测）。
  final int? balanceFen;

  /// 余额快照的货币代码（ISO 4217，如 CNY / HKD）；未读到余额时为 NULL，
  /// 展示层按人民币缺省口径回退（与钱包货币判定一致）。
  final String? currencyCode;

  /// 最近一次读取解析到的交易记录条数；未解析到交易文件时为 NULL。
  final int? transactionCount;

  /// 最近一次保存到档案的行程记录快照（JSON：CardSessionSnapshot——
  /// 交易行程 / 0x1A 进出站与上下车记录 / 读取时卡片城市代码）；
  /// 暂无记录数据时为 NULL（保存时不写入、不覆盖既有快照）。
  final String? sessionDataJson;

  /// 卡面图片路径（用户提供的图片 / 已验证的本地卡面资源）；
  /// 未匹配时为空，展示层使用统一占位图（不猜测卡面）。
  final String? cardImagePath;

  /// 最近一次读取时间（毫秒时间戳）。
  final int? lastReadAt;

  /// 创建时间（毫秒时间戳）。
  final int createdAt;

  /// 更新时间（毫秒时间戳）。
  final int updatedAt;
  const SavedCard({
    required this.id,
    required this.cardFingerprint,
    required this.cardType,
    this.officialName,
    this.customName,
    this.issuerName,
    this.cityName,
    required this.identificationSource,
    this.identificationConfidence,
    this.cardNumber,
    this.cardNumberMasked,
    this.balanceFen,
    this.currencyCode,
    this.transactionCount,
    this.sessionDataJson,
    this.cardImagePath,
    this.lastReadAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['card_fingerprint'] = Variable<String>(cardFingerprint);
    map['card_type'] = Variable<String>(cardType);
    if (!nullToAbsent || officialName != null) {
      map['official_name'] = Variable<String>(officialName);
    }
    if (!nullToAbsent || customName != null) {
      map['custom_name'] = Variable<String>(customName);
    }
    if (!nullToAbsent || issuerName != null) {
      map['issuer_name'] = Variable<String>(issuerName);
    }
    if (!nullToAbsent || cityName != null) {
      map['city_name'] = Variable<String>(cityName);
    }
    map['identification_source'] = Variable<String>(identificationSource);
    if (!nullToAbsent || identificationConfidence != null) {
      map['identification_confidence'] = Variable<double>(
        identificationConfidence,
      );
    }
    if (!nullToAbsent || cardNumber != null) {
      map['card_number'] = Variable<String>(cardNumber);
    }
    if (!nullToAbsent || cardNumberMasked != null) {
      map['card_number_masked'] = Variable<String>(cardNumberMasked);
    }
    if (!nullToAbsent || balanceFen != null) {
      map['balance_fen'] = Variable<int>(balanceFen);
    }
    if (!nullToAbsent || currencyCode != null) {
      map['currency_code'] = Variable<String>(currencyCode);
    }
    if (!nullToAbsent || transactionCount != null) {
      map['transaction_count'] = Variable<int>(transactionCount);
    }
    if (!nullToAbsent || sessionDataJson != null) {
      map['session_data_json'] = Variable<String>(sessionDataJson);
    }
    if (!nullToAbsent || cardImagePath != null) {
      map['card_image_path'] = Variable<String>(cardImagePath);
    }
    if (!nullToAbsent || lastReadAt != null) {
      map['last_read_at'] = Variable<int>(lastReadAt);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  SavedCardsCompanion toCompanion(bool nullToAbsent) {
    return SavedCardsCompanion(
      id: Value(id),
      cardFingerprint: Value(cardFingerprint),
      cardType: Value(cardType),
      officialName: officialName == null && nullToAbsent
          ? const Value.absent()
          : Value(officialName),
      customName: customName == null && nullToAbsent
          ? const Value.absent()
          : Value(customName),
      issuerName: issuerName == null && nullToAbsent
          ? const Value.absent()
          : Value(issuerName),
      cityName: cityName == null && nullToAbsent
          ? const Value.absent()
          : Value(cityName),
      identificationSource: Value(identificationSource),
      identificationConfidence: identificationConfidence == null && nullToAbsent
          ? const Value.absent()
          : Value(identificationConfidence),
      cardNumber: cardNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(cardNumber),
      cardNumberMasked: cardNumberMasked == null && nullToAbsent
          ? const Value.absent()
          : Value(cardNumberMasked),
      balanceFen: balanceFen == null && nullToAbsent
          ? const Value.absent()
          : Value(balanceFen),
      currencyCode: currencyCode == null && nullToAbsent
          ? const Value.absent()
          : Value(currencyCode),
      transactionCount: transactionCount == null && nullToAbsent
          ? const Value.absent()
          : Value(transactionCount),
      sessionDataJson: sessionDataJson == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionDataJson),
      cardImagePath: cardImagePath == null && nullToAbsent
          ? const Value.absent()
          : Value(cardImagePath),
      lastReadAt: lastReadAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastReadAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SavedCard.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavedCard(
      id: serializer.fromJson<String>(json['id']),
      cardFingerprint: serializer.fromJson<String>(json['cardFingerprint']),
      cardType: serializer.fromJson<String>(json['cardType']),
      officialName: serializer.fromJson<String?>(json['officialName']),
      customName: serializer.fromJson<String?>(json['customName']),
      issuerName: serializer.fromJson<String?>(json['issuerName']),
      cityName: serializer.fromJson<String?>(json['cityName']),
      identificationSource: serializer.fromJson<String>(
        json['identificationSource'],
      ),
      identificationConfidence: serializer.fromJson<double?>(
        json['identificationConfidence'],
      ),
      cardNumber: serializer.fromJson<String?>(json['cardNumber']),
      cardNumberMasked: serializer.fromJson<String?>(json['cardNumberMasked']),
      balanceFen: serializer.fromJson<int?>(json['balanceFen']),
      currencyCode: serializer.fromJson<String?>(json['currencyCode']),
      transactionCount: serializer.fromJson<int?>(json['transactionCount']),
      sessionDataJson: serializer.fromJson<String?>(json['sessionDataJson']),
      cardImagePath: serializer.fromJson<String?>(json['cardImagePath']),
      lastReadAt: serializer.fromJson<int?>(json['lastReadAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'cardFingerprint': serializer.toJson<String>(cardFingerprint),
      'cardType': serializer.toJson<String>(cardType),
      'officialName': serializer.toJson<String?>(officialName),
      'customName': serializer.toJson<String?>(customName),
      'issuerName': serializer.toJson<String?>(issuerName),
      'cityName': serializer.toJson<String?>(cityName),
      'identificationSource': serializer.toJson<String>(identificationSource),
      'identificationConfidence': serializer.toJson<double?>(
        identificationConfidence,
      ),
      'cardNumber': serializer.toJson<String?>(cardNumber),
      'cardNumberMasked': serializer.toJson<String?>(cardNumberMasked),
      'balanceFen': serializer.toJson<int?>(balanceFen),
      'currencyCode': serializer.toJson<String?>(currencyCode),
      'transactionCount': serializer.toJson<int?>(transactionCount),
      'sessionDataJson': serializer.toJson<String?>(sessionDataJson),
      'cardImagePath': serializer.toJson<String?>(cardImagePath),
      'lastReadAt': serializer.toJson<int?>(lastReadAt),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  SavedCard copyWith({
    String? id,
    String? cardFingerprint,
    String? cardType,
    Value<String?> officialName = const Value.absent(),
    Value<String?> customName = const Value.absent(),
    Value<String?> issuerName = const Value.absent(),
    Value<String?> cityName = const Value.absent(),
    String? identificationSource,
    Value<double?> identificationConfidence = const Value.absent(),
    Value<String?> cardNumber = const Value.absent(),
    Value<String?> cardNumberMasked = const Value.absent(),
    Value<int?> balanceFen = const Value.absent(),
    Value<String?> currencyCode = const Value.absent(),
    Value<int?> transactionCount = const Value.absent(),
    Value<String?> sessionDataJson = const Value.absent(),
    Value<String?> cardImagePath = const Value.absent(),
    Value<int?> lastReadAt = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => SavedCard(
    id: id ?? this.id,
    cardFingerprint: cardFingerprint ?? this.cardFingerprint,
    cardType: cardType ?? this.cardType,
    officialName: officialName.present ? officialName.value : this.officialName,
    customName: customName.present ? customName.value : this.customName,
    issuerName: issuerName.present ? issuerName.value : this.issuerName,
    cityName: cityName.present ? cityName.value : this.cityName,
    identificationSource: identificationSource ?? this.identificationSource,
    identificationConfidence: identificationConfidence.present
        ? identificationConfidence.value
        : this.identificationConfidence,
    cardNumber: cardNumber.present ? cardNumber.value : this.cardNumber,
    cardNumberMasked: cardNumberMasked.present
        ? cardNumberMasked.value
        : this.cardNumberMasked,
    balanceFen: balanceFen.present ? balanceFen.value : this.balanceFen,
    currencyCode: currencyCode.present ? currencyCode.value : this.currencyCode,
    transactionCount: transactionCount.present
        ? transactionCount.value
        : this.transactionCount,
    sessionDataJson: sessionDataJson.present
        ? sessionDataJson.value
        : this.sessionDataJson,
    cardImagePath: cardImagePath.present
        ? cardImagePath.value
        : this.cardImagePath,
    lastReadAt: lastReadAt.present ? lastReadAt.value : this.lastReadAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SavedCard copyWithCompanion(SavedCardsCompanion data) {
    return SavedCard(
      id: data.id.present ? data.id.value : this.id,
      cardFingerprint: data.cardFingerprint.present
          ? data.cardFingerprint.value
          : this.cardFingerprint,
      cardType: data.cardType.present ? data.cardType.value : this.cardType,
      officialName: data.officialName.present
          ? data.officialName.value
          : this.officialName,
      customName: data.customName.present
          ? data.customName.value
          : this.customName,
      issuerName: data.issuerName.present
          ? data.issuerName.value
          : this.issuerName,
      cityName: data.cityName.present ? data.cityName.value : this.cityName,
      identificationSource: data.identificationSource.present
          ? data.identificationSource.value
          : this.identificationSource,
      identificationConfidence: data.identificationConfidence.present
          ? data.identificationConfidence.value
          : this.identificationConfidence,
      cardNumber: data.cardNumber.present
          ? data.cardNumber.value
          : this.cardNumber,
      cardNumberMasked: data.cardNumberMasked.present
          ? data.cardNumberMasked.value
          : this.cardNumberMasked,
      balanceFen: data.balanceFen.present
          ? data.balanceFen.value
          : this.balanceFen,
      currencyCode: data.currencyCode.present
          ? data.currencyCode.value
          : this.currencyCode,
      transactionCount: data.transactionCount.present
          ? data.transactionCount.value
          : this.transactionCount,
      sessionDataJson: data.sessionDataJson.present
          ? data.sessionDataJson.value
          : this.sessionDataJson,
      cardImagePath: data.cardImagePath.present
          ? data.cardImagePath.value
          : this.cardImagePath,
      lastReadAt: data.lastReadAt.present
          ? data.lastReadAt.value
          : this.lastReadAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavedCard(')
          ..write('id: $id, ')
          ..write('cardFingerprint: $cardFingerprint, ')
          ..write('cardType: $cardType, ')
          ..write('officialName: $officialName, ')
          ..write('customName: $customName, ')
          ..write('issuerName: $issuerName, ')
          ..write('cityName: $cityName, ')
          ..write('identificationSource: $identificationSource, ')
          ..write('identificationConfidence: $identificationConfidence, ')
          ..write('cardNumber: $cardNumber, ')
          ..write('cardNumberMasked: $cardNumberMasked, ')
          ..write('balanceFen: $balanceFen, ')
          ..write('currencyCode: $currencyCode, ')
          ..write('transactionCount: $transactionCount, ')
          ..write('sessionDataJson: $sessionDataJson, ')
          ..write('cardImagePath: $cardImagePath, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    cardFingerprint,
    cardType,
    officialName,
    customName,
    issuerName,
    cityName,
    identificationSource,
    identificationConfidence,
    cardNumber,
    cardNumberMasked,
    balanceFen,
    currencyCode,
    transactionCount,
    sessionDataJson,
    cardImagePath,
    lastReadAt,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavedCard &&
          other.id == this.id &&
          other.cardFingerprint == this.cardFingerprint &&
          other.cardType == this.cardType &&
          other.officialName == this.officialName &&
          other.customName == this.customName &&
          other.issuerName == this.issuerName &&
          other.cityName == this.cityName &&
          other.identificationSource == this.identificationSource &&
          other.identificationConfidence == this.identificationConfidence &&
          other.cardNumber == this.cardNumber &&
          other.cardNumberMasked == this.cardNumberMasked &&
          other.balanceFen == this.balanceFen &&
          other.currencyCode == this.currencyCode &&
          other.transactionCount == this.transactionCount &&
          other.sessionDataJson == this.sessionDataJson &&
          other.cardImagePath == this.cardImagePath &&
          other.lastReadAt == this.lastReadAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SavedCardsCompanion extends UpdateCompanion<SavedCard> {
  final Value<String> id;
  final Value<String> cardFingerprint;
  final Value<String> cardType;
  final Value<String?> officialName;
  final Value<String?> customName;
  final Value<String?> issuerName;
  final Value<String?> cityName;
  final Value<String> identificationSource;
  final Value<double?> identificationConfidence;
  final Value<String?> cardNumber;
  final Value<String?> cardNumberMasked;
  final Value<int?> balanceFen;
  final Value<String?> currencyCode;
  final Value<int?> transactionCount;
  final Value<String?> sessionDataJson;
  final Value<String?> cardImagePath;
  final Value<int?> lastReadAt;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const SavedCardsCompanion({
    this.id = const Value.absent(),
    this.cardFingerprint = const Value.absent(),
    this.cardType = const Value.absent(),
    this.officialName = const Value.absent(),
    this.customName = const Value.absent(),
    this.issuerName = const Value.absent(),
    this.cityName = const Value.absent(),
    this.identificationSource = const Value.absent(),
    this.identificationConfidence = const Value.absent(),
    this.cardNumber = const Value.absent(),
    this.cardNumberMasked = const Value.absent(),
    this.balanceFen = const Value.absent(),
    this.currencyCode = const Value.absent(),
    this.transactionCount = const Value.absent(),
    this.sessionDataJson = const Value.absent(),
    this.cardImagePath = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavedCardsCompanion.insert({
    required String id,
    required String cardFingerprint,
    required String cardType,
    this.officialName = const Value.absent(),
    this.customName = const Value.absent(),
    this.issuerName = const Value.absent(),
    this.cityName = const Value.absent(),
    this.identificationSource = const Value.absent(),
    this.identificationConfidence = const Value.absent(),
    this.cardNumber = const Value.absent(),
    this.cardNumberMasked = const Value.absent(),
    this.balanceFen = const Value.absent(),
    this.currencyCode = const Value.absent(),
    this.transactionCount = const Value.absent(),
    this.sessionDataJson = const Value.absent(),
    this.cardImagePath = const Value.absent(),
    this.lastReadAt = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       cardFingerprint = Value(cardFingerprint),
       cardType = Value(cardType),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SavedCard> custom({
    Expression<String>? id,
    Expression<String>? cardFingerprint,
    Expression<String>? cardType,
    Expression<String>? officialName,
    Expression<String>? customName,
    Expression<String>? issuerName,
    Expression<String>? cityName,
    Expression<String>? identificationSource,
    Expression<double>? identificationConfidence,
    Expression<String>? cardNumber,
    Expression<String>? cardNumberMasked,
    Expression<int>? balanceFen,
    Expression<String>? currencyCode,
    Expression<int>? transactionCount,
    Expression<String>? sessionDataJson,
    Expression<String>? cardImagePath,
    Expression<int>? lastReadAt,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cardFingerprint != null) 'card_fingerprint': cardFingerprint,
      if (cardType != null) 'card_type': cardType,
      if (officialName != null) 'official_name': officialName,
      if (customName != null) 'custom_name': customName,
      if (issuerName != null) 'issuer_name': issuerName,
      if (cityName != null) 'city_name': cityName,
      if (identificationSource != null)
        'identification_source': identificationSource,
      if (identificationConfidence != null)
        'identification_confidence': identificationConfidence,
      if (cardNumber != null) 'card_number': cardNumber,
      if (cardNumberMasked != null) 'card_number_masked': cardNumberMasked,
      if (balanceFen != null) 'balance_fen': balanceFen,
      if (currencyCode != null) 'currency_code': currencyCode,
      if (transactionCount != null) 'transaction_count': transactionCount,
      if (sessionDataJson != null) 'session_data_json': sessionDataJson,
      if (cardImagePath != null) 'card_image_path': cardImagePath,
      if (lastReadAt != null) 'last_read_at': lastReadAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavedCardsCompanion copyWith({
    Value<String>? id,
    Value<String>? cardFingerprint,
    Value<String>? cardType,
    Value<String?>? officialName,
    Value<String?>? customName,
    Value<String?>? issuerName,
    Value<String?>? cityName,
    Value<String>? identificationSource,
    Value<double?>? identificationConfidence,
    Value<String?>? cardNumber,
    Value<String?>? cardNumberMasked,
    Value<int?>? balanceFen,
    Value<String?>? currencyCode,
    Value<int?>? transactionCount,
    Value<String?>? sessionDataJson,
    Value<String?>? cardImagePath,
    Value<int?>? lastReadAt,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return SavedCardsCompanion(
      id: id ?? this.id,
      cardFingerprint: cardFingerprint ?? this.cardFingerprint,
      cardType: cardType ?? this.cardType,
      officialName: officialName ?? this.officialName,
      customName: customName ?? this.customName,
      issuerName: issuerName ?? this.issuerName,
      cityName: cityName ?? this.cityName,
      identificationSource: identificationSource ?? this.identificationSource,
      identificationConfidence:
          identificationConfidence ?? this.identificationConfidence,
      cardNumber: cardNumber ?? this.cardNumber,
      cardNumberMasked: cardNumberMasked ?? this.cardNumberMasked,
      balanceFen: balanceFen ?? this.balanceFen,
      currencyCode: currencyCode ?? this.currencyCode,
      transactionCount: transactionCount ?? this.transactionCount,
      sessionDataJson: sessionDataJson ?? this.sessionDataJson,
      cardImagePath: cardImagePath ?? this.cardImagePath,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (cardFingerprint.present) {
      map['card_fingerprint'] = Variable<String>(cardFingerprint.value);
    }
    if (cardType.present) {
      map['card_type'] = Variable<String>(cardType.value);
    }
    if (officialName.present) {
      map['official_name'] = Variable<String>(officialName.value);
    }
    if (customName.present) {
      map['custom_name'] = Variable<String>(customName.value);
    }
    if (issuerName.present) {
      map['issuer_name'] = Variable<String>(issuerName.value);
    }
    if (cityName.present) {
      map['city_name'] = Variable<String>(cityName.value);
    }
    if (identificationSource.present) {
      map['identification_source'] = Variable<String>(
        identificationSource.value,
      );
    }
    if (identificationConfidence.present) {
      map['identification_confidence'] = Variable<double>(
        identificationConfidence.value,
      );
    }
    if (cardNumber.present) {
      map['card_number'] = Variable<String>(cardNumber.value);
    }
    if (cardNumberMasked.present) {
      map['card_number_masked'] = Variable<String>(cardNumberMasked.value);
    }
    if (balanceFen.present) {
      map['balance_fen'] = Variable<int>(balanceFen.value);
    }
    if (currencyCode.present) {
      map['currency_code'] = Variable<String>(currencyCode.value);
    }
    if (transactionCount.present) {
      map['transaction_count'] = Variable<int>(transactionCount.value);
    }
    if (sessionDataJson.present) {
      map['session_data_json'] = Variable<String>(sessionDataJson.value);
    }
    if (cardImagePath.present) {
      map['card_image_path'] = Variable<String>(cardImagePath.value);
    }
    if (lastReadAt.present) {
      map['last_read_at'] = Variable<int>(lastReadAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavedCardsCompanion(')
          ..write('id: $id, ')
          ..write('cardFingerprint: $cardFingerprint, ')
          ..write('cardType: $cardType, ')
          ..write('officialName: $officialName, ')
          ..write('customName: $customName, ')
          ..write('issuerName: $issuerName, ')
          ..write('cityName: $cityName, ')
          ..write('identificationSource: $identificationSource, ')
          ..write('identificationConfidence: $identificationConfidence, ')
          ..write('cardNumber: $cardNumber, ')
          ..write('cardNumberMasked: $cardNumberMasked, ')
          ..write('balanceFen: $balanceFen, ')
          ..write('currencyCode: $currencyCode, ')
          ..write('transactionCount: $transactionCount, ')
          ..write('sessionDataJson: $sessionDataJson, ')
          ..write('cardImagePath: $cardImagePath, ')
          ..write('lastReadAt: $lastReadAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SavedCardsTable savedCards = $SavedCardsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [savedCards];
}

typedef $$SavedCardsTableCreateCompanionBuilder = SavedCardsCompanion Function({
  required String id,
  required String cardFingerprint,
  required String cardType,
  Value<String?> officialName,
  Value<String?> customName,
  Value<String?> issuerName,
  Value<String?> cityName,
  Value<String> identificationSource,
  Value<double?> identificationConfidence,
  Value<String?> cardNumber,
  Value<String?> cardNumberMasked,
  Value<int?> balanceFen,
  Value<String?> currencyCode,
  Value<int?> transactionCount,
  Value<String?> sessionDataJson,
  Value<String?> cardImagePath,
  Value<int?> lastReadAt,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$SavedCardsTableUpdateCompanionBuilder = SavedCardsCompanion Function({
  Value<String> id,
  Value<String> cardFingerprint,
  Value<String> cardType,
  Value<String?> officialName,
  Value<String?> customName,
  Value<String?> issuerName,
  Value<String?> cityName,
  Value<String> identificationSource,
  Value<double?> identificationConfidence,
  Value<String?> cardNumber,
  Value<String?> cardNumberMasked,
  Value<int?> balanceFen,
  Value<String?> currencyCode,
  Value<int?> transactionCount,
  Value<String?> sessionDataJson,
  Value<String?> cardImagePath,
  Value<int?> lastReadAt,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

class $$SavedCardsTableFilterComposer
    extends Composer<_$AppDatabase, $SavedCardsTable> {
  $$SavedCardsTableFilterComposer({
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

  ColumnFilters<String> get cardFingerprint => $composableBuilder(
    column: $table.cardFingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardType => $composableBuilder(
    column: $table.cardType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get officialName => $composableBuilder(
    column: $table.officialName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customName => $composableBuilder(
    column: $table.customName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get issuerName => $composableBuilder(
    column: $table.issuerName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cityName => $composableBuilder(
    column: $table.cityName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identificationSource => $composableBuilder(
    column: $table.identificationSource,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get identificationConfidence => $composableBuilder(
    column: $table.identificationConfidence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardNumber => $composableBuilder(
    column: $table.cardNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardNumberMasked => $composableBuilder(
    column: $table.cardNumberMasked,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get balanceFen => $composableBuilder(
    column: $table.balanceFen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currencyCode => $composableBuilder(
    column: $table.currencyCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get transactionCount => $composableBuilder(
    column: $table.transactionCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionDataJson => $composableBuilder(
    column: $table.sessionDataJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardImagePath => $composableBuilder(
    column: $table.cardImagePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SavedCardsTableOrderingComposer
    extends Composer<_$AppDatabase, $SavedCardsTable> {
  $$SavedCardsTableOrderingComposer({
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

  ColumnOrderings<String> get cardFingerprint => $composableBuilder(
    column: $table.cardFingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardType => $composableBuilder(
    column: $table.cardType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get officialName => $composableBuilder(
    column: $table.officialName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customName => $composableBuilder(
    column: $table.customName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get issuerName => $composableBuilder(
    column: $table.issuerName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cityName => $composableBuilder(
    column: $table.cityName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identificationSource => $composableBuilder(
    column: $table.identificationSource,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get identificationConfidence => $composableBuilder(
    column: $table.identificationConfidence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardNumber => $composableBuilder(
    column: $table.cardNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardNumberMasked => $composableBuilder(
    column: $table.cardNumberMasked,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get balanceFen => $composableBuilder(
    column: $table.balanceFen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currencyCode => $composableBuilder(
    column: $table.currencyCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get transactionCount => $composableBuilder(
    column: $table.transactionCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionDataJson => $composableBuilder(
    column: $table.sessionDataJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardImagePath => $composableBuilder(
    column: $table.cardImagePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SavedCardsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavedCardsTable> {
  $$SavedCardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cardFingerprint => $composableBuilder(
    column: $table.cardFingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cardType =>
      $composableBuilder(column: $table.cardType, builder: (column) => column);

  GeneratedColumn<String> get officialName => $composableBuilder(
    column: $table.officialName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customName => $composableBuilder(
    column: $table.customName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get issuerName => $composableBuilder(
    column: $table.issuerName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cityName =>
      $composableBuilder(column: $table.cityName, builder: (column) => column);

  GeneratedColumn<String> get identificationSource => $composableBuilder(
    column: $table.identificationSource,
    builder: (column) => column,
  );

  GeneratedColumn<double> get identificationConfidence => $composableBuilder(
    column: $table.identificationConfidence,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cardNumber => $composableBuilder(
    column: $table.cardNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cardNumberMasked => $composableBuilder(
    column: $table.cardNumberMasked,
    builder: (column) => column,
  );

  GeneratedColumn<int> get balanceFen => $composableBuilder(
    column: $table.balanceFen,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currencyCode => $composableBuilder(
    column: $table.currencyCode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get transactionCount => $composableBuilder(
    column: $table.transactionCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sessionDataJson => $composableBuilder(
    column: $table.sessionDataJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cardImagePath => $composableBuilder(
    column: $table.cardImagePath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastReadAt => $composableBuilder(
    column: $table.lastReadAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SavedCardsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SavedCardsTable,
          SavedCard,
          $$SavedCardsTableFilterComposer,
          $$SavedCardsTableOrderingComposer,
          $$SavedCardsTableAnnotationComposer,
          $$SavedCardsTableCreateCompanionBuilder,
          $$SavedCardsTableUpdateCompanionBuilder,
          (
            SavedCard,
            BaseReferences<_$AppDatabase, $SavedCardsTable, SavedCard>,
          ),
          SavedCard,
          PrefetchHooks Function()
        > {
  $$SavedCardsTableTableManager(_$AppDatabase db, $SavedCardsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavedCardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavedCardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SavedCardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> cardFingerprint = const Value.absent(),
                Value<String> cardType = const Value.absent(),
                Value<String?> officialName = const Value.absent(),
                Value<String?> customName = const Value.absent(),
                Value<String?> issuerName = const Value.absent(),
                Value<String?> cityName = const Value.absent(),
                Value<String> identificationSource = const Value.absent(),
                Value<double?> identificationConfidence = const Value.absent(),
                Value<String?> cardNumber = const Value.absent(),
                Value<String?> cardNumberMasked = const Value.absent(),
                Value<int?> balanceFen = const Value.absent(),
                Value<String?> currencyCode = const Value.absent(),
                Value<int?> transactionCount = const Value.absent(),
                Value<String?> sessionDataJson = const Value.absent(),
                Value<String?> cardImagePath = const Value.absent(),
                Value<int?> lastReadAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavedCardsCompanion(
                id: id,
                cardFingerprint: cardFingerprint,
                cardType: cardType,
                officialName: officialName,
                customName: customName,
                issuerName: issuerName,
                cityName: cityName,
                identificationSource: identificationSource,
                identificationConfidence: identificationConfidence,
                cardNumber: cardNumber,
                cardNumberMasked: cardNumberMasked,
                balanceFen: balanceFen,
                currencyCode: currencyCode,
                transactionCount: transactionCount,
                sessionDataJson: sessionDataJson,
                cardImagePath: cardImagePath,
                lastReadAt: lastReadAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String cardFingerprint,
                required String cardType,
                Value<String?> officialName = const Value.absent(),
                Value<String?> customName = const Value.absent(),
                Value<String?> issuerName = const Value.absent(),
                Value<String?> cityName = const Value.absent(),
                Value<String> identificationSource = const Value.absent(),
                Value<double?> identificationConfidence = const Value.absent(),
                Value<String?> cardNumber = const Value.absent(),
                Value<String?> cardNumberMasked = const Value.absent(),
                Value<int?> balanceFen = const Value.absent(),
                Value<String?> currencyCode = const Value.absent(),
                Value<int?> transactionCount = const Value.absent(),
                Value<String?> sessionDataJson = const Value.absent(),
                Value<String?> cardImagePath = const Value.absent(),
                Value<int?> lastReadAt = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => SavedCardsCompanion.insert(
                id: id,
                cardFingerprint: cardFingerprint,
                cardType: cardType,
                officialName: officialName,
                customName: customName,
                issuerName: issuerName,
                cityName: cityName,
                identificationSource: identificationSource,
                identificationConfidence: identificationConfidence,
                cardNumber: cardNumber,
                cardNumberMasked: cardNumberMasked,
                balanceFen: balanceFen,
                currencyCode: currencyCode,
                transactionCount: transactionCount,
                sessionDataJson: sessionDataJson,
                cardImagePath: cardImagePath,
                lastReadAt: lastReadAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SavedCardsTable, SavedCard>(table),
                  BaseReferences<_$AppDatabase, $SavedCardsTable, SavedCard>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SavedCardsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SavedCardsTable,
      SavedCard,
      $$SavedCardsTableFilterComposer,
      $$SavedCardsTableOrderingComposer,
      $$SavedCardsTableAnnotationComposer,
      $$SavedCardsTableCreateCompanionBuilder,
      $$SavedCardsTableUpdateCompanionBuilder,
      (SavedCard, BaseReferences<_$AppDatabase, $SavedCardsTable, SavedCard>),
      SavedCard,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SavedCardsTableTableManager get savedCards =>
      $$SavedCardsTableTableManager(_db, _db.savedCards);
}
