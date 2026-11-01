# TrafArch 2.x 新界面内部预览交接

交接日期：2026-11-01，Asia/Shanghai。本文件是本次工作的交接快照；后续以实际分支、源码和新执行的检查结果为准。

## 1. 新任务先做什么

继续完成 **2.x 新界面 beta 的测试收尾、原签名 arm64-v8a Release 重新构建和最终 APK 核验**。界面代码已经提交，不需要从头重新搭建。用户明确要求暂时跳过截图与视觉对照，当前不恢复该步骤。

先阅读仓库根目录 `AGENTS.md`，再阅读本文件与 `docs/GALLERY.md`。核对当前分支及工作区，保留现有日志，定位未完成的测试；随后重新打包并交付最终 APK。

```powershell
Set-Location 'D:\somehow\GitHub\TrafArch'
git status --short --branch
git log -1 --oneline
```

交接时的状态：

| 项目 | 已核对的值 |
| --- | --- |
| 仓库 | `D:\somehow\GitHub\TrafArch` |
| 当前分支 | `2.x-preview`，跟踪 `origin/2.x-preview` |
| 当前提交 | `4f3195f feat(gallery): 新增 2.x 新界面内部预览功能` |
| 代码状态 | 写本文件前工作区干净；本次仅新增此交接文档 |
| 预览分支 pubspec | `1.0.2-beta.2+2111` |
| 预览分支 AppInfo | 版本名 `1.0.2-beta.2`，构建号 `2110` |

此前暂时切换过 `main`，现已按用户要求返回 `2.x-preview`。Gallery 文件没有丢失，它们在预览分支中。不要在缺少这些文件的 `main` 上重新实现一遍，也不要直接覆盖现有预览提交。

## 2. 用户已经确定的范围

- **前端从零重建**：新版页面、主题、组件、导航独立实现，以设计 Demo 2.4.0 为基线；不是逐项修改旧页面。
- 本轮是 Flutter 手机端 Gallery，新版只用模拟数据，后续再接真实业务。已有读取、协议、档案与参考数据库不作迁移。
- **“启用新界面（beta）”开关**：内部构建默认进入现有界面，在现有“设置 → 外观”开启；新版设置提供关闭入口。仅本次运行生效，重启回到现有界面。
- 新版默认正常 App 体验；“设置 → 演示工具 → 演示场景”进入场景目录，可选择预置状态或重置。
- 完整九页：五个主页面按 **首页 → 行程 → 专家 → 卡包 → 足迹** 排列；二级页为卡片详情、设置、知识库、乘车码解析。
- 模拟卡片、卡包、设置与编辑只存在于内存。相册使用内置样例，导出只展示内容预览，明确尚未保存文件；不调用真实 NFC、相机、相册、文件导出或上传服务。
- 支持系统／浅色／深色、五套手动配色、悬浮／下沉两种底栏。莫奈本轮演示雾蓝回退，真实壁纸取色后续接入。
- 演示时钟固定为 **2026-10-27 09:41 UTC+08:00**；本周统计和二维码时效不随运行日期漂移。
- 用户最后确认交付 **arm64-v8a Release APK**，使用提供的原签名。
- 用户明确说“别截图了，暂时跳过这一步骤”。因此本轮不承诺已通过视觉验收，也不再自动启动截图／图片对比流程。

## 3. 设计与代码入口

设计目录：`C:\Users\Makitoid\Desktop\TrafArch-UI-Redesign`。

| 内容 | 路径 |
| --- | --- |
| 权威设计 demo | `C:\Users\Makitoid\Desktop\TrafArch-UI-Redesign\design-demos\2.4.0-single-Trafarch.html` |
| 当前设计规范 | `C:\Users\Makitoid\Desktop\TrafArch-UI-Redesign\TrafficArch_2.x_Design_Spec.md` |
| 场景原定义 | `C:\Users\Makitoid\Desktop\TrafArch-UI-Redesign\figma-import\source\capture.cjs` |
| 品牌资产规则 | `C:\Users\Makitoid\Desktop\TrafArch-UI-Redesign\brand-spec.md` |

早期 `design-spec.md` 和 `direction-approved.md` 中的四项导航、旧底栏尺寸已过时；使用最新 demo 与当前规范。

下面的代码路径均相对于仓库根目录：

| 子系统 | 入口与职责 |
| --- | --- |
| 内部运行入口 | `lib/main_gallery.dart` → `lib/app/internal_preview_app.dart` |
| beta 开关 | `lib/app/beta_ui_scope.dart`；现有 `lib/features/settings/presentation/settings_page.dart` 仅在内部宿主存在时显示开关 |
| 现有应用兼容 | `lib/app/trafarch_app.dart` 增加默认开启的 `enableUpdateChecks` 参数；内部宿主传 false，普通入口行为不变 |
| 新版根与壳层 | `lib/gallery/gallery_app.dart`，主题、页面切换、返回、PageStorage 与弹层入口 |
| 模拟状态 | `lib/gallery/gallery_controller.dart`，`GalleryController` 与独立的 `GalleryQrController` |
| 数据与主题 | `lib/gallery/gallery_data.dart`、`gallery_theme.dart` |
| 组件与页面 | `lib/gallery/gallery_components.dart`、`gallery_pages.dart`、`gallery_inspection.dart`、`gallery_overlays.dart`，作为主库的 part 文件 |
| 专用资产 | `assets/gallery/fixtures.json`、原始 `tunion-logo.svg`、源设计地图示意 SVG |
| 提取工具 | `dev/gallery/extract_demo.cjs`，离线读取设计目录，生成 Gallery 专用资产 |
| APK 核验工具 | `dev/gallery/verify_apk.py`，已写入但尚未实际完成核验 |
| 说明与变更 | `docs/GALLERY.md`、`docs/ARCHITECTURE.md`、CHANGELOG 最新日期节已补充说明 |

已加入 `flutter_svg: 2.3.2`，保持 `dynamic_color 1.9.x`。交通联合标识直接加载本地原 SVG；不混用新旧 Material 类型。

启动内部预览：

```powershell
flutter run -t lib/main_gallery.dart
```

普通 `lib/main.dart` 不显示内部开关。不能用普通入口打包后，声称已经交付带开关的预览版。

## 4. 已实现的主要行为

- 首页：未读、读取中、成功、失败后保留上次结果、手动保存、自动保存及再次读取。
- 行程：日期分组、双端点卡片、过程事件、来源／方式筛选与详情弹层。最后一轮已把正常筛选交互改成原生 `PopupMenuButton<String>` 下拉菜单。
- 卡包与详情：保存、重命名、删除确认、四种卡面预设、内置图片与恢复默认；首页／列表／详情共享同一内存卡片。详情有三个页签与本周图表；最后一轮补了“分类开销”。
- 专家：四页签，交通卡／银行卡／FeliCa 示例，交通字段分组、九项符合性检查、原始帧与可选择文字。
- 足迹：样例统计、原设计地图示意及站点列表。
- 扫码：扫描、闪光灯、样例相册、有效／过期／格式错误／图片未识别／相机不可用、重试、取消与清除；保留完整 335 字节模拟载荷及 117 字节证书，不做密码学验签。
- 知识库：TU／CU 切换、概况、地区→线路→站点展开；各体系独立保留展开与滚动状态。
- 运行日志：仅启用后记录当前会话的界面操作；关闭停止收集；导出仍为预览。
- 切换、重置与销毁取消模拟计时器；进入扫码取消模拟读卡，迟到回调不能覆盖新状态。
- 上海样例余额从原值 86.50 元计算，关闭透支额度时显示 78.50 元，避免反复扣减；未知值不显示为零。

知识库是 **2026-10-30 的设计快照**：TU 41 地区／7658 编码，CU 7 地区／1732 编码。它与当前发布参考库统计可能不同，不因此手改 SQLite 或快照数字。

需要重新提取专用资产时才运行：

```powershell
node dev/gallery/extract_demo.cjs 'C:\Users\Makitoid\Desktop\TrafArch-UI-Redesign'
```

该脚本不维护正式发布参考数据库；不要凭空重建仓库缺失的 `tools/`。

## 5. 测试真实状态：尚未全绿

不要沿用之前进度消息中的“已通过”作为当前提交的最终验收结果。后面又修改了筛选和分类展示，最后一轮未完整结束。

| 检查 | 已有证据与当前结论 |
| --- | --- |
| 静态检查 | `build/gallery-analyze.log` 显示一次 `No issues found!`；这次检查早于最后的筛选／分类修改，当前提交应重跑 |
| 早期聚焦回归 | 会话中曾有 14 项新功能测试通过；随后加入下拉菜单测试，现在合计 15 项 |
| 最后一轮聚焦回归 | `build/gallery-functional-final.log` 记录 `+14`，最后的大字体测试 `did not complete [E]`，整轮退出失败；不能称 15 项全部通过 |
| 全量默认并发 | `build/gallery-full-test.log` 为 `+1989 -1`，出现加载阶段连接关闭及大量未完成测试，未通过 |
| 全量并发 2 | `build/gallery-full-test-serial.log` 为 `+1977 -2`，仍有 `Connection closed before test suite loaded` 和未完成项，未通过 |
| beta 单独回归 | `build/beta-switch-test.log` 记录两项通过；可见 Drift 多实例调试警告，需要与真正的失败区分 |
| 截图和视觉比对 | 按用户要求跳过，尚未验收 |
| 真机安装／覆盖升级 | 未执行 |

日志都在本机 `D:\somehow\GitHub\TrafArch\build`，属于构建目录，可能随清理消失。**先保留／阅读日志，再决定是否清理缓存。**

优先复测命令：

```powershell
flutter test test/gallery_controller_test.dart test/gallery_ui_test.dart test/beta_ui_switch_test.dart --concurrency=1 --reporter expanded
flutter test test/gallery_ui_test.dart --plain-name 'large text, long fields and both bottom bars fit narrow screens' --reporter expanded
flutter analyze
flutter test --concurrency=1 --reporter expanded
```

`gallery_controller_test.dart` 覆盖 52 个场景状态、读取、保存／编辑／删除、余额、筛选、二维码取消和重置；`gallery_ui_test.dart` 覆盖触摸链路、下拉筛选与 360dp／1.5 倍字大；`beta_ui_switch_test.dart` 覆盖开关与新旧根组件生命周期。

先区分断言失败、原生测试进程异常退出、加载连接断开与人为中断。已有一次 Windows verbose 日志出现 `flutter_tester` 退出码 `-1073741819`，但并未证明所有未完成项都由同一环境问题引起，不应直接跳过或删除测试。

目前已有两处与渲染／生命周期有关的实现选择，排查时注意：

- `GalleryData.load()` 使用 `rootBundle.load` 后在当前 isolate 做 UTF-8／JSON 解码；替换较大文本的隐式后台解码后，beta 切换定向测试曾通过。
- 新主题使用 `InkRipple.splashFactory`；分组容器使用 Material，避免新版 SDK 对有色 DecoratedBox 包裹 ListTile 的断言。不要随意恢复到旧实现后仍沿用旧检查结果。

另有一个需审阅的具体点：`_weekly()` 的金额显示当前固定带 `¥`，请核对 Suica（JPY）与八达通（HKD）的周消费显示，遵守明确币种、未知值不猜测的约束。尚未作为已修复项验收。

## 6. 构建号跨分支差异：打包前必须处理

本次核对发现：

| 分支 | pubspec 下一构建号 | AppInfo 保留的上次构建号 |
| --- | --- | --- |
| `2.x-preview` | 2111 | 2110 |
| `main` | 2115 | 2114 |

主分支信息来自 `git show main:pubspec.yaml` 和 `git show main:lib/app/app_info.dart`，并不等于已核验的 APK 版本。

因此不能简单沿用预览分支 2111，忽略其他分支已经消耗的号。新任务应检查最新源码、已有交付记录和可用的设备版本信息，将预览分支构建号提升到**尚未使用的新号**；若没有后续构建，已观察到的下一候选号是 2115。保持主版本名 `1.0.2-beta.2`，不自行改为 2.0.0 或 2.4.0。

每次实际生成安装包都消耗一个构建号，由既有 Gradle 流程自动预留下一号；普通测试、静态检查、dry-run 不消耗。不要关闭自增，不要用 repairBuild 跳过自增，不要强制忽略 ABI 版本偏移。最终以拆包得到的实际 Android versionCode 为准。

## 7. 原签名 v8a Release 构建与核验

用户提供的签名文件在仓库外，交接时已确认存在：

- `C:\Users\Makitoid\Downloads\key.properties`
- `C:\Users\Makitoid\Downloads\upload-keystore.jks`

使用已有配置加载流程，核对 keystore 路径解析；不要把文件复制入仓库，不打印密码，不用 Debug 签名回退替代原签名。

本机已用工具：Flutter `3.47.7`／Dart `3.13.5`，JBR 位于 `D:\Program Files\android studio\jbr`，Android Build Tools `36.0.0` 位于 `C:\Users\Makitoid\AppData\Local\Android\sdk\build-tools\36.0.0`。终端 PATH 里的 Java 可能是旧版，因此构建进程显式指定 JAVA_HOME。工具缓存和 SDK 目录可能需要按环境的正常提权机制访问，不要擅改系统 ACL。

修复、检查及构建号核对完成后执行：

```powershell
Set-Location 'D:\somehow\GitHub\TrafArch'
$env:JAVA_HOME = 'D:\Program Files\android studio\jbr'
$env:TRAFARCH_SIGNING_PROPERTIES = 'C:\Users\Makitoid\Downloads\key.properties'
flutter build apk --release -t lib/main_gallery.dart --target-platform android-arm64 --split-per-abi
```

默认输出路径：

```text
D:\somehow\GitHub\TrafArch\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
```

身份保持：显示名 `TrafArch`、包名及 namespace `com.kajolno.TrafArch`。不加 `.alpha`／`.repair` 后缀，不改变应用显示名。内部 target 的 Gradle 条件会排除 Google Services 插件与 Firebase Analytics；要核验最终 APK，不能只检查源码。

核验工具已写入，但还没有执行完成和产出有效报告：

```powershell
python -X utf8 dev/gallery/verify_apk.py 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk' --build-tools 'C:/Users/Makitoid/AppData/Local/Android/sdk/build-tools/36.0.0' --output 'build/gallery-delivery-verification'
```

运行前先审阅脚本。它检查清单、签名、ABI、16KiB 对齐、ZIP CRC、Firebase 自动初始化／测量组件和 SHA256，并输出 `apk-verification.json` 与 `SHA256SUMS.txt`。脚本当前仅检查版本码大于历史 4066，**还不足以代替与最新已安装／已发布版本比较**。

原正式证书 SHA256（来源为历史交付文档，需与最终 APK 证书比对）：

```text
3b86c43104ea366997126a8d1600a34b3ccaf83c212a30159eb0853e2e1312b5
```

应逐项确认：名称／包名正确、仅 arm64-v8a、Release 非 debuggable、实际版本码足以升级、证书匹配、对齐／CRC 通过、无 FirebaseInitProvider 和 AppMeasurement 自动组件。交付说明记录真实结果；未接设备时不要宣称已完成覆盖安装。

## 8. 已有 APK 不应当作最终产物交付

本机存在一次成功构建的 APK：`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`。日志为 `build/gallery-release-build.log`，记录 Release 构建成功、约 32.9 MB；本次文件检查长度为 **34,524,727 字节**，最后写入时间为 **2026-10-31 23:55:16 +08:00**。

该产物早于最后的下拉筛选与分类展示改动，且尚未完成实际清单、签名与版本码核验。不要把预期的 4110 写成它的已验证版本码，也不要把“构建成功”写成“已完成交付”。新任务应从当前分支修正后的源码重新构建，再生成完整核验结果和最终文件哈希。

## 9. 建议收尾顺序与完成标准

1. 核对 `2.x-preview`、AGENTS 和源码；保留本机日志，不重做已经存在的 Gallery。
2. 定向复现最后的大字体测试和下拉筛选测试；完成 beta 切换、取消／重置、未知值及币种审阅，必要修复后重跑。
3. 跑静态检查和全量回归；如仍有运行器问题，保留可复现信息、具体未通过项和实际测试范围，不伪称全绿。
4. 对齐尚未消耗的构建号，以仓库外原签名重新构建 arm64-v8a Release。
5. 核验最终 APK，交付 APK、SHA256、测试结果与清单／证书报告；视觉检查继续按用户要求暂缓。
6. 如继续修改，中文 CHANGELOG 并入既有最新日期节；更新当前架构说明，带日期的历史交接文档不随代码改写。

本轮不接入真实新版后台，不新增充值／支付／写卡／云同步，不变更 NFC 通道契约，不手改发布参考 SQLite，不擅自恢复截图任务。

## 10. 新聊天启动提示（可直接粘贴）

```text
继续 TrafArch 2.x 新界面 beta 的收尾工作。
请先阅读 D:\somehow\GitHub\TrafArch\AGENTS.md，以及 D:\somehow\GitHub\TrafArch\docs\GALLERY_HANDOFF_20261101.md。
工作分支是 2.x-preview，已有实现提交 4f3195f，不要从头重新搭建。
先处理最后一轮未完成测试并核对分支之间已消耗的构建号，再使用用户已提供的仓库外原签名，重新编译 arm64-v8a Release APK，完成清单、实际版本码、签名、对齐和 SHA256 核验后交付。
新版继续只用模拟数据；保留“启用新界面（beta）”开关；按照此前要求暂时跳过截图和视觉对照。
```
