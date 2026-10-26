# 迁移与开发者接手说明

当前源码 applicationId / namespace 为 `com.kajolno.TrafArch`，后续修改遵守根目录 AGENTS.md 的应用身份约束。旧 alpha / `.repair` 并装方案仅为历史；新 APK 的实际版本码和签名需在交付时核验，不能从历史构建说明推定。

## JSON 档案 v7 迁移

本次数据库 schema 升至 7，新增 `archive_documents(card_id, payload_json, dirty)`；不会重建、删除旧卡片或重解析快照。迁移保留完整卡片摘要、原始批次 ID/文本、每字段观察时间。保存、重命名和导入与 JSON 文档更新在同一事务完成；旧路径写入索引由触发器置 dirty，读取前刷新。已存在的完整文档再次打开时不把摘要补造为新批次。

完整备份导入保留原始批次标识，按卡指纹合并，同 ID 不同内容拒绝整批写入。自定义名称和较新的已观察字段保留；只含选定字段的 JSON 使用独立导入身份及原始行保存，不能当成完整 NFC 捕获。快照格式版本仍为 v1/v2/v3，CU 扩展仍为 v1，均与新外层 JSON 版本 1 独立。详细契约见 [JSON_ARCHIVE_FORMAT.md](JSON_ARCHIVE_FORMAT.md)。

合并替换的原始摘要保留在 `retainedSummaries`，详情与字段导出仍能读取其中有效记录，不能算作新 NFC 批次。摘要空值与观察时间索引在同一事务同步，避免重开或重命名后恢复过时字段。卡片/批次未知扩展保留，完整备份最外层未知扩展明确拒绝导入。

## TU 行程余额解析 v8

行程解析口径 `kTripParseVersion` 为 8；数据库 schema 7、快照格式 v3 和完整 JSON 外层版本 1 均不因此改变。交易后余额由最新原始槽位 1 对应的当前钱包余额沿连续 0x18 交易倒推。遇到槽位缺口、未知交易金额方向或顺序冲突时中断，不跨缺失交易计算。P1=03 观察值、八达通 TU 未核验口径仍不能作为钱包锚点。

1E 的 `balanceFen` 仅代表原始记录余额，不统一假定交易前或交易后，也不全局减去本次金额。有钱包连续倒推值时以其为准；没有倒推值时，严格唯一匹配的 1E 余额仍可展示为「记录余额」，但不能作为更旧交易的新锚点。1E 原始字节、线路站点关联及相对 1A 的优先级继续保留。

新快照显式写入 `balanceAfterIsRecorded`：`false` 为钱包或连续倒推的交易后余额，`true` 为原始记录余额。v8 恢复与归档展示不再通过金额相等猜测来源；未知余额保持 null。历史、文本和 JSON 字段导出共用余额投影，完整备份保留原始捕获文本和解析版本。跨口径的记录只有实际展示语义相同才允许合并。

v1–v7 捕获仍按原规则读取，不以新钱包或合并后的行程列表重新计算。旧快照没有完整的原始槽位连续性证据，自动改写会引入无法验证的余额；安装修复版后重新读卡即可生成 v8 批次。截图中的序号 41/40/39/38 已用于合成回归，预期交易后余额为 118.50/125.50/125.50/175.50 元；合成记录不等同于该次真实 APDU 回放或实卡验收。

## 外部签名配置

签名材料应保存在仓库外。配置有效时，Release 和 Debug 构建均使用该密钥。查找 properties 的优先级为：Gradle 属性 `trafarchSigningProperties`、环境变量 `TRAFARCH_SIGNING_PROPERTIES`、用户目录 `.config/TrafArch/signing/key.properties`、原有 `android/key.properties`。最后一项仅为旧开发环境兼容；新环境使用外部目录，不把密钥或密码放进源码树。

外部 properties 使用 `storeFile/storePassword/keyAlias/keyPassword` 四个字段；其中相对 `storeFile` 以 properties 所在目录为基准，绝对路径保持原义。旧 `android/key.properties` 的相对路径仍以 `android/app` 为基准。已选择的配置缺失或无效时失败，不能静默改用 Debug 证书；`unsignedApk=true` 仍明确禁用签名。没有任何签名配置时保留作者原有 Debug 回退行为，不能将其当成开发者签名发布。

密码不得出现在命令行参数、日志或文档中。构建后核验最终 APK 的签名证书、包名、显示名、实际 versionCode 和对齐；`repairBuild=true` 保持源码构建号不递增，使用时需核对应用内 `app_info.dart` 与 `pubspec.yaml` 一致。

## 历史迁移验收记录

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
