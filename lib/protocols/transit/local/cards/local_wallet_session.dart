import '../../tunion/tunion_codec.dart';
import '../../../transport/transport_failure.dart';
import '../apdu_exchange.dart';
import '../card_aid.dart';
import '../local_card_models.dart';
import '../local_hex.dart';
import '../trips/trip_records.dart';

abstract interface class LocalWalletReader {
  Future<bool> select(CardInfo info, List<ApduRecord> records);
  Future<void> read(LocalWalletSession session);
}

/// Evidence from a single publicly selected local wallet. Physical frames
/// retain their directory even when a command retries or the tag is lost.
class LocalWalletSession {
  LocalWalletSession(LocalTransceive transceive, this.directory) {
    apdu = ApduExchange(transceive: transceive, onExchange: _recordFrames);
  }
  late final ApduExchange apdu;
  String directory;
  String label = 'SELECT';
  final info = CardInfo();
  final records = <ApduRecord>[];
  final extras = CardExtras();
  final issues = <String>[];
  TransportFailure? failure;

  void _recordFrames(ApduExchangeResult result) {
    for (final frame in result.frames) {
      records.add(
        ApduRecord()
          ..directory = directory
          ..commandHex = LocalHex.bytesToHex(frame.command)
          ..response = frame.response
          ..label = label
          ..hasError =
              frame.failure != null ||
              (identical(frame, result.frames.last) && !result.isSuccess),
      );
    }
  }

  Future<List<int>?> read(
    List<int> command,
    String description, {
    int? length,
    bool optional = false,
  }) async {
    label = description;
    final result = await apdu.exchange(command);
    final error = result.failure;
    if (error != null) {
      if (error.stopsSession) throw error;
      // Missing optional directory/file/record is an ordinary end condition.
      if (!optional || !const {0x6A82, 0x6A83}.contains(error.details)) {
        issues.add('$directory / $description · $error');
        failure ??= error;
      }
      return null;
    }
    final data = result.response!.data;
    if (length != null && data.length != length) {
      issues.add('$directory / $description · 长度 ${data.length}，预期 $length');
      return null;
    }
    return data;
  }

  Future<void> readPurse({required bool suxin}) async {
    final raw = await read(const [0, 0xB0, 0x95, 0, 0x1E], '0x15', length: 30);
    if (raw != null) {
      info.rawInfo = raw;
      info.issuerCode2 = LocalHex.bytesToHex(raw.sublist(0, 4));
      info.cardNumber = LocalHex.bytesToHex(raw.sublist(10, 20));
      info.displayCardNumber = suxin
          ? LocalHex.bytesToHex(raw.sublist(0, 8))
          : info.cardNumber;
      if (suxin) {
        info.cityCode = 2150;
      } else if (raw.sublist(2, 4).every(TUnionCodec.isBcdByte)) {
        info.cityCode = TUnionCodec.bcdToInt(raw.sublist(2, 4));
      }
      info.expiryDate = TUnionCodec.parseBcdDate(raw.sublist(24, 28));
    }
    final balance = await read(
      suxin ? CardAid.balanceCheck3 : CardAid.balanceCheck,
      '钱包余额',
      length: 4,
    );
    if (balance != null) {
      final value = LocalHex.readBEInt(balance.sublist(1));
      final signed = value - 0x1000000;
      info.balance = balance[1] == 0xFF && signed > -100000 ? signed : value;
    }
    info.currencyCode = 'CNY';
  }

  Future<void> readTransactions(TripFile file) async {
    final sfi = file.sfi.toRadixString(16).padLeft(2, '0').toUpperCase();
    for (var number = 1; number <= 31; number++) {
      final data = await read(
        [0, 0xB2, number, file.p2, 0x17],
        '0x$sfi #$number',
        length: 23,
        optional: true,
      );
      if (data == null) break;
      final record = TripRecordReader.decode(
        info,
        data,
        file,
        number,
        directory: directory,
      );
      if (record != null) records.add(record);
    }
  }
}
