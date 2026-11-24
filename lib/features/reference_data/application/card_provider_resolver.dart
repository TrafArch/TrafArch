import '../../../platform/nfc/nfc_models.dart';
import '../../../protocols/iso7816/reset_provider_parser.dart';
import '../domain/card_provider_registry.dart';

enum CardProviderFieldState { found, ambiguous, unknown, unavailable }

class CardProviderField {
  const CardProviderField({
    required this.code,
    required this.names,
    required this.state,
    this.source,
  });

  const CardProviderField.unavailable()
    : code = null,
      names = const [],
      state = CardProviderFieldState.unavailable,
      source = null;

  final String? code;
  final List<String> names;
  final CardProviderFieldState state;
  final ResetProviderSource? source;

  String get displayText => switch (state) {
    CardProviderFieldState.found => '${names.single}（$code）',
    CardProviderFieldState.ambiguous => '${names.join(' / ')}（$code，备案表重码）',
    CardProviderFieldState.unknown => '未知（$code）',
    CardProviderFieldState.unavailable => '未提供',
  };
}

class CardProviderInfo {
  const CardProviderInfo({required this.chip, required this.icCard});

  const CardProviderInfo.unavailable()
    : chip = const CardProviderField.unavailable(),
      icCard = const CardProviderField.unavailable();

  final CardProviderField chip;
  final CardProviderField icCard;

  bool get hasProviderCode => chip.code != null || icCard.code != null;
}

class CardProviderResolver {
  const CardProviderResolver(this.registry);

  final CardProviderRegistry registry;

  CardProviderInfo resolve(NfcScanResult? tag) {
    if (tag == null) return const CardProviderInfo.unavailable();
    final historicalBytes = tag.historicalBytes;
    final sources = <(ResetProviderSource, String?)>[
      (
        ResetProviderSource.historicalBytes,
        historicalBytes == null || historicalBytes.trim().isEmpty
            ? tag.ats
            : historicalBytes,
      ),
      (ResetProviderSource.higherLayerResponse, tag.hiLayerResponse),
      (ResetProviderSource.nfcBApplicationData, tag.nfcBApplicationData),
      (ResetProviderSource.nfcBProtocolInfo, tag.nfcBProtocolInfo),
    ];
    CardProviderInfo? unregistered;
    for (final (source, value) in sources) {
      if (value == null || value.isEmpty) continue;
      for (final candidate in ResetProviderParser.parse(value, source)) {
        final chip =
            candidate.layout == ResetProviderLayout.providerBlockWithoutHighByte
            ? _resolveChipLowByte(candidate.chipProviderCode, source)
            : _resolveField(
                CardProviderKind.chip,
                candidate.chipProviderCode,
                source,
              );
        final icCard = _resolveField(
          CardProviderKind.icCard,
          candidate.icCardProviderCode,
          source,
        );
        final info = CardProviderInfo(chip: chip, icCard: icCard);
        if (candidate.layout == ResetProviderLayout.tUnionHistoricalBytes ||
            chip.names.isNotEmpty ||
            icCard.names.isNotEmpty) {
          return info;
        }
        // An ATR header alone is generic. Only a marked provider block
        // can supply raw codes without any registry match.
        if (candidate.layout != ResetProviderLayout.atr) unregistered ??= info;
      }
    }
    return unregistered ?? const CardProviderInfo.unavailable();
  }

  CardProviderField _resolveChipLowByte(
    String lowByte,
    ResetProviderSource source,
  ) {
    final matches = [
      _resolveField(CardProviderKind.chip, '00$lowByte', source),
      _resolveField(CardProviderKind.chip, 'FF$lowByte', source),
    ].where((field) => field.names.isNotEmpty).toList();
    return matches.length == 1
        ? matches.single
        : const CardProviderField.unavailable();
  }

  CardProviderField _resolveField(
    CardProviderKind kind,
    String code,
    ResetProviderSource source,
  ) {
    final lookup = registry.lookup(kind, code);
    return CardProviderField(
      code: code,
      names: lookup.names,
      state: switch (lookup.state) {
        CardProviderLookupState.found => CardProviderFieldState.found,
        CardProviderLookupState.ambiguous => CardProviderFieldState.ambiguous,
        CardProviderLookupState.missing => CardProviderFieldState.unknown,
      },
      source: source,
    );
  }
}
