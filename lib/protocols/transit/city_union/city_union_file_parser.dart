import 'city_union_models.dart';
import 'cj_t331_public_info_parser.dart';
import 'cj_t331_wallet_local_consumption_parser.dart';
import 'cj_t331_wallet_recharge_parser.dart';

/// City Union（CJ/T 331-2016）文件解析统一入口。
///
/// 职责边界：NFC 读取层只提供（SFI, 原始字节），本层按文件类型分发到
/// 具体解析器，页面按统一的 [CityUnionFileView] 展示原始值、解码值与
/// 异常信息；后续扩展发行基本信息、城市轨道交通应用信息等文件时，
/// 在 [CityUnionFileIds] 登记 SFI 并在本类 switch 中挂接解析器，
/// 无需重写基础结构。
class CityUnionFileParser {
  CityUnionFileParser._();

  /// TripReader CU application channels use explicit roles: 0x18 consumption,
  /// 0x10 recharge, 0x06 (Shanghai/Kunshan) or 0x1A foreign consumption.
  /// Keep [parse] available for the standalone CJ/T standard table layouts.
  static CityUnionWalletTransaction parseWalletRecord(
    int sfi,
    List<int> data, {
    required CityUnionTransactionKind kind,
    required int recordNumber,
  }) {
    if (kind == CityUnionTransactionKind.recharge) {
      return CjT331WalletRechargeParser.parseRecord(
        data,
        sourceSfi: sfi,
        recordNumber: recordNumber,
      );
    }
    final record = CjT331WalletLocalConsumptionParser.parseRecord(
      data,
      sourceSfi: sfi,
      recordNumber: recordNumber,
    );
    if (kind == CityUnionTransactionKind.consumption) return record;
    return CjT331WalletOfflineTransaction(
      sourceSfi: sfi,
      recordNumber: recordNumber,
      sequence: record.sequence,
      sequenceHex: record.sequenceHex,
      reservedHex: record.reservedHex,
      amountRaw: record.amountRaw,
      amountHex: record.amountHex,
      transactionType: record.transactionType,
      terminalNumber: record.terminalNumber,
      transactionDate: record.transactionDate,
      transactionTime: record.transactionTime,
      fields: record.fields,
      rawHex: record.rawHex,
    );
  }

  /// 按 SFI 分发解析。
  ///
  /// 已接入的 SFI 返回对应解析结果；未接入的 SFI 返回
  /// [CityUnionRawFileView] 原始占位（仅保留原始字节，不猜测字段布局）。
  /// SFI 0x18（电子钱包本地消费交易明细记录文件）与 0x1A（电子钱包充值
  /// 交易明细记录文件）均为循环记录文件，[data] 必须是单条完整 23 字节
  /// 记录；记录选取（最新记录 / 循环覆盖顺序）由读取层确认后逐条传入，
  /// 不按 23 字节对整文件切片。
  static CityUnionFileView parse(int sfi, List<int> data) => switch (sfi) {
    CityUnionFileIds.walletLocalConsumption =>
      CjT331WalletLocalConsumptionParser.parseRecord(data),
    CityUnionFileIds.walletRecharge => CjT331WalletRechargeParser.parseRecord(
      data,
    ),
    CityUnionFileIds.publicBasicInfo => CjT331PublicInfoParser.parse(data),
    _ => CityUnionRawFileView(sfi: sfi, raw: data),
  };
}
