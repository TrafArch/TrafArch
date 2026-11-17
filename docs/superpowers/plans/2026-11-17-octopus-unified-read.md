# Octopus Unified Read Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 将普通读卡与已授权的八达通联网查询统一为一个入口，并在现有摘要展示 HKD、TU 金额和卡内汇率。

**Architecture:** AppDependencies 协调普通扫描关闭后进入专用 NFC-F 查询，并绑定结果到当前扫描；OctopusOnlineController 分离持久同意与启用状态；主页面只消费当前绑定的展示模型。纯协议与原生通道不承担 UI 或设置逻辑。

**Tech Stack:** Flutter、Dart、现有 Kotlin NFC session；不新增依赖或数据库。

**Spec:** `docs/superpowers/specs/2026-11-17-octopus-unified-read-design.md`

## Global Constraints

- 使用当前 checkout，保留正在进行的 OCAP 边界修复与诊断。
- 原始 TU 金额、港币结果与历史档案含义不改写；不从 TU 倒算港币。
- 新安装默认关闭联网；首次明确同意持久保存；无授权不请求服务。
- 只在专用操作中更新汇率；普通查询禁止写卡。
- 所有 Flutter 命令串行执行；最终一次构建使用开发者原签名并核验真实版本码。

## Review Focus

- 自动扫描、停止、新扫描与联网设置异步加载的竞争。
- 两阶段读取间 NFC 关闭失败、旧结果或迟到结果混入新卡。
- 首次拒绝、设置写入失败与关闭后重开的同意状态。
- 普通卡、纯 FeliCa 八达通、全国通八达通、无行程与缺失金额。
- 窄屏、大字号、长卡号与余额及更新按钮的位置。

## Task 1 — 设置与持久同意

- 修改 controller、online_actions、SettingsPage；回归在 controller 和 settings widget 测试。
- 提供 `consentAccepted`、`acceptConsentAndEnable()`；`setEnabled(true)` 在已接受后重开。旧版 true 记录迁移为已同意。
- `read({bool updateRate=false, String? expectedCardIdm})` 支持普通 FeliCa 识别后的核对。
- `setOctopusOnlineEnabled(context, app, value)` 只负责设置，不触发读取；更新动作保留确认。
- RED→GREEN，设置与取消/持久化回归。

## Task 2 — 统一扫描协调与展示模型

- 修改 AppDependencies，添加本次绑定的 `currentOctopusResult`。
- 提供 `isOctopusCard`、`octopusBalanceText`、`octopusRateText`、`octopusReadNotice`、`canUpdateOctopusRate`。
- 普通扫描完成且物理关闭后按启用状态继续读取；统一 busy、停止与代次校验，开关关闭不联网。
- 清除旧卡绑定；更新只作用当前绑定，验证 FeliCa 可核对的 IDm。
- RED→GREEN：自动衔接、关闭失败、取消、错卡和离线情形。

## Task 3 — 页面合并

- 修改 HomePage、TransitSummaryPanel、TripsPage；移除两个独立在线面板。
- 首页最近扫描使用组合余额与汇率，纯 FeliCa 八达通也显示；行程无记录仍显示八达通摘要。
- 更新按钮只在八达通摘要出现、位于余额左侧；普通卡展示保持原有语义。
- widget 回归覆盖无独立面板、单读卡按钮、组合值、更新确认、无行程、窄屏和大字号。

## Task 4 — 整体验证与交付

- 独立复核；全量测试及静态检查；资产前后 SHA256。
- 更新当前架构及当天 changelog。
- 构建 ARM64 原签名 APK，核验包名/名称/versionCode/签名/CRC/16 KiB 对齐/包内资产及版本递增。

## 执行结果（2026-11-17）

- 设置、统一读取、页面合并和 OCAP 有界尾部兼容已完成；独立复核发现的在线关闭期间撤销绑定、行程离页取消问题均修复并复核。
- 全量 3220 项测试通过；专项及相关导航测试 157 项通过。原有日志接管与内存恢复时序回归已修复，最终全量再次通过。静态检查仅保留原有 5 条 info，无 error / warning / 新增 info。
- 原签名 ARM64 Release 2201 已生成，清单核验为 `TrafArch` / `com.kajolno.TrafArch` / `1.0.8-beta.2` / `2201`，自动预留下一号 2202。CRC、签名、16 KiB 对齐、包内协议诊断和首次同意标志均通过。
- 产物与详细证据位于 `C:/Users/captu/Documents/Codex/outputs/TrafArch-Octopus-framing-fix-20261117-2201/`。三份数据库和两份清单前后及 APK 内 SHA256 均一致。未进行实体设备安装、读卡或汇率更新验收。
