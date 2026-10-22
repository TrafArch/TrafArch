# GitHub 拉取与合并检查

检查日期：2026-10-20。仓库：`https://github.com/kajolno/TrafArch.git`。

## 结论

已执行 `git pull --ff-only origin main`，本地 `main` 从
`f2e4f179ac5c2af963faf5c83b871c17a793003a` 前进至
`8a4818e7d4dc848432a3e39a69195255138a3b95`。
该提交时间为 2026-10-20 23:10:20 +08:00。本轮未创建提交或推送。

开发者已解决此前 15 项 warning，但拉取的原始源码存在 11 项静态 error，
另有先前修复在合并时丢失。本轮在该提交之上补回确定的修改。

| 分析对象 | error | warning | info | 退出码 |
|---|---:|---:|---:|---:|
| 拉取前的本地合并版 | 0 | 15 | 45 | 2 |
| GitHub `8a4818e` 原始源码 | 11 | 0 | 43 | 3 |
| 本轮补回后的工作区 | 0 | 0 | 43 | 0 |

使用 Dart SDK 3.13.5，在项目根目录运行 `dart analyze --format machine .`。
日志随交付包提供。未修改分析配置或添加 ignore 来隐藏问题。
剩余 43 项 info 涉及弃用 API、冗余导入、空值写法及风格提示，未扩大本轮修改范围。

## 原 15 项 warning 的原因

这些修复已包含在开发者提交中，本轮保留并由静态分析重新核对。

- 1 项异步错误处理：数据库缓存重建后的 `_openOnce()` 在 try 内直接返回 Future，
  改为 `return await`，使异步失败进入当前 catch。
- 1 项接口注解错误：`regionsOverview()` 未覆盖任何接口方法；删除该冗余方法，
  并在实际接口实现 `queryOverviews()` 上加回 `@override`。
- 13 项未使用内容：导入、局部变量、字段、私有函数和测试构造参数。
  删除确实未使用的内容；Suica 余额夹具函数改由测试实际使用。
  在用的十六进制编码查询、前导零处理及 TU 分块读取保持不变。

逐项原始诊断位于交付包 `handoff/analysis-pre-pull.log`。

## 本轮修复的 11 项 error

| 数量 | 文件与原因 | 修改 |
|---:|---|---|
| 2 | `trip_stream_view.dart` 两处调用 `AppState.resolveBusLocation()`，AppState 中的方法与导入被漏合 | 恢复既有公交解析连接，继续调用 `resolveTunionBusLocation` |
| 2 | `city_union_parser_test.dart` 使用 `CityUnionCodec`，缺少导入 | 补回导入 |
| 1 | `felica_module_test.dart` 把裸 transceive 函数传给 `FelicaProtocol?` 参数 | 用 `FelicaProtocol(...)` 包装 |
| 6 | `felica_module_test.dart` 使用不存在的 `octopusHKD` 枚举值 | 对齐实际枚举名 `octopusHkd` |

前 2 项位于应用源码，会阻塞对应 Dart 源码编译；其余 9 项位于测试源码。
本次只静态检查测试文件，没有执行测试。

## 补回的行为修复

1. **APDU 重试长度校验**：`ApduExchange.call` 在 `6Cxx` 或 `6700` 重试后，
   使用最终命令的 Le 判断长度。远端误用原始 Le，例如请求 60 字节、卡片要求
   改为 2 字节时，会把随后有效的 2 字节响应误判为失败。
   Le=0 保持原有开放长度回退语义，尾部 `00` 数据不裁掉。
2. **CU 余额一致性**：成功读取的 CU 余额同时写入 `ParsedCard.info.balanceFen`
   与 `CardInfo.balance`，包括有效的 0。否则上海 CU 单侧可用时，合并用的
   `mergedCardInfo` 可保留默认 0，而 ParsedCard 中是实际余额。
   TU/CU 钱包仍各自保留，不相加。
3. **混合银行卡标签**：首页恢复 `BankCardProtocolFamily.mixed` 分支，显示
   “EMV + PBOC（按应用分别解析）”，避免被统一显示为 EMV。
4. **余额定位日志**：恢复解析金额、显示金额、归档金额和 CU 金额的同会话对照，
   不写入卡号，不对金额做固定补偿。

这些修改针对已确认丢失的代码，不代表实体卡功能已经验收。

## 保留的开发者改进

- Suica 历史记录使用 `amountIsBalance` 标识，首页金额附带“残高”说明。
- Suica 测试夹具按当前解析器的 bytes 10–11 残高、打包日期/时间更新，
  保留开发者新增的边界值和断言；本轮仅修正其接口与枚举静态错误。
- CU 公共信息不再因起止日期非法或相等直接整条抛弃；保留开发者字段级解析行为。
- 数据库异步 catch、接口注解、无用代码清理和网页页异步导航修改均保留。
- 已合入的北京公交/地铁、完整原始编码查表、银行卡 PAN 和每 AID 解析、
  二维码、有效零余额以及 Android FeliCa 通道代码继续保留。

FeliCa 测试源码在远端和本轮结果中均为 29 个 test、110 个 expect；
CU 解析测试均为 39 个 test、231 个 expect；上海合并测试均为 8 个 test、40 个 expect。
这是源码数量核对，不是测试通过数量。

## 数据库与交付边界

两个独立数据库与拉取前逐字节一致，未改写数据、线路编码或前导零。

| 文件 | SHA-256 |
|---|---|
| `assets/data/TrafArch_Database_CU.sqlite` | `66579e2c1aa4a96105ed92679d22d3517f3583eafa1dfac1f646309291ef468d` |
| `assets/data/TrafArch_Database_TU.sqlite` | `e2251edfa140dc05e8268f99408101d07c1658bbe38e8d54805fa56c93a1cbe9` |

保持用户“取消测试”的要求：未执行单元测试、APK 构建、模拟器或实体卡测试。
执行的检查限于源码对比、Dart 静态分析、补丁重建和归档文件一致性核对。
历史文档中 525 项通过不是当前版本的测试结果。

上海原 APK 的“实际 100 元、刚读卡首页显示 108 元”仍未确认根因或修复。
用户给出的唯一余额响应为 `80 5C 00 02 04 → 00 00 27 10 90 00`；
本轮未通过固定加减 800 分掩盖该问题。

现有 FeliCa 实现边界仍在：八达通适配器没有余额/历史服务读取；
FeliCa 结果尚未接入归档；Suica 历史读取中原生通道异常仍可能丢失已读取的部分结果。

## 回退与使用

拉取前源码已保存到 `outputs/TrafArch-before-GitHub-pull-20261020.zip`，
并保留 Git stash `adef019002e1d7bed77abaa649786504dcd9fc3a`
（消息 `pre-pull-20261020-preserve-local-merged-source`）。
远端已包含大部分本地修复，因此没有整体重新应用旧 stash。

新交付包包含完整项目、上述检查说明、静态日志和基于 `8a4818e` 的补丁。
完整项目已经包含补丁修改，不要重复应用。
补丁供开发者从该提交的干净检出审阅或应用；新建的历史说明和本地图标脚本亦包含在内。
不打包 `.git`、构建缓存、机器路径配置或签名私钥。
