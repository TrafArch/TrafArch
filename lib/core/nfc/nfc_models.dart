class NfcScanResult {
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
  final DateTime timestamp;

  const NfcScanResult({
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
    required this.timestamp,
  });

  factory NfcScanResult.fromMap(Map<dynamic, dynamic> map) {
    return NfcScanResult(
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
      timestamp: DateTime.tryParse('${map['timestamp']}') ?? DateTime.now(),
    );
  }
}
