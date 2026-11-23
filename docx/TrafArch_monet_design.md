# TrafArch 2.x — Monet Adoptive System
## DColor 1.1：莫奈自适应画布、预设主题与组件颜色

文档类型： UI Design & Development Specification  
适用平台： Flutter  Material 3  
设计模块： Theme System  Monet Color Extraction  Adaptive Surface  
版本： V1.1（2.6）  
状态：2.x 实现说明；原 V1.0 的色值与取色原则保留

---

# 1. 项目背景与设计目标

## 1.1 当前问题

目前 TraFArch 已经具备基于卡片图片进行莫奈取色的能力，并拥有多套预设主题。

但在当前设计中，莫奈取色主要影响主题色和部分交互元素，页面全局背景仍然采用固定的白色。

这导致：

1. 用户更换卡片图片后，应用的整体色彩氛围变化不够明显。
2. 主题色与页面背景之间缺乏联系，色彩系统不够完整。
3. 即使卡片已经呈现出明显的色彩特征，周围界面依然显得过于中性。
4. 页面背景、卡片容器、导航栏之间的视觉层级还有进一步优化的空间。

## 1.2 本次改造目标

引入 Monet Adaptive Canvas（莫奈自适应画布），让应用能够根据当前主题色动态生成一套协调的界面表面颜色。

本次改造包括：

- 六套预设主题的重新设计与统一。
- 莫奈动态取色背景生成机制。
- Light  Dark 两种模式的独立颜色适配。
- Flutter ThemeData 与 ThemeExtension 体系。
- 页面组件的颜色角色统一。
- 主题切换动画与无效取色回退机制。

## 1.3 核心设计理念

 让卡片决定界面的色彩氛围，让中性表面维持信息秩序，让主题色负责交互表达。

本次设计不是简单地将白色背景替换为主题色，而是建立一套有主次、有层级、可动态变化的表面颜色系统。

---

# 2. 总体颜色架构

## 2.1 四层表面结构

整个应用采用四层表面体系。

 层级  Token  使用场景 
---------
 Level 1  Canvas  页面全局背景 
 Level 2  Surface  内容卡片、弹窗、悬浮导航 
 Level 3  Surface Container  次级区域、选中状态、辅助容器 
 Level 4  Outline  卡片描边、分割线、边界 

四层颜色之间应当具有明确的亮度关系。

### Canvas：全局画布

- Light Mode：采用低饱和度的主题色衍生近白色。
- Dark Mode：采用带有微弱主题色倾向的深色。
- 页面背景统一使用 Canvas。
- 不允许直接使用莫奈提取出的原始主色作为大面积背景。

### Surface：内容表面

- Light Mode：默认保持纯白 `#FFFFFF`。
- Dark Mode：采用深灰蓝、深灰绿等低彩度深色。
- 用于承载主要信息。
- 与 Canvas 之间形成足够的视觉区分。

### Surface Container：辅助表面

用于表达次级层级和交互状态。

例如：

- Bottom Navigation 选中背景。
- 次级功能区域。
- 筛选器选中状态。
- 信息分组。
- 弱强调型按钮。

### Outline：描边与分割

- 不使用过重的边框。
- 描边应带有轻微主题色倾向。
- 与 Surface 和 Canvas 保持足够的边界辨识度。
- 不允许所有容器统一使用相同的边框颜色。

## 2.2 颜色层级关系

Light Mode：

Canvas  Surface Container  Surface

这里的大小关系表示视觉明度方向，而不是颜色优先级。

Dark Mode：

Canvas  Surface Container  Surface

暗色模式下同样保持由背景向内容表面逐渐提亮的结构。

---

# 3. 六套预设主题设计

## 3.1 主题总览

本次六套主题分别为：

1. 靛蓝 Indigo
2. 青绿 Teal
3. 藤紫 Wisteria
4. 蔷薇 Rose
5. 麦金 Wheat
6. 雾灰 Mist

六套主题共享同一套语义 Token，不允许因为主题不同而改变组件的颜色使用规则。

## 3.2 靛蓝 Indigo

设计定位：清爽、理性、沉稳。

保留此前讨论的图标颜色体系：

- 图标背景：`#D5E4F1`
- 图标图案：`#4E7098`

以 `#4E7098` 作为主题种子色。

 Token  色值 
------
 Seed  `#4E7098` 
 Canvas  `#F3F7FB` 
 Surface  `#FFFFFF` 
 Surface Container  `#EAF1F8` 
 Surface Container High  `#E3ECF5` 
 Primary  `#496B91` 
 Primary Container  `#E5EDF7` 
 Outline Soft  `#E4EBF2` 
 Outline  `#DCE7F1` 
 Outline Strong  `#C9D8E7` 

设计说明：

靛蓝作为默认主题，整体保持冷静、清爽的视觉感受。

Canvas 不能出现明显的蓝色覆盖感，而应更接近带蓝调的冷白色。

它也是本次莫奈自适应画布的参考基准。

## 3.3 青绿 Teal

设计定位：自然、温和、舒适。

 Token  色值 
------
 Seed  `#568276` 
 Canvas  `#F3F8F5` 
 Surface  `#FFFFFF` 
 Surface Container  `#EAF2ED` 
 Surface Container High  `#E2EEE7` 
 Primary  `#477365` 
 Primary Container  `#E4EFE8` 
 Outline Soft  `#E3ECE6` 
 Outline  `#DCE8E1` 
 Outline Strong  `#C9DCD1` 

设计说明：

青绿主题避免使用明显的薄荷绿色背景。

整体应该更加接近自然环境中的浅绿色调，不能过于鲜艳，也不能让页面显得发黄。

## 3.4 藤紫 Wisteria

设计定位：优雅、安静、细腻。

 Token  色值 
------
 Seed  `#806C98` 
 Canvas  `#F7F4F9` 
 Surface  `#FFFFFF` 
 Surface Container  `#EFEAF4` 
 Surface Container High  `#E8E1F0` 
 Primary  `#6E5A86` 
 Primary Container  `#EBE5F1` 
 Outline Soft  `#EAE5EF` 
 Outline  `#E3DCEA` 
 Outline Strong  `#D7CDE1` 

设计说明：

藤紫需要特别注意饱和度控制。

背景应偏向微微带紫的灰白色，而不是粉紫色。

避免产生过强的浪漫化、装饰化感受，保持 TraFArch 一贯的工具属性。

## 3.5 蔷薇 Rose

设计定位：温柔、细腻、柔和。

 Token  色值 
------
 Seed  `#A96878` 
 Canvas  `#FAF5F6` 
 Surface  `#FFFFFF` 
 Surface Container  `#F3E9EC` 
 Surface Container High  `#EEDFE4` 
 Primary  `#925363` 
 Primary Container  `#F2E5E9` 
 Outline Soft  `#F0E5E8` 
 Outline  `#E9DADF` 
 Outline Strong  `#E2CCD3` 

设计说明：

蔷薇主题不能直接将背景处理成明显的粉色。

应当以带有微弱红色倾向的暖白色为主要表现。

重点避免与 Success 等语义颜色发生混淆。

## 3.6 麦金 Wheat

设计定位：温暖、沉稳、复古。

 Token  色值 
------
 Seed  `#A18450` 
 Canvas  `#F8F6F0` 
 Surface  `#FFFFFF` 
 Surface Container  `#F0EBDD` 
 Surface Container High  `#EAE2CC` 
 Primary  `#806637` 
 Primary Container  `#EFE8D7` 
 Outline Soft  `#EEE9DC` 
 Outline  `#E5DDCA` 
 Outline Strong  `#DCCFB4` 

设计说明：

麦金需要控制黄色色相的存在感。

不应使用明显的米黄色背景，更不应该呈现纸张发黄的效果。

整体接近暖灰白色，带有轻微麦金倾向。

## 3.7 雾灰 Mist

设计定位：克制、理性、中性。

这是新增的第六套主题。

 Token  色值 
------
 Seed  `#687887` 
 Canvas  `#F5F7F8` 
 Surface  `#FFFFFF` 
 Surface Container  `#EBEFF2` 
 Surface Container High  `#E6ECEF` 
 Primary  `#526675` 
 Primary Container  `#E8EDF1` 
 Outline Soft  `#E5EAED` 
 Outline  `#DDE4E8` 
 Outline Strong  `#CBD6DD` 

设计说明：

雾灰并不是没有主题色，而是将主题色的彩度压低，使界面接近高级灰。

适合不喜欢明显彩色界面的用户。

同时可以作为莫奈提取失效时的一套中性回退选择。

---

# 4. Monet Adaptive Canvas 动态生成机制

这是本次改造最重要的部分。

## 4.1 基本原则

莫奈提取负责提供主题种子色。

自适应画布生成器负责将种子色转换为完整的界面色彩体系。

两者应当解耦。

不允许直接使用莫奈提取结果覆盖所有页面颜色。

例如：

用户卡片图片提取到明显的高饱和蓝色：

- 主题交互色可以保留较强的蓝色特征。
- Canvas 应当转换成浅蓝灰白色。
- Surface 继续保持纯白。
- Surface Container 使用低饱和蓝色。
- Outline 使用更加克制的浅蓝灰色。

## 4.2 使用 OKLCH 色彩空间

动态背景生成优先采用 OKLCH。

相比直接修改 RGB 或简单叠加透明度，OKLCH 可以更直接地控制：

- L：感知明度。
- C：感知彩度。
- H：色相。

从而避免不同主题在降低透明度后出现不一致的视觉效果。

### 输入

`seedColor`

即当前卡片莫奈取色后确定的代表色。

### 输出

生成：

- Canvas
- Surface
- Surface Container
- Surface Container High
- Primary
- Primary Container
- Outline Soft
- Outline
- Outline Strong
- On Primary

## 4.3 Light Mode 生成规则

设提取到的主色为：

`Seed = OKLCH(L, C, H)`

生成规则：

 Token  L  C  H 
------------
 Canvas  0.975  clamp(C×0.10, 0.006, 0.014)  H 
 Surface  1.000  0  不适用 
 Surface Container  0.945  clamp(C×0.18, 0.010, 0.022)  H 
 Surface Container High  0.925  clamp(C×0.20, 0.012, 0.026)  H 
 Outline Soft  0.925  clamp(C×0.12, 0.006, 0.016)  H 
 Outline  0.890  clamp(C×0.12, 0.008, 0.018)  H 

说明：

1. Canvas 的色彩倾向必须非常克制。
2. Surface 默认使用纯白，不跟随主题色变化。
3. Surface Container 的主题色倾向要比 Canvas 略明显。
4. Outline 需要保证结构辨识度，不能仅仅通过透明度叠加生成。
5. 最终 RGB 色值需要经过 sRGB 色域映射，避免溢出。

上述 OKLCH 参数是首轮实现的建议起点，最终视觉表现需要结合实际提取色进行校准。

## 4.4 Primary 生成规则

Primary 不直接使用未经处理的种子色。

应当：

1. 保留 Seed 的 H。
2. 保留适当的主题色彩度。
3. 根据背景和前景文字的对比度调整 L。
4. 保证按钮文字有足够的可读性。

对于主要按钮：

- 优先使用白色文字。
- 按钮背景需要达到 WCAG AA 普通文本 4.51 的对比度。
- 如果原始 Seed 过浅，则自动降低 Primary 的明度。
- 如果降低明度仍无法保证合理色彩表现，则使用主题色的深色衍生色。

不能为了保持原始取色而牺牲按钮可读性。

## 4.5 Dark Mode 生成规则

暗色模式不能简单地将 Light Mode 的颜色反转。

应当重新生成深色表面体系，但继承原始 Seed 的 H。

建议初始参数：

 Token  L  C 
---------
 Canvas  0.19  clamp(C×0.08, 0.006, 0.015) 
 Surface  0.23  clamp(C×0.08, 0.008, 0.018) 
 Surface Container  0.26  clamp(C×0.12, 0.010, 0.020) 
 Surface Container High  0.30  clamp(C×0.14, 0.010, 0.022) 
 Outline  0.40  clamp(C×0.10, 0.008, 0.018) 

Dark Mode 下：

- 避免纯黑色背景。
- 避免大面积高饱和主题色。
- 卡片主体使用深色中性表面。
- Primary 需要适当提亮，并重新计算前景文字颜色。
- 不允许主题色直接影响系统语义色。

## 4.6 极端颜色保护机制

动态取色需要增加保护机制。

 输入情况  处理方式 
------
 高饱和度红色  大幅压低背景彩度 
 高饱和度黄色  限制黄色背景的存在感 
 极浅颜色  使用适当加深后的交互色 
 极暗颜色  保留色相，重新生成适合 Light Mode 的色值 
 低彩度灰色  允许生成接近雾灰的画布 
 无有效提取色  回退到用户当前预设主题 

特别注意：

低彩度颜色并不一定意味着提取失败。只有当颜色缺乏可用的主题特征时，才考虑回退。

## 4.7 色彩过渡与色域处理

生成出来的颜色必须经过合法的 sRGB 色域处理。

不要简单地对 RGB 三个通道进行截断，否则可能造成色相偏移。

对于无法直接映射的 OKLCH 色值，应当优先降低 C，直到进入 sRGB 色域。

L 和 H 尽可能保持稳定。

---

# 5. 主题来源与状态管理

## 5.1 两种主题来源

应用需要明确区分：

### Preset Theme

用户主动选择六套预设主题中的任意一套。

此时使用预定义的颜色 Token。

### Monet Adaptive Theme

用户选择跟随当前卡片取色。

系统根据当前生效卡片的莫奈提取结果动态生成主题。

两种模式共享同一套 Token 结构。

## 5.2 主题种子来源优先级

Monet 模式下：

1. 当前首页正在展示的有效卡片。
2. 该卡片最近一次有效的莫奈取色结果。
3. 如果没有有效取色结果，则使用用户指定的默认预设主题。

不允许从最近一次行程、车站颜色或者第三方运营商 Logo 中提取主题色。

这些颜色属于业务数据，不应当参与应用主题生成。

## 5.3 卡面图片更新

用户修改卡面图片时：

- 不需要在裁切器拖动过程中实时重新生成整个主题。
- 应当在图片裁切确认并保存后更新提取色。
- 完成新颜色计算后再切换主题。
- 取消裁切不改变当前主题。

## 5.4 缓存机制

建议缓存以下信息：

- Card ID
- 图片资源标识或内容 Hash
- 原始 Seed
- 生成后的 Light Tokens
- 生成后的 Dark Tokens
- 算法版本

图片发生变化或算法版本更新时重新生成。

---

# 6. 页面组件颜色使用规范

本节规定全局 UI 如何使用新的颜色 Token。

## 6.1 Scaffold 与页面背景

所有主要页面的 Scaffold 使用 Canvas。

包括：

- 首页
- 行程页
- 专家页
- 卡包页
- 设置页

页面顶部状态栏区域保持与 Canvas 连续。

不允许不同页面自行指定独立的白色背景，除非有明确的沉浸式设计需求。

## 6.2 内容卡片

例如首页的最近一次行程卡片：

- 背景：Surface。
- 描边：Outline Soft 或 Outline。
- 文字：On Surface。
- 次级文字：On Surface Variant。

推荐使用轻量描边与克制的阴影。

不要通过给所有卡片增加明显的主题色背景来体现主题。

内容卡片的首要任务是承载信息。

## 6.3 交通卡展示区域

交通卡的卡面背景属于业务内容，不属于应用表面颜色。

必须保持原始设计及莫奈取色之外的独立性。

不允许：

- 自动给卡片图片叠加主题色。
- 修改卡片图片亮度以匹配页面背景。
- 使用 Canvas 覆盖卡片本身。
- 因为主题变化而修改卡片 Logo 的颜色。

卡片与界面背景应该保持相对独立。

## 6.4 主操作按钮

例如：

- 保存卡片
- 确认
- 完成
- 保存修改

使用 Primary 作为填充色。

文字采用 On Primary。

次级操作：

- 背景使用 Surface。
- 边框使用 Outline。
- 文字使用 Primary 或 On Surface。

禁用状态必须单独处理，不允许只依靠降低透明度。

## 6.5 Bottom Navigation

结合当前首页的设计：

- 导航栏整体使用 Surface。
- 容器保持圆角悬浮设计。
- 选中项使用 Primary Container。
- 选中图标与文字采用主题色。
- 未选中图标与文字采用 On Surface Variant。
- 导航容器阴影保持中性且克制。

不需要给整个导航栏染色。

## 6.6 Snackbar

保留之前确定的浅色悬浮式 Snackbar 方案。

背景使用 Surface。

文字使用 On Surface。

Success、Error、Warning 图标及状态色保持固定，不跟随莫奈主题变化。

主题色只影响必要的辅助交互元素，不影响语义状态识别。

## 6.7 Dialog 与 Bottom Sheet

- 背景使用 Surface。
- 页面下层仍使用 Canvas。
- 输入框和辅助区使用 Surface Container。
- 拖动手柄采用中性弱对比颜色。
- 主操作采用 Primary。

Bottom Sheet 展开和关闭时，不应因为背景动态生成而发生不必要的闪烁。

## 6.8 输入框

普通状态：

- 背景：Surface。
- 边框：Outline Soft。
- 文字：On Surface。

聚焦状态：

- 边框：Primary。
- 焦点指示应同时保留足够的形状或宽度差异。

错误状态使用固定 Error 色。

### 知识库搜索（2.6）

搜索入口位于知识库标题之后、TU/CU 切换和数据总览之前，随内容滚动。默认 52dp，26dp 胶囊圆角，支持系统大字，不使用高饱和底色或叠加阴影。

| 搜索角色 | `GalleryTokens` 对应角色 |
| --- | --- |
| `inputContainer` | `surfaceContainer`，与普通卡片 `surface` 区分 |
| `inputForeground` | `text`，承接对比度校正后的 On Surface |
| `inputHint`、`inputIcon` | `muted`，承接 On Surface Variant |
| `inputOutline` | `outlineSoft` |
| `inputFocusedOutline`、`inputCursor` | `action`，承接交互主色 |
| `inputDisabled` | 独立禁用前景，针对输入表面校正，不降低整控件透明度 |
| 数据加载失败 | `danger` 搭配明确文案和重试；不清除输入，也不把数据错误标成字段错误 |
| 命中的编码 | 详情用 `tone` 强调匹配记录，并显示原始编码和来源字段（如有） |

六套预设（靛蓝、青绿、藤紫、蔷薇、麦金、雾灰）与卡面莫奈共用这些接口。搜索不读取当前预设 ID，不从图片或数据图例直接取色。语义状态色与数据色保持独立：轨道→data-1，公交→data-2，其他→data-3；主题可以调和色相，但不改变分类索引。

---

# 7. 全局中性色与语义颜色

虽然本次加入动态主题，但中性色及语义色必须保持统一。

## 7.1 Light Mode 中性色

 Token  色值 
------
 On Surface  `#202A35` 
 On Surface Variant  `#65717E` 
 Muted Text  `#89939D` 
 Disabled Text  `#A6AFB8` 

这些颜色不随莫奈主题改变。

## 7.2 Dark Mode 中性色

 Token  色值 
------
 On Surface  `#EEF2F6` 
 On Surface Variant  `#B1BCC7` 
 Muted Text  `#8995A1` 
 Disabled Text  `#697582` 

## 7.3 固定语义颜色

以下颜色需要独立于主题系统：

 语义  参考颜色 
------
 Success  `#347864` 
 Warning  `#9A6A25` 
 Error  `#B45353` 
 Info  `#4F7098` 

暗色模式需要提供对应的浅色版本，并重新验证对比度。

语义颜色与主题颜色不能相互替代。

---

# 8. Flutter 技术实现规范

## 8.1 技术方案

使用：

- Flutter
- Material 3
- ThemeData
- ColorScheme
- ThemeExtension

不建议让具体页面直接读取莫奈取色结果并自行计算背景色。

所有颜色计算应该集中在统一的主题管理层。

## 8.2 推荐架构

建议划分为以下几个模块：

```text
lib
├── core
│   └── theme
│       ├── app_theme.dart
│       ├── app_color_scheme.dart
│       ├── app_theme_extension.dart
│       ├── preset_theme.dart
│       ├── monet_theme_generator.dart
│       ├── color_space_utils.dart
│       └── theme_repository.dart
```

职责划分：

preset_theme.dart

负责六套预设主题的数据定义。

monet_theme_generator.dart

负责根据 Seed 生成完整的动态主题。

color_space_utils.dart

负责 OKLCH、sRGB 转换和色域映射。

app_theme_extension.dart

负责扩展 Flutter 原生 ColorScheme 未覆盖的自定义颜色角色。

theme_repository.dart

负责主题来源、缓存与状态管理。

app_theme.dart

负责生成 Light  Dark ThemeData。

## 8.3 ThemeExtension 建议字段

```dart
class AppThemeExtension
    extends ThemeExtensionAppThemeExtension {

  final Color canvas;
  final Color surface;
  final Color surfaceContainer;
  final Color surfaceContainerHigh;

  final Color primary;
  final Color primaryContainer;

  final Color outlineSoft;
  final Color outline;
  final Color outlineStrong;

  final Color onSurfaceVariant;
  final Color mutedText;

  const AppThemeExtension({
    required this.canvas,
    required this.surface,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.primary,
    required this.primaryContainer,
    required this.outlineSoft,
    required this.outline,
    required this.outlineStrong,
    required this.onSurfaceVariant,
    required this.mutedText,
  });
}
```

以上为结构示意，实际实现时还应补充 copyWith、lerp 等 ThemeExtension 必需方法。

## 8.4 ThemeData 生成

由统一的主题工厂生成：

```dart
ThemeData buildAppTheme({
  required AppThemeExtension tokens,
  required bool isDark,
}) {
  final scheme = ColorScheme(
    brightness isDark
         Brightness.dark
         Brightness.light,
    primary tokens.primary,
    onPrimary isDark
         const Color(0xFF18212B)
         const Color(0xFFFFFFFF),
    secondary tokens.primary,
    onSecondary isDark
         const Color(0xFF18212B)
         const Color(0xFFFFFFFF),
    surface tokens.surface,
    onSurface isDark
         const Color(0xFFEEF2F6)
         const Color(0xFF202A35),
    surfaceContainer tokens.surfaceContainer,
    error const Color(0xFFB45353),
    onError const Color(0xFFFFFFFF),
  );

  return ThemeData(
    useMaterial3 true,
    colorScheme scheme,
    scaffoldBackgroundColor tokens.canvas,
    extensions [tokens],
  );
}
```

注意：这是便于理解的实现示意。正式开发需要补齐当前 Flutter SDK 对应版本的 ColorScheme 必需字段，并将所有组件颜色角色同步映射。

## 8.5 组件取色要求

Widget 内禁止硬编码主题色值。

统一通过：

```dart
final tokens = Theme.of(context)
    .extensionAppThemeExtension()!;
```

或者使用 `Theme.of(context).colorScheme` 取得语义颜色。

避免出现：

- 某个页面单独写死背景色。
- 某个卡片固定使用靛蓝色边框。
- 某个按钮直接读取莫奈原始颜色。
- 某个主题只改变 Scaffold，却没有同步导航栏和弹窗。

---

# 9. 主题切换动画

## 9.1 动画目标

当用户更换预设主题，或者修改卡片图片导致莫奈主题变化时：

所有表面颜色应该自然过渡。

不能出现页面闪白、容器突然跳色或局部组件短暂使用旧颜色的情况。

## 9.2 动画参数

建议：

 属性  参数 
------
 Duration  200ms（开启减少动态效果时为 0ms） 
 Curve  Curves.easeInOutCubic 
 实现  AnimatedTheme 
 作用范围  全局 ThemeData 

使用一次统一的主题变化驱动整个页面。

避免每个 Widget 自己执行独立的颜色动画。

知识库搜索的输入控制器、焦点和结果列表独立于主题。主题变化只更新角色色值，不重新索引、检索或重置滚动位置。时长规范见 [TrafArch Motion 1.0.1](TrafArch_motion_system.md)。

## 9.3 图片更新时的动画处理

在图片裁切器中：

- 拖动裁切范围时不更新全局主题。
- 点击确认后开始处理新图片。
- 新主题计算完成后执行颜色过渡。
- 页面其余布局保持稳定。

不能让图片加载与主题计算互相阻塞。

## 9.4 系统状态栏

主题变化时同步更新 Android System UI Overlay Style。

Light Mode 使用深色状态栏图标。

Dark Mode 使用浅色状态栏图标。

状态栏背景与页面 Canvas 保持一致。

---

# 10. 性能与异常处理

## 10.1 避免主线程计算

颜色空间转换和动态调色属于计算任务。

建议将图片采样与复杂颜色计算放入后台 Isolate。

UI 线程只接收最终颜色结果。

## 10.2 缓存

同一张图片没有变化时，不需要重复执行莫奈提取。

通过图片 Hash 和算法版本判断是否需要重新计算。

## 10.3 异常回退

出现以下情况时：

- 图片读取失败。
- 莫奈提取失败。
- 返回无效颜色。
- 颜色转换异常。
- 色域映射异常。

使用最后一次有效主题。

若没有历史主题，则回退到靛蓝 Indigo。

不允许出现纯黑背景、透明背景或空白闪烁。

---

# 11. 验收标准 Acceptance Criteria

## 11.1 预设主题验收

- [ ] 六套预设主题均能正常切换。
- [ ] 六套主题均拥有独立 Canvas。
- [ ] 六套主题的 Surface 保持一致的语义定位。
- [ ] 六套主题的 Primary 满足交互对比度要求。
- [ ] 导航栏、卡片、弹窗均同步变化。
- [ ] 页面不存在硬编码旧主题色的遗漏。

## 11.2 莫奈动态主题验收

- [ ] 蓝色卡片能够生成浅蓝灰色背景。
- [ ] 绿色卡片能够生成浅绿色背景。
- [ ] 紫色卡片能够生成浅紫灰色背景。
- [ ] 红色、粉色卡片不会导致页面明显泛粉。
- [ ] 黄色、金色卡片不会导致页面明显泛黄。
- [ ] 高饱和度图片不会造成大面积高饱和背景。
- [ ] 低彩度图片能够正常回退或生成中性画布。
- [ ] 不同色相的卡片能够产生可辨别但克制的背景变化。

## 11.3 Light  Dark Mode 验收

- [ ] 两种模式拥有独立的颜色生成规则。
- [ ] Dark Mode 不使用纯黑色大面积背景。
- [ ] 暗色模式保留当前主题的色相特征。
- [ ] 文字、图标、按钮对比度符合要求。
- [ ] 系统状态栏同步更新。
- [ ] 页面切换模式时不出现白屏或闪烁。

## 11.4 视觉验收

重点检查：

1. 首页视觉重心是否仍然明确。
2. 白色卡片与带色相 Canvas 是否有足够的层次。
3. Bottom Navigation 是否依然具有悬浮感。
4. 内容卡片是否没有被背景染色干扰。
5. 主题变化是否自然且不过度明显。

所有普通文本应达到 WCAG AA 的 4.51 对比度要求；大号文字至少达到 31。交互组件边界及图标也应满足相应的非文本对比度要求。

---

# 12. 开发实施顺序

建议按照以下顺序实施，避免同时修改过多模块。

### Phase 1：建立六套预设主题

1. 实现六套主题 Token。
2. 实现统一的 ThemeData 工厂。
3. 将现有页面中的硬编码颜色逐步迁移。
4. 验证所有页面的主题一致性。

完成标准： 用户切换六套主题，所有页面都能够正确响应。

### Phase 2：实现 Monet Adaptive Canvas

1. 建立 OKLCH 转换工具。
2. 实现 Seed 归一化。
3. 实现 Canvas、Surface Container、Outline 的动态生成。
4. 实现 Primary 可读性调整。
5. 实现 sRGB 色域映射。
6. 建立动态主题生成器。

完成标准： 任意有效主题色均能生成一套完整的表面颜色。

### Phase 3：接入莫奈取色流程

1. 接入当前卡片的有效 Seed。
2. 建立主题来源状态管理。
3. 接入图片更新后的主题刷新。
4. 完成缓存与异常回退。
5. 避免裁切过程中的频繁主题刷新。

完成标准： 用户更换自定义卡面后，主题可以自动更新。

### Phase 4：暗色模式与动画

1. 建立 Dark Mode 色彩生成规则。
2. 接入 AnimatedTheme。
3. 同步系统状态栏。
4. 完成深浅主题的切换验证。

完成标准： 两种模式下均能保持完整的主题一致性。

### Phase 5：视觉验收与优化

使用以下测试卡面进行验证：

- 浅蓝色卡面。
- 高饱和深蓝卡面。
- 绿色卡面。
- 藤紫色卡面。
- 粉红色卡面。
- 金黄色卡面。
- 黑白灰卡面。

检查背景生成效果、按钮对比度、卡片层级、页面整体氛围和性能表现。

---

# 13. 最终设计约束

以下原则作为整个颜色系统的长期约束：

1. Canvas 可以随主题变化，但 Surface 不应随意变化。
2. 莫奈取色决定色相倾向，不直接决定背景彩度。
3. Primary 负责交互，不允许背景色代替交互色。
4. 语义色独立于主题色，保证状态含义始终稳定。
5. Light  Dark Mode 必须独立生成，而不是简单反转。
6. 所有页面使用统一 Token，禁止局部私自定义主题颜色。
7. 主题更新应当平滑，不允许干扰用户当前操作。

---

# 14. 最终设计结论

TraFArch 2.x 的颜色系统从传统的固定页面背景，升级为基于主题种子色的动态表面系统。

六套预设主题提供稳定、可预测的视觉体验。

Monet Adaptive Canvas 则为用户的自定义卡面提供更进一步的个性化表达。

无论用户选择哪种主题，应用都应当维持一致的信息层级、组件结构和交互语言。

最终希望达成的效果是：

每一张卡片都能带来属于自己的色彩氛围，但用户始终能够感受到这是同一个 TraFArch。
