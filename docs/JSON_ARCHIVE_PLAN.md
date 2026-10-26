# JSON 卡片档案实施计划

设计依据：[JSON_ARCHIVE_DESIGN.md](JSON_ARCHIVE_DESIGN.md)。用户已明确 workflow 负责飞书处理，仅需稳定 JSON；本机固定分支实施，无提交或发布。

## 任务与接口

- [x] 存储：`card_archive_document.dart` 定义 card/archive v1 文档；数据库 v7 的 `archive_documents` 存储规范 JSON，保留 SQL 摘要索引、历史和观察时间。仓库新增 exportDocuments/previewImportDocuments/importDocuments/refreshDocument。
- [x] 表格记录：`archive_export_options.dart` 定义稳定字段与中文标签；`archive_records_json.dart` 提供 projectArchiveRecords/encodeArchiveRecords/decodeArchiveRecords，覆盖 TU、CU、独立过程记录与既有导入记录。
- [x] 平台：ArchiveDocumentStore.openJson/saveJson，Android 系统文档选择器，UTF-8 和 32 MiB 文件限制，取消返回 null，生命周期确保一次响应。
- [x] 编排：ArchiveTransferController 执行选择、校验、预览、确认、事务导入和选择字段导出；AppDependencies 注入并等待进行中的存储任务。
- [x] 界面：卡片页全部/单卡导出和导入；模式和字段选择；导入预览；历史详情明确展示裁剪文件的导入记录。
- [x] 文档：README 用户流程、JSON 格式字段表、合成示例，架构/迁移说明和 CHANGELOG。
- [x] 验收：针对迁移、往返、去重/冲突/原子性、字段隐私、格式校验、取消/并发/销毁的回归；全量 Flutter 测试、analyze、原生编译与测试、独立审查。

## 进度与裁决

- 已核实基线 6074346，原工作树干净；现有 schema6/快照v3/CU投影v1 分别保持自身版本含义。
- 存储回归已先运行，因 archive_documents 尚不存在按预期失败，开始实现。
- 裁决：裁剪字段文件独立保存导入来源，缺少卡身份的记录以规范化文件内容生成命名空间，避免把同名卡合并；保留同一文件内相同记录的出现次数，重复导入幂等。
- 裁决：完整备份保留批次ID；同ID不同原文/元数据拒绝整批导入，避免余额来源引用失效。
- 裁决：不能确定进出方向的CU/TU记录另提供 station/line 字段，避免编造进出站。
- 裁决：合并后被替换的摘要保留独立证据封套，历史与字段导出继续可见，读取批次与余额来源引用不伪造；所有观察时间随选中值更新，显式 null 与 SQL 索引一致。
- 裁决：最外层备份封套的未知扩展明确拒绝导入；卡片/批次中的未知扩展保留。无行程卡片提示使用完整备份，避免生成无法恢复卡片的空记录文件。
- 独立审查已覆盖存储、投影、UI/平台与整体接线，审查发现的封套元数据、1E 编码、未知交易方向问题均纳入回归修复。

## 验证结果（2026-10-26）

- `flutter test --reporter expanded`：1,305 项全部通过，退出码 0；涵盖既有协议/匹配/迁移及新增 JSON 存储、控制器、界面、workflow 示例回归。
- `flutter analyze`：No issues found，退出码 0。
- `gradlew :app:testDebugUnitTest --tests com.kajolno.TrafArch.storage.ArchiveDocumentIoTest -PrepairBuild=true --console=plain`：BUILD SUCCESSFUL；原生文档读写 9 项测试，0 失败、0 错误、0 跳过，包含 Kotlin 主代码编译。
- 定向集成 38 项通过；字段投影审查补充 5 项回归（共 17 项投影测试）后纳入上述全量验证。新用例已先确认失败，覆盖未关联 1E 原码和未知金额方向。
- Dart 变更格式化与 `git diff --check` 通过；Flutter/Gradle 全程串行执行。基线仍为 6074346、分支 dev/harumakigohan；包名与 namespace 为 com.kajolno.TrafArch，pubspec/lockfile/参考数据资产没有变更。
- `adb devices` 没有连接设备。已完成平台通道和原生 I/O 测试，未宣称实机文件选择/保存、真实用户旧库升级、客户 workflow 或飞书端联调通过。本次未构建交付 APK，未安装、提交或推送。
