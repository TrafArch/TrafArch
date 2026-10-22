/// A failed optional native probe must remain distinguishable from missing data.
class NfcMetadataIssue {
  const NfcMetadataIssue({
    required this.stage,
    required this.exception,
    this.message,
  });
  final String stage;
  final String exception;
  final String? message;

  factory NfcMetadataIssue.fromMap(Map<dynamic, dynamic> map) =>
      NfcMetadataIssue(
        stage: '${map['stage'] ?? 'unknown'}',
        exception: '${map['exception'] ?? 'unknown'}',
        message: map['message']?.toString(),
      );

  Map<String, dynamic> toJson() => {
    'stage': stage,
    'exception': exception,
    'message': message,
  };
}

class NfcScanResult {
  final String? sessionId;
  final List<NfcMetadataIssue> metadataIssues;
  final String uid;
  final List<String> technologies;
  final String? atqa;
  final String? sak;
  final String? ats;
  final String? atsDescription;
  final String? cardType;
  final String? historicalBytes;
  final String? hiLayerResponse;
  final String? nfcBApplicationData;
  final String? nfcBProtocolInfo;
  final String? nfcFSystemCode;
  final String? nfcFManufacturer;
  final String? nfcVDsfId;
  final String? nfcVResponseFlags;
  final String? mifareType;
  final int? mifareSize;
  final int? mifareSectorCount;
  final int? mifareBlockCount;
  final String? mifareManufacturerBlock;
  final bool? mifareBccValid;
  final int? maxTransceiveLength;
  final String? tagDescription;
  final bool isoDepConnected;

  /// 原生是否已建立 NFC-F（FeliCa）连接：Suica / 八达通等卡
  /// 走独立 FeliCa 链路，不经过 ISO-DEP APDU 流程。
  final bool felicaConnected;
  final DateTime timestamp;

  const NfcScanResult({
    this.sessionId,
    this.metadataIssues = const [],
    required this.uid,
    required this.technologies,
    this.atqa,
    this.sak,
    this.ats,
    this.atsDescription,
    this.cardType,
    this.historicalBytes,
    this.hiLayerResponse,
    this.nfcBApplicationData,
    this.nfcBProtocolInfo,
    this.nfcFSystemCode,
    this.nfcFManufacturer,
    this.nfcVDsfId,
    this.nfcVResponseFlags,
    this.mifareType,
    this.mifareSize,
    this.mifareSectorCount,
    this.mifareBlockCount,
    this.mifareManufacturerBlock,
    this.mifareBccValid,
    this.maxTransceiveLength,
    this.tagDescription,
    required this.isoDepConnected,
    this.felicaConnected = false,
    required this.timestamp,
  });

  factory NfcScanResult.fromMap(Map<dynamic, dynamic> map) {
    return NfcScanResult(
      sessionId: map['sessionId']?.toString(),
      metadataIssues: List.unmodifiable(
        ((map['metadataIssues'] as List?) ?? const []).whereType<Map>().map(
          NfcMetadataIssue.fromMap,
        ),
      ),
      uid: '${map['uid'] ?? ''}',
      technologies: ((map['technologies'] as List?) ?? const [])
          .map((e) => '$e')
          .toList(),
      atqa: map['atqa']?.toString(),
      sak: map['sak']?.toString(),
      ats: map['ats']?.toString(),
      atsDescription: map['atsDescription']?.toString(),
      cardType: map['cardType']?.toString(),
      historicalBytes: map['historicalBytes']?.toString(),
      hiLayerResponse: map['hiLayerResponse']?.toString(),
      nfcBApplicationData: map['nfcBApplicationData']?.toString(),
      nfcBProtocolInfo: map['nfcBProtocolInfo']?.toString(),
      nfcFSystemCode: map['nfcFSystemCode']?.toString(),
      nfcFManufacturer: map['nfcFManufacturer']?.toString(),
      nfcVDsfId: map['nfcVDsfId']?.toString(),
      nfcVResponseFlags: map['nfcVResponseFlags']?.toString(),
      mifareType: map['mifareType']?.toString(),
      mifareSize: (map['mifareSize'] as num?)?.toInt(),
      mifareSectorCount: (map['mifareSectorCount'] as num?)?.toInt(),
      mifareBlockCount: (map['mifareBlockCount'] as num?)?.toInt(),
      mifareManufacturerBlock: map['mifareManufacturerBlock']?.toString(),
      mifareBccValid: map['mifareBccValid'] as bool?,
      maxTransceiveLength: (map['maxTransceiveLength'] as num?)?.toInt(),
      tagDescription: map['tagDescription']?.toString(),
      isoDepConnected: map['isoDepConnected'] == true,
      felicaConnected: map['felicaConnected'] == true,
      timestamp: DateTime.tryParse('${map['timestamp']}') ?? DateTime.now(),
    );
  }
}
