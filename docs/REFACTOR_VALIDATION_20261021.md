# TrafArch 完整重构验证与交付记录

> 历史构建记录：本文件中的 `.repair` APK、测试签名和 Android 版本码 2066 属于上一批并装交付。用户随后要求保持原包名测试覆盖安装，当前包名 / 版本码 / 签名交付以 [UPGRADE_HANDOFF_20261021.md](UPGRADE_HANDOFF_20261021.md) 为准。原重构测试、数据和审阅记录继续保留，新批次另有验收日志。

日期：2026-10-21（Asia/Shanghai）。源码 `1.0.1-alpha+2066`，基线 `8a4818e7d4dc848432a3e39a69195255138a3b95`，分支 `refactor/offline-modules-20261020`。所有更改保留在工作树，未提交、未推送、未发布。

用户在本轮明确要求“完整测试，确保可直接交付用于实体卡测试的源码包和 apk 包文件”，覆盖此前取消测试的历史限制。当前交付完成主机自动化、数据、编译与制品校验；真实 NFC 硬件行为和实体卡结果仍须使用下列 APK 验收。

## 最终结果

| 验证项 | 实际结果 | 证据 |
|---|---|---|
| Flutter 全量单元 / Widget / 回放 | **611 项通过，退出码 0** | flutter-test-full-final.log |
| Dart analyzer | **0 error / 0 warning / 0 info，退出码 0** | flutter-analyze-final.log |
| Dart 格式 | 247 个文件，0 changed，退出码 0 | dart-format-final.log |
| Git 空白检查 | 通过，退出码 0；Windows EOL 转换提示另记 | git-diff-check-normalized-final.log |
| Android 原生编译 | Kotlin / Java / 资源构建完成；资源迁移先 clean，再在最终源码上重建 | android-clean.log、构建日志 |
| arm64 Release APK | 构建成功，退出码 0，R8 / 资源压缩启用 | apk-release-build-final.log |
| arm64 Debug APK | 构建成功，退出码 0 | apk-debug-build-final.log |
| Android Lint | **0 error / 7 warning，任务退出码 0** | android-lint-unit-verified.log、android-lint-results-final.xml/html |
| Android 原生 Unit Test | **NO-SOURCE**；项目没有原生测试，不能虚计通过数量 | android-lint-unit-verified.log |
| TU / CU 数据 | integrity / foreign keys 通过，90 / 20 张原表结构与行保留 | final-data-validate.json |
| 相同引擎重建 | 两 SQLite 与 manifest 逐字节一致 | final-data-build-py314.json、final-data-reproducibility.json |
| 依赖 / 迁移 | 216 Dart 库、652 条依赖，无缺失引用、环、协议反向依赖、旧实现 | final-dependency-audit.json |
| Native 静态契约 | 11 Kotlin 文件，无语法 / 空白问题，通道、旧方法及错误码保留 | native-static-verification.json |
| APK 制品 | 签名验证、ZIP CRC、16 KB ZIP 对齐、包名 / 版本 / ABI、两库与清单内容核对 | apk-verification.json、apk-*-*.log |
| 源码 / 补丁 | 交付脚本在干净基线上实际应用完整 binary patch，逐文件比较原始字节与源码 ZIP；真实 Git index 前后哈希核对 | source-reconstruction-receipt.json |
| 源码 / APK 对应 | 构建前后 273 个源码 / 资产 / Android / pubspec 输入哈希相同，并与源码 ZIP 清单交叉核对 | apk-build-inputs.json、source-files-sha256.json、source-reconstruction-receipt.json |

未运行模拟器 / 真实 Android 安装与启动、实体卡读取或生产签名旧版本升级。Widget “启动冒烟”是 Flutter 测试环境，不能当作设备启动结果。

## 测试覆盖与实际修复

- 原有协议、北京公交、CU / TU 查询、上海余额、EMV / PBOC、FeliCa、二维码、UI、档案及导出测试全部纳入全量命令。银行卡中断回归保留先前成功 PAN，同时断言终止错误之后不再进行物理交换。
- 新增运行时契约 9 项：真实发布资产加载、CU 独立打开、命名空间 1210 隔离、线路原码 / 前导零、深圳严格上下文与截止时间、哈希篡改拒绝、设置并发 / 损坏失败保留、会话替换 / 错配和释放错误。
- 部分读取回归 8 项：TU 身份文件中断与地方卡后续历史 / 扩展失败仍保留已观测身份 / 余额；未知与合法零区分，终止后不进行跨协议探测。修复前 6 项失败，修复后 8 项通过。
- 新增档案迁移 / 历史 / pending-save 回归文件共 29 项，使用真实 SQLite v1–v6 旧 DDL，验证真实缺列、坏 / 空 / 未来 / 旧 JSON 原文、幂等重开、前导零、自定义名称、观察时间、offset / 范围、来源合并与保存 ID 所有权。
- 独立字段新鲜度文件 1 项覆盖真实文件关闭重开、同内容重复观察、较新部分读取、迟到保存、合法零和删除重建。批次去重与字段观察时间分离；不改旧批次 readAt。
- 收尾复核又发现 legacy fallback 覆盖持久化时间。新增 v2 / v5 / v6 迁移 → 1000 时刻部分读取 → 重开 → 800 时刻迟到字段的三用例，修复前 3/3 失败，修复后通过。明确观察时间先合并，legacy 时间仅用于无观察证据的字段。
- 日志启停 marker 缺失已修；测试夹具按真实发布文档构造，Widget 中真实 SQLite I/O 使用 runAsync 并释放句柄，消除 fakeAsync 挂起；未删除回归断言或弱化 lint。

## 剩余 warning 的处理

Android Lint 的 7 条为：`UnusedAttribute` 1 条（API 33 的返回手势属性，低版本忽略），`GradleDependency` 1 条（检查当时提示 Firebase BoM 35.0.0 可升级 35.0.2），`IconLauncherShape` 5 条（保留现有五个密度的 legacy 图标轮廓）。没有添加 suppress、baseline 或降低 severity。依赖和品牌图标未为消除提示贸然更换。

初轮 Lint 的 Windows properties 盘符转义和相机特性 errors 已修；重复 / 未使用资源已清理，多余 v21 / v26 资源限定及空目录已移除。第二轮资源增量缓存残留导致 AAPT 失败，clean 后构建和最终 Lint 成功。中间失败日志仅为过程记录。

Gradle / AGP / Flutter 插件仍输出 legacy Kotlin / DSL / applicationVariants 等弃用提示，与上述 7 条 Lint 分开。当前工具链实际构建通过；AGP 10 适配需连同 Flutter 插件另作迁移，未用 suppress 隐藏。

## APK 信息与使用

| 项目 | Release / Debug |
|---|---|
| 包名 | com.kajolno.TrafArch.repair |
| 显示名称 | TrafArch 修复验证版 |
| versionName / code | 1.0.1-alpha-repair / 2066 |
| ABI | arm64-v8a |
| min / target | API 26 / 37 |
| 签名 | Android Debug 测试证书，两包一致；apksigner 验证通过 |
| Debug certificate SHA256 | 170d22e831892df36fcc45994b963c379d6be32e8646fa85b564a4f3c14ef501 |
| 建议 | 实体卡优先 Release，问题诊断使用 Debug；同包名可相互替换 |

验证包可与正式版并装，使用独立数据空间。安装它不会迁移正式版旧数据，因此不能凭并装验证正式版升级。源码不含测试证书私钥或正式签名；开发者本机构建生成的签名可能不同，后续覆盖安装须使用匹配签名。`repairBuild=true` 不消耗正式构建号。ZIP 对齐核验不等同所有设备生命周期或 NFC 兼容性验证。

Release SHA256：`2f90bb32f9a77a4e6969d82e8e1bcfce654d4768f7f6505e47003014f774195d`。

Debug SHA256：`910e66a1e42ccef03e4a2309f9bef97ee4e222fe5fe2745635750d9caaca3ebf`。

两 APK 内的 TU / CU SQLite 与 manifest 均逐字节等于导出的源码资产。TU SHA256 为 `aab2ff4653a9cfac4bdf5ab3f45eb03920acbf2b93bd16953d87e028353ff789`，CU 为 `18d94a2b2e3c5ffd7f2e3943cddf39b1bae6f241a8de90e812d7b04b85a838dc`。

## 可重跑的命令与环境

实际使用 Flutter 3.47.6 stable / Dart 3.13.5、Microsoft OpenJDK 21.0.12.1、Android SDK 37 / Build tools 37.0.0 / NDK 30.0.16248370、Gradle 9.7.1 / AGP 9.4.0。离线数据字节复现使用 Python 3.14，SQLite 精确版本记在发布清单；不同 SQLite 引擎的输出可能不同，validate 会拒绝不匹配，不能将其当作同引擎复现结果。

项目根目录：

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
dart format --output=none --set-exit-if-changed lib test
git diff --check
python -X utf8 -m tools.reference_data validate
flutter build apk --release --target-platform android-arm64 --split-per-abi -PrepairBuild=true -Pforce-version-code-ignoring-abi=true --no-pub
flutter build apk --debug --target-platform android-arm64 --split-per-abi -PrepairBuild=true -Pforce-version-code-ignoring-abi=true --no-pub
.\android\gradlew.bat -p android :app:lintDebug :app:testDebugUnitTest -PrepairBuild=true --console=plain
```

Windows 的 Flutter 可能重写本机 local.properties；直接 Gradle Lint 前需转义盘符冒号（`C\:/...`）。此本机文件不交付。空白检查使用项目正常 Git EOL 规则，Windows CRLF 转换提示不等于行尾空格；补丁导出另用 alternate index 保留原始字节并验证真实 index 未变。原始字节补丁应在 `core.autocrlf=false` 创建的独立干净基线上应用；验证脚本使用同设置的 git archive，避免 Windows 自动换行转换改变基线。

## 独立审阅和证据解释

`final-independent-review.md` 记录修复前两项 P2（TU 身份部分成功、地方卡后续失败）；修后定向与全量回归已通过。`archive-regression-report.md` 记录修前 25 通过 / 1 失败；修后迁移回归为 29 项通过。`final-followup-review.md` 记录 legacy fallback 的新增 P2，`final-followup-resolution-review.md` 是该问题修复后的限定复核。原始历史报告保留，不将修前结论当作最终状态。

独立源码审阅不代替设备测试，主机自动化由父端执行，报告分别标明范围。最终 JSON / 日志、完整补丁应用和源码 ZIP 一致性回执、SHA256SUMS 随交付。源码 ZIP 含所有新目录 / 原始来源 / 工具 / 测试和 Gradle wrapper，不含 .git、SDK / Flutter 缓存、local.properties、私有签名和设备日志。

## 实体卡验收重点

1. 上海实体 TU：按用户给出的唯一余额交换 `80 5C 00 02 04` → `00 00 27 10 90 00`，本地回归首页与档案均为 100 元；仍需实体卡复核原 APK 的 108 元症状。没有固定减 800 分，未声称原始实机根因已证明。
2. 北京公交：核对线路号、站点、原始终端字段和交易时间；参考数据未命中与卡片未返回分别记录。数据库保存全部已有数据，不代表覆盖每条现实线路。
3. 银行卡：检查可读 PAN 标签、应用列表和各应用 EMV / PBOC 结果；万事网联 / 美国运通等双应用逐一复核。卡片未开放标签时不能补造卡号。
4. 中断 / 换卡 / 再次扫描：检查已观测字段与错误诊断、旧会话不能关闭新会话、保存弹窗 ID 和零余额。真实 Android 回调竞态未由主机测试完全证明。
5. 档案升级：备份后用开发者受控同包名 / 同签名构建验证，核对旧 ID、自定义名、历史原文与回填。并装验证 APK 使用独立数据库。

未新增八达通未知余额 / 历史服务，未新增银行卡 / FeliCa 归档策略；无法恢复的旧时区 / 币种 / 来源保持未知并保留原文。
