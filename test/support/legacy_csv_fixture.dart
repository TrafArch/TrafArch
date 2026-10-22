import 'package:transit_card_analyzer/features/reference_data/domain/station_codes.dart';

/// 解析读卡识途数据文件（CSV：City/Prefix,Code,Type,Line,Station）。
///
/// 表头首列为 PREFIX 时按 prefix 模式处理（codes 键为 Prefix+Code 拼接，
/// cityCode 为 null）；表头不识别或无有效编码行时返回 null（跳过）。
StationDataset? parseTripreaderDatasetCsv({
  required String file,
  required String csvText,
  String? cityName,
  String? province,
  String system = 'tu',
  String kind = 'mixed',
}) {
  final rows = _parseCsv(csvText);
  if (rows.length < 2) return null;
  final header = rows.first.map((h) => h.trim().toUpperCase()).toList();
  if (header.length < 5) return null;
  final prefixMode = header.first == 'PREFIX';

  final codes = <String, StationCodeEntry>{};
  final cellCityCodes = <String>{};
  for (final row in rows.skip(1)) {
    if (row.length < 5) continue;
    final cellCity = row[0].trim();
    final code = row[1].trim();
    if (code.isEmpty) continue;
    cellCityCodes.add(cellCity);
    final key = prefixMode ? '$cellCity$code' : code;
    final type = row[2].trim();
    final line = row[3].trim();
    final station = row[4].trim();
    codes[key] = StationCodeEntry(
      code: key,
      type: type.isEmpty ? null : type,
      line: line.isEmpty ? null : line,
      station: station.isEmpty ? null : station,
      system: system,
      kind: kind,
      datasetFile: file,
    );
  }
  if (codes.isEmpty) return null;
  return StationDataset(
    file: file,
    cityCode: prefixMode || cellCityCodes.isEmpty ? null : cellCityCodes.first,
    cityName: cityName,
    province: province,
    system: system,
    kind: kind,
    codes: codes,
  );
}

/// 简易 CSV 解析（支持引号包裹与转义，容忍 CRLF 与 BOM）。
List<List<String>> _parseCsv(String text) {
  var source = text;
  if (source.startsWith('\uFEFF')) source = source.substring(1);
  final rows = <List<String>>[];
  var field = StringBuffer();
  var row = <String>[];
  var inQuotes = false;
  for (var i = 0; i < source.length; i++) {
    final ch = source[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < source.length && source[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (ch == ',') {
      row.add(field.toString());
      field = StringBuffer();
    } else if (ch == '\n') {
      row.add(field.toString());
      field = StringBuffer();
      rows.add(row);
      row = <String>[];
    } else if (ch != '\r') {
      field.write(ch);
    }
  }
  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  return rows.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
}
