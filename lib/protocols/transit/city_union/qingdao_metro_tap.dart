import '../tunion/tunion_codec.dart';
import 'city_union_codec.dart';
import 'city_union_models.dart';

/// The latest metro clocks from QinDaoTong's CU 0x19 statistics file.
/// A clock can corroborate a wallet record and cannot create a transaction.
class QingdaoMetroTap extends CityUnionRawFileView {
  QingdaoMetroTap(this.recordNumber, List<int> data)
    : clock = _readClock(recordNumber, data),
      super(sfi: 0x19, raw: data);

  final int recordNumber;
  final String? clock;
  bool get isEntry => recordNumber == 3;

  @override
  String get fileLabel => '琴岛通地铁时间 · 0x19 #$recordNumber';

  @override
  List<String> get errors => clock == null ? ['最近地铁时间无有效字段'] : const [];

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'recordNumber': recordNumber,
    'metroClock': ?clock,
  };

  static String? _readClock(int number, List<int> data) {
    if (data.length != 0x20 || (number != 3 && number != 7)) return null;
    final offset = number == 3 ? 9 : 7;
    final bcd = data.sublist(offset, offset + 7);
    return TUnionCodec.parseBcdDateTime(bcd) == null
        ? null
        : CityUnionCodec.hex(bcd);
  }
}
