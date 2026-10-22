library;

import '../local_card_models.dart';

/// 自底向上扫描流水，识别“同一趟行程”的重复/换乘记录并打标记
class TripDeduper {
  TripDeduper({this.minGapMs = 0, this.maxGapMs = 7200000});
  final int minGapMs;
  final int maxGapMs;

  void process(CardInfo info, List<ApduRecord> records) {
    if (records.isEmpty) return;

    var prevMetro = _blank();

    for (var i = records.length - 1; i >= 0; i--) {
      final r = records[i];
      if (_rawLen(r) < 20) continue;

      final gapPrev = r.timestamp
          .difference(prevMetro.timestamp)
          .inMilliseconds;

      if (r.isTransferCandidate &&
          prevMetro.hasError &&
          _cityMatches(info, r) &&
          gapPrev > minGapMs &&
          gapPrev <= maxGapMs) {
        r.isTransfer = true;
      }

      if (r.isMetro) prevMetro = r;
    }
  }

  static ApduRecord _blank() => ApduRecord();
  static int _rawLen(ApduRecord r) => r.response?.length ?? 0;

  static bool _cityMatches(CardInfo info, ApduRecord r) {
    if (info.cityCode != 2000 && r.cityCode == info.cityCode) return true;
    if (info.cityCode == 2900 && r.cityCode == info.cityCode) return true;
    return false;
  }
}

extension on ApduRecord {
  bool get isTransferCandidate => isMetro || isBus || isFerry;
}
