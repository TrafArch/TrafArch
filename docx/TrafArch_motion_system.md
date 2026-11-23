# TrafArch Motion 1.0.1

全局运动设计系统与实现规范。适用范围：Flutter 2.x 界面（`lib/gallery/`），含独立样例预览与正式入口的实卡体验。

| 项目 | 内容 |
| --- | --- |
| 版本 | 1.0.1 |
| 蓝本 | `2.7_spec.md`（Trafficarch Motion 1.0 全文） |
| 实现 | `lib/gallery/gallery_motion.dart`（`GalleryMotion`） |
| 状态 | 现行 |

动效只表达层级、状态和方向，不延迟操作。路由、滚动位置与业务状态不由过时的动画完成回调决定；动画结束回调不得覆盖更新的状态。

## 版本说明（1.0.1）

1.0.1 把蓝本全文回写进本文件：补齐缓动语义、位移与缩放尺度、透明度、优先级、各场景的进入/退出过程与运行规则、中断与反向、减少动态效果、性能边界、实现映射与验证边界。

**参数未变**：所有时长、曲线、位移与缩放值与 `GalleryMotion` 现有 Token 一致，1.0.1 不改变已上线的动效表现。蓝本与实现的冲突以蓝本为准，列在第 8 节；US-009 已完成代码对齐（D1、D3、D4、D5），新增 Token 见 2.2、3.9 与第 7 节。

## 1. 目标与原则

### 1.1 目标

- **一致性**：同类组件使用同一套参数，不因页面或作者不同而漂移。
- **自然性**：运动符合对空间、速度和惯性的直觉，不机械地突然出现或消失。
- **克制性**：动效用于辅助理解与反馈，不为视觉表现干扰任务。
- **响应性**：操作即时反馈，动画可中断、可反向、可连续触发。
- **可复用性**：参数与行为集中管理，业务页面不重复定义。
- **无障碍性**：尊重系统减少动态效果设置，状态语义不依赖动画传达。

### 1.2 原则

1. 动画服务于内容，而不是内容服务于动画。
2. 全局统一运动规律，但不强制所有场景使用同一动画。
3. 优先使用透明度、位移、尺寸等轻量动画。
4. 不使用没有实际意义的弹跳、旋转、循环装饰。
5. 动画不能阻碍用户操作。
6. 组件状态与动画状态必须一致。
7. 系统级导航与手势反馈优先遵循平台规范。

### 1.3 边界

- 页面级转场和半模态不受局部位移尺度限制，按视口与目标位置计算。
- 共享元素转场是可选增强，不是页面切换的默认要求。
- 跟手拖动进度保持线性，不使用缓动改写手指位置。
- 输入调度（搜索防抖、消息展示计时、读卡模拟计时）不属于动效，不套用本规范时长。

## 2. 基础 Token

所有场景必须引用 Token，不在业务页面散落硬编码参数。

### 2.1 时长

| Token | 时长 | 用途 |
| --- | ---: | --- |
| `instant` | 100ms | 即时状态反馈，按钮按压 |
| `fast` | 160ms | 图标、轻量内容切换 |
| `normal` | 220ms | 常规状态变化、收起、半模态吸附 |
| `medium` | 300ms | 页面进入、弹窗 |
| `slow` | 400ms | 较复杂的空间变化，谨慎使用 |

`slow` 不应成为普通交互的默认值。场景值可以偏离基础档位，但必须在第 3 节表格中列出并由 Token 承载。

### 2.2 缓动

| Token | 曲线 | 用途 |
| --- | --- | --- |
| `standard` | `easeInOutCubic` | 常规状态变化、局部过渡（如箭头旋转）；不用于页面／同级转场 |
| `emphasized` | `easeOutCubic` | 重要元素进入 |
| `decelerate` | `easeOutCubic` | 弹窗、菜单、提示进入（默认曲线） |
| `accelerate` | `easeInCubic` | 元素退出 |
| `linear` | `linear` | 跟手进度、持续进度 |
| `readCurve` | `easeInOutCubicEmphasized` | 读卡示意专用强调曲线（项目补充，见 3.7） |

进入用缓出、退出用缓入；反向播放时使用镜像曲线（`Curves.easeInCubic.flipped`），避免退出看起来比进入更慢。不同动画可以共用同一条曲线，但要根据方向和组件特性选择，不统一套 `Curves.easeInOut`。默认曲线 `GalleryMotion.curve` 等于 `decelerate`。

`standard` 的实际归属：主壳（`gallery_app.dart`）的主题切换虽传 `themeAnimationCurve: GalleryMotion.standard`，但 `themeAnimationDuration` 为 `Duration.zero`，不播放曲线动画；许可同意屏（`gallery_consent_screen.dart`）的 `theme` 200ms 不是一次性切换，仍按局部过渡播放。页面进入与同级切换都取 `GalleryMotion.curve`（= `decelerate`，easeOutCubic），见 `gallery_navigation.dart:343`／`:668`。

### 2.3 位移

| Token | 位移 | 用途 |
| --- | ---: | --- |
| `micro` | 2dp | 极轻微状态反馈、折叠收起上移 |
| `small` | 4dp | 图标、轻量反馈、提示退出 |
| `distance` | 8dp | 内容渐入、提示进入 |
| `large` | 16dp | 较明显的局部内容过渡（当前未使用，备用） |
| `menuDistance` | 6dp | 锚点菜单与折叠内容进入 |
| `expandDistance` | 6dp | 折叠内容进入 |

局部位移只用于小于一个页面的变化；页面与半模态按实际高度推进。位移方向与视觉层级一致：进入从触发方向靠拢并归位，退出沿进入方向退回，不做无来源的飘移。

### 2.4 缩放

| 场景 | 缩放 |
| --- | --- |
| 普通按钮按压 | `pressedScale` .98 → 1 |
| 锚点菜单进入 | `menuScale` .96 → 1 |
| 锚点菜单退出 | 1 → `menuExitScale` .98 |
| 列表项 | 不建议缩放 |
| 页面切换 | 默认不缩放 |
| 半模态 | 默认不缩放 |

禁止大范围缩放导致文字、图标变形或模糊。

### 2.5 透明度

- 进入 0 → 1，退出 1 → 0。
- 内容切换旧内容淡出、新内容淡入，两者交叉但不叠影。
- 遮罩 0 → 目标不透明度；半模态目标为 0.40（`sheetScrim` = `0x66000000`）。
- 透明度与尺寸、位移同步推进，不用透明度掩盖布局问题。

### 2.6 优先级

1. 系统级导航和手势反馈。
2. 当前主要交互组件。
3. 组件内部内容变化。
4. 装饰性动画。

同时触发时优先保证当前操作对应的动画；打开半模态时底层页面不同时做缩放、位移或装饰动画；非必要装饰动画暂停或取消。

## 3. 场景规范

### 3.1 折叠面板（展开／收起）

适用：知识库城市与线路展开、站点列表、卡包详情信息、设置选项、统计数据等具备折叠状态的组件。

主动画是尺寸变化，透明度与位移为辅助；展开高度必须由子组件实际布局决定，不使用固定展开高度。

| 属性 | 展开 | 收起 |
| --- | --- | --- |
| 时长 | `expand` 260ms | `collapse` 220ms |
| 缓动 | `emphasized`／`decelerate`（easeOutCubic） | `accelerate`（easeInCubic） |
| 内容透明度 | 0 → 1 | 1 → 0 |
| 内容位移 | +6dp → 0（`expandDistance`） | 0 → −2dp（`micro`） |
| 箭头旋转 | 0° → 180°，`arrow` 200ms | 180° → 0° |

展开过程：点击标题或展开按钮 → 箭头开始旋转 → 区域按实际高度向下扩展 → 内容同步渐显并轻微上移归位 → 到达最终尺寸进入稳定态。内容动画不应明显晚于尺寸动画。

收起过程：触发收起 → 内容开始淡出 → 面板同步收缩 → 箭头复位 → 回到初始尺寸。

内容类型适配：

- **列表型**：整体尺寸变化、整组淡入，不给每行加入场动画；用惰性构建处理大量数据。
- **标签型**：按 `Wrap` 实际布局高度展开，整组标签统一淡入，不逐个弹出，避免逐行等待感。
- **信息型**：同样只做尺寸过渡与整体淡入，图表不叠加多余入场动画。

嵌套展开（城市 → 线路 → 站点）：每层独立状态，内层展开不重触发外层动画，内层高度正确反馈到外层布局；快速连续展开收起允许反向；重建子组件不得丢失内部状态或滚动位置。

运行规则：

- 展开中再次点击立即反向，从当前高度与偏移继续，不回跳初始态。
- 关闭中的内容不可点击、不可聚焦、不进入语义树；关闭完成后才从布局移除。
- 收起不应造成滚动位置跳动，也不自动强制滚动，除非业务明确要求。

实现：`_GalleryCollapse`（`gallery_navigation.dart`）；展开/收起时长、箭头、位移均取 `expand`/`collapse`/`arrow`/`expandDistance`/`micro`。

### 3.2 半模态（Bottom Sheet）

适用：图片选择与裁切、贡献者名单、操作确认、内容选择、筛选、临时信息。

弹窗属于当前页面上层，底层页面保留为背景上下文；不从屏幕外弹跳进入，不做缩放。

| 属性 | 打开 | 关闭 |
| --- | --- | --- |
| 时长 | `sheet` 320ms | `sheetBack` 240ms |
| 缓动 | `decelerate`（easeOutCubic） | `accelerate`（easeInCubic） |
| 位置 | 屏幕底部之外 → 目标位置 | 当前高度 → 屏幕底部之外 |
| 遮罩 | 0 → 0.40（`sheetScrim`） | 0.40 → 0 |
| 内容透明度 | 0 → 1 | 1 → 0 |

弹窗与遮罩严格同步，内容不出现二次弹跳。

固定高度与可拖动两种形态：

- **固定高度**：高度由内容与设计规格确定，不允许拖动改高。
- **可拖动**：如贡献者与许可详情，中位 57%、展开 90%、低于 42% 触发关闭；吸附时长取 `normal` 220ms，减少动态效果时不吸附。拖动时弹窗跟随手指，遮罩透明度随位置同步变化；松手按速度与位移决定关闭或恢复，恢复从当前位置继续，不重置起点。拖动与程序触发的打开/关闭共用同一位置状态。

关闭方式按场景配置，不要求所有半模态一致：关闭按钮、点击遮罩、下滑、系统返回、Android 预测性返回。拖动关闭不能是唯一方式。图片裁切在存在未提交修改时由业务层拦截关闭并给出确认；卡面裁切属于「返回先退出编辑，再次返回才关闭弹窗」。

实现：`_GallerySheet`（`gallery_overlays.dart`，`DraggableScrollableSheet`，比例常量 0.57／0.42／0.90）；路由时长与遮罩取 `_GalleryPopupRoute` 的 `sheet`/`sheetBack`/`sheetScrim`。

### 3.3 锚点菜单

适用：排序、筛选、更多操作、下拉选择器、Popup/Dropdown。

菜单从触发器附近出现，具有明确锚点，不像半模态从屏幕底部进入。

| 属性 | 进入 | 退出 |
| --- | --- | --- |
| 时长 | `menu` 180ms | `menuBack` 140ms |
| 缓动 | `decelerate`（easeOutCubic） | `accelerate`（easeInCubic） |
| 透明度 | 0 → 1 | 1 → 0 |
| 缩放 | .96 → 1 | 1 → .98 |
| 位移 | 6dp → 0（`menuDistance`，向下展开取 −6dp） | 随缩放收敛 |

- 下方空间足够向下展开，不足向上展开；不超出屏幕边界，锚点保持合理。
- 菜单完全打开后才把退出缩放基准切到 .98，避免进入过程被退出参数污染。
- 轻量 Popup 只放少量操作，通常不加遮罩；Dropdown 保留当前选择并给明确反馈，内容复杂时改用独立页面或半模态，不无限加长菜单。
- 同一时刻只允许一个菜单 Overlay；重复点击复用或关闭现有实例。
- 支持点击外部、键盘与系统返回关闭；锚点移动、键盘与焦点变化时重新定位。

实现：`_GalleryMenuAnchor`（`gallery_navigation.dart`）、`_GalleryMenuTransition` 与 `_GalleryMenuLayout`（`gallery_overlays.dart`），参数取 `menu`/`menuBack`/`menuScale`/`menuExitScale`/`menuDistance`。

### 3.4 层级导航（进入／返回）

适用：城市详情、线路详情、卡包详情、设置子页面等父子层级。

| 属性 | 进入 | 返回 |
| --- | --- | --- |
| 时长 | `page` 300ms | `back` 260ms |
| 新页面 | 从右向左推进，保持清晰，不强制淡入 | — |
| 旧页面 | 轻微左移（次级进度 × .06） | 从左侧恢复 |
| 当前页面 | — | 向右退出 |

- 页面不做明显缩放，返回与进入保持空间连续。
- 用稳定路由条目保留搜索词、滚动位置与页面状态；返回后恢复原列表位置。
- 预测性返回手势跟手时进度按手势原值驱动，取消时回到原位，提交后才弹栈；不能在手势取消时错误弹栈，也不能在提交时从 1.0 重播。
- 快速连续导航不得重复 Pop，不得让动画回调覆盖最新路由状态。
- 平台原生导航体验优先于强制统一的自定义转场。

实现：`_GalleryPageRoute`（`page`/`back`）、`_GalleryPredictiveRoute`（预测性返回的取消与提交）。

### 3.5 同级页面切换

适用：底栏四个主页面之间。

- 时长 `main` 200ms（蓝本区间 180–220ms），曲线取 `GalleryMotion.curve`（= `decelerate`，easeOutCubic），见 `gallery_navigation.dart:668` 的 `_GalleryMotion.curve.transform(_animation.value)`。
- 正文原位交叉淡化，可带 ≤200ms 的左右滑动；底栏与标题栏固定，不随页面转场移动。
- 只允许点击底栏切换，正文横滑不切功能页；保留各分支页面状态与滚动位置。
- 快速反向时从当前不透明度继续，不从 0 重来。
- 页面切换不重复执行不必要的入场动画。

实现：`_GalleryMainTransition`（`main`）；底栏与分段胶囊用 `capsule` 180ms。

### 3.6 提示（Snackbar / Toast）

| 属性 | 出现 | 消失 |
| --- | --- | --- |
| 时长 | `feedbackIn` 240ms | `feedbackOut` 180ms |
| 缓动 | `decelerate`（easeOutCubic） | `accelerate`（easeInCubic） |
| 透明度 | 0 → 1 | 1 → 0 |
| 位移 | +8dp → 0（`distance`） | 0 → +4dp（`small`） |

- 保持轻量，不使用明显弹跳；提示不遮挡右上安全区与主要操作。
- 统一队列：同一时刻只显示一条，新消息按重要程度替换或排队，不无限堆叠。
- 支持成功、失败、信息、警告与手动关闭；展示时长属于消息调度，不属于动效。
- 状态图标切换用轻量淡入（`fast` 160ms），错误可用轻微水平位移，不持续震动或摇晃。
- 消息动画不得阻碍其他交互。

实现：`GalleryFeedbackHost`（`gallery_feedback.dart`），进入/退出与位移取 `feedbackIn`/`feedbackOut`/`distance`/`small`。

### 3.7 按钮与状态变化

- **按压**：`pressedScale` .98，`instant` 100ms，不改变布局；松开回到 1，用缓出曲线。禁用态必须有明确视觉与交互限制，不能只靠动画表达。
- **开关**：滑块平滑移动、背景色同步过渡，无弹跳；触摸立即反馈。
- **图标切换**：收藏、复制、展开等用 `AnimatedSwitcher` 或专用转场，时长 `content` 160ms，避免直接替换造成闪烁。
- **数据状态**：旧数据退出、新数据渐入；不做大范围数字滚动；高频更新做节流。
- **骨架屏**：Loading 结束时骨架淡出、内容淡入，两者布局尽量一致，避免页面高度突变。
- **识别结果**：首页读卡结果卡的高度以 `readResult` 560ms 调整，曲线取 `readCurve`（`easeInOutCubicEmphasized`，项目补充）；内容淡入用 `slow` 400ms + `decelerate`，淡出用 `content` 160ms + `accelerate`。读卡示意形变用 `readMorph`（= `readResult`）560ms，失败徽标 `readFailure` 520ms，示意循环 `readLoop` 2800ms（纯装饰，蓝本未定义）。全部由 `GalleryMotion` 承载，减少动态效果时直接显示。

实现：`GalleryPressFeedback`（`gallery_motion.dart`）、`_GalleryFade`（`gallery_navigation.dart`）、`gallery_read_prompt.dart`。

### 3.8 颜色与主题

- 局部过渡：箭头旋转用 `arrow`（= `theme`）200ms、`standard` 曲线（`gallery_app.dart:597`）；底栏图标与胶囊底色用 `capsule` 180ms、`decelerate` 曲线（`gallery_navigation_item.dart:66`／`:74`／`:87`）；动作组背景切换的 `switchInCurve`／`switchOutCurve` 取 `decelerate`／`accelerate`。
- **项目已确定例外**：全局亮暗主题切换一次性应用语义色（`themeAnimationDuration: Duration.zero`，仅主壳 `gallery_app.dart`；许可同意屏不受此限）。整树逐帧交叉淡化会重建全部主题化组件并掉帧；一次性应用保留布局、状态、滚动位置与输入，减少动态效果用户看到的结果相同。该例外不是遗漏，不得改回整树动画。

### 3.9 列表项增删与左滑操作

适用：卡包与行程列表的删除、读卡完成后新卡片插入、卡片左滑揭示操作。

| 属性 | 插入／左滑揭示 | 移除／回弹 |
| --- | --- | --- |
| 时长 | `insert` 260ms／`swipe` 200ms | `remove` 220ms／`swipe` 200ms |
| 缓动 | `decelerate`（easeOutCubic） | `standard`（easeInOutCubic） |
| 尺寸与透明度 | 高度 0 → 实际高度，透明度同步 | 高度 → 0 |
| 位移 | 左滑跟手全程线性，松手用 `swipe` 吸附 | 松手回弹同 `swipe` |

- 左滑只揭示操作托盘，动作必须二次点击；跟手位移始终线性，只有程序吸附用曲线。
- 插入／移除沿用折叠的等值档位（`insert` = `expand`，`remove` = `collapse`），语义与展开收起分开，便于单独调整。
- 轻量局部高亮（如裁切框激活描边）用 `highlight` 180ms。
- 减少动态效果时尺寸与位移直达目标态，删除回调不等待动画。

实现：`_GalleryWalletItem`／`_GallerySwipeReveal`（`gallery_wallet_item.dart`）、裁切框（`gallery_face_crop.dart`）。

## 4. 中断、反向与连续操作

### 4.1 中断

所有交互组件都要处理中断：展开中点击收起、半模态打开中关闭、菜单出现中点击别处、页面切换中触发返回。

1. 从当前视觉状态继续，不强制等待上一段结束。
2. 不回跳到初始状态。
3. 控制器复用或正确重建，不重复启动导致状态异常。
4. 动画结束后组件状态与业务状态一致；完成回调不得覆盖更新后的状态。

### 4.2 快速连续操作

禁止：

- 多次点击产生多个 Overlay、多个菜单、多个半模态。
- 重复启动同一控制器造成跳变。
- 返回时重复 Pop。
- 旧动画的完成回调改写最新业务状态。

反向时长为正向时长乘以剩余进度，或使用镜像曲线；跟随手指的进度始终线性。

### 4.3 滚动与展开协调

- 滚动列表时不意外触发其他组件动画。
- 展开不造成无意义滚动跳动，嵌套展开保持滚动上下文。
- 不自动强制滚动，除非业务明确要求。

### 4.4 动画与布局

动画期间不得出现文字变形、裁剪错误、边框闪烁、圆角突变、阴影跳动或内容重叠。尺寸动画必须基于实际布局，不用固定高宽硬撑。

## 5. 减少动态效果与无障碍

### 5.1 减少动态效果

读取系统偏好（`MediaQuery.disableAnimationsOf`／`maybeDisableAnimationsOf`）。启用时：

- 取消非必要的大幅位移、缩放与装饰动画。
- 简化或跳过页面与半模态转场。
- 直接显示目标态；`GalleryMotion.duration()` 返回 `Duration.zero`。
- 保留状态反馈、焦点顺序、消息队列、返回栈与滚动位置，交互逻辑不变。
- 拖动吸附关闭，松手直接落到目标位置。

### 5.2 语义

- 展开面板提供展开/收起状态、可操作性与选中态，不能只靠箭头方向传达。
- 关闭按钮具有明确语义标签；隐藏或不可交互的内容退出语义树。
- 触控区域符合项目无障碍尺寸；拖动关闭不能是唯一关闭方式；系统返回行为可预测。

## 6. 性能与实现边界

- 简单动画优先 Flutter 内置 Animated Widgets；需要手势协调或中断的用 `AnimationController`。
- 大列表惰性构建，展开不为整表一次性建子项；必要处用 `RepaintBoundary`。
- 避免 `setState` 扩散、动画期间同步大数据处理、不必要的全屏重绘。
- 不为了统一而过度封装，不为每个简单动画建独立控制器。
- 必须在真机验证帧率、输入法与预测性返回，模拟器通过不等于设备通过。
- 现行组织方式：Token 集中于 `lib/gallery/gallery_motion.dart`，场景组件为 `lib/gallery/` 下的私有 `_Gallery*` 组件，不按蓝本第 11 节的 `lib/core/motion/` 目录拆分；组织方式不同不影响参数，按现状映射。

## 7. GalleryMotion 实现映射

### 7.1 基础 Token

| 文档 Token | 代码常量 | 值 |
| --- | --- | --- |
| `instant` | `GalleryMotion.instant` | 100ms |
| `fast` | `GalleryMotion.fast` | 160ms |
| `normal` | `GalleryMotion.normal` | 220ms |
| `medium` | `GalleryMotion.medium` | 300ms |
| `slow` | `GalleryMotion.slow` | 400ms |
| `standard` | `GalleryMotion.standard` | `Curves.easeInOutCubic` |
| `emphasized` | `GalleryMotion.emphasized` | `Curves.easeOutCubic` |
| `decelerate` | `GalleryMotion.decelerate` | `Curves.easeOutCubic` |
| `accelerate` | `GalleryMotion.accelerate` | `Curves.easeInCubic` |
| `linear` | `GalleryMotion.linear` | `Curves.linear` |
| `readCurve` | `GalleryMotion.readCurve` | `Curves.easeInOutCubicEmphasized`（项目补充） |
| 默认曲线 | `GalleryMotion.curve` | `decelerate` |
| `micro` | `GalleryMotion.micro` | 2.0 |
| `small` | `GalleryMotion.small` | 4.0 |
| `distance` | `GalleryMotion.distance` | 8.0 |
| `large` | `GalleryMotion.large` | 16.0 |
| `menuDistance` | `GalleryMotion.menuDistance` | 6.0 |
| `expandDistance` | `GalleryMotion.expandDistance` | 6.0 |
| `menuScale` | `GalleryMotion.menuScale` | .96 |
| `pressedScale` | `GalleryMotion.pressedScale` | .98 |
| `menuExitScale` | `GalleryMotion.menuExitScale` | .98 |
| `sheetScrim` | `GalleryMotion.sheetScrim` | `Color(0x66000000)`（0.40） |

### 7.2 场景别名

| 场景 | 代码常量 | 值 | 文档小节 |
| --- | --- | ---: | --- |
| 折叠展开 | `expand` | 260ms | 3.1 |
| 折叠收起 | `collapse` | 220ms | 3.1 |
| 箭头旋转／局部过渡 | `arrow`（= `theme`） | 200ms | 3.1／3.8 |
| 半模态打开 | `sheet` | 320ms | 3.2 |
| 半模态关闭 | `sheetBack` | 240ms | 3.2 |
| 菜单进入 | `menu` | 180ms | 3.3 |
| 菜单退出 | `menuBack` | 140ms | 3.3 |
| 页面进入 | `page` | 300ms | 3.4 |
| 页面返回 | `back` | 260ms | 3.4 |
| 同级切换 | `main`（= `mainTab`） | 200ms | 3.5 |
| 底栏／分段胶囊 | `capsule` | 180ms | 3.5 |
| 提示进入 | `feedbackIn` | 240ms | 3.6 |
| 提示退出 | `feedbackOut` | 180ms | 3.6 |
| 图标／内容切换 | `content` | 160ms | 3.7 |
| 识别结果高度调整／读卡形变 | `readResult`／`readMorph` | 560ms | 3.7 |
| 读卡失败徽标 | `readFailure` | 520ms | 3.7 |
| 读卡示意循环（装饰） | `readLoop` | 2800ms | 3.7 |
| 列表项插入 | `insert`（= `expand`） | 260ms | 3.9 |
| 列表项移除 | `remove`（= `collapse`） | 220ms | 3.9 |
| 左滑揭示与回弹 | `swipe` | 200ms | 3.9 |
| 局部高亮／描边 | `highlight` | 180ms | 3.7 |

`GalleryMotion.duration(context, token)` 统一处理减少动态效果，返回 `Duration.zero`；直接在 `MediaQuery` 上分支的路径必须保持同样结果。

### 7.3 项目已确定例外

1. **主题切换一次性应用**：`gallery_app.dart` 的 `themeAnimationDuration: Duration.zero`，避免整树交叉淡化掉帧；`theme` 200ms 仅用于局部过渡与箭头。
2. **搜索防抖 280ms**：`gallery_knowledge_search.dart` 属输入调度，不是动效，不纳入 Token。
3. **首页专用交互**：贴卡示意、分段胶囊、跟随滚动的卡面为既有专用交互，不套页面转场；读卡相关时长（`readResult`／`readMorph`／`readFailure`／`readLoop`）与曲线 `readCurve` 是项目补充值，统一由 Token 承载。
4. **消息展示时长与读卡模拟计时**：属于业务调度，不套用动效时长。

## 8. 蓝本与实现差异清单

以蓝本 `2.7_spec.md` 为准。D1、D3、D4、D5 已由 US-009 在代码与本文档中对齐；其余差异按现状保留。

| 编号 | 项目 | 蓝本要求 | 当前实现 | 处置建议 |
| --- | --- | --- | --- | --- |
| D1 | 同级切换 Token | 180–220ms | US-009 前：`main` 借用 `theme` 的 200ms，数值合规但语义混用 | 已对齐（US-009）：拆出独立 `mainTab`／`swipe` Token，取值保持 200ms |
| D2 | 菜单退出位移 | 5.4 只列透明度与缩放 | `_GalleryMenuTransition` 退出时仍带 `menuDistance` 位移 | 以蓝本为准，退出只保留 1→.98 与淡出 |
| D3 | 硬编码时长 | 所有动效取 Token | US-009 前：`gallery_wallet_item.dart` 200／260／220ms；`gallery_face_crop.dart` 180ms；`gallery_detail.dart` 260ms；`gallery_read_prompt.dart` 160／400／560／520ms | 已对齐（US-009）：逐一替换为 Token，识别结果保留 560ms 语义 |
| D4 | 硬编码曲线 | 仅五条 Token 曲线 | US-009 前：`gallery_components.dart` 213–214、`gallery_detail.dart` 793／853、`gallery_face_crop.dart` 220、`gallery_wallet_item.dart` 51／252–253 直接引用曲线 | 已对齐（US-009）：改用 `standard`／`decelerate`／`accelerate` |
| D5 | 强调曲线 | 未定义 `easeInOutCubicEmphasized` | US-009 前：`gallery_read_prompt.dart` 116／177／228 使用该曲线 | 已对齐（US-009）：作为读卡专用曲线补入 `readCurve`，并回写 2.2／7.1；观感不变 |
| D6 | 位移 8 与 6 | 2.3 写「菜单、内容渐入 8dp」，5.3 写菜单 6dp | 菜单取 6dp，提示与内容取 8dp | 按场景值执行：菜单 6、提示 8；蓝本内部表述以 5.3 为准 |
| D7 | 组件与目录 | 建议 `lib/core/motion/` 与 `App*` 组件 | Token 在 `lib/gallery/gallery_motion.dart`，场景为私有 `_Gallery*` | 保留现状：参数已统一，拆目录不产生用户可见收益 |
| D8 | 共享元素转场 | 可选增强 | 未实现 | 不列为缺陷，按需再做 |
| D9 | 可拖动半模态阈值 | 蓝本未给数值 | 57%／90%／42%，吸附 220ms | 作为项目补充保留，已写入 3.2 |
| D10 | 减少动态效果 | 取消或缩短非必要动画 | 统一返回 `Duration.zero`，直接到目标态 | 与「保留状态反馈」一致，不改 |

## 9. 验证边界

### 9.1 自动化覆盖

Flutter 测试至少覆盖：快速反向（展开、页面、菜单）、返回手势取消与提交、遮罩与拖动、减少动态效果、主题切换、搜索状态与滚动恢复、消息队列不叠加。

### 9.2 设备验收

模拟器与 widget 手势不等于 Android 真机验证。以下仍需设备检查：低端机帧率、输入法弹出与收起、系统级预测性返回、不同屏幕尺寸与字体缩放、真机触感与拖动阈值手感。

### 9.3 验收清单

- [ ] 参数全部取自 Token，无新增硬编码。
- [ ] 缓动与方向匹配，无无意义弹跳。
- [ ] 动画不阻碍操作，状态与业务一致。
- [ ] 折叠高度自适应，嵌套互不干扰，连续点击无异常。
- [ ] 半模态遮罩同步、拖动跟手、关闭方式可配置、返回后底层状态保留。
- [ ] 菜单锚点正确、不越界、外部点击关闭、不产生多个实例。
- [ ] 页面进入/返回方向正确，滚动与查询状态保留，连续导航无路由异常。
- [ ] 提示不堆叠、不遮挡、可手动关闭。
- [ ] 减少动态效果下直达目标态且功能完整。
- [ ] 无语义缺失、内容闪烁或动画结束后的状态错误。

## 10. 版本历史

- **1.0.1**（2026-11-23）：按 `2.7_spec.md` 全文回写；补齐基础 Token 语义、场景运行规则、中断与反向、无障碍与验证边界；新增实现映射与差异清单。动效参数不变。
  - **1.0.1 内修订（US-009，2026-11-23）**：全量 Token 化落地——新增 `mainTab`／`swipe`／`insert`／`remove`／`highlight`／`readMorph`／`readFailure`／`readLoop`／`readCurve`，补 3.9 列表项与左滑场景，D1／D3／D4／D5 标记已对齐；参数值不变。
- **1.0**：首版，基础 Token、场景时长与验证边界，随 2.x 界面迁入项目。