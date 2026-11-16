import '../../../protocols/felica/felica.dart';
import '../../../platform/nfc/nfc_models.dart';
import 'local_card_parser.dart';
import '../domain/card_read_outcome.dart';

/// Owns reader precedence and typed family dispatch; no widget or archive state.
class CardReadCoordinator {
  const CardReadCoordinator();

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
      ).read();
      if (result != null) {
        return TransitReadOutcome(
          result.parsedCard,
          shanghai: result.shanghai,
          applications: result.applications,
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
