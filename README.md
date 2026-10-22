# TrafArch

基于 Flutter / Dart 与 Android Kotlin NFC 的交通卡读取和分析项目。当前重构以 `8a4818e7d4dc848432a3e39a69195255138a3b95` 为基线，源码版本 `1.0.1-alpha+2066`。当前 alpha 验证包使用 applicationId `com.kajolno.trafarch.alpha`，可与原应用并行安装；arm64 Release APK 使用 Android Debug 证书签名。

项目维护约束：后续每次修改均保持 applicationId **`com.kajolno.trafarch.alpha`**；非正式/测试发布显示名为 **TrafArch Alpha <数字>**（当前为 **TrafArch Alpha 1**），正式发布显示名 **TrafArch**，Debug、Release 和验证构建均适用。具体约束写入 [AGENTS.md](AGENTS.md)。

## 功能与边界

- 交通联合（TU）：电子钱包、公共应用信息、交易明细、SFI 0x1A / 0x1E 乘车过程文件及行程分析。
- 城市一卡通（CU / C-Union）：独立应用读取和独立参考数据库；保留卡内原始文件、城市码、终端码和查询证据。
- 地方交通卡：保留现有北京、上海、深圳、广州、苏州等读取路径。各卡种具体支持范围由卡片开放文件决定。
- 银行卡：EMV / PBOC 只读应用枚举、FCI / GPO / AFL / TLV 解析，按每个应用选择逻辑并保留混合结果。卡号仅在卡片返回相应标签时可提取；本轮未做实卡验证。
- FeliCa：保留现有识别、服务探测和卡适配器。未增加未经证据支持的八达通余额或历史服务。
- JT/T 1179 二维码：应用内相机、系统扫码选项及相册导入，保留纯 Dart 图片解码兜底。
- 交通卡档案：保存读取批次、余额观察和原始证据，支持自定义名、历史详情、删除和导出。银行卡及 FeliCa 未新增归档策略。

系统扫码默认关闭，应用内相机需要相机权限；手动开启系统扫码后使用 Google Play 服务，设备不具备服务时需关闭该开关恢复内置相机。当前 Android 配置使用非捆绑 ML Kit 模型，内置相机首次识别可能需要下载模型；图片导入另有纯 Dart 解码路径。不要把参考数据离线能力理解为所有扫码服务都无需网络。

## 本地参考数据

应用直接读取项目自有发布包，不连接 Trip Reader 数据服务，不在启动时解析 CSV、合并来源或重建知识库索引。

| 发布文件 | 主要内容 |
|---|---|
| `assets/data/TrafArch_Database_TU.sqlite` | TU 原始地区、站点、公交 / BRT、卡前缀、发卡城市及构建好的领域文档 |
| `assets/data/TrafArch_Database_CU.sqlite` | CU 独立站点、终端规则、线路编码、公交字典和卡名文档 |
| `assets/data/reference_manifest.json` | 格式 / 内容版本、SHA256、大小、表计数、来源、冲突决策及字段溯源 |

原始输入冻结在 `data/reference/sources/`；维护工具在 `tools/reference_data/`。用户覆盖和未知站点报告写入独立 `reference_user.sqlite`，与只读参考包分离。数据来源致谢保留，但来源链接不是运行时依赖。

```powershell
python -X utf8 -m tools.reference_data inspect
python -X utf8 -m tools.reference_data build
python -X utf8 -m tools.reference_data validate
```

工具使用 Python 标准库。逐字节重建需与发布清单相同的 SQLite 引擎、输入、策略和工具源码；详见 [离线维护说明](docs/REFERENCE_DATA_TOOLING.md)。不要通过 Gradle 从本机目录覆盖 SQLite 文件。旧 `transitDbMasterDir` 已退役。

## 开发入口

- [Changelog](CHANGELOG.md)：Feature、Bug fix、Refactor、Data、Migration、Docs 和验证限制。
- [架构与目录职责](docs/ARCHITECTURE.md)：控制器、依赖方向、协议和平台边界。
- [迁移说明](docs/MIGRATION.md)：档案 schema 6、快照 v3、用户覆盖迁移、开发者升级步骤。
- [离线数据维护](docs/REFERENCE_DATA_TOOLING.md)：导入、构建、校验、差异报告及 SQL。
- [NFC 会话契约](docs/NATIVE_SESSION_CONTRACT.md)：兼容通道、会话标识、取消与释放失败。
- [旧包名升级交付（历史）](docs/UPGRADE_HANDOFF_20261021.md)：原 `com.kajolno.TrafArch` 升级包的版本码、原证书指纹和未签名 APK 记录，不适用于当前 alpha 并装包。
- [重构验证记录](docs/REFACTOR_VALIDATION_20261021.md)：上一批并装 APK 的历史构建证据及重构测试 / 数据结论；当前安装身份以覆盖安装交付文档为准。

## 环境与验证

项目声明 Dart `^3.13.5`，Android 最低 API 26、编译 / 目标 API 37。Flutter、Android SDK、JDK 和签名配置由开发者本地准备；源码包不包含私钥、Firebase 私有配置或机器路径。版本号取自 `pubspec.yaml`；普通发布构建保留版本递增机制，`repairBuild=true` 的验证构建不递增版本。

用户在 2026-10-21 重新明确授权完整测试和源码 / APK 交付。最终全量 Flutter 测试 611 项通过，Dart analyzer 无问题；Android Kotlin / Gradle 编译及 Release / Debug 构建成功。详细 Lint 警告、签名、资产哈希和交付复验见验证文档。未安装或启动真实设备，未进行实体卡验证。

在项目根目录执行：

```powershell
flutter pub get
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
python -X utf8 -m tools.reference_data validate
flutter build apk --release --target-platform android-arm64 --split-per-abi -PrepairBuild=true -PunsignedApk=true --no-pub
flutter build apk --debug --target-platform android-arm64 --split-per-abi -PrepairBuild=true -PunsignedApk=true --no-pub
.\android\gradlew.bat -p android :app:lintDebug :app:testDebugUnitTest -PrepairBuild=true -PunsignedApk=true --console=plain
```

Windows 直接运行 Gradle Lint 前，若 Flutter 生成的 `android/local.properties` 含未转义的盘符冒号，应写为 `C\:/...`（或 Java properties 的完整反斜杠转义形式）。该文件是本机配置，不随源码交付。原生 Unit Test 任务为 `NO-SOURCE`；611 项指 Dart / Flutter 测试，不能当作 Android 设备测试数量。

当前测试发布 APK 显示名为“TrafArch Alpha 1”，applicationId 为 `com.kajolno.trafarch.alpha`，versionName 为 `1.0.1-alpha`。源码构建号为 2066，arm64 拆包由 Flutter 按 ABI 生成 Android versionCode **4066**。当前 alpha 验证 APK 按用户要求使用 Android Debug 证书签名；Debug 签名不能覆盖原签名应用，也不代表开发者原签名。`repairBuild=true` 仅控制无私有 Firebase 配置和不自动递增构建号；`unsignedApk=true` 明确关闭 Gradle 签名，便于后续使用 Debug 或开发者密钥重签。

alpha 包使用独立 applicationId 和数据空间，可与原应用并存。上海 TU 卡“实际 100 元、原 APK 显示 108 元”已有原始响应到 UI / 档案的 100 元回归用例，但仍需用实体卡复核；代码未加入固定减 8 元补偿。
