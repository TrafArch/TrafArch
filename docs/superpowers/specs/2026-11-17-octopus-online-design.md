# 八达通联网余额与全国通汇率

用户于 2026-11-17 确认：按首次使用明确提示、用户开启联网读卡的方案接入；向八达通官方服务器发送本次 NFC 应答；首页显示真实 HK$ 余额和卡内汇率；行程页通过按钮更新卡内汇率；普通查询阻止退款等额外写操作。本次禁止编译 APK。

## 数据与界面

- 港币余额来自官方查询结果，使用整数分保存，零与负余额有效；未知显示“未读取”。不可把 TU 侧人民币读数改标港币，也不可用参考汇率反推账户余额。
- 汇率以服务端 `motRate` 十进制字符串保存，展示为 `1 HK$ = ¥…`；`motExpiryDate` 为 `yyyyMMddHHmm`，保留原时间文本，不猜时区。已过期与有效期未知必须有不同提示。
- 首页和行程共享一份明确标注本次查询卡号、时间的在线结果。行程为空仍显示余额和更新入口。TU 行程保留原币种。
- 不以 TU 卡号与 NFC-F IDm 猜测同卡；联网结果独立标识。更新必须重新贴上与上次在线查询相同 IDm 的卡。开始新普通读卡时清除在线结果，避免旧值覆盖新卡。
- 第一次联网提示官方服务器、传送卡片应答和安装标识、可能需要匿名登记；用户主动开启后才发请求。无需上传 TrafArch 日志、档案或行程数据库。
- 所有提示为简体中文；更新状态区分成功、已经最新、失败、结果未确认。断卡/超时发生在写操作之后不能显示成功。

## 实现依据

提供 APK：`com.octopuscards.nfc_reader`，12.51.0 (3451)，SHA256 `5c545765b765d1a8df2c2c44c6ae29de58c81c8121c32553fd9307b7f5d406c9`。

普通查询和更新均使用普通 `cardoperation` OCAP 协议，生产站点 `https://wfe.oos.octopus-cards.com/`，路径分别为 `enquiry` / `motupdate`。`cardoperationMOT` 的 JSON fixtransit 不属于本功能。初始 GET /index.htm 能取得新传输会话不代表完整业务已验收。

查询输入为 `oma_config`、`cardid_list_v2`；更新仅 `oma_config`。更新未发现专用 token 前置申请；拦截器仅监测超时。不能把 APP_HASH 字段称为私钥或直接推定服务器接受任意客户端。查询可能报告退款、自动汇率更新，因此不能盲目透传服务端所有写指令。

`cardDataVO.balance`、`motRate`、`motExpiryDate`、`hasNewMotRate` 是官方查询的结果字段。R0 表示成功；R140 表示已最新；R144 表示非全国通；其他状态不得包装成成功。无卡网页仅是参考汇率，不替代卡内读数。

## 边界

- 协议层纯 Dart，只依赖注入的服务器交换与 NFC 交换函数；HTTP、持久化与 UI 位于平台/feature 层。
- 新增独立 NFC-F 扫描入口，复用现有原生会话控制器及关闭屏障；既有 NFC 通道的方法、参数键、sessionId 行为保持不变。原生不解析八达通协议。
- 普通联网查询仅允许已知读取/认证帧，拒绝写入和未知操作。更新只连接固定官方 motupdate 端点，绑定卡片 IDm、明确按钮操作和一次会话；不开放通用服务器 URL/任意写卡入口。
- 不复制官方账户凭据或密钥，不默认联网，不修改参考库/manifest，不改归档结构，不编译 APK、不递增构建号。
- 必须报告实际兼容性的不确定性：静态分析与模拟服务器/卡片测试无法代替实体八达通及真实服务端验证。

## 验收

覆盖 OCAP 编解码、VM 边界、只读指令拒绝、同卡约束、结果精度/未知值/错误码、超时取消与关闭、首次许可、无行程展示及 HK$。运行全量 Flutter 测试和 analyze；前后 SHA256 核对。不得以占位界面或会话 GET 成功声称余额/更新已通过真卡验证。

## 验证记录（2026-11-17）

- 全量 Flutter 测试 3140 项全部通过；`flutter analyze --no-fatal-infos` 退出码 0，无 error / warning / 新增 info，保留原有 5 条 info。最后只作等价的格式／mounted 判断展开，八达通专项 66 项再次全部通过。
- 真实无卡检查使用新生成的 TrafArch 安装标识和官方 enquiry 端点，完成初始 OCAP 交换并收到首条获准 NFC 指令；回调在提供任何卡片应答前主动终止（`SMOKE_STOP`，`reachedNfc=true`）。未进行匿名登记、实卡查询或写卡。
- 独立复核发现并修复授权初始化／关闭重试等待期间的取消遗漏，以及 OCAP 标签／数据 ID 的有符号解析；相应回归先复现后通过。
- Kotlin 类型检查和隔离 JVM 会话检查通过；未执行 Gradle 打包或生成 APK。pubspec 保持 `1.0.8-beta.2+2198`，AppInfo 保持上次产物的 `2197`，本次未触发构建预留流程。
- 数据库及清单前后 SHA256 相同，并逐字节匹配本次开始时的 HEAD：

| 文件 | 修改前及修改后 SHA256 |
| --- | --- |
| `assets/data/TrafArch_Database_TU.sqlite` | `517c59f3596c06a6ccff40752e7cf39db1bc2b2a76bd74d13d2381ab7ada6c53` |
| `assets/data/TrafArch_Database_CU.sqlite` | `77ba3ad4310782f7625f7b1b1f87a7bc99fee2420cf9060477b614f1580c6ed3` |
| `assets/data/reference_manifest.json` | `37cfdbdcdc7d619237f2decc2094367e41e68d853463c6336d3f8cdcc04f23c0` |
