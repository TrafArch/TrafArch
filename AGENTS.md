# 项目维护约束

## Android 应用身份

用户在 2026-10-21 曾要求 alpha 并装版本使用独立包名；2026-10-22 明确安装包名改为 `com.kajolno.TrafArch`（与旧正式包完全一致）。后续修复、重构、测试构建与发布均遵守：

- 非正式/测试发布 APK 显示名称为 `TrafArch Alpha <数字>`（当前测试发布为 `TrafArch Alpha 1`）；正式发布显示名称为 `TrafArch`。
- Android applicationId / 安装包名固定为 `com.kajolno.TrafArch`，保留原正式包大小写；alpha 并装包 `com.kajolno.trafarch.alpha` 已停用。
- applicationId 与旧正式包相同，安装按覆盖升级处理，不再与原应用并存；只有与旧包相同的签名证书才能升级，Debug 或其他密钥会因 `INSTALL_FAILED_UPDATE_INCOMPATIBLE` 失败，需先卸载旧应用，旧应用数据随之丢失。
- Kotlin namespace 保持 `com.kajolno.TrafArch`，与 applicationId 同值，仅作为原生类命名空间。
- Debug、Release 和验证构建都保持同一 applicationId；不得追加 `.repair` 等 applicationIdSuffix，也不得把显示名称改成“修复验证版”或其他名称（测试发布的 Alpha 命名除外）。
- 版本号按发布策略维护；验收前核验最终 APK 的实际 Android versionCode，不把源码构建号直接当作拆包后的版本码。
- 按用户要求，本机并装验证 APK 使用 Android Debug 证书签名；必须明确标注为 Debug 签名，不能冒充开发者原签名，也不能覆盖安装在原签名应用上。
- 验收最终 APK 的清单，而非仅检查 Gradle 源码；在交付说明中记录显示名称、包名、Android 版本码和签名状态。

`docs/UPGRADE_HANDOFF_20261021.md` 记录旧 `com.kajolno.TrafArch` 升级包的 versionCode 与证书指纹，可用于当前包的升级与签名比对；其中未签名 APK 与 Debug 签名结论仍需按本文约束区分。
