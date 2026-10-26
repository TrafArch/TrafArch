# TU 查询回归的独立基准

`tu-lookup-20261021.json` 是 2026-10-21 冻结的原始 Trip Reader 字面量映射，逐字节保留现有发布清单中 `sources.id=tu_lookup` 的输入。它来自原始 JADX 字段与索引的独立提取，不由待测的运行时 SQLite 或其查询结果生成。

- SHA256：`a797c8be381808106894fbb59d3e767acb3b05400845505c2fa8865e3ebb6245`
- 大小：495,518 字节，UTF-8，LF 换行。
- 内容：4,014 条终端别名、270 条线路前缀、30 个历史线路/站名键；保留原始键、值、字段和日期字面量。
- 发布来源：`assets/data/reference_manifest.json` 中的 `sources/user-tu-afdaca5f8ff3-source-v3/tu-lookup-20261021.json`。

`test/tu_lookup_service_test.dart` 先验证本文件与发布清单的哈希一致，再用其独立期望值测试发布包。测试夹具纳入版本控制，确保新 clone 不依赖被忽略的 `data/` 或本机旧目录。夹具不包含用户读卡日志，不随运行时结果自动更新。参考数据升级时，应审查新的冻结来源及其清单，并同步更新夹具和本说明。
