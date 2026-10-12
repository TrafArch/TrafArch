import 'city_union_models.dart';
import 'cj_t331_composite_transaction_parser.dart';
import 'cj_t331_public_info_parser.dart';
import 'cj_t331_wallet_offline_transaction_parser.dart';
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

  /// 按 SFI 分发解析。
  ///
  /// 已接入的 SFI 返回对应解析结果；未接入的 SFI 返回
  /// [CityUnionRawFileView] 原始占位（仅保留原始字节，不猜测字段布局）。
  /// SFI 0x17（复合交易记录文件）的 [data] 必须是单条完整 48 字节记录；
  /// 0x00A0 为文件大小而非单条记录长度，整文件读取需由读取层确认记录
  /// 边界后逐条传入，不按 48 字节切片。
  /// SFI 0x10（电子钱包异地消费交易明细记录文件）为循环记录文件，
  /// [data] 必须是单条完整 23 字节记录；记录选取（最新记录 / 循环覆盖
  /// 顺序）由读取层确认后逐条传入，不按 23 字节对整文件切片。
  /// SFI 0x1A（电子钱包充值交易明细记录文件）同为循环记录文件，
  /// [data] 必须是单条完整 23 字节记录，约定与 0x10 一致。
  static CityUnionFileView parse(int sfi, List<int> data) => switch (sfi) {
        CityUnionFileIds.walletOfflineTransaction =>
          CjT331WalletOfflineTransactionParser.parseRecord(data),
        CityUnionFileIds.walletRecharge =>
          CjT331WalletRechargeParser.parseRecord(data),
        CityUnionFileIds.publicBasicInfo => CjT331PublicInfoParser.parse(data),
        CityUnionFileIds.compositeTransaction =>
          CjT331CompositeTransactionParser.parseRecord(data),
        _ => CityUnionRawFileView(sfi: sfi, raw: data),
      };
}