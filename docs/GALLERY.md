# TrafArch 2.x 界面 Gallery

设计基线为 Demo 2.4.0，采用独立 Flutter 页面、组件、主题和导航；正式 NFC、协议、档案与参考数据库不作迁移。

## 运行与切换

```powershell
flutter run -t lib/main_gallery.dart
```

默认进入现有界面。在“设置 → 外观”开启“启用新界面（beta）”，新版设置中的同名开关可以关闭。重启恢复现有界面；普通 `lib/main.dart` 入口不显示内部开关。切换会销毁离开的界面会话，新版不会接收真实卡片或设置。

新版“设置 → 演示工具”提供 52 个确定性场景和恢复初始样例。初始首页未读取，卡包含深圳通、Suica、八达通三个样例；悬浮底栏、跟随系统、莫奈雾蓝回退，自动保存／上海透支／日志关闭。模拟读取延迟 1600ms，二维码获取延迟 700ms；重置、进入扫码及离开界面会取消对应任务。

## 数据与边界

- 所有卡片、行程、证书与原始字节为设计样例。时钟固定为 2026-10-27 09:41 UTC+08:00，二维码样例保留完整 335 字节载荷和 117 字节证书，不执行密码学验签。
- 新版不创建业务依赖或数据库，不调用 NFC、相机、真实相册、外链或文件导出。复制原始数据仅响应用户的复制操作；导出显示“尚未保存文件”的内容预览。
- 日志开关只收集本次启用后的界面动作，不记录卡名、卡号或站点；关闭停止收集。
- 上海样例总余额原值为 86.50 元，默认显示 78.50 元，每次从原值计算，交易金额与原始字节不变。其他卡片和未知余额保持各自语义。
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

```powershell
flutter test
flutter analyze
```

回归覆盖 52 个场景状态、模拟读取／保存／编辑／删除、余额设置、筛选、二维码取消和重置隔离、新旧界面切换、触摸交互与大字体布局。用户已要求本轮暂时跳过截图和视觉对照，因此不将本次交付声明为已通过视觉验收；真机界面与覆盖安装仍需设备实测。
