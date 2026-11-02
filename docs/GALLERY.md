# TrafArch 2.x 界面 Gallery

设计基线为 Demo 2.4.0，采用独立 Flutter 页面、组件、主题和导航；正式 NFC、协议、档案与参考数据库不作迁移。

## 运行与切换

```powershell
flutter run -t lib/main_gallery.dart
```

默认进入现有界面。在“设置 → 外观”开启“启用新界面（beta）”，新版设置中的同名开关可以关闭。重启恢复现有界面；普通 `lib/main.dart` 入口不显示内部开关。切换会销毁离开的界面会话，新版不会接收真实卡片或业务设置；预测性返回偏好由宿主单独保存。

新版“设置 → 样例管理 → 内置场景”提供 52 个确定性场景和恢复初始样例。初始首页未读取，卡包含深圳通、Suica、八达通三个样例；悬浮底栏、跟随系统、莫奈雾蓝回退，自动保存／上海透支／日志关闭。模拟读取延迟 1600ms，二维码获取延迟 700ms；重置、进入扫码及离开界面会取消对应任务。应用可见内容统一使用“内置样例”等表述，移除“测试”“演示”和 Demo 版本标签；样例来源与尚未保存文件的提示仍明确保留。

悬浮底栏使用单个包住图标与文字的选中胶囊，以 180ms 水平移动；连续点击从当前位置转向新目标。项间距 5dp，下沉底栏保留图标指示器。文字与图标仅绘制一次显式颜色过渡，固定字重，无阴影或触摸焦点描边，键盘焦点单独使用细描边。专家页列表与横向页签保持稳定滚动标识。

动画统一采用无弹跳的 easeOutCubic：主页面按底栏顺序左右滑动 240ms，跨项直达目标，底栏固定；只通过点击底栏切换，不增加整页左右手势。子页进入／返回为 280／220ms，上一页轻微联动；底部抽屉上浮／下沉为 260／200ms，遮罩同步变化；居中弹窗淡入并从 0.96 倍恢复／反向退出为 180／140ms；下拉菜单展开／关闭为 140ms；折叠高度与箭头旋转为 180ms；读取状态与页内页签淡入淡出为 160ms。退出中的内容禁止交互。系统减少动画时取消非必要位移、缩放与等待。

“设置 → 外观 → 预测性返回手势”默认开启。支持的 Android 系统上，子页随返回手势水平露出上一页，抽屉向下收起；取消后恢复当前内容，提交后才真正返回。优先关闭弹层，再退出二维码获取视图，最后返回子页；主功能根页交给系统退出。关闭选项或系统减少动画时保留普通返回。宿主复用 app_settings.txt 的独立键 gallery_predictive_back_enabled 保存偏好，不写数据库；退出新版、重启和恢复样例均保留选择。读取失败使用默认值，保存失败提示本次选择未保存，两者都提供重试。

设置中的“关于”和“问题反馈”为独立全屏页面，沿用新版配色、圆角和排版，返回回到设置的原滚动位置。关于包含图标、版本、作者、致谢、开放源代码许可和隐私政策；致谢与许可也使用独立页面。许可按需读取 Flutter LicenseRegistry。问题反馈提供 QQ 群、邮箱、问卷及复制操作；浏览器不可用时保留链接与重试入口。公共地址集中在 `lib/shared/app_support.dart`，与现有界面共享。

行程筛选与卡片管理均为贴近触发按钮的下拉菜单，不遮暗背景；筛选左对齐，选中标记位于右侧。卡片菜单提供重命名、更改卡面、删除本卡三项，删除保留确认；导出通过页面工具栏进入。菜单会避让屏幕边缘，支持外部点击、返回键和 Esc 关闭；内置场景也复用同一菜单。

## 数据与边界

- 除上述返回手势偏好外，新版设置与所有模拟操作仅在内存生效。
- 所有卡片、行程、证书与原始字节为设计样例。时钟固定为 2026-10-27 09:41 UTC+08:00，二维码样例保留完整 335 字节载荷和 117 字节证书，不执行密码学验签。
- 新版不创建业务依赖或数据库，不调用 NFC、相机、真实相册或文件导出。公共支持链接通过内部宿主注入的回调，仅在用户主动点击后调用浏览器或打开邮件应用；不自动填入、上传或提交卡片与日志。复制仅响应用户操作；导出显示“尚未保存文件”的内容预览。
- 日志开关只收集本次启用后的界面动作，不记录卡名、卡号或站点；关闭停止收集。
- 上海样例总余额原值为 86.50 元，默认显示 78.50 元，每次从原值计算，交易金额与原始字节不变。其他卡片和未知余额保持各自语义。
- 周消费按固定演示周（2026-10-26 至 2026-11-01）统计明确日期与币种的扣款；总额、日均、分类和图表读屏使用样例自身币种，Suica 为整数 JPY，八达通为 HK$，未知币种显示暂不可用。不补写缺失日期，不把充值计入消费。
- 知识库为 2026-10-30 的设计快照，TU 41 地区／7658 编码，CU 7 地区／1732 编码，保留来源与 SHA256；不是当前发布数据库的实时统计。

可离线重新提取设计样例与原始交通联合 SVG：

```powershell
node dev/gallery/extract_demo.cjs '<TrafArch-UI-Redesign 目录>'
```

该脚本仅读取设计 HTML 和场景目录，更新专用 Gallery 资产，不访问或修改发布 SQLite。官方交通联合标识由 `flutter_svg` 直接渲染本地原始 SVG，保持比例与原色。

## 构建与验证

签名配置继续使用仓库外的 `key.properties` 和对应 keystore。为构建进程设置 `TRAFARCH_SIGNING_PROPERTIES`，然后执行：

```powershell
flutter build apk --release -t lib/main_gallery.dart --target-platform android-arm64 --split-per-abi
```

内部 target 排除 Google Services 和 Firebase Analytics，现有界面关闭自动更新检查。名称固定 TrafArch，包名固定 `com.kajolno.TrafArch`，主版本名沿用源码，每次生成安装包预留下一构建号；arm64 保留 ABI 版本偏移。最终核验 APK 清单、证书、对齐和 SHA256。

打包前检查各分支已消耗的构建号及可用交付／设备记录，选择尚未使用的新号。核验时明确传入本次源码构建号与最新已消耗 Android 版本码基线，不以历史固定版本码代替升级比较：

```powershell
python -X utf8 dev/gallery/verify_apk.py '<APK路径>' --build-tools '<Android build-tools目录>' --output '<核验输出目录>' --expected-build-number <本次构建号> --min-version-code <已消耗版本码基线>
```

脚本核验版本名、名称、包名、arm64 ABI 版本偏移、原签名、Release 标记、Gallery 资产、Firebase 自动组件缺席、ZIP CRC／16KiB 对齐及每个原生库的 ELF LOAD 对齐。输出 `apk-verification.json` 与 `SHA256SUMS.txt`，任一检查失败均以非零状态退出；核验报告不代表已完成设备安装。

```powershell
flutter test
flutter analyze
```

### Windows Flutter 3.47.x 测试进程访问冲突

本机 Flutter 3.47.7／Dart 3.13.5 的 `flutter_tester.exe` 会间歇性以 `-1073741819`（`0xC0000005`）退出，剩余用例显示 `did not complete`。默认测试启动的 Dart CPU 性能采样器与官方问题 [dart-lang/sdk#64627](https://github.com/dart-lang/sdk/issues/64627) 的受影响版本一致；当前对照实验支持该原因，尚未捕获本机崩溃栈。不要把这一现象直接描述为 Android 应用闪退，也不要通过跳过断言或删除测试规避。

在仓库根目录，可用下列临时入口执行相同测试：

```powershell
./dev/gallery/test_windows.ps1 --concurrency=2 --reporter expanded
./dev/gallery/test_windows.ps1 test/gallery_controller_test.dart test/gallery_ui_test.dart test/beta_ui_switch_test.dart --concurrency=1 --reporter expanded
```

脚本从 PATH 定位 Flutter，将 SDK 专用启动器模板复制到 `build/gallery/`，使用 SDK 自身的包配置，只移除 Windows `flutter_tester` 的 `--enable-dart-profiling`。Flutter 引擎在该开关缺席时关闭 CPU 采样；测试发现、断言、超时与结果退出码保持原流程。脚本不修改 SDK 或应用构建，使用私有 Flutter 工具接口并限定于 Windows Flutter 3.47.1–3.47.7；SDK 升级后须重新审阅并优先恢复标准 `flutter test`。本次证据见 [测试退出排查记录](GALLERY_TEST_DIAGNOSIS_20261101.md)。

回归覆盖 52 个场景状态、模拟读取／保存／编辑／删除、余额设置、筛选、二维码取消和重置隔离、新旧界面切换、触摸交互与大字体布局；另覆盖页面与弹层动画中间帧、底栏深浅色像素、快速反向切页覆盖、折叠、页签滚动恢复、预测性返回取消／提交、偏好跨宿主恢复及读写失败重试。自动化验证不代表 Android 真机视觉与系统手势验收；本轮未连接设备；安装包核验结果及实际构建号以交付报告为准。
