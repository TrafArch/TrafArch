# 按城市维护的 TU 数据库更新

当前站点数据使用开发者提供的
`TrafArch_Database_TU_city_sourcekey_sort_cancelled.sqlite`，发布名保持
`assets/data/TrafArch_Database_TU.sqlite`。附件名用于辨认输入，不改变应用资产名。
每个城市的记录继续保存在 `regions.table_name` 指定的原城市表内，例如
`region_天津_1121`、`region_南京_3010`；不建立全城市共享的站点补充表。

## 本次替换范围

- TU 以开发者附件的城市业务表为准；相对增量前发布包新增 427 行，涉及 20 个城市。
- 南京按附件删除 580 条旧 `M0.E.a` 公交记录，不从上一版本补回。
- CU 没有提供新的整理库，因此逐字节恢复至本次社区增量之前的发布包。
- 删除原集中社区表方案、补充 JSON、导入器和专用查询层。来源署名继续保留。
- 不改变附件城市表名、站点 ID、原始编码、前导零、来源字段、原始 JSON 和展示值。

附件新增记录没有现有 `record_provenance` 的关联行，而 `all_records` 使用内连接。
发布器仅按现有已知 TU 来源字段补齐缺失关联，并同步真实统计；不借元数据新建
集中站点资料。附件已有的 `reference_documents` 保持原字节，未把新增城市映射
复制进 `tu_lookup` JSON 文档。全部城市业务行发布后与附件逐行比较。

## 离线发布

发布器使用 Python 标准库，不执行附件中的代码，不联网。输入和基线保存在仓库外，
输出固定为原 TU/CU 资产名及 `reference_manifest.json`。

```powershell
python -X utf8 scripts/reference_data/publish_city_database.py --source-db C:\path\TrafArch_Database_TU_city_sourcekey_sort_cancelled.sqlite --baseline-dir C:\path\before --asset-dir assets/data --report C:\path\city-publish.json
python -X utf8 scripts/reference_data/publish_city_database.py --source-db C:\path\TrafArch_Database_TU_city_sourcekey_sort_cancelled.sqlite --baseline-dir C:\path\before --asset-dir assets/data --report C:\path\city-verify.json --verify
```

`--baseline-dir` 应包含增量前 TU、CU 和清单；不能传入被撤回的集中表版本。
`--fixture-output test/fixtures/developer_tu_city_rows.json` 可输出从输入独立冻结的
新增行测试样本；它只用于测试，不是运行时数据源。

发布前在暂存目录校验完整性、来源关联、表清单、业务行保真和清单哈希，发布异常时
恢复旧输出。完整输入哈希、工具哈希和维护元数据调整记在发布报告与清单中。
同一输入重复发布必须产生相同内容，`--verify` 只验证，不修改发布资产。

## 查询与验证边界

运行时直接读取原城市表。对于原始编码有无城市前缀的两种形式，仅在已确认的
轨道交通应用和来源字段中，按六字节位置字段比较原码前缀；最长匹配按实际消费的
位置字段长度衡量。原始 `source_key` 原样作为查询证据保存。

原有完整地点、历史名称、歧义和读取错误继续保留；同线路的空站名可由城市表补齐。
公交、运营商、处理终端和已知 0x18 终端别名不混入 1E 位置字段。特殊城市原有
终端及位置切片规则继续独立执行，不因数据库更新推导新的字段布局。

开发者资料中存在相同原码的不同名称，以及裸码与带城市前缀记录的名称冲突。
这些原始行全部保留，不按站点 ID 或插入顺序选最后一条。不能仅凭数据重复确认
更名、线路改属或有效日期；冲突与缺少字段依据的记录在验证报告中列出。

新增记录的城市表查询、原视图可见性与实际乘车解析分别验证。合成位置探针和
截图回放不代表实体卡验证，数据已入库也不代表所有终端布局都已确认。
