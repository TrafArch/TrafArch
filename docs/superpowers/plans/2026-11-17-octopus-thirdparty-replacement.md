# 八达通第三方余额读取替换计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 按用户 2026-11-17 的新要求，用所供 Octopus Card Reader 的余额读取流程替换官方联网查询，移除汇率显示、更新与旧联网设置。

**Architecture:** 保留普通读卡及必要的专用 NFC-F 第二阶段，协议由纯 Dart reader 实现；独立余额 controller 管理取消、超时、会话身份及关闭屏障。首页最近扫描和行程摘要通过 AppDependencies 读取本次绑定余额，TU 金额仍取原始 TU 结果。

**Tech Stack:** Flutter / Dart、现有 Kotlin NFC MethodChannel、合成协议及 widget 回归；APK/反汇编材料保存在仓库外。

**Spec:** 用户本轮明确要求及原有统一读取、HK$ 港币余额（￥TU 余额）展示要求；以下协议细节必须由完整第三方分包证据决定。

## Global Constraints

- 保留 TrafArch / com.kajolno.TrafArch、现有 Suica 修改和全部数据库记录；五项数据库/清单前后 SHA256 对照。
- 不将 TU 金额换标签当作 HKD，不从假定汇率推算 HKD；失败余额保持未知，不能显示零。
- 移除产品中的官方联网开关、同意提示、汇率行和更新汇率入口；不再调用官方 OCAP/HTTP 服务。
- 不读取第三方账户或私有数据；ADB 仅用于本轮授权的安装包提取。
- 不猜读卡指令或余额公式；静态分析与合成回归不等于实卡成功。
- 本轮尚无新 APK 编译授权，源码检查完成后再按具体交付结果处理。

## Review Focus

- 卡片离开、发现超时、物理关闭失败：保持旧普通信息并报告部分失败，不卡住扫描状态。
- 切页、重读、内存回收、迟到回调：不得发布已失效余额或启动旧请求。
- 普通 TU 卡与八达通全国通组合：只有识别到八达通才运行第二阶段，原币种/金额不改写。
- 零/负数/大金额、畸形/短响应、错 IDm：精确处理并有边界回归。
- 旧设置中曾启用官方查询：升级后不能再启动官方网络调用；汇率 UI 不得从通用 FeliCa 渲染路径漏出。

## Task 1 — 提取与还原第三方读取

- [x] ADB 获取 com.yeahh.octopus 全部 5 个安装分包，保存文件哈希与完整 ZIP。
- [x] 校验 base 与所附 APK 相同，提取 ARM64 libapp.so / libflutter.so。
- [x] 还原实际读卡指令、余额字段、端序/偏移与换算；核实该路径是否联网。
- [x] 保存可追溯反汇编证据，不把字符串猜测当成完整算法。

**协议证据（2026-11-17）**

- 目标：`com.yeahh.octopus` 1.0.13（versionCode 13），5 个分包经 ADB 拉取；base SHA256 `e103f403434351661e66028c9af0ab33e20a06cdac971ccd453f359a9ef2c9c8`，libapp.so SHA256 `0A5204E29DDE27CC7C686A14CEFB07CD6F8CD3706FBD841014FFE3BBC92F44D0`，libflutter.so SHA256 `AC977AD375350CF07A9CB88B60530F2E035423EB22932AF48C60426D5010AC20`。
- 反汇编：blutter（commit `4a60ac648bf448c5a7596437243bcd0b9376fdf0`）配合 Dart 3.12.2（commit `d684a576a6aa954ae107a03b2b4e1d61c3bebe93`）；证据在仓库外 `C:/Users/captu/Documents/Codex/outputs/Octopus-thirdparty-20261117/core-audit/blutter-output/`，其中 `card_reader_flutter/cardreader/Types/OctopusReader.dart`、`AbstractReader.dart`、`pp.txt` 为可追溯来源。
- 实卡日志：用户同卡由第三方 App 读出 HK$50，与官方 App 一致。2026-11-17 12:21 UTC 只读 logcat 捕获到实际帧（摘录：仓库外 `Octopus-thirdparty-20261117/real-card-logcat-20261117.txt`）：
  - Polling 命令 `060080080117`，响应 `140101011301E2223F08043B46858482CCFF8008`（IDm `01011301E2223F08`）。
  - 余额读取命令 `100601011301E2223F08011701018000`，即 FeliCa Read Without Encryption、服务 `0117`、块列表元素 `8000`。
  - 响应 `1D0701011301E2223F0800000100000352000000000000000000000005`；状态 `0000`、块数 `01`、16 字节块 `00000352...0005`。
  - 余额公式：块字节 2..3 `0352` = 850；`(850-350)/10 = HK$50.00`；反汇编中为 `int.parse(hex4, radix:16)-350` 再除以 10。
- 该读取路径只使用 `flutter_nfc_kit` 的 NFC-F `transceive`，没有 HTTP/OCAP 调用；App 的广告/网络权限不属于余额读取路径。

## Task 2 — 余额协议与会话替换

**Files:** `lib/protocols/octopus/octopus_balance_reader.dart`、`lib/features/octopus/octopus_balance_controller.dart`、`lib/app/app_dependencies.dart`、`lib/features/home/home_page.dart`。

**Interfaces:** `OctopusBalanceResult` 提供 `balanceMinor`、`idmHex`、`readAt`；`OctopusBalanceController` 提供 `read(expectedCardIdm:)`、`cancel()`、`clearResult()`、`busy`、`result`、`lastAttemptSucceeded`、`releaseError`、`progressMessage`、`cancellationRevision`。

- [x] 用第三方算法建立合成正常/异常响应回归，先确认 RED，再实现 reader。
- [x] 保留 sessionId 校验、取消代次、关闭屏障、发现/操作超时；注入执行器验证迟到响应、错卡与关闭失败。
- [x] 默认应用组合使用新读取器；旧官方启用设置不参与新读卡。
- [x] 保留 `isOctopusCard`、`octopusBalanceText`、`octopusReadNotice`、`octopusReadFailure` 页面接口，移除汇率 API。
- [x] 迁移应用层测试后执行相关测试，源码不存在可达的官方查询/更新入口。

实现要点：`OctopusBalanceReader` 只发送 Polling 与 RWE 两帧；校验响应 LEN/响应码/IDm/状态/块数；余额保存为港币分（`(raw-350)*10`），不经过浮点。控制器保持先暂存结果、物理关闭成功后才发布；迟到响应、错卡、取消和关闭失败均不能发布余额。

## Task 3 — 页面与设置

**Files:** `settings_page.dart`、`transit_summary_panel.dart`、`felica_summary_panel.dart`、`trips_page.dart`；相关 settings/pages/balance tests。

- [x] 测试确认设置不存在旧联网开关、页面不存在汇率/更新按钮；先 RED 再改 UI。
- [x] 首页保留唯一读取入口；最近扫描保留组合余额；行程保留卡名卡号/余额/记录数与必要错误提示。
- [x] 删除按钮后不保留空列，验证 320dp/双倍字体；不修改 Suica 视图。

## Task 4 — 完整验证与交付

- [x] 独立复审并处理问题。
- [x] 串行执行相关及全量 Flutter 测试、静态分析；核对输入稳定性、资产哈希。
- [x] 更新当前架构/原生契约的必要说明及当日 CHANGELOG；历史带日期证据不改。
- [x] 报告完整分包路径、源码实现范围、实际验证结果与实卡验证边界。

## Execution notes

- 当前复用用户指定共享 checkout，保留未提交修改；不另建 worktree，不提交/推送。
- UI 子任务可在协议反汇编期间独立进行；Flutter 测试串行，初期由 UI agent 持有测试执行权。
- 初始 base APK 缺 ABI 核心程序的问题已通过用户授权的 ADB 提取解决。

## 执行结果（2026-11-17 续作）

- 已完成 `OctopusBalanceReader`：Polling 使用实卡捕获的 `060080080117`；余额读取使用标准 FeliCa RWE（服务 `0117`、块元素 `8000`）；按实卡块字节 2..3 与 `(raw-350)×10` 得到港币分。未加入写卡、认证或网络调用。
- 新增 `test/octopus_balance_reader_test.dart` 13 项：实卡正常帧、错卡、状态拒绝、块数异常、长度/响应码/截断、取消前后、零/负/大额换算，以及块偏移与缺少 PMm 的边界；控制器新增默认读取器按实卡帧完成的端到端回归，统一读取新增 IDm 派生回归。八达通专项 8 个文件 104 项通过。
- 页面与设置侧的旧联网开关、同意、汇率行和更新按钮均已不存在；`lib/` 中无可达的官方 OCAP/HTTP/update 入口。相关页面回归随专项测试通过。
- 全量 Flutter 测试 3,191 项通过、0 失败；退役线上路径的 OCAP/HTTP/update 测试已移至仓库外，未计入本仓库全量。静态检查无 error/warning，仅保留既有 Gallery 5 条 info。
- 五项数据库/清单资产（TU/CU/Suica SQLite 与两份 manifest）未修改，SHA256 前后一致：TU `517C59F3...A6C53`、CU `77BA3AD4...C6ED3`、参考清单 `37CFDBDC...F23C0`、Suica `57D4FE1A...43ABD`、Suica 清单 `1ABDE503...5864F`。
- 独立复审无阻断项；已处理：优先使用普通 FeliCa 读取到的 IDm 绑定余额（不再因可选系统码元数据缺失而丢弃）、港币改为整数分格式化、重读开始时清除旧结果、Polling 缺少 PMm 时拒绝、补充块偏移与真实读取器集成回归，并修正基础识别“不读取余额”的过期文案。
- 修复卡包仍显示「港币余额未读取」：普通读卡先自动保存，港币第二阶段在保存之后才完成。`ArchiveController.attachVerifiedAccountBalance` 现在把本次 HKD 读数写入该次快照的 `VerifiedAccountBalance`，同步更新 pending 与本次已保存行；TU `balanceFen`/`CNY` 不变。新增 2 项归档回归，八达通专项 106 项通过。
- 残余边界：TU 结果没有可证明的 NFC-F IDm 映射时，组合展示仍依赖用户保持同一张卡连续贴卡的交互上下文（`ARCHITECTURE.md` 已声明，不能宣称跨接口身份已验证）；若用户在第二阶段故意换卡，本机无法从 TU 卡号证明映射。未在 TrafArch 安装包上做实卡端到端验收。
- 按用户本轮明确要求生成 2208 原签名 ARM64 Release 测试包（直接要求覆盖工作区先前的「禁止编译apk」约束）：`TrafArch-1.0.8-beta.2-2208-arm64-release.apk`，35,610,087 字节，SHA256 `d10475c3fe206ce194d4d67e0f70126c5d7f33c63d9cf15c2c0b4fb1d25bea02`；AppInfo 2208，pubspec 预留 2209。
- 随后生成含归档修复的 2209：`TrafArch-1.0.8-beta.2-2209-arm64-release.apk`，35,610,091 字节，SHA256 `d71d9ddf0e7e7d445f54fa911fe505a704ec759a661a155c8d9329f233d279ae`；包名/显示名/证书/v2/CRC/16 KiB 对齐/非 debuggable 均通过，AppInfo 2209，pubspec 预留 2210。产物与核验记录在仓库外 `TrafArch-Octopus-archive-fix-20261117-2209`。
- 仍未安装到手机、未在 TrafArch 本包上做实卡端到端验收；实卡协议证据来自用户同卡的第三方 App 只读 logcat，不等同于 TrafArch 自身原生通道的实卡验收。
