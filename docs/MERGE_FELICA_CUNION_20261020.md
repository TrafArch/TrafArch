# FeliCa / CUnion 与本地修复版合并说明

> 历史记录：本文记录从开发者 ZIP 合并时的状态。随后已拉取 GitHub
> `8a4818e7d4dc848432a3e39a69195255138a3b95` 并补回漏合修复。
> 当前静态结果、Suica 夹具更新与 CU 日期容错变更见
> `GITHUB_PULL_REVIEW_20261020.md`；本文的 15 warning / 45 info 不代表当前结果。

日期：2026-10-20。

## 来源与合并方式

- 本地项目：`TrafArch`，包含此前公交 / 地铁、EMV / PBOC、二维码及余额处理等未提交修复。
- 开发者文件：用户提供的 `C:/Users/captu/Downloads/TrafArch.zip/TrafArch.zip`（1,772,021,497 字节）。
- 双方共同 Git 基线：`f2e4f179ac5c2af963faf5c83b871c17a793003a`。压缩包的 Git HEAD 仍在该提交，新增功能来自压缩包内的工作区文件，而非新的 Git 提交。
- 按“共同基线 / 本地修复 / 开发者源码”三方比较合并。没有用开发者旧版文件覆盖本地独有修复。
- 保留开发者版本：`pubspec.yaml` 为 `1.0.1-alpha+2066`；源码内静态构建号沿用开发者值。项目原有 release 构建递增机制不变。

## 已合入的开发者内容

- Android NFC-F 通道：`FelicaNfcBridge`、原生 `transceiveFelica`、`felicaConnected` 标签状态与关闭连接处理。
- Dart FeliCa 协议、探测、适配器、数据模型与解析模块；NFC-F 分派、首页与专家页展示。
- CU 公共信息卡号解码、字段 / 日期布局校验、固定长度文件读取及日期时间组合修复。
- 上海交通联合专用 TU / CU 双路读取、两侧独立状态、结果合并与归档类型识别。
- 开发者新增的 FeliCa / 上海卡测试源码，以及其他随包源码改动；本次不执行测试。

## 冲突处理

双方同时修改了 4 个文件，其中 3 个存在文本冲突（共 6 段）：

| 文件 | 合并决策 |
|---|---|
| `lib/core/transit/local_card/apdu_exchange.dart` | 合并开发者的严格长度拒绝与本地的最终 Le 校验；在 6C / 6700 重试后使用实际命令 Le，保留尾部 00 数据。 |
| `lib/core/transit/local_card/cards/common_unit_tu.dart` | 保留开发者 `lastCardInfo` 和上海识别所需信息；保留本地有效零余额与循环记录修复。该文件自动合并后另做语义核对。 |
| `lib/state/app_state.dart` | 保留 FeliCa 通道、上海双路状态及 TU 家族分派，同时保留本地公交解析连接、银行卡按应用处理和余额诊断。 |
| `lib/features/home/recent_scan_section.dart` | 保留 FeliCa / 上海卡面板，同时保留银行卡 EMV + PBOC 混合结果展示。 |

额外集成修正：

- CU 成功读取的余额同时回填 `ParsedCard.info.balanceFen` 和 CU 侧 `CardInfo.balance`，包含有效零余额，避免上海 CU 单侧结果结构出现默认零与真实余额不一致。TU / CU 金额各自保留，不相加。
- 开发者 `city_union_parser_test.dart` 补充缺失的 `CityUnionCodec` 导入。
- 开发者 `felica_module_test.dart` 的旧枚举拼写与协议参数类型对齐当前接口；保留原断言。
- 上海合并结果测试夹具补入实际读取器会填写的 `CardInfo` 字段，保持原断言。

## 本地修复与数据库保留

本地北京公交线路 / 站序、完整站点编码查询、原始线路号与前导零、TU 过程记录、EMV / PBOC 每 AID 解析与卡号提取、二维码载荷和改名对话框修复均保留。

TU / CU 数据库在两份来源中完全一致，合并不改写其内容；CU 继续作为独立 SQLite 文件存在：

| 文件 | SHA-256 |
|---|---|
| `assets/data/TrafArch_Database_CU.sqlite` | `66579e2c1aa4a96105ed92679d22d3517f3583eafa1dfac1f646309291ef468d` |
| `assets/data/TrafArch_Database_TU.sqlite` | `e2251edfa140dc05e8268f99408101d07c1658bbe38e8d54805fa56c93a1cbe9` |

## 验证范围

遵照用户此前“取消测试”的要求，本次仅执行源码比较、冲突审阅、Dart 语法 / 静态分析和文件一致性检查。**未执行单元测试、APK 构建、模拟器或实体卡测试。** 之前文档中的 525 项通过是合并前的历史结果，不能当作本次合并后的测试结果。

最终全项目 Dart 静态分析为 **0 error、15 warning、45 info**，日志与合并清单随源码交付。分析命令因 warning 返回 2，不能宣称全项目零告警。FeliCa、CU 的真实读卡能力仍取决于开发者实现及卡片可读取的服务，不能把源码合并宣称为实体卡验收通过。

上海旧 APK “实际 100 元、首页显示 108 元”的问题仍未确认修复：用户确认仅有 `80 5C 00 02 04 → 00 00 27 10 90 00`。此次没有固定减去 800 分；原有余额诊断继续保留。

## 源码审阅发现的开发者实现边界

以下来自传入代码本身，未作为新功能扩展在本次合并中重写：

- `OctopusAdapter` 默认只确认八达通族并建立不可读钱包占位，没有执行八达通余额或交易服务读取。合入 FeliCa 模块不代表八达通余额读取已实现。
- `AppState._readFelica` 保留本次会话结果和界面展示，尚未调用卡片归档保存流程。
- Suica 历史读取仅在适配器内捕获 `FelicaProtocolException`；原生 `PlatformException` 可能到达读取器通用失败分支，导致此前已读到的钱包 / 记录未出现在最终结果中。
- FeliCa 测试源码仍有与当前解析器不一致的金额字节、历史日期 / 金额和异常阶段夹具。仅修正静态编译错误，没有执行测试或根据未执行的结果改动断言。
- CU 新日期布局校验在日期非法或起止日期相同时回退为原始文件视图，可能减少可用于识别的部分字段。这是开发者引入的行为，原始数据仍保留。

## 构建与回退

构建环境和命令见同目录 `REPAIR_NOTES_20261020.md`。源码包补有 Gradle wrapper；开发者按自己的 SDK / Flutter 路径创建 `android/local.properties`，正式发布配置由开发者提供。

本次没有提交或推送 Git。合并前源码备份为交付目录中的 `TrafArch-premerge-20261020.zip`。合并源码包已包含最终修改，不要再次对其应用随附补丁。

压缩包中的 `.git` 历史、构建缓存、机器专用路径、签名私钥和自动生成的插件注册文件未作为新源码导入；原 APK NFC 回放实验未参与本次合并。
