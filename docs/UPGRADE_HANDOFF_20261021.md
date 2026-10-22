# 2026-10-21 原包名覆盖安装交付

当前交付目录为 `outputs/TrafArch-upgrade-20261021`。本次提供完整重构源码、arm64 Release / Debug 未签名 APK、完整 binary patch、Changelog 和验证证据。用户已明确选择由开发者使用原密钥签名。**未签名 APK 不能直接安装；开发者签名后再进行覆盖安装测试。**

## 应用身份与长期约束

| 项目 | 本次 Release / Debug |
|---|---|
| APK 显示名称 | `TrafArch` |
| applicationId / 包名 | `com.kajolno.TrafArch` |
| versionName | `1.0.1-alpha` |
| 源码版本 | `1.0.1-alpha+2066` |
| Android versionCode | **4066** |
| ABI | 仅 `arm64-v8a` |
| minSdk / targetSdk | 26 / 37 |
| Release / Debug 属性 | Release 非 debuggable，Debug 为 debuggable |
| 当前签名 | 两个 APK 均明确未签名 |

用户要求以后每次修改都保持 APK 显示名称和包名。项目根 `AGENTS.md` 已记录此约束，README 同步说明；Debug、Release、验证构建均适用。不得重新加入 `.repair` 包名后缀或“修复验证版”显示名称。正常版本号可按发布策略维护。

`repairBuild=true` 现在仅用于不自动递增源码构建号、无需本机私有 Firebase 配置的构建；不会改变应用身份。`unsignedApk=true` 明确关闭 Release 和 Debug 的签名。

## 与原 APK 的对应关系

已用 aapt 和 apksigner 核验用户提供的 `app-arm64-v8a-release.apk.1`：原包名 `com.kajolno.TrafArch`、原显示名称 `TrafArch`、versionName `1.0.1-alpha`、Android versionCode **4059**。本次 APK 的 4066 高于原 4059。

Flutter arm64 拆包在源码构建号 2066 上加 ABI 偏移 2000，最终 Android versionCode 为 4066。不要向本批命令传 `force-version-code-ignoring-abi=true`，否则会得到低于原 4059 的 2066。以后每次发布都核对最终 APK 清单中的实际版本码。

原 APK 的正式签名证书 SHA256：

```text
3b86c43104ea366997126a8d1600a34b3ccaf83c212a30159eb0853e2e1312b5
```

原 APK 文件 SHA256：

```text
d6788c2b8bed1099f15e0dc5bd221e4d6c53c7dafd784a39ce98967665fbe773
```

原密钥未包含在本地项目或源码包中。开发者签名后应核对上述证书指纹；本机 Android Debug 测试证书与它不同，不能替代原签名进行覆盖安装。

## 开发者签名与覆盖安装

以下 PowerShell 示例由开发者在本地执行；替换 SDK 路径、密钥路径和别名。密码由 apksigner 交互提示输入，不写入命令、源码或聊天。

```powershell
$env:JAVA_HOME = 'C:\path\to\jdk-21'
$env:Path = "$env:JAVA_HOME\bin;$env:Path"
$bt = 'C:\path\to\Android\Sdk\build-tools\37.0.0'
$unsignedApk = '.\TrafArch-1.0.1-alpha-4066-arm64-release-unsigned.apk'
$signedApk = '.\TrafArch-1.0.1-alpha-4066-arm64-release-signed.apk'

& "$bt\apksigner.bat" sign --ks 'C:\path\to\original-key.jks' --ks-key-alias 'ORIGINAL_ALIAS' --out $signedApk $unsignedApk
if ($LASTEXITCODE -ne 0) { throw 'APK signing failed' }
& "$bt\apksigner.bat" verify --verbose --print-certs $signedApk
if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed' }
& "$bt\zipalign.exe" -c -P 16 -v 4 $signedApk
if ($LASTEXITCODE -ne 0) { throw 'APK alignment verification failed' }
& "$bt\aapt.exe" dump badging $signedApk
if ($LASTEXITCODE -ne 0) { throw 'APK manifest verification failed' }
```

确认签名输出中的证书 SHA256 与上文完全一致，包名 / 显示名称 / 版本码分别为 `com.kajolno.TrafArch` / `TrafArch` / `4066`。APK 已在签名前完成对齐；签名后不要再修改 APK。Debug 包可按同样步骤另行签名，优先使用 Release 做实体卡验收。

备份原应用可导出的档案和数据后，可由开发者或测试者执行 `adb install -r <signed.apk>` 或通过系统安装器覆盖安装。保留原应用进行升级验收；不需要卸载来绕过签名或版本检查。**本次没有实际执行设备安装、启动、覆盖升级或实体卡读取。**

## 本批重新执行的验证

| 检查 | 实际结果 |
|---|---|
| `flutter analyze --no-pub` | 无 issues |
| `flutter test --no-pub --reporter expanded` | 611 项全部通过 |
| `dart format --output=none --set-exit-if-changed lib test` | 247 文件，0 changed |
| `git diff --check` | 通过，按项目正常 Git EOL 设置 |
| arm64 Release / Debug 构建 | 均成功；显式 `--split-per-abi`、`repairBuild=true`、`unsignedApk=true` |
| Android `lintDebug` | 0 errors / 7 warnings |
| Android `testDebugUnitTest` | `NO-SOURCE`，不计为原生设备测试 |
| APK 清单 / ZIP | 两包原名原包、versionCode 4066、仅 arm64、CRC 通过 |
| APK 对齐 / 签名状态 | 两包 `zipalign -c -P 16 -v 4` 通过；apksigner 验证按预期报告未签名，未附带签名块或 META-INF 签名 |
| APK 内置数据 | TU、CU 和 manifest 与当前源码资产逐字节相同 |
| 源码与 APK 对应 | 构建前后 273 个源码、资产、Android 和 pubspec 输入哈希一致；导出时与源码 ZIP 交叉核对 |
| 源码 / 补丁交付 | 在干净基线实际应用完整 binary patch，并与源码 ZIP 逐文件字节比较；回执随包提供 |

Android Lint 7 条提示为：`UnusedAttribute` 1 条（API 33 属性在低版本被忽略）、`GradleDependency` 1 条（检查时提示 Firebase BoM 35.0.0 有更新）、`IconLauncherShape` 5 条（legacy 启动图标轮廓）。未添加 suppress / baseline 或降低 severity。另有 Gradle / Flutter 插件旧 Kotlin / DSL / variant API 弃用提示。保留图标和当前已验证依赖；没有宣称 Android Lint 零警告。

当前全量测试覆盖既有协议、北京公交、TU/CU 查询、银行双应用、上海余额回放、FeliCa、二维码、档案、UI 和导出。上海指定交换 `80 5C 00 02 04` → `00 00 27 10 90 00` 在回归中显示 / 保存为 100 元；没有固定减 800 分的补偿。原 APK 实机显示 108 元的根因仍须实卡证据确认。北京路线 / 站点、可开放的银行卡号、双应用和真实升级档案也需要设备验收。

TU / CU 原始表、线路编码、前导零和使用条件未因本次构建身份修正发生变化。本批离线数据 `validate` 已通过；完整重构阶段的同 SQLite 引擎重建与数据审阅证据在证据包 `refactor-history/` 中保留，按其原始范围解读。

## 文件与重建入口

- `TrafArch-source-upgrade-1.0.1-alpha-2066.zip`：完整当前源码，包括 AGENTS、工具、冻结来源、两套参考数据库、测试和文档。
- `TrafArch-1.0.1-alpha-4066-arm64-release-unsigned.apk`：优先交给开发者签名的 Release。
- `TrafArch-1.0.1-alpha-4066-arm64-debug-unsigned.apk`：诊断用 Debug，同样需要原密钥签名。
- `TrafArch-refactor-from-8a4818e.patch`：针对基线 `8a4818e7d4dc848432a3e39a69195255138a3b95` 的完整补丁，不能盲目重复应用到已合并的后续分支。
- `CHANGELOG.md` / `MIGRATION.md`：全部 Feature / Bug fix / Refactor / Data / Migration / Docs 与迁移边界。
- `TrafArch-upgrade-evidence-20261021.zip`：本批测试、构建、原 APK 签名、当前 APK 核验、源码重建回执及标注范围的重构历史证据。
- `source-files-sha256.json` / `source-reconstruction-receipt.json`：源码清单与实际补丁重建结果。
- `apk-verification.json` / `verification-results.json` / `SHA256SUMS.txt`：本批结构校验、测试摘要与交付文件哈希。

重建命令见项目 README。源码包不含 SDK、Flutter / Gradle 缓存、local.properties、签名私钥、key.properties 或私有 Firebase 配置。完整补丁保留源文件原始字节；应使用 `core.autocrlf=false` 创建基线的独立干净 checkout，再执行 `git -c core.autocrlf=false apply --check <patch>` 与相同设置的 apply。交付脚本实际用同设置的 `git archive` 重建并比较，没有修改真实 Git index。

本批输出与旧 `TrafArch-refactor-20261021` 分目录保存。旧目录里的 `.repair` / 测试签名 / versionCode 2066 是上一批历史产物，不能作为本次覆盖安装包。`REFACTOR_VALIDATION_20261021.md` 已标注历史构建范围；当前身份和签名以本文及本批 JSON 为准。

所有更改保留在当前工作树，未提交、未推送、未发布。
