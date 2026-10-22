# 项目维护约束

## Android 应用身份

用户在 2026-10-21 明确要求：alpha 并装版本使用新包名，避免与原应用冲突。后续修复、重构、测试构建与发布均遵守：

- 非正式/测试发布 APK 显示名称为 `TrafArch Alpha <数字>`（当前测试发布为 `TrafArch Alpha 1`）；正式发布显示名称为 `TrafArch`。
- Android applicationId / 安装包名固定为 `com.kajolno.trafarch.alpha`。
- Kotlin namespace 保持 `com.kajolno.TrafArch`，仅作为原生类命名空间，不决定安装身份。
- Debug、Release 和验证构建都保持同一 applicationId；不得追加 `.repair` 等 applicationIdSuffix，也不得把显示名称改成“修复验证版”或其他名称（测试发布的 Alpha 命名除外）。
- 版本号按发布策略维护；验收前核验最终 APK 的实际 Android versionCode，不把源码构建号直接当作拆包后的版本码。
- 按用户要求，本机并装验证 APK 使用 Android Debug 证书签名；必须明确标注为 Debug 签名，不能冒充开发者原签名，也不能覆盖安装在原签名应用上。
- 验收最终 APK 的清单，而非仅检查 Gradle 源码；在交付说明中记录显示名称、包名、Android 版本码和签名状态。

`docs/UPGRADE_HANDOFF_20261021.md` 记录的是旧 `com.kajolno.TrafArch` 升级包历史证据，不适用于当前 alpha 并装包。
