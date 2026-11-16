# Amusement IC Access Code 实施计划

> **For agentic workers:** Use subagent-driven-development / executing-plans to implement each bounded task with regression verification.

**Goal:** 在 TrafArch 的现有 NFC 读取中显示 Amusement IC（Aime、Bandai Namco Passport、e-amusement、NESiCA）的20位Access Code。

**Architecture:** FeliCa Lite/Lite-S 已知系统 `88B4` 路由到独立适配器。服务 `000B` 只读块 `82` 的DFC确认发行方，再读取块 `00`（SPAD0），在设备本地解码。Access Code 使用独立结果字段，不填充IDm或交通卡号；主页/专家/本地诊断/恢复现场共享该结果。

**Tech Stack:** 既有 Flutter/Dart、注入式 FeliCaProtocol，纯Dart解码，不新增原生通道或网络请求。

**Spec:** 本次用户明确要求日本Amusement IC四社通卡Access Code读取；限定带AIC标准的FeliCa卡，旧版非AIC的MIFARE卡不在本次范围。

## Constraints

- 只读，不写卡、不登录或调用游戏平台、不模拟卡片。
- 不编译APK、不调整版本号/构建号、不改AGENTS或数据库资产/表结构。
- `88B4`仅确认Lite候选，不能单独认定AIC或Aime。DFC、解码版本、BCD及公司前缀分别校验。
- 保留原始帧/块和错误；未知或损坏结果不使用IDm生成替代码。
- 不给游戏身份卡构造余额、币种、行程；本次不新增长期卡包保存。
- 解码表采用明确MPL-2.0来源并保留许可与固定版本出处；不宣称已验证未知的Access Code校验和算法。

## Tasks

- [x] 纯Dart模型、SPAD0解码及格式检查：有效向量/BCD/版本/边界测试，隔离公开逆置换表及许可。
- [x] 读取编排识别Lite系统，避免向Lite发送不支持的Request System Code/Request Service；其他卡保持既有命令顺序。
- [x] AIC适配器只读DFC和SPAD0，处理未知发行方/不匹配前缀/访问拒绝/中断/错误IDm。
- [x] Access Code在主页/专家可选择复制，诊断和恢复保留冻结结果，不触发重读或自动归档。
- [x] 定向与全量Flutter测试、静态检查、独立审查、数据库哈希核对及文档交付。

## Primary references

- Sony FeliCa Lite产品/IC Type说明：https://www.sony.co.jp/en/Products/felica/business/tech-support/list.html
- Sony Lite-S安全指南DFC说明：https://www.sony.net/Products/felica/business/tech-support/data/fls_scrty_1.12.pdf
- 原研究者协议文档：https://sega.bsnk.me/allnet/amusement_ic/
- MPL-2.0参考解码表与格式：https://git.fragrance.moe/zhicheng233/PN532-Aime-Reader
- 向量为与独立参考实现交叉验证的合成数据，不代表实卡测试或校验和真实性验证。

## Implementation review and verification

- 首轮 RED：新增 parser/model 缺失；4 个读取用例、Lite 路由及展示/恢复用例证明原行为未支持本功能。实现后定向测试 86 项通过（其中 AIC / Lite 新增 56 项，既有 FeliCa 回归 30 项）。
- 独立审查发现拒读状态在总体摘要中错误降为“不支持”；身份块与 SPAD0 拒读两个场景先实测 RED，再补 `FelicaScanResult.state` 的 `accessDenied` 汇总，86 项定向回归通过。
- 最终 `flutter test --no-pub`：3008 项通过、0 失败、0 跳过；包括本轮新增 56 项 AIC / Lite 用例，日志 `full-tests.log`。
- 最终 `flutter analyze --no-pub --no-fatal-infos`：退出码 0，无 error / warning 或新增 info；仅保留 Gallery 5 条既有 info，日志 `analyze-final.log`。`git diff --check` 通过。
- 没有编译 APK；当前 AppInfo 构建号 4191、pubspec 预留 4192 均与本轮开始一致。
- 日志目录：`C:\Users\captu\Documents\Codex\outputs\amusement-ic-20261116`。

## Database and manifest SHA256

下列已有资产在实施前后逐项一致，没有数据库表结构、记录或参考包修改：

| 资产 | 前后相同 SHA256 |
| --- | --- |
| `assets/data/TrafArch_Database_TU.sqlite` | `517c59f3596c06a6ccff40752e7cf39db1bc2b2a76bd74d13d2381ab7ada6c53` |
| `assets/data/TrafArch_Database_CU.sqlite` | `77ba3ad4310782f7625f7b1b1f87a7bc99fee2420cf9060477b614f1580c6ed3` |
| `assets/data/reference_manifest.json` | `37cfdbdcdc7d619237f2decc2094367e41e68d853463c6336d3f8cdcc04f23c0` |
| `assets/suica/suica_stationcode.db` | `57d4fe1af5154e9adab0a4a38619fe8095c7f509ac28c743bf554ba199a43abd` |
| `assets/suica/manifest.json` | `1abde5038c9a5f60ff0b4c7c4006d8bf215e20351bf1d3880afc3f361985864f` |
