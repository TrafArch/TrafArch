library;

import 'dart:typed_data';
import 'local_hex.dart';

/// 集中所有 SELECT / BALANCE 常量
class CardAid {
  static final List<int> balanceCheck = const [0x80, 0x5C, 0x00, 0x02, 0x04];
  static final List<int> balanceCheck2 = const [0x80, 0x5C, 0x05, 0x02, 0x10];
  static final List<int> balanceCheck3 = const [0x80, 0x5C, 0x00, 0x01, 0x04];
  static final List<int> selectMf = const [0x00, 0xA4, 0x00, 0x00, 0x02, 0x3F, 0x00];
  static final List<int> selectMf1 = const [0x00, 0xA4, 0x00, 0x00, 0x02, 0x3F, 0x01];
  static final List<int> select1001 = const [0x00, 0xA4, 0x00, 0x00, 0x02, 0x10, 0x01];
  static final List<int> select1002 = const [0x00, 0xA4, 0x00, 0x00, 0x02, 0x10, 0x02];
  static final List<int> suzhouPinVerify = const [0x00, 0x20, 0x00, 0x00, 0x03, 0x12, 0x34, 0x56];

  static final Uint8List selectCU = _select('A00000000386980701');
  static final Uint8List selectTU = _select('A000000632010105');
  static final Uint8List motBmac = _select('91560000144D4F542E424D4143303031');

  static final Uint8List paySzt = _selectAscii('PAY.SZT');
  static final Uint8List suxin = _selectAscii('SUXIN.DDF01');
  static final Uint8List suzCika = _select('535A504B5F5A5959'); // "SZPK_ZYY"
  static final Uint8List payAppy = _selectAscii('PAY.APPY');
  static final Uint8List payTicl = _selectAscii('PAY.TICL');
  static final Uint8List tft = _select('D156000015B9ABB9B2D3A6D3C3');

  static Uint8List _select(String aidHex) =>
      LocalHex.hexToBytes(LocalHex.wrapSelectCmd(aidHex));

  static Uint8List _selectAscii(String s) =>
      _select(LocalHex.bytesToHex(s.codeUnits));
}