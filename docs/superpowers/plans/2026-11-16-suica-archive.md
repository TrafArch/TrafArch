# Suica 档案与测试修复实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将 Suica 读取结果保存到卡包，重启后查看冻结行程，统一 JP￥，修复全量测试两个跳过和两个失败。

**Architecture:** 复用现有 v3 snapshot extensions、读取批次和完整档案文档。Suica 通过独立 FeliCa IDm 命名空间关联卡片，逻辑卡号保持 null；记录保留原始字节、日期精度和冻结展示，以原文及同批重复次数去重。

**Tech Stack:** Flutter/Dart、现有 Drift/SQLite 档案、FeliCa 解析器。

**Spec:** 用户本次明确要求档案保存、JP￥或J￥与两个跳过/两个失败修复；采用 JP￥。

## Global Constraints

- 不编译 APK，不变更版本号、AGENTS.md 或数据库表结构。
- 不改参考数据库资产及 manifest，交付核对 SHA256。
- 不把 IDm 当卡号，不把余额差当票价，不将整数日元除以100。
- 不重解析历史站点；未知金额、时间保持未知。

## Review Focus

- 缺失/非法 IDm 不归档；其他协议身份规则不变。
- 重复读取、部分读取与重启后余额来源和自定义名称正确。
- 循环块滑动只合并相同原始记录，同批重复保留。
- 历史损坏或未来版本有提示，完整备份不丢原文。
- 窄屏大字体稳定，未启用截图导出也运行布局检查。

## Tasks

- [x] 添加保存/重启/备份与部分读取 RED 测试，实现 Suica staging 与严格指纹。
- [x] 添加历史投影/详情/计数/导出 RED 测试，实现冻结展示与保守去重。
- [x] 添加日元金额 RED 测试，实现读卡、行程、档案与示例 JP￥。
- [x] 复现 Gallery 滚动振荡，修复补偿；将两个跳过改为默认布局检查；验证 updates fixture 修复。
- [x] 串行定向测试、全量 flutter test、flutter analyze、独立审查与资产哈希核对。

## 资产与版本核对

以下 SHA256 与本轮修改前逐项一致，未修改数据库资产、配套 manifest 或表结构：

| 文件 | 修改前 = 修改后 SHA256 |
| --- | --- |
| assets/data/TrafArch_Database_TU.sqlite | 517c59f3596c06a6ccff40752e7cf39db1bc2b2a76bd74d13d2381ab7ada6c53 |
| assets/data/TrafArch_Database_CU.sqlite | 77ba3ad4310782f7625f7b1b1f87a7bc99fee2420cf9060477b614f1580c6ed3 |
| assets/data/reference_manifest.json | 37cfdbdcdc7d619237f2decc2094367e41e68d853463c6336d3f8cdcc04f23c0 |
| assets/suica/suica_stationcode.db | 57d4fe1af5154e9adab0a4a38619fe8095c7f509ac28c743bf554ba199a43abd |
| assets/suica/manifest.json | 1abde5038c9a5f60ff0b4c7c4006d8bf215e20351bf1d3880afc3f361985864f |

未编译 APK；pubspec 仍为 `1.0.8-beta.2+4192`，AppInfo 保留 `1.0.8-beta.2 / 4191`，本轮未消耗构建号。

## 审查与验证过程

- 保存、磁盘数据库重开、完整备份导入、显示/导出等首轮 9 文件专项 94 项通过。
- 原 Gallery 失败与两组截图测试专项 27 项通过，截图目录缺省也实际编码 PNG。
- 独立审查发现恢复摘要错误除100、同日铁路占位午夜排序两项 P2；均补失败测试后修复，再经独立只读复核无剩余 P1/P2。
- 额外覆盖未知历史不显示0、跨设备时区不重复归档、同日日期/分钟混合精度保持卡内顺序，以及恢复后保存到卡包。
- 全量发现旧日元文案断言和旧数字居中断言；金额预期按用户要求更新，居中断言按现行 design.md 的整组左对齐/4dp间距替换为同样9组尺寸字号的强几何检查。相关57项回归通过。
- 最终 `flutter test --no-pub --reporter expanded`：**2952 项通过、0 失败、0 跳过**（3分24秒，退出码0）。日志：`C:/Users/captu/Documents/Codex/outputs/suicareader-analysis-20261116/archive-full-tests-final.log`。
- `flutter analyze --no-pub`：无error/warning，保留5条既有info；最后以 `--no-fatal-infos` 复核退出码0，未新增info。`git diff --check` 通过。
- 静态检查日志：`C:/Users/captu/Documents/Codex/outputs/suicareader-analysis-20261116/archive-analyze-final.log`。未执行实卡贴卡或设备安装验证。
