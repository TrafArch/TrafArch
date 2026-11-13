# TrafArch 项目约束

## 数据库铁律（用户于 2026-11-01 明确要求）

- **禁止修改任何现有数据库文件、数据库表结构和数据记录。** TU/CU SQLite、开发者源库和用户档案数据库均适用；排查时只允许只读查询。
- 不得通过 SQL 更新、迁移、离线发布、重新生成、导入、替换数据库文件或改写配套 manifest 绕过禁令。本文其他数据库发布流程说明及历史文档不能作为修改授权。
- 数据匹配错误在解析、查询或展示代码中修复；保留原始城市、线路、站点编码和匹配证据，不篡改原始日志或已保存快照。
- 每次相关修复前后核对数据库资产及配套 manifest 的 SHA256，交付时明确报告是否保持不变。只有用户明确撤销本条禁令后，才可重新讨论数据库修改。

## 项目概览与开发目标

TrafArch 是一款 Android NFC 交通卡读取与分析工具（Flutter + Kotlin 原生），当前处于 Alpha 阶段（见 `README.md`、`CHANGELOG.md`）。开发目标按优先级：

- 读准：扩大卡片兼容性（交通联合 / 城市一卡通 / 地方卡 / FeliCa / 八达通相关产品），修读取回归时必须有对应测试覆盖。
- 识别准：结合内置参考数据识别线路、站点；参考数据改动必须走 `docs/REFERENCE_DATA_TOOLING.md` 的离线 CLI 流程，不手改 sqlite 资产。
- 只读边界：应用只做信息读取与展示，不提供充值、支付或写卡功能；新增功能不得越过这条线。
- 隐私边界：卡片数据、日志可能含卡号、行程等敏感信息；导出与日志相关改动不得默认联网或上传。

## 技术栈与架构边界

详细架构见 `docs/ARCHITECTURE.md`，原生通道契约见 `docs/NATIVE_SESSION_CONTRACT.md`。改动时遵守：

- 依赖方向：UI → `AppDependencies`（`lib/app/app_dependencies.dart`）→ 各 feature 控制器 → `protocols/` 与 `platform/`。协议代码只依赖 Dart、协议领域模型和注入的传输函数，禁止反向引用 app、features、Flutter 平台通道或 SQLite。
- NFC MethodChannel `transit_card_analyzer/nfc` 的方法名、参数键（`apdu` / `frame`，不是 `data`）、sessionId 语义是冻结契约；原生层不做协议解析，改动前先读 `NATIVE_SESSION_CONTRACT.md`。
- 参考数据发布包（`assets/data/TrafArch_Database_TU.sqlite` / `_CU.sqlite` / `reference_manifest.json`）由 Python CLI 构建并校验 SHA256，运行时校验 manifest；不手工编辑这些资产。
- 线路和站点数据按城市存放在 `regions.table_name` 指向的原城市表；禁止新增全城市集中的站点补充表。开发者整理库按 `docs/CITY_DATABASE_UPDATE.md` 发布，保留原库名、表名、原码和业务记录。
- 档案快照结构有版本化迁移（Drift，`lib/features/archive/data/`），改表结构必须写迁移路径并补回归测试；时间 / 币种未知要显式保留，不猜默认值。
- Material 依赖锁定 `dynamic_color 1.9.x`（内置 Material），迁移 material_ui 是整体性工作，不逐点混用。

## 常用命令

在仓库根目录执行：

```bash
flutter test                      # 全量测试；改动必须跑，协议与回归测试都在 test/
flutter analyze                   # 静态检查，lint 规则见 analysis_options.yaml
dart run build_runner build --delete-conflicting-outputs   # Drift 代码生成（改动表后）
python -X utf8 -m tools.reference_data build    # 重建参考数据包
python -X utf8 -m tools.reference_data validate  # 校验发布包与 manifest
```

- 参考数据 CLI 的完整用法（inspect / build / validate / diff / import-csv）见 `docs/REFERENCE_DATA_TOOLING.md`；`tools/` 目录不进 git，本地缺失时先向用户确认来源，不要凭空重建。
- 构建与交付流程（含 unsignedApk / repairBuild 行为）见 `docs/UPGRADE_HANDOFF_20261021.md` 与 CHANGELOG 最新条目。

## 文档与变更约定

- `docs/` 下带日期的文件（如 `*_20261021.md`）是历史证据与交接记录，不随代码现状更新；描述当前架构的只有 `ARCHITECTURE.md`、`NATIVE_SESSION_CONTRACT.md`、`MIGRATION.md`、`REFERENCE_DATA_TOOLING.md`，代码与这些文档冲突时以代码为准并回写文档。
- CHANGELOG 按日期分节、中文书写。用户于 2026-11-13 明确要求：changelog 不定死在单一日期，每条改动按实际更新当天的日期写入对应日期节（什么时候更新就写哪条的时间），不同日期的改动不得并入同一日期节。用户已要求每次构建自动递增构建号，见下方版本约束。

## Android 应用身份

用户在 2026-10-21 曾要求 alpha 并装版本使用独立包名；2026-10-22 明确安装包名改为 `com.kajolno.TrafArch`（与旧正式包完全一致）。后续修复、重构、测试构建与发布均遵守：

- 用户在 2026-10-28 明确要求测试产品也命名为 `TrafArch`；非正式、测试与正式发布 APK 的显示名称均固定为 `TrafArch`。
- Android applicationId / 安装包名固定为 `com.kajolno.TrafArch`，保留原正式包大小写；alpha 并装包 `com.kajolno.trafarch.alpha` 已停用。
- applicationId 与旧正式包相同，安装按覆盖升级处理，不再与原应用并存；只有与旧包相同的签名证书才能升级，Debug 或其他密钥会因 `INSTALL_FAILED_UPDATE_INCOMPATIBLE` 失败，需先卸载旧应用，旧应用数据随之丢失。
- Kotlin namespace 保持 `com.kajolno.TrafArch`，与 applicationId 同值，仅作为原生类命名空间。
- Debug、Release 和验证构建都保持同一 applicationId；不得追加 `.repair` 等 applicationIdSuffix，也不得把显示名称改成 Alpha、“修复验证版”或其他名称。
- 用户在 2026-10-30 明确要求每次构建（包括测试构建及 repairBuild）版本号自增。Debug / Profile / Release 的 APK / AAB 统一使用 pubspec 当前构建号，生成安装包后自动预留下一号；本次产物内 AppInfo 保留本次号。不得再用 repairBuild 跳过自增。普通测试、静态检查与 dry-run 不递增；主版本名未经指示不改。
- 用户在 2026-11-09 明确要求从本次开始，每次修复都构建 APK 用于检验修复成果；完成源码修复及检查后须交付使用开发者原签名的 APK，并报告构建与产物核验结果。
- 验收前核验最终 APK 的实际 Android versionCode，不把源码构建号直接当作拆包后的版本码；串行生成多个安装包时，每次构建均使用不同构建号。
- 后续测试与发布构建使用用户提供的开发者原签名，供覆盖安装；签名材料保存在仓库外，不复制入仓库、不打印密码，不使用 Debug 证书替代原签名。
- 验收最终 APK 的清单，而非仅检查 Gradle 源码；在交付说明中记录显示名称、包名、Android 版本码和签名状态。

`docs/UPGRADE_HANDOFF_20261021.md` 记录旧 `com.kajolno.TrafArch` 升级包的 versionCode 与证书指纹，可用于当前包的升级与签名比对；其中未签名 APK 与 Debug 签名结论仍需按本文约束区分。
