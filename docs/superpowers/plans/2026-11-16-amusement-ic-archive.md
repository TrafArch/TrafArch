# Amusement IC 卡包保存实施计划

**Goal:** 将已读到的 Amusement IC Access Code 与发行品牌一起存入卡包，重启后在详情页查看和复制。

**Architecture:** 复用现有 PendingCardSave、ArchiveController 和 v3 CardSessionSnapshot，以独立 `amusementIc` 扩展冻结字段和原始证据。Access Code 使用独立指纹命名空间，不占用交通卡号；确认保存、自动保存与恢复后保存复用已有流程。数据库结构无需变化。

**Identity:** `felica:amusement_ic:access-code:<20 digits>`，只有已确认 AIC、有效已知前缀代码与非空品牌才能建档。未读到 Code 的新结果不覆盖旧档案；同 Code 不同 RF IDm 仍关联同卡，保留自定义名称与读取批次。

**Display:** 详情投影使用同一历史批次冻结的 Code 和品牌；损坏或未知扩展版本保留原文并给出提示，可回退旧有效批次。详情与保存确认显示独立 Access Code，复制得到不带分组空格的20位数字；不构造余额、币种或行程。

**Constraints:** 不编译 APK、不调整版本号、不修改 AGENTS 或参考数据资产，不新增数据库表或字段。既有未提交 Suica/AIC 工作保留。完整备份沿原文导出/导入。

## Tasks

- [x] 添加归档身份、快照捕获与 controller 路由，先验证保存回归 RED，再实现。
- [x] 添加严格的历史展示投影与损坏/版本/身份边界测试。
- [x] 卡片详情、卡包列表与保存确认展示品牌及代码，新增显式复制与布局/剪贴板回归。
- [x] 验证手动/自动/恢复保存、重复读取、改名、文件数据库重开与完整备份导入。
- [x] 独立审查、全量测试、静态检查、资产哈希前后比较与文档交付。

## Baseline

- 开始前版本：AppInfo `1.0.8-beta.2 / 4191`，pubspec `1.0.8-beta.2+4192`。
- TU SHA256: `517c59f3596c06a6ccff40752e7cf39db1bc2b2a76bd74d13d2381ab7ada6c53`
- CU SHA256: `77ba3ad4310782f7625f7b1b1f87a7bc99fee2420cf9060477b614f1580c6ed3`
- 参考清单 SHA256: `37cfdbdcdc7d619237f2decc2094367e41e68d853463c6336d3f8cdcc04f23c0`
- Suica库 SHA256: `57d4fe1af5154e9adab0a4a38619fe8095c7f509ac28c743bf554ba199a43abd`
- Suica清单 SHA256: `1abde5038c9a5f60ff0b4c7c4006d8bf215e20351bf1d3880afc3f361985864f`
- 日志：`C:\Users\captu\Documents\Codex\outputs\amusement-ic-archive-20261116`。

## Verification

- 本轮新增 26 项：保存端到端 4 项、历史投影 16 项、实际 UI / 剪贴板 6 项。
- 保存 RED 为 3 项预期失败（尚无待保存项／自动保存／恢复保存），无效字段用例原本通过；投影 RED 缺新增 API；UI RED 为 5 项预期缺显示失败。实现后 38 项定向回归通过，含既有 AIC 展示与 Suica 保存。
- 后续品牌可选择复制及 AIC 通用副标题两项断言先 RED，生产修改后 14 项新旧 AIC UI 测试通过。
- 独立只读审查未发现本轮可确认问题；确认字段同批冻结、缺代码不覆档、其他卡 UI 分支保持。
- TU、CU、Suica 数据库与两个清单的 SHA256 实施后逐项匹配 Baseline；没有修改表结构或参考包。版本／构建号与 Baseline 一致。
- 全量 `flutter test --no-pub`：3034 项通过、0 失败、0 跳过（`full-tests.log`）。随后删除静态检查指出的一处多余类型转换，投影 16 项复跑通过（`projection-final.log`）。
- 最终 `flutter analyze --no-pub --no-fatal-infos`：退出码 0，无 error / warning / 新增 info，保留 Gallery 5 条既有 info（`analyze-final.log`）。`git diff --check` 通过。
