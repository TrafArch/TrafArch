# 2.x 视觉与交互验收

日期：2026-11-03。分支：2.x-preview。本记录对应本轮源码交付；设计依据见根 [design.md](../design.md)，长期偏好见 [DESIGN_MEMORY.md](DESIGN_MEMORY.md)。

## 需求与证据

| 要求 | 当前实现与验证 |
| --- | --- |
| 亮暗色阶及对比色 | 五套运行时主题分别定义亮暗主色；中性表面分级，青绿／琥珀辅助，状态色与前景容器配对。gallery_design_test 验证五主题×两模式的实际使用文字／表面组合，对比度至少 4.5:1，卡面渐变两端文字同样达标。 |
| 字体与排版 | GalleryTypography 统一页面 26、区块 18、正文 15、技术字段 14、辅助 12；字号／行高／间距共同建立层级。逐段滚动检查 320dp／两倍字号的全部主要内容页、卡片详情各栏及专家四栏；卡面标题、尾号和余额标签防重叠测试通过。 |
| 阴影与下拉 | 贴面／卡片／悬浮／模态四级；浅影配线、双层菜单影、主题化影色，主题插值同时过渡阴影强度。菜单局部 180／120ms 淡入、4dp 位移及 .96→1 缩放，向上翻转并锚定触发器边缘；退出不可交互，预测性返回和减少动画回归通过。 |
| 卡包 | 海蓝／青玉／鸢紫／暖铜预设集中定义；数字与币种分列，固定共同中心线。320／360／412dp×1／1.5／2 倍字号的数字坐标测量通过，另检查负值、长金额、未知余额，卡面样式及只修改目标卡的原有回归通过。 |
| 首页标志与莫奈 | 复用原 SVG 几何，颜色映射有效主题；复用锁定的 dynamic_color 1.9.x，系统不可用回退交通蓝，恢复前台刷新。真实 Android 核心色板整数数组、亮暗主色保持、手动覆盖、恢复系统色及前台刷新均有通道测试。 |
| 主页面滑动 | 五页双向跟手、取消归位、边界不循环、胶囊同步、滑动与点击交替及快速切页覆盖通过；专家标签条滚动不改变内部选择，正文滑动只切主页面，子页面和弹层不误触。 |
| Android 底栏 | 悬浮／下沉共用根系统安全区计算；0／24／48dp、键盘 300dp 展开收起、横屏底部／侧边系统区域均有实际控件坐标断言。正文及提示条由统一总占位推导，不重复计入键盘。 |
| 持续规范 | 已新增根 design.md 和 docs/DESIGN_MEMORY.md，AGENTS.md 添加后续必读入口；现行 Gallery／架构说明及 CHANGELOG 同步更新，历史日期文档未改。 |

## 检查结果

- 全量 Flutter 测试：**2311 通过**；1 项可选本地截图入口在普通全量运行中跳过，已单独执行通过。
- 静态检查：**No issues found**。
- 最后一次 Gallery 专项交互／设计／截图组合：57 项通过；随后增加的横屏与菜单边缘回归已纳入最终全量测试。
- 截图：**22 张**亮暗界面，包括首页、保存卡面、卡包、卡片菜单、行程、筛选菜单、专家、周消费、足迹、外观设置及下沉底栏卡包。使用微软雅黑／Consolas／Material Icons，并开启真实模糊阴影。
- 截图目录：`build/gallery/review/`；亮暗菜单对照：`design-review.png`。可选重现命令见 GALLERY.md。
- 验证日志：`build/gallery/ui-delivery-tests.log`、`ui-analyze-delivery.log`、`ui-gallery-final.log`、`ui-edge-audit.log`、`ui-android-palette.log`。

```powershell
./dev/gallery/test_windows.ps1 --no-pub --concurrency=2 --reporter expanded
flutter analyze --no-pub
```

Windows 全量测试沿用项目现有的启动器，只关闭已记录问题中的 Dart CPU 采样；保留全部测试发现、断言与退出码，未跳过业务测试。

## 数据库与构建

以下为开工前及完成后相同的 SHA256：

| 资产 | SHA256 |
| --- | --- |
| TrafArch_Database_TU.sqlite | `FA585D815B8F29EC52183E71F783FFA3ACD7EACF1CA74907C44F5150E7529DEB` |
| TrafArch_Database_CU.sqlite | `77BA3AD4310782F7625F7B1B1F87A7BC99FEE2420CF9060477B614F1580C6ED3` |
| reference_manifest.json | `EE63A70E93C92812F889FF5DAD150582F3CD9DBEBFA0CBD59353ED62CE153379` |

数据库文件、结构、记录、manifest 和冻结 Gallery fixtures 均未改写。没有运行参考包构建、导入、发布或数据库生成。

上述 UI 源码验收阶段没有生成 APK／AAB，当时 pubspec 为 1.0.3-beta.1+2132。随后用户另行要求构建，追加交付见下文。

## 实际限制

`adb devices -l` 未发现已连接 Android 设备。界面截图来自 Flutter 测试渲染与 Windows 字体，底部使用模拟系统安全区，未伪造系统小白条；它们不等同于 Android 真机字体、系统手势导航外观及帧耗时验收。真机流畅度仍需在设备上核验。新版业务仍使用原有隔离样例，系统取色是本轮接通的只读系统能力。

## 追加安装包交付

用户随后要求构建 arm64-v8a Release。依据当前工作区重新完成全量 2311 项测试与静态检查，使用原签名生成 1.0.3-beta.1／构建号 2133，实拆 versionCode 4133，自动预留下一号 2134。应用名称 TrafArch、包名 com.kajolno.TrafArch，签名、ZIP／全部原生库 ELF 16KiB 对齐及包内参考资产／品牌 SVG 核验通过。

产物及公开报告位于 `build/gallery/release-2133/`，其中 BUILD_REPORT.md 和 apk-verification.json 记录实际清单、原签名、SHA256 与资产比对。数据库及 manifest 保持开工前字节不变；本次没有安装设备。


## 2026-11-03 截图细节调整追加验收

本节记录后续八项细节调整，主页面手势、默认主色及菜单外框以本节和现行 design.md 为准；前文保留上一轮验收证据。

- 分段底轨改为普通表面混入 25% 凹陷表面；默认手动蓝色改为亮色图标同系深靛蓝（#101D50），暗色配套雾靛蓝（#BCC8F0）。系统莫奈仍使用系统角色。
- 卡包普通字号下金额保持卡名右侧，最大金额列宽为可用宽度 40%，同列统一缩放；大字体保留统一上下布局。320／360／412dp 同行和数字中心线回归通过。
- 足迹三项固定一行等宽，数字单行，标签可换行；320dp／1、1.5、2 倍字号回归通过。
- 下拉移除外描边，选项间增加 1dp 分割线；保留双层阴影、选中标记、锚定、键盘和预测性返回。
- 首页识别后卡片从提示高度以 180ms 向下展开，首页列表保持挂载；自动保存开／关均有中间帧断言。减少动画直接显示目标，避免零时长 AnimatedSize 的 SDK 布局断言。
- 详情卡面仅保留名称、适用的交通联合标识、卡号及余额；大字号下内容和布局回归通过。
- 主页面正文横滑不切页，底栏点击仍保留 240ms 左右转场、胶囊移动与中途反向；专家标签滚动、子页预测性返回和各页状态恢复仍通过既有回归。

最终全量：2319 通过，1 项可选截图入口在普通全量运行中跳过；静态检查 No issues found。截图入口单独执行通过，生成 22 张 360dp 亮暗截图，并检查卡包、足迹、菜单、详情与设置。日志及图片位于 build/ui_refinement/，截图总览为 screenshots/review-contact-sheet.png。Windows 截图不代表 Android 真机验收。

数据库前后 SHA256 与前文三项完全相同，证据为 build/ui_refinement/database-before.json 和 database-after.json；数据库、结构、记录、原快照与 manifest 均未修改。本轮未生成安装包，未消耗构建号。


### 细节版追加构建

用户要求保留卡号后，已恢复详情卡面的原有脱敏卡号，并重新完成全量 2319 项测试、静态检查及 22 张源码截图。随后构建原签名 arm64-v8a Release：构建号 2134，实际 versionCode 4134，版本名 1.0.3-beta.1，显示名称 TrafArch，包名 com.kajolno.TrafArch；下一号自动预留 2135。原签名、ZIP／ELF 16KiB 对齐、包内资产与数据库不变性均核验通过，报告位于 build/gallery/release-2134/。未安装 Android 设备。


## 模式切换动画与弹窗按钮追加验收

卡片详情的最近交易／本周消费／卡片信息，以及知识库的 TU／CU 选择器，现在保持列表与滑块状态。选中胶囊沿用 180ms 连续移动，可中途反向；下方内容以 160ms 淡入淡出，各栏独立保存滚动位置。减少动画时直接显示目标。保存和重命名弹窗的确认／取消按钮与主界面共用 14dp 圆角，包括禁用状态。

全量 2325 项测试通过，1 项可选截图测试在普通全量运行中跳过；静态检查 No issues found。截图入口单独运行通过，生成 28 张 360dp 亮暗截图，已检查详情、知识库及亮暗保存弹窗。动画中间帧、快速反向、内容过渡、滚动位置与启用／禁用按钮圆角均有回归覆盖。日志与截图位于 build/ui_switch_motion/；截图来自 Windows Flutter 测试渲染，未进行 Android 真机流畅度验收。

TU／CU 数据库与 reference_manifest.json 的 SHA256 前后完全一致，核对记录为 build/ui_switch_motion/database-before.json 和 database-after.json。本轮未生成 APK／AAB，pubspec 仍为 1.0.3-beta.1+2135，未消耗构建号；此前交付的 4134 安装包不包含本轮修改。

## 底栏与卡包调整追加验收

悬浮底栏移除阴影，模糊 sigma 由 12 增至 14、最大宽度收至 320dp；下沉按钮行由 64 增至 65dp，系统安全区、正文和提示条继续统一计算。底栏仅显示首页、行程、专家和卡包四项；足迹页面及全部 52 个冻结场景保留，用户可见场景为 51 个，没有启用开关。

下沉胶囊背景原先在主题色与透明黑之间插值，产生灰暗中间帧。新增背景像素回归在旧实现上失败：切换后首个 45ms 采样的红色通道为 175，超出背景色与主题色对应的 225–234 范围。修复为固定主题色、仅动画 alpha 后，亮暗／减少动画四组回归全部通过，包含按住、取消、松开、旧新胶囊与快速反向；原有焦点、单层字形、安全区和页面动画回归继续通过。

卡包缩略图采用约 1.586:1、60×38dp 的横向比例。大卡面名称／官方标识在上，余额左下、脱敏卡号右下，长金额和大字号自动改两行；详情仅保留四项信息，首页与预览保留原有辅助说明。列表与大卡面共用纯展示格式，支持 CNY ¥、JPY ¥、HKD $、USD $、MOP ¥，不从裸货币符号猜币种。列表前缀与数字共享列宽，交易数按数字中心线对齐；修复长金额受继承字距影响意外换行的问题，保留原余额字段、导出、交易明细及周统计。

- 全量 Flutter 测试：**2342 通过**，1 项可选截图入口在普通全量中跳过，随后单独运行通过。
- 静态检查：**No issues found**；`git diff --check` 通过。
- 新增 17 项回归；布局覆盖 320／360／412dp × 1／1.5／2 倍字号、五币种、零值、负值、长金额和未知余额。
- 生成 **36 张**亮暗截图，已核对卡包、深圳通／Suica 大卡面、首页已保存卡、下沉底栏、320dp 两倍字号及长金额。截图来自 Windows Flutter 测试渲染与本地字体，未进行 Android 真机视觉或帧耗时验收。
- 日志与截图位于 `build/ui_wallet_nav_refinement/`，包括 `flutter-test.log`、`flutter-analyze.log`、`screenshots.log` 和 `screenshots/`。

TU／CU 数据库与 reference_manifest.json 的 SHA256 前后完全一致，与本文先前记录相同；核对文件为 `build/ui_wallet_nav_refinement/database-before.json` 和 `database-after.json`。数据库、结构、记录、历史快照、manifest 与冻结 Gallery fixtures 未修改。未生成 APK／AAB，pubspec 保持 1.0.3-beta.1+2135，未消耗构建号。

### 底栏与卡包版追加构建

随后按用户要求构建原签名 arm64-v8a Release，入口为 lib/main_gallery.dart。版本名 1.0.3-beta.1，本次构建号 2135，APK 实际 versionCode 4135；显示名称 TrafArch，包名 com.kajolno.TrafArch。开发者原签名、非 debuggable、仅 arm64、ZIP CRC 与 ZIP／全部 7 个原生库 ELF LOAD 16KiB 对齐通过。TU／CU／manifest 的源码 SHA256 与构建前一致，包内字节完全匹配。AppInfo 保留本次 2135，pubspec 自动预留下一号 2136。产物及报告位于 build/gallery/release-2135/；未安装设备，36 张截图仍为源码测试渲染结果。

## 2026-11-07 小窗与折叠屏追加验收

本节记录独立 2.x Gallery 的基础适配。保留单列、四项底栏与现有主题；标题和正文居中限宽 720dp，全部路由和弹层统一落在最大实体铰链子屏，等面积优先左侧再上侧。普通折痕和半折姿态不改变布局。顶部系统功能栏沿用 Flutter captionBar Insets，局部化安全区后再由 Scaffold／SafeArea 消费。

窄窗标题按统一阈值换为两行，导航先收紧留白，再按需统一隐藏标签并保留读屏名称；240dp 及以上四项点击宽度均不小于 48dp。卡包按局部内容宽度统一重排，分段标签和七日图按文字测量横滚，金额完整缩放；矮窗插画缩至 96dp，极矮窗标题区域可独立滚动，保留正文和操作可达。菜单跟随真实触发器，触发器滚出视口后关闭；表单、滚动状态和模拟读取在缩放时继续保持。

最终验证按用户后续指令“不要静态检查，只跑新增回归”执行：`test/gallery_window_layout_test.dart` 的 **8 项行为回归与 1 项截图测试全部通过**，日志为 `build/gallery/window-final-tests.log`。未继续执行静态检查或全量测试，本节不声明最终全量或静态检查通过。

- 连续窗口序列为 390×844 → 240×320 → 280×400 → 600×320 → 600×800 → 840×800 → 1200×900 → 390×844，核验路由／页面身份、专家栏位、筛选、滚动位置和四项导航可访问。
- 覆盖 240／280／320dp、1／1.5／2 倍字号及两种底栏；覆盖顶部 24／48dp、底部 0／24／48dp 与键盘 0／180dp 组合，核验草稿控制器身份和末尾确认操作位置。
- 注入竖向、横向、不对称及等面积实体铰链，检查页面、导航、菜单、弹窗和抽屉不跨遮挡；普通折痕与半折信号不改变布局。另覆盖实时菜单、极矮大字窗操作及缩放中的模拟读取。
- 生成 **18 张**亮暗截图，覆盖小窗首页及操作、卡包、两倍字号、宽窗、竖向／横向铰链、菜单和抽屉。已复核亮暗小窗、宽窗及两种铰链的布局与浮层；截图索引见 `build/gallery/window-review/README.md`。

复现命令：

```powershell
$env:GALLERY_WINDOW_CAPTURE_DIR = 'build/gallery/window-review'
./dev/gallery/test_windows.ps1 --no-pub test/gallery_window_layout_test.dart --concurrency=2 --reporter expanded
```

TU、CU 和 manifest 完工 SHA256 与开工记录完全相同，核对证据为 `build/gallery/window-review/database-verification.json`：

| 资产 | SHA256 |
| --- | --- |
| TrafArch_Database_TU.sqlite | `FA585D815B8F29EC52183E71F783FFA3ACD7EACF1CA74907C44F5150E7529DEB` |
| TrafArch_Database_CU.sqlite | `77BA3AD4310782F7625F7B1B1F87A7BC99FEE2420CF9060477B614F1580C6ED3` |
| reference_manifest.json | `EE63A70E93C92812F889FF5DAD150582F3CD9DBEBFA0CBD59353ED62CE153379` |

数据库、结构、记录、原始日志、保存快照和 manifest 均未修改。保留开工前 AppInfo／pubspec 的未提交版本改动，未生成 APK／AAB，未递增构建号。没有修改原生 NFC／相机契约、增加厂商通道或引入依赖。

截图来自 Windows Flutter 测试渲染，使用本地中文字体和模拟系统 Insets；厂商小窗操作杆、连续拖拽性能、失焦恢复及内外屏切换未进行 Android 真机验收。按已确认的底栏偏好，本轮不声明通过 ITGSA 宽屏导航与全部增值布局认证。
