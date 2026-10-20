# TrafArch 读取修复与上海余额复测说明

日期：2026-10-20。基于 GitHub `kajolno/TrafArch` 的 `f2e4f17`，未推送至远程。

## 上海交通联合实体卡：已确认事实与当前边界

用户确认：此前提供的 `app-arm64-v8a-release.apk.1`，刚读卡后的首页余额显示 108 元；实际余额 100 元；同次只有 `80 5C 00 02 04` 这一条余额查询，没有其它 `5C` 查询。响应为：

```text
>> 80 5C 00 02 04
<< 00 00 27 10 90 00
```

`0x2710 = 10000` 分，响应本身为 100 元。不能据此把多出的 8 元判定为透支额，也不能对所有上海卡固定减去 800 分。

在这份源码中，从 NFC 通道回放上述响应，经过真实读取器、AppState、分析模型、SQLite 存档和首页组件，结果均为 100 元；旧存档 108 元会被新读数 100 元替换。该用例的余额响应来自用户，卡号、发行信息与其它响应均为合成数据。它证明的是源码链路行为，不等于已经复现或修好了原 APK 上的 100→108。

另已复现并修复一个独立缺陷：`P1=00` 成功返回 0 时，旧逻辑继续读取 `P1=03`，可能用另一个金额覆盖 0。现在有效的 0 与其它成功余额同样被保留。

修复验证版在 APDU 页新增以下诊断行，不包含卡号：

```text
== 余额核对：parser=tunion; aid=A000000632010105; parsedFen=10000; display=¥100.00; archiveFen=10000; cuFen=null ==
```

`parsedFen` 为解析层的分值，`display` 是 TU 首页使用的显示文本，`archiveFen` 是待存档分值，`cuFen` 是单独的 CU 钱包读数。实际是否双应用及 AID 以卡片响应为准。

实体卡复测：使用名称为“**TrafArch 修复验证版**”的应用读同一张卡，记录首页余额。如果仍出现 108 元，请保留同次读取的全部 `5C` 指令/响应与这一行余额核对，以及首页显示。无需提供卡号。原 APK 的异常仍须通过实体卡复测或完整会话回放定位。

## 公交与地铁

- 北京公交：加入从 Trip Reader 原有规则还原的线路解码，覆盖普通线路、区间、夜班、专线及特殊线路；连接 TU 0x1A、0x1E、交易分析和行程显示。
- 公交匹配只接受完整编码、公交类型和城市范围；不会把公交字段送入地铁片段表。真实名称查表优先，未收录时可显示北京编码中的“第 N 站”，它是站序，不是假造的站名。
- 保留原始线路、站点、运营商字段及前导零。未知编码保留原值。
- 修正轨道站点片段归一化，避免 `000A`、`0A`、`A` 之间的不一致导致漏配。
- 修正终端拆出的线路/站点短码没有查询数据库完整 `source_key` 的问题（例如 `3910 + 02 + 31 → 39100231`）；站点未收录但线路已知时，仍可展示查表得到的线路名。
- 修复 0x1E 循环文件有 `70` 模板封装时的拆分边界，支持逐条封装和整段封装；修正 0x1A 可变记录的实际长度处理。
- 修复严格 APDU 模式对尾部 `00` 数据的截断，并为北京地方卡短响应添加长度检查。

## 银行卡

- 按各应用 AID 独立选择 EMV/PBOC 解析器；同一张物理卡可同时保留两种结果，界面显示“EMV + PBOC”。
- 每个应用重新 SELECT 后读取；一个应用失败不丢弃另一个应用已有数据。
- 卡号优先来自 `5A`，也可从 `57` / `9F6B` 磁道二字段提取，保留来源标签，不把有效期、服务码等拼入卡号。
- 处理 `6Cxx` 的 Le 修正和 `61xx` 的 GET RESPONSE 链，包括 GET RESPONSE 自身的 Le 修正；保留 FCI/GPO 数据、处理 AFL 和 DOL 边界，异常保留明确记录。
- 自动测试使用合成银行卡资料，尚未以用户的万事网联或美国运通实体卡完成验收。具体卡片不返回的字段不会凭空补全。

## 全量测试发现的额外修复

二维码离线解码原先将 ZXing 的 `rawBytes`（含模式、长度、填充等码字）直接当作业务载荷。现在从解码后的 byte segments 取得二进制载荷，保留 `00`、高位字节和多段顺序；纯数字等文本模式使用解码文本。

卡片改名原先在对话框退出动画结束前释放 `TextEditingController`，触发已释放对象被继续使用的错误。现在由输入组件自行管理控制器生命周期。旧测试的站点 SQLite 夹具、金额字节、货币元数据和已合并的二维码界面选择器也已对齐，并保留对真实行为的验证。

## 验证结果

`flutter test --no-pub --concurrency=1 --reporter expanded`：**525 项通过，0 项失败**。新增解析模块、银行卡和二维码等专项静态分析无问题；全项目静态分析为 **0 error、7 warning、42 info**，并非全项目零告警。日志随交付提供。原 APK 的上海实体卡异常没有被冒充为已完成实体卡验收。

## 数据与版本溯源

TU、CU SQLite 资产未被修改，均与用户提供 APK 内相应文件逐字节一致，SQLite 完整性检查为 `ok`：

| 文件 | 字节数 | user_version | SHA-256 |
|---|---:|---:|---|
| TrafArch_Database_CU.sqlite | 5001216 | 2 | `66579e2c1aa4a96105ed92679d22d3517f3583eafa1dfac1f646309291ef468d` |
| TrafArch_Database_TU.sqlite | 5394432 | 4 | `e2251edfa140dc05e8268f99408101d07c1658bbe38e8d54805fa56c93a1cbe9` |

原 APK SHA-256：`d6788c2b8bed1099f15e0dc5bd221e4d6c53c7dafd784a39ce98967665fbe773`。Manifest 显示 `1.0.1-alpha`、versionCode `4059`。Flutter ARM64 分包版本码增加 2000，因此它对应基础构建号 2059；仓库发布成功后会将 `pubspec.yaml` 自动递增为下一号 2060。不能仅凭 4059/2060 的差异断言 APK 与源码不一致，也没有反向证明两者所有实现完全相同。

## 构建与交付

使用 Flutter 3.47.6 与 JDK 21。本机默认 JDK 27 在 Gradle 配置阶段出现 `Unsupported class file major version 71`；本次改用工作目录中的 JDK 21 运行，没有改变系统默认 Java。

通过 `-PrepairBuild=true` 构建 debug ARM64 验证包：包名 `com.kajolno.TrafArch.repair`，名称“**TrafArch 修复验证版**”。它与原应用并行安装、使用独立存储，以 debug 证书签名。缺少私有 Firebase 配置时不应用 Google Services 配置插件。

最终 APK 的 Manifest 为 `versionName=1.0.1-alpha-repair`、`versionCode=4060`，仅含 ARM64 架构。APK v2 签名验证通过，启动 Activity 为 `com.kajolno.TrafArch.MainActivity`。程序内“关于”的原有静态构建号仍来自源码的 2059 字段，识别本验证包请以应用名称、独立包名和 Manifest 为准。

```powershell
# 将 JAVA_HOME 指向 JDK 21；android/local.properties 指向本机 Flutter 和 Android SDK。
# 先在项目根目录执行 flutter pub get，然后进入 android 目录。
.\gradlew.bat :app:assembleDebug -PrepairBuild=true -Ptarget-platform=android-arm64 -Psplit-per-abi=true --console=plain
```

最终 APK、完整源码、相对基线的补丁、测试日志和 SHA-256 清单放在交付目录。构建成功和自动测试通过均不能替代真实 NFC 卡片的复测。
