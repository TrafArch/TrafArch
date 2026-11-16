import '../../../protocols/transit/card_parser.dart';
import '../../archive/domain/card_types.dart';

const unrecognizedCardTypeLabel = '暂无可识别卡种';

String transitTypeLabel(String? parserId) => cardTypeLabel(switch (parserId) {
  CardParserIds.shanghaiTunion => CardTypes.shanghaiTransitUnion,
  CardParserIds.harbinTunion => CardTypes.harbinTransitUnion,
  CardParserIds.lingnanTong => CardTypes.lingnanTong,
  CardParserIds.beijingBmac => CardTypes.beijingBmac,
  CardParserIds.lingnanTunion => CardTypes.lingnanTunion,
  CardParserIds.shenzhenTunion => CardTypes.shenzhenTunion,
  CardParserIds.cityUnion => CardTypes.cityUnion,
  _ => CardTypes.chinaTunion,
});

String transitDisplayName({
  required String? parserId,
  String? identifiedName,
  String? localName,
}) =>
    (parserId == CardParserIds.lingnanTong ? '岭南通' : identifiedName) ??
    (parserId == null
        ? unrecognizedCardTypeLabel
        : parserId == CardParserIds.localCard
        ? localName ?? '地方交通卡'
        : transitTypeLabel(parserId));
