import 'package:flutter/services.dart' show AssetBundle;

import '../../../protocols/felica/felica.dart';
import '../../../platform/nfc/nfc_models.dart';
import 'local_card_parser.dart';
import '../../../protocols/bank/parsers/bank_card_analyzer.dart';
import 'bank_card_probe_impl.dart';
import '../../../protocols/bank/parsers/emv/emv_parser.dart';
import '../../../protocols/bank/parsers/pboc/pboc_parser.dart';
import '../domain/card_read_outcome.dart';

/// Owns reader precedence and typed family dispatch; no widget or archive state.
class CardReadCoordinator {
  CardReadCoordinator(this.bundle);
  final AssetBundle bundle;
  Future<BankCardAnalyzer>? _bank;

  Future<BankCardAnalyzer> _bankAnalyzer() => _bank ??= () async {
    final pboc = await PbocParser.load(bundle.loadString);
    final emv = await EmvParser.load(bundle.loadString);
    return BankCardAnalyzer([pboc, emv]);
  }();

  Future<CardReadOutcome> read(
    NfcScanResult tag, {
    required Future<List<int>> Function(List<int>) apdu,
    required Future<List<int>> Function(List<int>) felica,
    required void Function(String) onStage,
    required void Function(int) onProgress,
  }) async {
    if (tag.isoDepConnected) {
      final result = await LocalCardParser(
        apdu,
        onStage: onStage,
        onProgress: onProgress,
        bankProbe: BankCardProbeImpl(_bankAnalyzer),
      ).read();
      if (result?.bank != null) return BankReadOutcome(result!.bank!);
      if (result?.parsedCard != null) {
        return TransitReadOutcome(
          result!.parsedCard!,
          shanghai: result.shanghai,
        );
      }
    } else if (tag.felicaConnected) {
      final word = tag.nfcFSystemCode?.replaceAll(' ', '');
      return FelicaReadOutcome(
        await FelicaReader(
          felica,
          onStage: onStage,
          onProgress: onProgress,
        ).read(
          preferredSystemCode: word == null
              ? null
              : int.tryParse(word, radix: 16),
        ),
      );
    }
    return const UnsupportedReadOutcome();
  }
}
