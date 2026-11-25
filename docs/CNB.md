# 在 CNB 构建 TrafArch 和使用 transit

## 构建与下载

1. 将本次提交推到 GitHub，等仓库已有的「Sync to CNB」工作流完成；直接推到 CNB 的分支也可以。GitHub 镜像同步使用已有的 `CNB_GIT_TOKEN`。
2. 在 CNB 打开要打包的**分支详情页**，展开自定义按钮，进入「Android 安装包」。两个按钮共用现有开发者签名。
3. 点击「构建分架构 APK」获得 `armeabi-v7a`、`arm64-v8a`、`x86_64` 三个可独立安装的 APK。点击「构建 Universal APK」获得一份同时包含这三种 ABI 的 APK。两种模式均为 Release，使用正式入口 `lib/main.dart`。
4. 打开本次构建对应的 **Commit → 附件**。安装包名称含版本名、实际版本码和架构，可用同页的 `SHA256SUMS-<版本码>-<模式>.txt` 核对下载。Windows 可以执行 `Get-FileHash -Algorithm SHA256 -LiteralPath '.\下载的文件.apk'`。

按钮对应手动事件。普通 push 只在 `main` 更新知识库。按钮触发权限及提交附件的规则见 [CNB 手动触发文档](https://docs.cnb.cool/zh/build/web-trigger.html) 与 [CNB 附件插件](https://cnb.cool/cnb/plugins/cnbcool/attachments)。

## 开发者签名从哪里读取

「签名并核验 APK」步骤通过 `.cnb.yml` 的 `imports` 直接引用密钥仓库 `TrafArch/taKeystore` 的 `main/androidSigning.yml`。CNB 将以下两个字段注入该步骤。[构建配置](../.cnb.yml) · [签名文件](https://cnb.cool/TrafArch/taKeystore/-/blob/main/androidSigning.yml) · [CNB 密钥仓库说明](https://docs.cnb.cool/zh/repo/secret.html)

| 导入的环境变量 | 解码后的文件 |
| --- | --- |
| `KEYSTORE_JKS_BASE64` | `upload-keystore.jks` |
| `KEY_PROPERTIES_BASE64` | `key.properties` |

云端解码后把临时 `key.properties` 的 `storeFile` 指向同目录的 `upload-keystore.jks`，其余签名属性沿用原文件。若 CNB 报密钥引用权限不足，可核对密钥仓库对 `TrafArch/TrafArch`、目标分支和 `web_trigger_apk` 事件的授权。

签名材料仅由签名步骤在临时目录还原。附件上传前，每个 APK 都要通过 Android 工具对实际应用名 `TrafArch`、包名 `com.kajolno.TrafArch`、版本名与版本码、开发者原证书、ABI、ZIP 完整性和对齐的检查。云端从 Git 跟踪的源码构建，Firebase 配置沿用项目的公开检出行为。

## 云构建的版本码

两个按钮共用同一个仓库锁和计数。脚本取源码 `pubspec.yaml` 的待用号与上次云端预留号加一中的较大值，将它写入本次临时检出，再由项目既有 Gradle 逻辑同步 AppInfo 并预留下一个号。一次分架构构建的三个包共用一个版本码。

已预留的号记录在项目初始提交 `9a6a6736d74aed6de177e256a933f7e87001dd70` 的元数据 `trafarch-android-last-version-code` 中。失败或取消可能留下跳号。云端更新的是 CNB 元数据；之后若要从本地发行覆盖升级包，应先把本地待用号提到最新云端预留号以上。[版本码脚本](../.cnb/reserve_version.py) · [CNB 元数据](https://docs.cnb.cool/zh/repo/annotations.html)

## 使用和更新 transit

CNB 仓库的默认分支是 `main`。把配置和派生文档合入并推送到 `main` 后，等「更新 transit 知识库」流水线成功。在仓库主页点「问 transit」，或在 Issue / PR 中输入 `@TrafArch/TrafArch(transit)`。

可试问「TU 重庆原码 69001501 对应哪个站？」或「正式入口在哪里，Flutter 如何把 APDU 交给 Android？」前者应定位到重庆 15 号线曾家，后者应引用正式入口与原生通道契约。[参考资料目录](transit-data/README.md) · [原生通道契约](NATIVE_SESSION_CONTRACT.md)

索引只收录指定的公开资料和技术文档。TU、CU 原库或清单，以及影响索引的技术版本变动后，在仓库根目录执行以下命令，将生成的 Markdown 随源文件一起提交。`--check` 会校验发布包哈希并报告缺失、过时或多余的文档。

```sh
python -X utf8 .cnb/transit_knowledge.py
python -X utf8 .cnb/transit_knowledge.py --check
```

CNB 按提交差异索引支持的文档格式；角色定义来自默认分支。[知识库更新机制](https://docs.cnb.cool/zh/build/internal-steps/knowledge/update.html) · [NPC 角色配置](https://docs.cnb.cool/zh/repo/settings-npc.html)

## 可改文案清单

直接编辑下表所指的配置文件。以下 PowerShell 命令可从当前工作树输出**全部构建按钮、流水线名称、步骤标题、NPC 标语、完整提示词和知识库入口文案**，方便复制给协作者或自行改写。

```powershell
Get-Content -Encoding utf8 .cnb/web_trigger.yml
Select-String -Encoding utf8 -Path .cnb.yml -Pattern '^\s*- name:' | ForEach-Object { $_.Line.Trim() }
Get-Content -Encoding utf8 .cnb/settings.yml
```

| 显示位置 | 字段 | 当前文案 |
| --- | --- | --- |
| 云原生开发按钮名称 | `workspace.launch.button.name` | 一键启动 1000 万以内最好的云原生平台 |
| 云原生开发按钮说明 | `workspace.launch.button.description` | 啊这个这个这个 |
| 构建按钮分组 | 两个按钮的 `groupName` | Android 安装包 |
| 分架构按钮 | 第一个按钮的 `name` | 构建分架构 APK |
| 分架构按钮说明及构建标题 | 第一个按钮的 `description` | 分别生成 ARMv7、ARM64、x86_64 安装包 |
| 通用按钮 | 第二个按钮的 `name` | 构建 Universal APK |
| 通用按钮说明及构建标题 | 第二个按钮的 `description` | 生成一个包含三种架构的通用安装包 |
| 构建流水线 | `web_trigger_apk` 下的 `name` | 构建 Android 安装包 |
| 构建步骤 1 | `stages` 中的 `name` | 准备 Flutter 和 Android 工具链 |
| 构建步骤 2 | 同上 | 分配 Android 版本码 |
| 构建步骤 3 | 同上 | 签名并核验 APK |
| 构建步骤 4 | 同上 | 上传 APK 和 SHA256 校验清单 |
| 知识库流水线 | `main.push` 下的 `name` | 更新 transit 知识库 |
| 知识库步骤 1 | `stages` 中的 `name` | 核对 TU 和 CU 知识库资料 |
| 知识库步骤 2 | 同上 | 索引交通卡资料和项目技术文档 |
| NPC 显示名及默认角色 | `npc.roles[0].name` 和 `npc.defaultRole` | transit |
| NPC 卡片标语 | `npc.roles[0].slogan` | 查交通卡原码，读 TrafArch 源码 |
| NPC 完整角色提示词 | `npc.roles[0].prompt` | 默认全文见下方，可调整口吻、回答形式、引用和追问方式 |
| 知识库入口按钮 | `npc.button.name` | 问 transit |
| 知识库按钮说明 | `npc.button.description` | 查询交通卡参考资料与 TrafArch 技术实现 |

随本次配置提供的角色提示词如下。

```text
你是 TrafArch 的交通卡资料助手 transit。用提问者的语言回答，先给结论，再附资料或代码链接。
查询城市、线路、站点、终端、发卡机构或卡种时，先查当前版本的 docs/transit-data。区分 TU（交通联合）与 CU（城市一卡通），逐位比对原码并保留前导零。
给出协议、地区码、原始字段、匹配名称和适用条件。同码有多个候选时全部列出，说明还需要哪个字段才能区分。标明推算记录、兼容副本和缺失信息。
区分参考库记载、软件解析结果和实体卡验证。运营状态、票价、时刻表和实时余额需要各自的来源。
回答技术问题时，引用对应版本的项目源码、架构说明、原生通道契约或参考数据工具文档。
举例使用公开原码或合成数据。遇到完整卡号、UID、个人行程、原始读卡日志或凭据，请提醒提问者脱敏，避免复述敏感内容。
```

按钮文案、构建步骤标题与 NPC 文案分别存放于三个文件。角色改名时同步 `defaultRole` 和提示词中的自称；`defaultRepo` 填实际 CNB 仓库路径。事件名 `web_trigger_apk` 与密钥允许的事件关联，`split`、`universal` 与脚本的模式参数关联。[按钮原文](../.cnb/web_trigger.yml) · [流水线原文](../.cnb.yml) · [NPC 完整原文](../.cnb/settings.yml)

若还要调整附件命名、日志提示或知识文档的标题与表头，分别在 [成品核验和命名](../.cnb/build_apk.py)、[签名脚本](../.cnb/build_apk.sh)、[版本码脚本](../.cnb/reserve_version.py) 和 [知识文档生成器](../.cnb/transit_knowledge.py) 修改。城市、站名和原码由发布库产生；仅修改派生 Markdown 会被下一次核对检出。
