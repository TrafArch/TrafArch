# Suica 卡片标识与空历史槽修复计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Follow the test-first checks below.

**Goal:** 区分公开可读的 IDm 与不可公开读取的 IDi 卡面编号，支持用户手工保存卡面编号，并修复空历史槽误显示为交易。

**Architecture:** 保留 `felica:suica:idm:` 档案身份。手工编号存入现有完整档案 JSON 的独立用户扩展，不写入已观察卡号、不修改历史快照或数据库结构。空槽只按已证实的精确字节模式过滤，新读取和旧档案展示使用相同规则。

**Tech Stack:** Flutter / Dart、现有 Drift 档案仓库、FeliCa 只读协议。

**Spec:** 用户反馈 JE 卡面编号缺失，并于本轮确认“都做”：修正提示、显示 IDm，同时增加手工填写及保存入口。手工字段支持修改、清除、复制，再次读取保留。遵守当前不编译 APK 的项目约束。

## 依据与边界

- 实卡日志只含 polling、系统码、090F 服务和20个历史块；没有 IDi 数据。日志原件留在用户提供位置，不复制真实卡号或 IDm 到测试。
- [ICカードこれひとつ 开发商 FAQ](https://allnfc.app/jp/faq/tran_zen.html) 的 IDi 条目说明 JE 等开头号码处于加密区；[Metrodroid 原始实现](https://raw.githubusercontent.com/metrodroid/metrodroid/master/src/commonMain/kotlin/au/id/micolous/metrodroid/transit/suica/SuicaTransitData.kt) 的 serialNumber 为空。不能从 IDm 推测卡面号。
- 实卡块0为新卡发行、2026-08-22、JP￥500。其余为9个全零块和10个仅第4字节为80的空槽；所有原始块仍保留。
- 手工输入仅校验两字母及15位数字的外观格式，不声称验证发行方校验码或持卡真实性。
- 用户补充确认日本交通卡分组规则：首组两字母加三位数字，后续三组各四位；例如 `JE123 4567 8901 2345`。现有 `SuicaManualNumber.formatted` 及存储/UI回归已覆盖此格式，不使用Amusement IC的四位均分规则。
- 参考库、manifest、版本号、AGENTS.md 不改；不提交或推送。

## 执行与验证

- [x] 实卡原始块、源码和公开原始资料交叉核查。
- [x] 空槽 parser / adapter replay / 旧档案投影 / count / export 回归先复现4项失败。
- [x] IDm 展示、IDi 说明、旧档案及冲突身份 UI 回归先复现7项失败。
- [x] 最小修复空槽判定和读卡、保存确认、卡包列表、详情标识展示。
- [x] 手工编号独立扩展的保存、修改、清除、重读保留、备份恢复和流刷新先测后实现。
- [x] 卡包详情手工填写、错误提示、持久化重开、复制和清除交互回归。
- [x] 独立审查身份冲突、未知字段保护、旧备份冲突与空槽精确边界。
- [x] 串行执行定向测试、全量 `flutter test` 和 `flutter analyze`，记录实际结果。
- [x] 核对五份参考数据资产 SHA256 与修复前完全一致，更新 CHANGELOG。

## 验证记录

本轮日志与资产修复前 SHA256 位于仓库外 `C:/Users/captu/Documents/Codex/outputs/TrafArch-Suica-identity-fix-20261116/`。测试不代表手机安装或受保护 IDi 读取验证。

Suica 修复阶段定向57项通过；首轮全量3068项通过、0失败、0跳过。审查指出的列表/详情跨批身份不一致和不支持手工扩展误提供编辑入口均先复现后修复，复审已关闭。静态检查新增的一处null-aware集合写法已清理；最终结果在追加需求完成后复核。

## 同轮追加：Amusement IC 卡包名称和卡号区

用户要求卡包保存后的名称显示 `Amusement IC ( Aime )`（按已保存发行品牌替换括号内容），卡号位置显示每4位分组的Access Code。现有自定义名称继续保留，副标题显示带品牌的完整默认名称；复制仍为连续20位代码。

- [x] 先补保存确认、卡包列表与详情回归；保留窄屏、品牌复制、Access Code复制和坏快照回退。
- [x] 从完整历史的有效冻结资料生成名称和号码，不改NFC解析、指纹、逻辑cardNumber或旧快照；列表无逐卡额外查询。
- [x] 新旧档案和各发行品牌共用展示规则，读取不完整时不猜Code或发行品牌。
- [x] 独立审查后串行运行定向、全量测试和静态检查，再次确认资产不变。

## 最终验收

- AIC更新后的联合专项：63项通过。
- 最终全量：3074项通过、0失败、0跳过，退出码0；本轮共新增36项测试。
- `flutter analyze --no-pub --no-fatal-infos`：退出码0，无error/warning，仅5条既有Gallery info。
- 两项Suica展示审查问题均补RED、修复并复审关闭；AIC最终审查无可行动P1/P2。
- 参考数据及清单5份SHA256修复前后完全一致；AGENTS.md未修改。完整哈希见仓库外交付目录的 `assets-verification.json`。
- 最终机器可读验收记录：`C:/Users/captu/Documents/Codex/outputs/TrafArch-Suica-identity-fix-20261116/verification.json`。
- 未编译APK，pubspec仍为 `1.0.8-beta.2+2196`，AppInfo保留此前产物号 `2195`。未提交、推送或进行此版本手机实测。

## 后续授权构建（同日2196）

用户随后明确授权编译，并要求使用开发者原签名。已从上述通过验证的源码构建正常入口ARM64 Release：实际APK versionCode为2196、AppInfo为2196、pubspec自动预留2197，签名与开发者原证书一致。

交付文件位于 `C:/Users/captu/Documents/Codex/outputs/TrafArch-Suica-AmusementIC-20261116-2196/TrafArch-1.0.8-beta.2-2196-arm64-release.apk`；SHA256为 `357c840e14b8c8f3210aa0b785f4e375901c4eaa9e8690f526b91b553e7d364d`。

同目录 `delivery-verification.json`、`feature-payload-verification.json` 和 `aot-feature-check.json` 记录清单/原签名/16 KiB对齐、包内参考数据与Firebase配置检查，以及实际AOT中新手工卡面编号和AIC新名称展示的标记；五份参考数据及清单构建前后与包内哈希一致。未执行设备安装，用户将自行实卡测试。
