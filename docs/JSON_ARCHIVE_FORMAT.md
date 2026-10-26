# 卡片 JSON 文件格式

UTF-8；导入允许 BOM。单文件最大 32 MiB。客户 workflow 负责飞书多维表格处理，应用不联网写表。两种导出均可重新导入 TrafArch。没有行程记录的卡片使用完整备份；按字段导出会提示没有可导出的记录。

## 按字段导出：trafarch.records v1

```json
{
  "format": "trafarch.records",
  "version": 1,
  "exportedAt": "2026-10-26T12:00:00.000Z",
  "fields": ["time", "entry_station", "exit_station", "amount", "currency"],
  "records": [
    {
      "time": "2026-10-26T08:35:00",
      "entry_station": "示例起点站",
      "exit_station": "示例终点站",
      "amount": "-3.00",
      "currency": "CNY"
    }
  ]
}
```

workflow 遍历 `records`，每个对象映射一行、字段名映射列。`fields` 决定列顺序；只有勾选字段进入记录，不附带完整卡号、原始 APDU 或恢复快照。选中但未知的字段为 `null`，未选中的字段不存在。原始含义不因脱敏或表格展示而补造。

### 字段

每个值均为字符串或 `null`，包括金额和编码。金额使用十进制文本避免二进制浮点误差；workflow 可按币种将 `amount` 转为数值列。卡号/编码不可转数字，以免丢失前导零。

| 字段键 | 含义 |
| --- | --- |
| card_name / card_number | 名称／卡号（卡号默认不选） |
| record_type / source | 记录类型／文件来源 |
| time | 交易或过程事件时间 |
| entry_time / exit_time | 已知的进入／离开时间 |
| time_basis | 时间依据，见下文 |
| entry_station / exit_station | 进入／离开站点名称 |
| entry_station_code / exit_station_code | 原始进入／离开站点编码 |
| entry_line / exit_line | 已捕获的进入／离开线路名称 |
| entry_line_code / exit_line_code | 原始进入／离开线路编码 |
| station / station_code | 未能确定进出方向的站点及原码 |
| line / line_code | 未能确定进出方向的线路及原码 |
| amount | 单位和币种已知时的十进制交易金额，支出为负；非交易事件或未知时为 null |
| currency | 已确认币种 |
| amount_raw | 记录中保留的金额整数或编码文本；不能脱离单位当成元 |
| amount_unit | 例如 `10^-2 CNY`，未知为 `unknown` |
| balance | 有对应依据且单位明确的十进制余额 |
| city | 交易城市；不以发卡城市补齐未知受理地区 |
| terminal | 原始终端编码，可能含 A–F |

`time_basis` 为 `card_local_unverified` 时，时间保留卡内民用时间且不追加假定时区；旧快照只有时间戳时使用 `stored_epoch_unverified` 并输出对应 UTC 表示；CU 投影已有 UTC+08 依据时标注 `UTC+08:00`。未知为 `unknown`。`exportedAt` 必须带 `Z` 或 `±HH:mm`，它表示导出时间，不是刷卡时间。

TU 使用保存时的关联证据合并 18/1A/1E，未关联过程独立保留；标准 14 位 HEX 的 1E `lineStationCode` 按既有模型提取原始线路码和站码，保留前导零，其他布局不硬拆。一个已完成消费金额不同时附在其剩余独立进站侧。1E 进站记录和未知交易类型不作为收入金额，只提供原始金额；确认消费或充值才赋有符号金额。CU 独立处理，未知单位不推断；站点只有一侧且方向不明时进入普通 station/line 列。

字段 JSON 导入为独立来源的记录，允许缺列与 null，不据卡号或名称与 NFC 实卡自动合并。规范化内容生成稳定身份，同一文件换名再次导入幂等；同一文件内相同的行仍保留其出现次数。不同内容文件不会被当成完整备份覆盖原卡。只有完整备份能恢复原来的 NFC 捕获及全部上下文。

合成示例见 [trafarch-records.example.json](examples/trafarch-records.example.json)，不含真实用户卡号或行程。

## 完整备份：trafarch.archive v1

外层为 `format, version, exportedAt, cards`。cards 每项是 `trafarch.card` v1：

- `card`：完整卡片摘要、用户名称及时间。内部标识作为字符串。
- `batches`：不可变读取批次，含 `id/cardId/cardFingerprint/readAt/parseVersion/payloadJson`。`payloadJson` 保留完整原文，包括旧版本、未知扩展或原本损坏的快照。
- `fieldObservationTimes`：摘要每字段的观察时间，用于部分/迟到读取后的新鲜度判断。
- `importedRecords`：从按字段文件导入的平铺记录；不补造 NFC 证据。
- `retainedSummaries`：合并后被替换的原始摘要证据，使用 `trafarch.card-summary` v1 封套，保存原 `card` 与 `fieldObservationTimes`，包括原卡片 ID 和未改写的 `sessionDataJson`。摘要中的有效记录继续参与历史展示和按字段导出，并明确标为保留摘要，不伪造 NFC 读取批次。
- 卡片文档、卡片字段和批次中的未知扩展原样保留。不支持的外层版本拒绝导入；完整备份最外层出现未知扩展字段时，也明确拒绝整次导入，避免多卡合并或单卡重导出时静默丢失封套元数据。

完整备份包含所有字段，不使用字段裁剪；用户在导出对话框中明确选择此模式。卡面路径是元数据，备份不打包手机本地图片或任意外部文件。导入不执行 JSON 中的内容，也不重新查询当前站名库。

导入先完整校验和预览，再在单一事务中重新检查冲突后写入。相同卡指纹合并；本机自定义名和较新观察保留。批次 ID 不重编号，同 ID 不同证据拒绝整批，确保余额来源引用不失效。任何失败都不能留下半张卡或部分批次。顶层格式、字段文件、卡片文档、SQLite schema 和解析口径各自独立版本化。
