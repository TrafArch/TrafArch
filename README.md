# TrafArch v1.0.1-beta

Flutter + Android Kotlin NFC 的第一版工程骨架。

## 当前版本实现

- Flutter Material 3 UI
- 首页 / 行程 / 交易 / 专家 四个入口
- Android 原生 NFC Reader Mode
- 读取 NFC Tag 基础信息
- NFC-A：UID / ATQA / SAK
- ISO-DEP：连接测试、ATS、历史字节、最大收发长度
- 原始 NFC 信息在专家模式中展示
- 基础交通交易模型与动态 TransitResolver 骨架
- 内置一组示例数据，方便先跑 UI

> v1.0.1-beta 不会向卡片发送任意 APDU，也不会尝试绕过访问控制、读取受保护区域或修改卡片数据。
> 后续可以在合法、已知协议和卡片允许访问的前提下增加具体卡型解析器。

## 使用方法（Windows）

1. 安装 Flutter SDK，并确保 `flutter` 在 PATH。
2. 解压本项目。
3. 在本目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\bootstrap.ps1
```

脚本会在 `_flutter_project/` 中创建一个干净的 Flutter Android 工程，再自动复制本项目源码。

然后：

```powershell
cd _flutter_project
flutter run
```

也可以手动创建：

```powershell
flutter create --platforms=android --org com.example --project-name transit_card_analyzer _flutter_project
```

再把本项目的 `lib/`、`pubspec.yaml`、`android/app/src/main/AndroidManifest.xml` 和 Kotlin NFC 文件复制进去。

## NFC 测试

- 使用真实 Android 手机。
- 打开系统 NFC。
- App 运行后进入“专家”页面。
- 将支持 NFC 的交通卡贴近手机背面。
- App 会进入 Reader Mode 并显示 Tag 基础信息。

当前版本主要验证“Flutter UI ↔ Android NFC 原生层”的链路。
