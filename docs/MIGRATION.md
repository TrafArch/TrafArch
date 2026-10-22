# 迁移与开发者接手说明

当前 alpha 并装包显示名称为 `TrafArch Alpha 1`（非正式/测试发布命名）、applicationId `com.kajolno.trafarch.alpha`，Android versionCode 4066。后续修改继续遵守根目录 AGENTS.md 的名称 / 包名约束。该 APK 按用户要求使用 Android Debug 证书签名，不能覆盖原签名应用；旧 `com.kajolno.TrafArch` 升级记录见[历史交付](UPGRADE_HANDOFF_20261021.md)。`.repair` 并装包同样仅保留为历史。

日期：2026-10-21。本轮已运行真实 SQLite v1–v6 旧 DDL 的自动迁移、坏 / 未来快照、重复打开、字段新鲜度与删除重建回归，并纳入 611 项全量测试。未运行真实 Android 设备升级；正式版升级仍需备份和受控验收。

## 接手步骤

1. 保存当前开发分支和数据库备份，以交付的基线 / 补丁核对是否已合入部分更改。补丁针对 `8a4818e7d4dc848432a3e39a69195255138a3b95`，不能直接当作任意后续分支的补丁。
2. 使用源码包中的 `tools/`、`data/`、两个 SQLite 和 `reference_manifest.json`。不要单独替换一个数据库而保留旧清单。
3. 移除本地 Gradle / 命令行中的 `transitDbMasterDir`。旧的本机路径自动复制会破坏发布包一致性，已停用；检测到该属性时构建配置给出明确迁移提示。
4. 修改数据时新增冻结来源目录、来源描述和审核决策，再运行 `python -X utf8 -m tools.reference_data build` 与 `validate`。逐字节重建需使用清单中记录的 SQLite 引擎版本。
5. 开发环境自行恢复 Android SDK、签名及必要的私有服务配置。源码 ZIP 无密钥、设备数据和 Flutter / Gradle 缓存；同目录另交付已校验结构、对齐和数据资产的 arm64 Release / Debug 未签名 APK，需原密钥签名后安装。构建和测试命令见 README，当前交付证据见 UPGRADE_HANDOFF_20261021.md，完整重构历史见 REFACTOR_VALIDATION_20261021.md。

`lib/core/...`、`lib/state/app_state.dart`、`lib/database/...` 的调用方需按 `REFACTOR_FILE_MAP_20261021.json` 更新。根对象现为 `AppDependencies`；根组件注入点为 `createDependencies`。生成的 Drift `.g.dart` 与主文件同目录，`part` 名称保留。

## 参考包与用户库

- 发布路径继续使用 `assets/data/TrafArch_Database_TU.sqlite` 和 CU 同名文件，不重命名已约定资产。格式版本 1；内容版本是来源、工具、策略和引擎的哈希。
- 已安装参考文件位于 application support 目录的 `trafarch_reference/{tu|cu}-{sha256}.sqlite`，只读打开。包升级产生新的内容地址文件，未删除旧参考文件。
- 用户数据单独位于 application support 目录的 `reference_user.sqlite`，保存 `tu_user_station_overrides`、`tu_unknown_station_reports`、迁移标记和完整原行 JSON。
- 首次打开 TU 前，读取旧路径 `trafarch_db/trafarch_database_tu.sqlite`。在一个事务中迁移覆盖和报告，成功后写 marker。失败回滚、保留旧文件并在知识库页展示错误，不按空库假装成功。
- 覆盖按 `(region_code, source_key, source_field)` 关联，新旧更新时间按 DateTime 比较。无法判定时间时保守保留已有值；完整旧行另存供人工恢复。未知站点报告合并首末时间和次数，marker 防止重复累计。
- 原始 `source_key`、`source_field`、编码线路号和前导零始终保留。TU 的 `1210` 为石家庄，CU 的 `1210` 为锦州。

## 档案 schema 6

应用数据库名称仍是 `transit_card_analyzer`（由 Drift 原有目录策略定位）。升级和 beforeOpen 都在事务中检查实际列：缺失的 `card_number`、`card_number_masked`、余额、币种、交易数和旧快照列按需补齐，创建批次表和查询索引。没有删表重建，也不把 masked 值推断成完整卡号。指纹算法、自定义名称、档案 ID 和已有批次保留。

旧 `saved_cards.session_data_json` 在任何新保存覆盖前回填为历史批次，以精确原文相等去重；坏 JSON、空字符串和未来格式也保留。回填 ID 记录旧 scalar 来源和读取时间取值依据；缺 last_read_at 时明确记录 updated_at / created_at 来源。失败阻止打开或写入，不能绕过迁移覆盖旧内容。

在同一事务中幂等创建辅助表 `archive_field_observation_times(card_id, field_name, observed_at)`，主键为 `(card_id, field_name)`。schema 版本仍为 6；`beforeOpen` 根据真实结构修复，因此既有 v6 也可获得该表。内容相同而被批次去重的读取仍以 UPSERT MAX 记录字段观察时间；不改旧批次内容和 readAt。计算新鲜度时先合并持久化时间和 payload 中的明确观察，只给仍无观察时间的旧字段使用保守兜底；较新部分读取的 lastReadAt 不得覆盖已记录的字段时间。删除档案时清理辅助行。

迟到保存按字段自身的观察时间决定是否更新余额、卡号、交易数和识别信息；较新的部分读取不会把已知余额抹空，较早弹窗确认也不能替换最新捕获。自定义名始终由改名操作维护。旧字段缺少观察证据时采用保守时间界限，不编造缺失历史。

## 快照 v3 与历史展示

v1 / v2 / v3 严格分派；未知版本、错类型和损坏记录显示诊断并保留原文。可解码的有效记录继续展示，不用吞异常把坏内容变成合法空快照。原捕获 parseVersion 不被当前程序版本重标。

v3 增加应用 / 卡系统、币种、精度、观察字段、参考包版本和逐记录来源；原始物理帧、TU / CU 文件与元数据诊断一并保存。0x1A 与 0x1E 的存档独立于页面去重 / 抑制。未读到交易文件与成功读到空文件分别表示为未知和零条。

新记录保存解析时的 civil 时间文本、转换所用设备 offset 及未核实标记，避免查看设备时区改变后显示漂移。设备 offset 不能证明卡片时间所属时区。旧记录仅存 epoch 且无时区时显示稳定 UTC 并标记原始卡内时区未知。越界时间显式诊断，原文保留。

详情与导出共同使用 ArchiveHistory。参考包版本变化不再单独制造一笔重复事件，但每个读取批次和来源仍保留；真实原始字节、线路、站点、币种和语义上下文不同的记录不混同。

## 回退与已知限制

正式设备升级前请备份原应用数据库。回退旧应用读取 schema 6 / v3 的行为本轮未验证，不应视作安全降级流程。源码和补丁包含恢复所需的版本信息，但没有用户实机数据库副本。

上海实体 TU 卡 `80 5C 00 02 04` → `00 00 27 10 90 00` 是 100 元原始余额；原 APK 首页 108 元的原因尚未通过设备验证。保留余额链路诊断，未加入固定减 800 分。北京线路 / 站点和银行卡双应用已调整源码，实卡验收仍待开发者执行。
