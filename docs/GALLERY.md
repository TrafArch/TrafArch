# TrafArch 2.x 界面 Gallery

设计基线为 Demo 2.4.0，采用独立 Flutter 页面、组件、主题和导航；正式 NFC、协议、档案与参考数据库不作迁移。

## 运行与切换

```powershell
flutter run -t lib/main_gallery.dart
```

默认进入现有界面。在“设置 → 外观”开启“启用新界面（beta）”，新版设置中的同名开关可以关闭。重启恢复现有界面；普通 `lib/main.dart` 入口不显示内部开关。切换会销毁离开的界面会话，新版不会接收真实卡片或设置。

新版“设置 → 演示工具”提供 52 个确定性场景和恢复初始样例。初始首页未读取，卡包含深圳通、Suica、八达通三个样例；悬浮底栏、跟随系统、莫奈雾蓝回退，自动保存／上海透支／日志关闭。模拟读取延迟 1600ms，二维码获取延迟 700ms；重置、进入扫码及离开界面会取消对应任务。

悬浮底栏按 Demo 2.4.0 使用包住图标与文字的整项选中胶囊，项间距 5dp；下沉底栏使用图标指示器。切换页面为 220ms 淡入与 8dp 位移动画，退出内容不参与触摸、焦点或读屏；系统减少动画时立即切换。按钮按下不出现水波纹、灰色遮罩或抬升阴影，键盘焦点仍有提示。

行程筛选与卡片管理均为贴近触发按钮的下拉菜单，不遮暗背景；筛选左对齐，选中标记位于右侧。卡片菜单提供重命名、更改卡面、删除本卡三项，删除保留确认；导出通过页面工具栏进入。菜单会避让屏幕边缘，支持外部点击、返回键和 Esc 关闭；演示场景也复用同一菜单。

## 数据与边界

- 所有卡片、行程、证书与原始字节为设计样例。时钟固定为 2026-10-27 09:41 UTC+08:00，二维码样例保留完整 335 字节载荷和 117 字节证书，不执行密码学验签。
- 新版不创建业务依赖或数据库，不调用 NFC、相机、真实相册、外链或文件导出。复制原始数据仅响应用户的复制操作；导出显示“尚未保存文件”的内容预览。
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

回归覆盖 52 个场景状态、模拟读取／保存／编辑／删除、余额设置、筛选、二维码取消和重置隔离、新旧界面切换、触摸交互与大字体布局。用户已要求本轮暂时跳过截图和视觉对照，因此不将本次交付声明为已通过视觉验收；真机界面与覆盖安装仍需设备实测。
