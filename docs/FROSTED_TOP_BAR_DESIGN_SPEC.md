# 磨砂顶栏设计规范（可迁移）

本文定义一种可复用的移动端磨砂顶栏：主题色半透明底、局部背景模糊、清楚且唯一的边界，以及与固定控件一致的整体几何。它既记录 Review 的实际 Flutter 实现，也给其他应用提供可照着实现和验收的规范。跨框架移植时沿用分层和布局规则，不要把 Flutter 代码逐字移植成另一套组件。

## 1. 设计目标

- 顶栏有明确的主题色底，不是无底色的全透明层。
- 模糊只作用于顶栏区域，滚动内容经过顶栏时可见柔和的背景细节。
- 顶栏区域包含所有固定在滚动内容上方的控件，不只包含标题和返回按钮。
- 顶栏结束边界对齐最后一行固定控件的下沿；可滚动内容从边界下开始，或在明确采用覆盖模式时从顶栏后方滚动。
- 一个交界处只保留一种边界表达，避免相邻控件底线、AppBar 底线和 body Divider 重叠成双线。
- 返回、标题、搜索、分类选择、焦点、键盘、辅助功能和滚动逻辑保持独立且可用；磨砂只改变材质，不应悄悄改变交互。

## 2. 视觉分层与材质参数

从屏幕上到下按以下职责组织：

1. **系统状态栏安全区**：由主顶栏组件负责覆盖和处理。`primary: true` 的 Flutter `AppBar` 会计入顶部安全区。页面不要再给同一顶栏或 body 重复添加 `MediaQuery.padding.top`。
2. **顶栏 Material 底色与纵向渐变**：从主题 `AppBarTheme.backgroundColor` 取色；未设置时回退 `Scaffold` 背景色。AppBar Material 使用 alpha 0.45；其上再覆盖一层从顶部 alpha 0.95 渐变到边界 alpha 0 的同色层，因此顶部合成后的主题色为 `1 - (1 - 0.95) × (1 - 0.45) = 0.9725`，即约 97.25% 不透明；状态栏附近基本不透，越接近底部分界越透，边界处保留 Material 自身 0.45 的底色。颜色必须直接设在 `AppBar.backgroundColor`，并保持 `forceMaterialTransparency: false`。
3. **局部磨砂层**：参考 ReviewX 当前源码的绘制顺序，在顶栏内直接使用 `ClipRect → BackdropFilter(ImageFilter.blur(sigmaX: 20, sigmaY: 20)) → 渐变 DecoratedBox`。不在 `BackdropFilter` 外再套 `ShaderMask` 或独立模糊 alpha 遮罩；颜色渐变本身让状态栏侧的模糊几乎不可见、靠近边界时逐渐显现。滤镜只覆盖顶栏，不叠多层滤镜，标题与操作控件不作为滤镜遮罩内容。
4. **工具栏与固定内容**：标题栏下方若有搜索框、分类标签、筛选条或其他固定控件，这些控件属于同一顶栏视觉区，必须计入其高度和模糊覆盖范围。
5. **唯一的底部边界**：可以用一条非常轻的 0.5dp 主题轮廓线，也可以只用顶栏材质与页面底色的交界表达。二者选择其一；如果附近已经有一条线，就关闭重复的那条。不要在标签行和整个顶栏下沿各画一条相邻的线。
6. **可滚动内容**：边界之后开始，或按照本节模式 B 的覆盖模式从顶栏后方滚动。不要同时把固定控件放进顶栏和 body。

Review 的共享参数基准如下。迁移到其他应用时可从这些值开始，最后仍需按真实主题色、对比度和设备画面验收：

| 参数 | Review 基准 | 用途 |
| --- | --- | --- |
| 底色来源 | AppBar 主题色；缺省回退 Scaffold 背景色 | 让明暗主题和自定义主题一致 |
| AppBar Material 底色 alpha | 0.45 | 作为全高基础底色；边界处保留 45% 主题色 |
| 顶部渐变叠加 alpha | 顶部 0.95 → 边界 0 | 顶端合成 0.9725（约 97.25% 不透明）；向下逐渐提高透光度 |
| 背景模糊 | sigma X/Y = 20 | 形成局部磨砂质感 |
| 模糊 alpha 遮罩 | 状态栏侧 0 → 边界 0.60 | 上端基本不模糊，靠近分界线平滑增强；独立于颜色渐变 |
| 模糊裁剪 | `ClipRect` 包围模糊层 | 防止滤镜影响顶栏以外区域 |
| surface tint | 透明 | 避免 Material elevation tint 改变主题色 |
| elevation / scrolled-under elevation | 0 / 0 | 避免滚动时多出另一道阴影边 |
| 可选底部分隔线 | 0.5dp，`outlineVariant` alpha 0.24 | 只有在没有第二条相邻边界时启用 |

关键合成规则：半透明主题底色在 `AppBar` 自身的 Material 上；顶部同色叠加层 alpha 0.95 与 Material alpha 0.45 合成后为 0.9725（约 97.25% 不透明），边界叠加层 alpha 0 时仅保留 Material 的 0.45。绘制顺序复用 ReviewX 的简单实现：`ClipRect` 裁切后直接绘制 `BackdropFilter`，再由其 child 绘制 flexibleSpace 内容和主题色渐变；不加 `ShaderMask`、不指定非默认混合模式。此前给滤镜套纵向 `ShaderMask`、再改 `BlendMode.src` 的尝试并未在用户设备上恢复可见模糊，不能把 widget 树中“存在 BackdropFilter”或 alpha 计算通过当作视觉成功。只在 `flexibleSpace` 里画颜色、同时让 AppBar Material 透明，可能因合成顺序、页面背景或设备差异再次看起来像全透明；`BackdropFilter` 单独存在也不会自动提供主题底色。Review 统一用 `ReviewFrostedBackdrop` 和 `reviewFrostedMaterialAlpha`，标准 AppBar、时间线/热搜自定义栏和超话详情 SliverAppBar 共用同一材质与渐变。

## 3. 几何规则：先定边界，再选布局

不要把“顶栏”默认等同于标题行。先检查页面的完整纵向结构，并标出最后一个固定在滚动区域上方的控件。这个控件的下沿才是视觉边界：

```text
状态栏安全区
标题/返回/操作栏
固定搜索框（如果有）
固定分类或筛选标签（如果有）
标签下方的材质缓冲区（需要时）
                               ← 顶栏底边
可滚动列表/网格
```

### 模式 A：固定控件属于顶栏，body 从顶栏之后开始（默认）

适用于固定搜索栏、固定分类筛选等页面，前提是滚动内容不需要从顶栏后方经过。将额外固定控件作为 `AppBar.bottom`，用 `PreferredSize` 声明真实高度。Scaffold 默认会把 body 放在整个 AppBar（标题栏 + bottom 控件）之后；此时不要再给 body 重复添加状态栏、工具栏或固定标签栏高度。超话中心使用模式 B，因为它需要时间线式的滚动磨砂效果。

额外固定区高度按所有子项的实际布局计算：

```text
bottomHeight = 顶部 padding + 搜索框高度 + 中间间距
             + 分类行高度 + 底部 padding
```

Review 超话中心当前使用 `4 + 48 + 10 + 38 + 8 = 108dp`：搜索框上下留白 4/10dp，搜索框约 48dp，分类横滑行 38dp，标签下方额外保留 8dp 磨砂材质缓冲区，避免边界贴着标签像被切断。若调整文字缩放、前缀图标、输入框约束、标签行高或缓冲区，必须一并更新并重新实测 `PreferredSize`，防止内容被裁剪或边界错位。

结构示意：

```dart
final fixedHeader = PreferredSize(
  preferredSize: const Size.fromHeight(108),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
        child: searchField,
      ),
      SizedBox(height: 38, child: horizontalCategoryList),
      const SizedBox(height: 8), // 标签与材质边缘之间留缓冲
    ],
  ),
);

Scaffold(
  appBar: ReviewFrostedAppBar(
    title: const Text('页面标题'),
    bottom: fixedHeader,
    // 该页用材质交界表达整体边缘，不再叠一条标签下方细线。
    showBottomBorder: false,
  ),
  // body 默认从完整顶栏之后布局；只留内容本身需要的间距。
  body: resultsList,
);
```

`ReviewFrostedAppBar` 的 `flexibleSpace` 覆盖 AppBar 总高度；因此当固定控件放进 `bottom` 后，模糊/底色/可选边界自然延伸至这些控件的下沿。`preferredSize` 必须包含 `bottom.preferredSize.height`，不能只按标题行申报高度。

### 模式 B：内容需要从磨砂层后方经过

若设计目标是列表滚动时持续穿过顶栏并被其模糊，使用 `extendBodyBehindAppBar: true` 或等价的覆盖布局。滚动视口本身必须从屏幕顶部开始、绘制在整个 AppBar 后方；把首项 inset 放在**滚动视口内部**，补齐整个顶栏可视高度（系统顶部安全区、工具栏和所有固定 bottom 控件），并只计算一次。不要用外层 `Padding`、`Column` spacer 或把列表放在 `Expanded` 的较低位置来推开滚动视口：它们会让视口从顶栏下方才开始，滚动内容无法经过顶栏，磨砂看起来就像只从固定标签下边缘开始。固定搜索/分类控件仍由 AppBar 最上层承载并保持固定；其下的列表首项按内容间距从顶栏边界之后开始，滚动时可从整个顶栏后方经过。

**Review 超话中心使用模式 B。** 它开启 `extendBodyBehindAppBar`，全屏 `Stack` 中的纵向列表占满屏幕视口；列表自身的顶部 padding 为“状态栏安全区 + 56dp 工具栏 + 108dp 固定搜索/分类区 + 4dp 列表间距”。108dp 固定区含标签下方的 8dp 磨砂缓冲区；缓冲区加列表间距仍为原来的 12dp，因此首条结果的屏幕位置不变。向上滚动时列表可在标题栏和固定标签后方移动，并由同一块完整高度的 `BackdropFilter` 模糊。加载/空状态仍从同一固定头部下方开始布局。

覆盖式页面的关键结构（`headerInset` 在返回 `Scaffold` 前、用页面自身的 context 计算）：

```dart
const fixedHeaderHeight = 108.0;
final headerInset = MediaQuery.paddingOf(context).top
    + kToolbarHeight + fixedHeaderHeight;

Scaffold(
  extendBodyBehindAppBar: true,
  appBar: ReviewFrostedAppBar(bottom: fixedHeader),
  body: Stack(
    children: [
      Positioned.fill(
        child: ListView(
          // viewport remains at y=0; only its initial content is inset.
          padding: EdgeInsets.only(top: headerInset + 12),
          children: content,
        ),
      ),
    ],
  ),
);
```

Flutter 会为 `extendBodyBehindAppBar` 下的 body 调整 `MediaQuery.padding.top`，表示 AppBar 已占据的完整高度。因此要在外层页面 context 先算好 inset 并传入滚动内容，不要在扩展后的 body 子树再次读取并累加，否则会把首项重复下移。

不要把 `SafeArea`、`MediaQuery.padding.top`、toolbar 高度、`PreferredSize` bottom 高度和列表首项 padding 随意叠加。用布局测量或单一共享高度来源推导总高度，并用 widget/设备画面确认第一项起点。若输入框弹出键盘、吸顶 Sliver 或播放器固定区会改变几何，先判断该页面是否适合模式 B；不适合时用模式 A，保留稳定布局。要注意：模式 A 虽能固定头部几何，但 body 不在 AppBar 后方，BackdropFilter 没有滚动内容可模糊；页面要求时间线式的真实磨砂时，必须使用模式 B。

## 4. Flutter 参考实现

Review 的实现位于 `lib/core/design_system/components/review_frosted_app_bar.dart`。核心实现如下；它刻意把底色放在真实 AppBar Material，而不是只装饰 `flexibleSpace`：

```dart
final theme = Theme.of(context);
final baseColor = theme.appBarTheme.backgroundColor ??
    theme.scaffoldBackgroundColor;

AppBar(
  bottom: bottom,
  backgroundColor: baseColor.withValues(alpha: reviewFrostedMaterialAlpha), // 0.45
  forceMaterialTransparency: false,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  scrolledUnderElevation: 0,
  flexibleSpace: ReviewFrostedBackdrop(
    color: baseColor,
    borderColor: theme.colorScheme.outlineVariant,
    showBottomBorder: showBottomBorder,
    child: flexibleSpace,
  ),
)
```

`ReviewFrostedBackdrop` 的顺序是 `ClipRect → BackdropFilter(sigma 20, 默认 srcOver) → Stack(原 flexibleSpace、纵向渐变 DecoratedBox)`。不在滤镜外使用 `ShaderMask` 或独立模糊遮罩；由顶部 alpha 0.95 到边界 alpha 0 的主题色层来形成“顶部近乎不透光、底部模糊清晰”的观感。叠加 Material alpha 0.45 后，顶部颜色合成约 0.9725 不透明；边界处保留 Material 的 0.45，边缘线只画在最下沿。固定控件仍在渐变层上方清晰绘制。两个色层都静态绘制，不逐帧捕获截图，不引入额外依赖。

Review 的 `showBottomBorder` 默认是 `true`，保证现有页面不变；像超话中心这种整体材质边缘已经足够、相邻细线显得重复的页面显式设为 `false`。不要为了去掉某一页的细线而全局删掉所有页面的边界，也不要通过透明 AppBar 来“隐藏”这条线。

## 5. 常见失败及根因

| 现象 | 常见根因 | 正确处理 |
| --- | --- | --- |
| 顶栏看起来一大片透明 | 只在 `flexibleSpace` 画颜色；AppBar Material 透明或被 `forceMaterialTransparency` 覆盖 | 将主题色 alpha 直接设到 AppBar Material，并保留局部模糊 |
| 只有标题行有磨砂，标签/搜索区像裸背景 | 固定控件仍放在 body，磨砂范围/边界只覆盖标准 toolbar | 将固定控件并入 `AppBar.bottom`，或纳入同一个 pinned/overlay header |
| 顶栏边缘错位、第一条内容被压住/留白过大 | `PreferredSize` 少算固定区，或状态栏/toolbar inset 重复计算 | 按实际固定控件高度计算一次；确认 body 的起点和 overlay 模式匹配 |
| 磨砂视觉像从固定标签下方才开始，标题栏/标签后没有滚动模糊 | body 未延伸到 AppBar 后方，或滚动视口被外层 Column/Padding 下移 | 开启 `extendBodyBehindAppBar`；滚动视口铺满整个 body，完整顶栏高度只作为 ScrollView 内部首项 padding |
| 标签下方出现两条线 | 同时启用了标签/子组件边框、共享 AppBar hairline、body `Divider` 或额外容器边框 | 沿绘制树找出每条线，只保留一个边界源；需要时仅该页面关闭 `showBottomBorder` |
| 滚动后颜色突然变深/多出阴影 | `scrolledUnderElevation`、surface tint 或另一个父层叠加了底色 | 统一设置 surface tint 透明和 elevation；保留 Material 0.45 + 单一顶到底边的同色渐变 |
| 模糊完全不可见 | 在 `BackdropFilter` 外套了 `ShaderMask` 或改了 blendMode，改变了有效合成链 | 采用 `ClipRect → BackdropFilter → 渐变 DecoratedBox`；不要用 ShaderMask 包裹滤镜 |
| 背景滚动时看不到模糊内容 | body 没有延伸到顶栏后方，滤镜采样区域只有 Scaffold 底色 | 对适合覆盖布局的页面检查 `extendBodyBehindAppBar` 和滚动内容 inset；不要靠加大 sigma 掩盖几何问题 |
| 顶栏边缘被滤镜拖出、整页模糊 | `BackdropFilter` 没有局部 `ClipRect`，或裁剪范围错误 | 把 ClipRect 精确包围顶栏视觉区，包含固定 bottom 控件但不含列表 |

## 6. 覆盖式顶栏与下拉刷新

`extendBodyBehindAppBar: true` 下，Flutter 会调整 body 子树的 `MediaQuery.padding.top`，其中可能包含整块 AppBar 高度，而不只是系统状态栏。`EasyRefresh` 默认 `safeArea: true` 会把该 inset 再加到触发阈值：`actualTriggerOffset = triggerOffset + safeOffset`。这会让用户感觉要把列表拉得特别深才刷新。

Review 的全局默认 ClassicHeader 保持原样，非覆盖式页面不受影响。内容视口确实从磨砂顶栏后方开始的页面使用 `reviewFrostedAppBarRefreshHeader`：`safeArea: false`、触发距离保持 70dp；仅把指示器视觉位置下移完整 `MediaQuery.padding.top`，让提示出现在顶栏下方。不要把 `triggerOffset` 设为 0 来抵消 inset：ClassicHeader 的图标/文案布局高度也依赖该值，会让指示器变形或不可见。非覆盖式、嵌入式、聊天/网页/视频等有自己滚动或固定头部约束的页面不要套用此 header。

回归测试应同时验证：存在安全 inset 时仍由 70dp 阈值触发；正常手势确实调用刷新回调；指示器视觉位置与完整顶栏错开；全局非覆盖页面默认 header 未变。Widget 测试只能确认布局参数和手势回调，最终触发手感与遮挡仍需目标设备验收。

## 7. 实施与回归验收清单

每个新页面按这个顺序做，不要先给标题栏随手加一个 Blur：

1. **画结构**：标出状态栏、标准 toolbar、固定搜索/分类/筛选控件、可滚动 body，以及预期边界。
2. **确定唯一所有者**：固定控件只由 AppBar bottom / pinned header / overlay header 中的一处构建；body 不复制它们。
3. **选择布局模式**：普通固定头部用模式 A；只有确实需要滚动内容从背景后经过时才用模式 B。
4. **计算总高度**：包含全部固定控件、padding 和间距；顶部系统安全区由 primary AppBar 或一个明确的替代实现处理，不能重复加。
5. **接入材质**：主题色设在 Material（alpha 0.45），同色渐变从顶部 alpha 0.95 到底边 alpha 0（顶部合成约 0.9725 不透明）；将 sigma 20 `BackdropFilter` 直接放进 `ClipRect`，其 child 再绘制渐变；不加 ShaderMask/独立 blur alpha mask，关闭额外 surface tint/阴影；边界只选一种。
6. **验证真实树和几何**：测试 AppBar 实际 Material 颜色、`forceMaterialTransparency == false`、模糊裁剪及遮罩端点/方向、固定控件确实在 header 子树内、列表在预期边界外/后方、没有重复 Divider。
7. **检查状态组合**：至少覆盖浅色、深色和纯黑主题，初始/滚动状态，带键盘的搜索输入，较大字体，以及横向分类滚动。编译通过不等同于设备视觉验收。

Review 中的回归测试是 `test/review_frosted_app_bar_test.dart`、`test/chaohua_center_page_test.dart` 与 `test/review_refresh_header_test.dart`。前者验证 Material 底色、颜色渐变端点、滤镜直接位于 ClipRect 内且没有 ShaderMask 包裹，以及可独立关闭 hairline；超话测试验证固定搜索/分类行、8dp 材质缓冲、完整视口与首项 inset；刷新测试验证覆盖式顶栏下 70dp 阈值不会重复叠加安全 inset。widget 结构测试不能证明设备上出现了模糊，仍需真机滑动内容经过顶栏复验。新页面还应按自己的固定行数和动态高度补充结构/几何断言。

## 8. 迁移到其他应用

迁移时需要映射目标应用的主题底色、系统状态栏 inset、toolbar 高度、固定标签区和滚动容器；保留“Material 底色 + 局部模糊 + 固定内容边界 + 单一分隔方式”这四个约束。不要只复制 `sigma=20`，也不要把 Review 的具体头部高度硬套到其他页面：应按新应用中搜索框、标签行、边缘缓冲区、字体缩放和系统安全区重新计算并测试。

本规范依赖的实现原理和像素值是视觉基线，而非对所有屏幕/设计系统的强制常数。只在真机截图发现对比度或模糊观感确有问题时再调整，并同步更新组件、测试和这份规范；不接受只写“增加磨砂效果”而不说明实际颜色层、模糊裁剪、固定内容高度与边界归属的实现说明。
