library;

import 'dart:typed_data';

/// 单次 APDU 请求/响应记录（含行程记录字段）
class ApduRecord {
  String? commandHex;
  List<int>? response;
  String? label;
  int type = 0; // 2 = 城市卡通用流水
  int balanceDelta = 0;
  int balanceAfter = 0;
  DateTime timestamp = DateTime.fromMillisecondsSinceEpoch(0);
  bool isMetro = false;
  bool isBus = false;
  bool isFerry = false;
  bool isOtherA = false;
  bool isOtherB = false;
  int cityCode = 0;
  bool flagged = false;
  bool hasError = false;
  Uint8List? rawBody;

  int recordNumber = 0;
  int fileSelector = 0;
  int statusCode = 0;
  int posType = 0;
  String? terminalHex;
  List<int>? identity;
  bool isTransfer = false;
}

/// 一张被读取卡的汇总
class CardInfo {
  String cardNumber = '';
  String issuerCode = '';
  String issuerCode2 = '';
  int cityCode = 0;
  int terminalCode = 0;
  int balance = 0;
  int previousBalance = 0;
  int deposit = 0;
  int bonus = 0;
  int extraBalance = 0;
  int remainingTrips = 0;
  int validFromDays = 0;
  int cardTypeCode = 0;
  int subtypeCode = 0;
  DateTime? issueDate;
  DateTime? expiryDate;
  DateTime? startDate;
  int timezoneOffsetMinutes = 0;
  List<int>? rawInfo;

  bool isSuzhou = false;
  bool isTU = false;
  bool isCU = false;
  bool isBeijing = false;
  bool isTFT = false;
  bool isSZT = false;
  bool isYCT = false;
  bool isSuxin = false;
  bool isCika = false;
  bool isCikaMode = false;
  bool specialLocal = false;
  int lastSeenRecordIndex = -1;

  /// 是否属于地方卡（非通用 TU/CU）识别出的卡种 —— 供上层判定是否认领。
  bool get isLocalCard =>
      isBeijing || isYCT || isSZT || isSuzhou || isTFT;

  /// 卡种可读名（用于展示层回退标题）。
  String get cardKindLabel {
    if (isBeijing) return '北京互通卡';
    if (isYCT) return '羊城通';
    if (isSZT) return '深圳通';
    if (isSuzhou) return isCika ? '苏州·计次卡' : '苏州·苏薪卡';
    if (isTFT) return '天府通';
    if (isTU) return '交通联合';
    if (isCU) return '城市一卡通';
    return '地方交通卡';
  }
}

/// READ RECORD 的文件选择子（P2）；SFI = p2 >> 3。
enum TripFile {
  metro(196), // 0xC4 地铁
  bus(76), // 0x4C 公交
  ferry(52), // 0x34 轮渡
  suxinTx(132), // 0x84 苏州通行流水
  other(212); // 0xD4 其它交易流水

  const TripFile(this.p2);
  final int p2;
  int get sfi => p2 >> 3;
}

/// 一张卡除基本信息外的“扩展槽位”。
class CardExtras {
  List<int>? dateRaw;
  int? amount;
  int? bonus;
  int? counter;
  List<int>? recordBlob;
  List<int>? lineCode;
  bool lineDirection = false;
  final Map<String, Object?> slots = {};
}

/// 一次读卡产出的完整结果：卡信息 + 记录（含行程）+ 扩展槽位。
class ReadResult {
  ReadResult({required this.info, required this.records, required this.extras});
  final CardInfo info;
  final List<ApduRecord> records;
  final CardExtras extras;

  /// 已解析出的乘车流水（type==2 的记录）
  List<ApduRecord> get trips =>
      records.where((r) => r.type == 2).toList(growable: false);
}