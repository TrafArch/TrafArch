# Gallery 测试原生退出排查记录

日期：2026-11-01，Asia/Shanghai。此文件记录本轮诊断证据；不更新既有交接快照。

## 结论与证据边界

本轮已复现 Windows 宿主 `flutter_tester.exe` 的访问冲突：退出码 `-1073741819`，即 `0xC0000005`。这发生在 Flutter 单元／组件测试进程，不能据此判断 Android APK 会闪退。测试进程中断后，尚未运行完的用例统一显示 `did not complete`，并非这些用例分别产生断言失败。

根因高度指向当前 SDK 的 Dart CPU 性能采样器缺陷。默认方式间歇性崩溃；只移除测试进程的 `--enable-dart-profiling` 后，相同聚焦测试连续八轮全部通过，全量 2123 项也通过。测试内容、应用源码、发现规则、断言与超时没有为本次诊断而改变。

本机尚未捕获到崩溃时的符号化原生堆栈，不能把具体指令级原因当成本机已证实事实。挂调试器的六轮均通过，说明调试改变了复现条件。另一个独立的 1 MiB isolate 字节传输最小探针单轮通过，也没有作为独立复现成功的证据。

## 本机版本与上游对应

- Flutter：`3.47.7`，framework `abaf9c523780a608bd46686fd5e53740a07077f8`。
- Engine：`deb287481e3ce9468f3434937ced4240a70539ca`。
- Dart：`3.13.5`；Windows x64 原生测试宿主。
- 官方问题：[dart-lang/sdk#64627](https://github.com/dart-lang/sdk/issues/64627)，关联 [flutter/flutter#191069](https://github.com/flutter/flutter/issues/191069)。

2026-11-01 查询官方问题与评论：受影响版本明确包含 Windows Flutter 3.47.1–3.47.7／Dart 3.13.1–3.13.5。上游解释为原生栈采样器在被采样线程执行大块内存复制时，将非栈帧的 RBP 当作有效帧指针，错误解引用后访问冲突；修复 `0a7701121edee26d7e175c53af52063b94652a88` 用当前 SP 收紧栈边界。

2026-10-28 官方维护者说明修复计划随 Dart 3.14 发布，未接受回补 3.13。因此 issue 已关闭不代表本机 3.13.5 已修复。本轮没有更换全局 SDK。

## 实验记录

聚焦组命令为 `flutter test test/gallery_controller_test.dart test/gallery_ui_test.dart test/beta_ui_switch_test.dart --concurrency=1 --reporter expanded --verbose`。

| 实验 | 结果 | 本地日志，均相对仓库根目录 |
| --- | --- | --- |
| 首次默认运行 | 20 项通过 | `build/gallery-crash-repro-20261101.log` |
| 默认重复，第 1／2 轮 | 各 20 项通过 | `build/gallery-crash-repeat-1.log`、`-2.log` |
| 默认重复，第 3 轮 | 15 项完成后整轮失败；Gallery UI 原生宿主访问冲突，后续未完成 | `build/gallery-crash-repeat-3.log`，原生退出见约第 399 行 |
| 挂调试器，六轮 | 每轮 20 项通过，未捕获原生异常 | `build/gallery-crash-debugger-2.log` 至 `-7.log` |
| 移除 CPU 采样开关，八轮 | 每轮 20 项通过，共 160 项 | `build/gallery-profiler-off-1.log` 至 `-8.log`；汇总 `build/gallery-profiler-off-results.json` |
| 关闭采样，全量并发 2 | 2123 项通过，约 1 分 47 秒，退出码 0 | `build/gallery-profiler-off-full.log` |
| 最终模板生成入口，聚焦组 | 20 项通过，退出码 0 | `build/gallery-windows-entry-final.log` |
| 最终静态检查 | `flutter analyze --no-pub` 无问题，退出码 0 | `build/gallery-crash-analyze-final.log` |

曾尝试直接传 `--dart-flags=--no-profiler`，引擎 VM 参数白名单拒绝该参数，三个测试文件在加载前失败。此轮日志为 `build/gallery-no-profiler-1.log`，不计入有效对照。最终方案只移除 `--enable-dart-profiling`；本机引擎 `runtime/dart_vm.cc` 的 `ProfilingFlags(false, ...)` 会自行设置关闭采样的 VM 参数。

正常完成时 Flutter runner 会主动终止不再需要的宿主，verbose 日志可见 `Terminating flutter_tester process` 后的 `code=-1`；随后全部测试通过、工具退出码为 0。不能把这种清理退出混同于 `0xC0000005`。

## 后续测试入口

仓库新增 `dev/gallery/test_windows.ps1` 与 `windows_test_runner.dart.template`：从 PATH 定位当前 Flutter，在 `build/gallery/` 生成 SDK 专用启动器，仅对 Windows Flutter 3.47.1–3.47.7 的测试宿主移除 CPU 采样开关。既有 Flutter 测试发现与执行流程继续运行；没有修改全局 SDK，也没有自动重试、删除、跳过测试或改变断言。

```powershell
./dev/gallery/test_windows.ps1 --concurrency=2 --reporter expanded --no-pub
```

这是临时工具链绕过，使用 Flutter 私有 API，不能视为引擎根治。SDK 升级后先核对修复是否进入当前版本，再复测标准 `flutter test`。本轮未生成 APK，因此不消耗构建号，也不作设备运行验收结论。构建目录日志可能随清理删除，需要长期保存时另行归档。
