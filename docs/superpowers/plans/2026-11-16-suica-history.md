# Suica History Implementation Plan

> **For agentic workers:** Use executing-plans / test-driven-development; parallel independent source investigation and reference package work.

**Goal:** 在现有读卡结果和行程页提供 Suica 历史解析、离线站名和可信金额语义。

**Architecture:** 协议层产出纯 Dart Suica 明细，独立 feature 参考包精确匹配站名，
展示层提供行程与恢复投影。沿用原始帧和现有 NFC 会话。

**Tech Stack:** Dart / Flutter、Python 标准库离线提取、现有 sqlite3 与 crypto。

**Spec:** ../specs/2026-11-16-suica-history-design.md

## Global Constraints

- 禁止编译 APK；不改变版本号、签名或原生通道。
- 不修改现有数据库、表结构、业务记录和 TU/CU manifest，前后核对 SHA256。
- 保留工作区已有未提交修改；不自动提交或推送。
- 协议不依赖 Flutter/SQLite/UI；未知时间、币种和站名不猜测。

## Review Focus

- 部分读取和空块不会跨缺口生成余额差。
- 同线路站码在不同地区不会误匹配，特殊端点不会假造站名。
- 只有日期的铁路记录不会显示虚构的 00:00。
- 原始记录、差额依据与冻结站名在诊断/恢复中不丢失。
- 参考库加载失败不影响 NFC 解析，未知站点保留原码。

## Task 1: 协议字段与历史范围

Files: `lib/protocols/felica/models/suica_transaction_details.dart`,
`felica_models.dart`, `parsers/suica_record_parser.dart`, `cards/suica_adapter.dart`,
`cards/felica_card_profiles.dart`, `test/suica_history_test.dart`, `test/felica_module_test.dart`.

- [x] 核对 APK 中字段分类与历史读取范围，记录来源证据。
- [x] 先写字段/读取/缺口测试并验证失败。
- [x] 实现纯字段模型与解析，真实流水号与块号分开；相邻有效记录才计算余额差。
- [x] 定向测试通过，保留异常读取的已读记录。

## Task 2: 独立只读站点包

Files: `dev/suica/publish_suica.py`, `assets/suica/`,
`lib/features/reference_data/data/suica_station_repository.dart`, corresponding tests.

Interface: `SuicaStationRepository.load(AssetBundle)`, `lookup({areaCode,lineCode,stationCode})`,
`close()`, `hash`; immutable station company/line/station names.

- [x] 先写提取与查询测试，验证失败。
- [x] 原样离线提取并验证 6435 条记录、来源哈希、完整性，发布独立清单。
- [x] 运行时验哈希、只读查询，未知和歧义返回 null。
- [x] 运行 Python 与 Dart 定向测试；原库哈希不变。

## Task 3: 行程展示与冻结证据

Files: `lib/features/trips/suica_trip_*.dart`, `trips_page.dart`,
`lib/features/home/presentation/felica_summary_panel.dart`, `summary_formatters.dart`,
`lib/features/scan/`, `lib/features/recovery/`, `lib/app/app_dependencies.dart`, `pubspec.yaml`.

- [x] 先写完整行程/日期精度/未命中/恢复/诊断测试并验证失败。
- [x] 装配参考数据；展示全部记录与详细原码、明确余额差语义。
- [x] 冻结站名与新增字段，恢复不重读卡或重匹配。
- [x] 跑定向回归；更新当前架构、参考包流程与当天 CHANGELOG。

## Task 4: 验证与审查

- [x] 新鲜审查新增差异，修正实际问题。
- [x] 串行执行全量 flutter test 与 flutter analyze，记录结果。
- [x] 校验原 APK、新站库、原 TU/CU 资产和 manifest SHA256。
- [x] 交付源码变化及真机/档案边界，明确未编译 APK。

## 执行与验证记录

- 读取范围和日期精度先真实复现失败，再实施；独立包首轮缺实现失败；并发
  损坏缓存修复先复现 PathNotFoundException 再转绿。JPY 无钱包、无效日期
  精度与特殊记录地点均经针对性 RED → GREEN 验证。
- 最终定向测试：Suica 四份测试、原 FeliCa 模块、更新、解析器/响应诊断及
  内存恢复，共 **112 项通过**。新增 Suica 测试共 36 项。
- Python 离线发布 **5 项通过**，对输入 APK 的 `--verify` 通过。
- 全量 `flutter test --no-pub --reporter expanded`：**2924 通过、2 跳过、2 失败**。
  `updates_test` 的 CU 更新用例原 fixture 未装载新 Suica 资产，补齐 fixture 并
  增加 CU 更新/重启后 Suica 哈希与东京站查询保持不变的断言，已在最终 112 项
  中通过。余下 `gallery_wallet_refinements_test` 的
  `card face keeps its fields separate for long and unknown money` 于第 673 行
  `pumpAndSettle` 超时；本次未修改其测试或 Gallery 实现，不宣称套件全绿。
- `flutter analyze --no-pub`：无 error / warning；本次修改文件无 info，现有
  Gallery 文件保留 5 条 info，工具因已有 info 返回 1。
- 新鲜独立只读审查：未发现 P1/P2。长期档案身份、Gallery 模拟页面、实体卡
  NFC 验收、原有其他 dirty 文件以及站库再分发许可结论不在本次代码验收范围。
  此处是边界记录，不是对真机正确性或来源许可的确认。
- 保留现有工作区，未提交/推送；不编译 APK。pubspec 保持
  `1.0.8-beta.2+4192`，AppInfo 保持 `1.0.8-beta.2 / 4191`，没有消耗构建号。
- 原始 APK 及反编译证据留在仓库外；仓库仅新增独立 Dart 实现、原站库、
  来源清单、离线脚本与测试。新 CLI 放 `dev/suica`，避免被旧 `scripts/` 忽略。

### 数据保真核对

| 文件 | 修改前与修改后 SHA256 |
|---|---|
| TU | `517c59f3596c06a6ccff40752e7cf39db1bc2b2a76bd74d13d2381ab7ada6c53`（相同） |
| CU | `77ba3ad4310782f7625f7b1b1f87a7bc99fee2420cf9060477b614f1580c6ed3`（相同） |
| 原 reference_manifest.json | `37cfdbdcdc7d619237f2decc2094367e41e68d853463c6336d3f8cdcc04f23c0`（相同） |
| Suica 原库 / 新资产 | `57d4fe1af5154e9adab0a4a38619fe8095c7f509ac28c743bf554ba199a43abd`（相同） |
| 新 Suica manifest | `1abde5038c9a5f60ff0b4c7c4006d8bf215e20351bf1d3880afc3f361985864f` |

日志位于仓库外 `C:/Users/captu/Documents/Codex/outputs/suicareader-analysis-20261116/`：
`full-tests.log`、`final-targeted-tests.log`、`analyze-final.log`。
