import '../../../iso7816/ber_tlv.dart';
import '../apdu_exchange.dart';
import '../card_aid.dart';
import '../local_card_models.dart';

/// Files 04 and 05 belong to MF. DF 1001 is a relative file identifier;
/// successful selection alone cannot identify the issuer or purse layout.
class Df1001Directory {
  Df1001Directory(this.apdu);
  final ApduExchange apdu;
  List<int>? issuer;
  List<int>? basic;
  List<int>? fci;

  Future<bool> select(List<ApduRecord> records) async {
    issuer = basic = fci = null;
    final mf = await apdu(CardAid.selectMf, 'SELECT MF', records: records);
    if (mf != null && _matchesFid(mf, 0x3F00)) {
      issuer = await apdu(
        const [0, 0xB0, 0x84, 0, 0x3C],
        'MF 0x04',
        records: records,
        strict: true,
      );
      basic = await apdu(
        const [0, 0xB0, 0x85, 0, 0x20],
        'MF 0x05',
        records: records,
        strict: true,
      );
    }
    final selected = await apdu(
      CardAid.select1001,
      'SELECT DF 1001',
      records: records,
    );
    if (selected == null || !_matchesFid(selected, 0x1001)) return false;
    fci = selected;
    return true;
  }

  // FID 83 is optional. A conflicting explicit identifier means the requested
  // directory was not established even if the response status was 9000.
  static bool _matchesFid(List<int> response, int fid) {
    final roots = BerTlvParser.parse(response).roots;
    final templates = [
      for (final r in roots) ...[
        if (r.tagHex == '62' || r.tagHex == '6F') r,
        if (r.tagHex == '6F')
          ...r.children.where((child) => child.tagHex == '62'),
      ],
    ];
    final ids = templates
        .expand((tag) => tag.children)
        .where((tag) => tag.tagHex == '83');
    return ids.every(
      (tag) =>
          tag.value.length == 2 && ((tag.value[0] << 8) | tag.value[1]) == fid,
    );
  }
}
