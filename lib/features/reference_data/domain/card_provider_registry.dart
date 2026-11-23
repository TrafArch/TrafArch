enum CardProviderKind { chip, icCard }

enum CardProviderLookupState { found, ambiguous, missing }

class CardProviderEntry {
  const CardProviderEntry({
    required this.kind,
    required this.code,
    required this.name,
    required this.sourceRow,
  });

  final CardProviderKind kind;
  final String code;
  final String name;
  final int sourceRow;
}

class CardProviderLookupResult {
  const CardProviderLookupResult({
    required this.kind,
    required this.code,
    required this.names,
  });

  final CardProviderKind kind;
  final String? code;
  final List<String> names;

  CardProviderLookupState get state {
    if (names.isEmpty) return CardProviderLookupState.missing;
    return names.length == 1
        ? CardProviderLookupState.found
        : CardProviderLookupState.ambiguous;
  }
}

class CardProviderRegistry {
  CardProviderRegistry._({
    required this.sourceSha256,
    required this.sourceRows,
    required Map<String, List<CardProviderEntry>> chipProviders,
    required Map<String, List<CardProviderEntry>> icCardProviders,
  }) : _chipProviders = _freeze(chipProviders),
       _icCardProviders = _freeze(icCardProviders);

  static const formatVersion = 1;
  static final _codePattern = RegExp(r'^[0-9A-F]{4}$');
  static final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

  final String? sourceSha256;
  final int? sourceRows;
  final Map<String, List<CardProviderEntry>> _chipProviders;
  final Map<String, List<CardProviderEntry>> _icCardProviders;

  int get chipProviderCount =>
      _chipProviders.values.fold(0, (count, rows) => count + rows.length);
  int get icCardProviderCount =>
      _icCardProviders.values.fold(0, (count, rows) => count + rows.length);

  const CardProviderRegistry.empty()
    : sourceSha256 = null,
      sourceRows = null,
      _chipProviders = const {},
      _icCardProviders = const {};

  factory CardProviderRegistry.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('机构备案表顶层必须是对象');
    }
    if (value['format_version'] != formatVersion) {
      throw const FormatException('不支持的机构备案表版本');
    }
    final source = value['source'];
    String? sourceSha256;
    int? sourceRows;
    if (source != null) {
      if (source is! Map) {
        throw const FormatException('source 必须是对象');
      }
      final hash = source['sha256'];
      if (hash is String) {
        if (!_sha256Pattern.hasMatch(hash)) {
          throw const FormatException('source.sha256 格式错误');
        }
        sourceSha256 = hash;
      }
      final rows = source['rows'];
      if (rows is int) {
        if (rows < 0) throw const FormatException('source.rows 不能为负数');
        sourceRows = rows;
      }
    }
    final chip = _readEntries(value['chip_providers'], CardProviderKind.chip);
    final icCard = _readEntries(
      value['ic_card_providers'],
      CardProviderKind.icCard,
    );
    return CardProviderRegistry._(
      sourceSha256: sourceSha256,
      sourceRows: sourceRows,
      chipProviders: chip,
      icCardProviders: icCard,
    );
  }

  CardProviderLookupResult lookup(CardProviderKind kind, String? code) {
    final normalized = normalizeCode(code);
    if (normalized == null) {
      return CardProviderLookupResult(kind: kind, code: null, names: const []);
    }
    final entries = switch (kind) {
      CardProviderKind.chip => _chipProviders[normalized],
      CardProviderKind.icCard => _icCardProviders[normalized],
    };
    final names = <String>{
      for (final entry in entries ?? const <CardProviderEntry>[]) entry.name,
    }.toList(growable: false);
    return CardProviderLookupResult(
      kind: kind,
      code: normalized,
      names: List.unmodifiable(names),
    );
  }

  static String? normalizeCode(String? value) {
    if (value == null) return null;
    final normalized = value.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    return _codePattern.hasMatch(normalized) ? normalized : null;
  }

  static Map<String, List<CardProviderEntry>> _readEntries(
    Object? value,
    CardProviderKind kind,
  ) {
    if (value is! List) {
      throw FormatException('${kind.name} 提供机构必须是数组');
    }
    final entries = <String, List<CardProviderEntry>>{};
    for (var index = 0; index < value.length; index++) {
      final raw = value[index];
      if (raw is! Map) {
        throw FormatException('${kind.name}[$index] 必须是对象');
      }
      final rawCode = raw['code'];
      final code = rawCode is String ? normalizeCode(rawCode) : null;
      final name = raw['name'];
      final sourceRow = raw['source_row'];
      if (code == null || code != rawCode) {
        throw FormatException('${kind.name}[$index].code 必须是四位大写 HEX');
      }
      if (name is! String || name.trim().isEmpty) {
        throw FormatException('${kind.name}[$index].name 不能为空');
      }
      if (sourceRow is! int || sourceRow < 1) {
        throw FormatException('${kind.name}[$index].source_row 必须是正整数');
      }
      final entry = CardProviderEntry(
        kind: kind,
        code: code,
        name: name.trim(),
        sourceRow: sourceRow,
      );
      entries.putIfAbsent(code, () => <CardProviderEntry>[]).add(entry);
    }
    return entries;
  }

  static Map<String, List<CardProviderEntry>> _freeze(
    Map<String, List<CardProviderEntry>> value,
  ) => Map.unmodifiable({
    for (final entry in value.entries)
      entry.key: List<CardProviderEntry>.unmodifiable(entry.value),
  });
}
