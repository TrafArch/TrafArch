# Amusement IC 解码数据来源与边界

TrafArch 的 Amusement IC 读取只执行 FeliCa Polling 与 Read Without
Encryption。Access Code 从卡片 SPAD0 解码，不由 IDm、PMm 或发行方名称
计算，不请求 AiMeDB 或其他网络服务。本目录不包含发卡密钥或卡片写入功能。

## 采用的第三方数据

- 项目：[zhicheng233/PN532-Aime-Reader](https://github.com/zhicheng233/PN532-Aime-Reader)。
- 固定修订：`2b1ef450283fb07230308a8dcc9cad563bcbfacd`。
- 原文件：[src/NfcAime.Cli/FeliCaDecryptor.cs](https://github.com/zhicheng233/PN532-Aime-Reader/blob/2b1ef450283fb07230308a8dcc9cad563bcbfacd/src/NfcAime.Cli/FeliCaDecryptor.cs)。
- 采用范围：`SBoxInv` 的 9 × 256 字节逆置换表。
- 本地文件：`lib/protocols/felica/parsers/amusement_ic_substitution_tables.dart`。
- 修改：只保留逆表，以 Dart 不可变常量表达；不带入原项目的读卡器、网络、
  MIFARE 认证、正向置换或写卡代码。
- 按表序、每表字节序拼接后的 2304 字节 SHA256：
  `28E1992462FF8F4DDEA558462B776303A7873B8D1B6C771DB91E82BB374A86AD`。
- 原项目声明采用 Mozilla Public License 2.0；本地完整文本为
  [MPL-2.0.txt](MPL-2.0.txt)，原文见其
  [LICENSE](https://github.com/zhicheng233/PN532-Aime-Reader/blob/2b1ef450283fb07230308a8dcc9cad563bcbfacd/LICENSE)。
  该 Dart 数据文件保留 MPL-2.0 标记、出处及修改说明，分发时保留许可证，
  并提供该文件及其后续修改的源代码。

解析器的格式判断与协议模型由 TrafArch 实现。未复制其他未声明许可证
项目的源文件。以上出处记录针对此次采用的数据，不将 MPL 声明扩展到整仓。

## 协议事实与校验范围

[原研究者的 Amusement IC 文档](https://sega.bsnk.me/allnet/amusement_ic/)
说明了 SPAD0 的置换与旋转规则。先用第 9 张逆表处理全部 16 字节，
随后根据末字节执行若干轮前 15 字节的 5 位右旋与逆置换。
解码后第 0 字节的低 4 位是版本；第 1–5 字节未作语义解释；
第 6–15 字节是 10 字节 BCD Access Code。不能要求未解释字段全部为零。

读取使用系统码 `88B4`、服务码 `000B`（请求按小端发送 `0B 00`）、
SPAD0 块 `00` 与 ID 块 `82`。ID 块第 8–9 字节为大端 DFC：
`0078` 为 SEGA，`0068` 为 KONAMI，`002A` / `003A` 为 Bandai Namco，
`0079` 为 TAITO / NESiCA。这里的块号 `82` 不等于请求中包含短块格式
标志的两字节元素 `80 82`。

[Access Code 格式研究](https://sega.bsnk.me/allnet/access_codes/aicc/)
记录公司前缀 `500` / `501`、`510`、`520`、`530`，以及末 5 位校验码。
此次只核验 SPAD0 长度、字节范围、版本低 4 位、20 位十进制 BCD、
已知公司前缀及读取端的 DFC 对应关系。没有获得并验证末 5 位校验码的
算法，因此不宣称通过发卡方校验、卡片认证或验证网络账号存在。
[KONAMI 官方说明](https://p.eagate.573.jp/gate/eapass/aboutaccc.html)
确认卡背印刷的 Access Code 为 20 位数字。

普通 FeliCa、旧款非 Amusement IC Aime / Banapass / NESiCA，和旧
e-amusement pass 不应因名称、IDm 或一次相似响应被推断为本格式。
无法解码时保留原始证据和原因，Access Code 保持未知。

## 验证材料

`test/amusement_ic_parser_test.dart` 使用独立于生产解析器生成的合成向量，
覆盖各已知公司前缀、非零未解释字段、版本低位、非法 BCD、坏长度、
无效字节与损坏档案数据。这些向量不是实卡转储，末 5 位校验码未验证。
测试中不调用生产加密函数，也不向卡片写入数据。

实卡读取兼容性需要用户的带 Amusement IC 标志卡片确认；合成测试不能
证明所有卡片、手机 NFC 芯片或游戏厂商的实际兼容性。
