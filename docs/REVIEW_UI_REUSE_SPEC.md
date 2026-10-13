# Review M3 UI 复用规范与提示词

> 提炼日期：2026-10-13。基线为本地 `D:\App\Review` 当前工作区源码，`pubspec.yaml` 为 `3.2.0+171`，HEAD 为 `25a02ef52b1f15f4124a20d0473b7cccde871788`；工作区存在未提交修改，版本号或 HEAD 不能唯一标识这份源码。本文是源码提炼，未核对当前手机上的配置、截图或根目录 APK 与源码是否完全一致。

## 1. 复用目标与常见偏差

Review 当前采用 Flutter Material 3，并在主题之上增加局部磨砂顶栏、两种底栏、设置分组、内容卡片、字体权重和转场规则。当前源码不再提供 Miuix/液态玻璃设计语言切换，历史记录中的这些实现不属于本规范。

“使用 M3”“参考 Review”“照搬主题”都不足以固定外观。主题只是一层默认值；组件和页面可以覆盖它。例如 `CardTheme` 默认 elevation 为 0，`ReviewCard` 默认传入 1，`TweetCard` 又按布局显式覆盖。迁移时要追到最终调用处，而不是把任一默认值推广到所有页面。

要复现的是可对应页面的视觉与交互：原封迁移 UI 实现，替换业务数据与回调。不同业务的信息结构不可能天然逐像素相同；没有对应页面时，应组合已有组件，并列出新增布局，不能声称已经“一模一样”。

## 2. 必须一起阅读的源码

以下路径均相对 `D:\App\Review`，不是要求把整套微博业务复制到新应用。

| 层次 | 源码入口 | 迁移责任 |
|---|---|---|
| 应用入口 | `lib/main.dart` | 明暗主题接线、DynamicColorBuilder、中文 locale、DefaultTextStyle |
| 主题与状态 | `lib/core/theme/app_theme.dart`、`theme_provider.dart`、`weibo_style_provider.dart` | 配色、字体、组件主题、路由动效；核对 `lib/core/storage/storage_service.dart` 中的实际默认值 |
| 页面壳与磨砂 | `lib/core/design_system/components/review_page_scaffold.dart`、`review_frosted_app_bar.dart` | 安全区、内容 inset、Material 色层、局部滤镜 |
| 导航与主框架 | `lib/core/design_system/components/review_navigation_bar.dart`、`lib/features/home/presentation/main_scaffold.dart` | 悬浮/贴底分支、页面保活、Tab 转场、重复点击行为 |
| 设置组件 | `lib/core/widgets/app_section_card.dart`、`lib/core/design_system/components/review_preference_tile.dart`、`review_switch_tile.dart`、`review_choice_tile.dart` | 设置分组、导航行、开关行、单选行；不能用一个普通 ListTile 替换全部 |
| 设置布局 | `lib/features/settings/presentation/settings_view.dart`、`lib/features/profile/presentation/theme_settings_page.dart` | 首页无独立标题栏、分组间距、分割线和实际组件覆盖；首页私有 `_SettingsSectionCard` 与 AppSectionCard 同材质 |
| 内容布局 | `lib/core/design_system/components/review_card.dart`、`lib/features/feed/presentation/widgets/tweet_card.dart` | 内容卡片的最终 margin、shape、elevation、正文和媒体间距；只提取目标业务需要的表现部分 |
| 反馈与触感 | `lib/core/utils/app_dialog.dart`、`app_toast.dart`、`haptic_feedback_util.dart` | 弹窗/Toast 的实际表现与时序、触感开关及去重；不要只迁移外壳 |
| 媒体（按需） | `lib/core/widgets/app_avatar.dart`、`lib/features/detail/presentation/widgets/image_gallery_page.dart` | 迁移前核对实际调用；头像、媒体缓存、Hero/缩放路径不能用普通路由替换 |

若源路径不存在，先搜索真实实现并修正文档/迁移清单，不能凭类名重新设计。跨框架移植以参数、分层、几何和交互为约束，不能把 Flutter Widget 机械翻译成另一框架的默认组件。

## 3. 当前视觉参数

以下值来自代码，是 Review 的实现值，不是泛指所有 M3 应用必须遵守的官方尺寸。dp 对应 Flutter 逻辑像素，文字仍受系统字体缩放影响。

### 3.1 配色与字体

- `useMaterial3: true`；默认种子色 `#FA2F3A`，通过 `ColorScheme.fromSeed` 生成语义配色，不能把种子色直接涂在所有选中项上。另有橙、蓝、绿、紫、粉、青碧、黑灰预设。
- 默认跟随系统明暗、动态取色关闭、纯黑关闭、悬浮底栏开启；实际安装状态可能已被用户修改。动态取色开启时由设备提供色板。
- 浅色页面底为 `scheme.surface`；深色页面底 `#111215`、普通卡片 `#1B1C20`、贴底导航底 `#16171B`。纯黑页面/顶栏/贴底栏为黑，普通卡片 `#121212`。不能只设置 `Brightness.dark` 代替深色实现。
- 字体基于 `Typography.material2021(platform: TargetPlatform.android)`，没有另设统一 fontFamily；主题文字 letterSpacing 为 0。标题 large 加粗、medium/small 为 w600；系统字重与自定义字重通过 `adjustFontWeight` / `context.adjustWeight` 处理，不能到处写死 bold。
- 标准顶栏标题左对齐，18sp、加粗。普通 `ListTileTheme` 标题 15sp / 行高 1.35、副标题 12.5sp / 1.4；但 `ReviewPreferenceTile` 显式使用 `textTheme.titleMedium/bodyMedium`，开关/单选行又覆盖为 16sp/14sp。不能全局强制所有设置文字为 15sp 或 17sp。

### 3.2 磨砂顶栏与页面几何

- 底色取 AppBar 主题色，缺省回退 Scaffold 背景色；真实 AppBar Material 使用 alpha **0.45**，`forceMaterialTransparency: false`。
- 局部绘制顺序为 `ClipRect → BackdropFilter(sigmaX/Y: 20) → Stack(原 flexibleSpace + 同色纵向渐变)`；渐变顶部 alpha **0.95**、底部 **0**，顶部合成不透明度约 **0.9725**。
- 标准 `ReviewFrostedAppBar` 显式覆盖 elevation / scrolledUnderElevation 为 0、surfaceTint 透明。不要把全局 AppBarTheme 的 scrolledUnderElevation 1.5 当成标准磨砂栏的最终值。
- 底部可选单条 0.5dp、outlineVariant alpha 0.24 边界；不能和邻近标签分割线重复。固定搜索/分类也属于顶栏材质范围。
- 可覆盖滚动的页面使用 `extendBodyBehindAppBar`，滚动视口延伸到顶栏后方；首项在列表内部补回状态栏与 toolbar inset，不能用外层 Padding 把整个视口推到顶栏下面。`ReviewPageScaffold` 提供的 top inset 是安全区 + `kToolbarHeight`。
- 键盘表单、网页、播放器、复杂 pinned 布局按原页面约束处理，不能批量强开覆盖式布局。覆盖式 EasyRefresh 保持 70dp 触发阈值，只下移指示器，不能重复叠加安全 inset。
- 不使用 ShaderMask、独立 blur alpha mask、BlendMode.src 或全屏模糊/截图 shader。完整原理及例外见 `FROSTED_TOP_BAR_DESIGN_SPEC.md`。

### 3.3 底栏：两套实现必须区分

| 项目 | 默认悬浮底栏 | 贴底 NavigationBar |
|---|---|---|
| 几何 | 264×64，外圆角 32，内部 padding 4；三个入口均分 | 高 68，系统底部安全区另由组件处理 |
| 放置 | SafeArea 内，bottom padding 有系统底 inset 时 6，否则 14 | 页面底部，全宽 |
| 背景 | surfaceContainerHigh；阴影黑色 alpha 浅色 0.12 / 深色 0.35，blur 16，offset (0,4) | 浅色 surfaceContainer；深色/纯黑见配色段；无 elevation/tint |
| 选中 | secondaryContainer / onSecondaryContainer，选中块圆角 28，160ms easeOutCubic 淡入 | primaryContainer 指示胶囊，图标 onPrimaryContainer、标签 primary |
| 图文 | 图标 22，图文间隔 2，文字 11.5sp，选中 w600 / 未选 w400 | 标签一直显示，12sp，选中 bold / 未选 w500 |
| 未选色 | onSurfaceVariant | onSurfaceVariant |

主 Scaffold 仅在悬浮分支 `extendBody: true`。三个入口图标采用 outlined/rounded 状态切换。三个入口的 264dp 胶囊不能直接塞进五个入口后仍宣称原样复用；入口数或文案长度改变时列为明确适配。

### 3.4 设置、信息流和弹层

- 设置分组：圆角 **24**，margin **0**，elevation **0**，无描边、无阴影、无 tint；通常 surfaceContainerLow，纯黑改 surfaceContainer。外层已加左右 **16**，不能再加 CardTheme 默认 margin。
- 设置首页：没有仅标题的独立 AppBar，列表 top 为安全区 + **20**；分组标题与卡片间 **12**，大分组间 **32**；悬浮底栏时 bottom padding **72**，贴底时 **16**。
- 个性化子页：ReviewPageScaffold 返回顶栏，列表 horizontal **16** / vertical **12** 再加 contentInsets；多个分组卡片间通常 **16**。首页分组间距不能直接套到子页。
- ReviewPreferenceTile：左右 padding **16**，leading 最小宽 **24**、title gap **16**、minVerticalPadding **8**；默认右箭头 **24**。有 leading 的首页分割线卡片内 indent **56**，对应屏幕文字起点 72；不能误用 72 作为卡片内 indent。其他单选行的 divider 按真实布局保留，不能全局改成 56。
- 通用 CardTheme：圆角 **22**、margin 横 **10** / 纵 **5**、0.8dp 轻描边、elevation **0**。它不是设置分组卡片的规范。
- 信息流默认 `card_rounded`：圆角 **22**、margin 横 **8** / 纵 **4**、elevation **1**、shape 无描边、内 padding **(14,14,14,10)**；正文默认 **16sp / 行高 1.3**。`floating_rounded` 等选项、详情零 margin/零 elevation 分支不能丢失。不能把所有卡片统一改成设置分组样式。
- Dialog 圆角 **28**，主题标题 **18sp** / 正文 **14sp**；`showAppDialog` 原地 **60ms** 淡入，没有上下平移或缩放。BottomSheet 顶圆角 **28**，surfaceContainerLow，纯黑 **#141414**，拖动条 **38×4.5**。FAB 圆角 **20**、elevation **1.5** / highlight **3**。SearchBar 为 StadiumBorder、elevation 0、surfaceContainerHigh，纯黑 **#1C1C1E**。
- 个别弹窗/搜索框有页面级覆盖，需读对应调用。Toast 复用 AppToast 顶层 Overlay 的原地反馈方式，不能自行换成随路由滑动的提示条。

### 3.5 动效与交互

- 主 Tab：页面保持挂载，当前页与目标页按入口顺序反向同步平移一个屏宽，**260ms easeOutCubic**；RTL 反转。Offstage、TickerMode、IgnorePointer 共同控制非活动页面。保留快速切换和重复点击语义，不能只换成会重建页面的 AnimatedSwitcher。
- 普通路由：新页全宽滑入覆盖静止旧页，push **320ms easeOutCubic** / pop **220ms easeInCubic**；LTR 从右、RTL 从左；无旧页位移和额外淡入。Android 接预测式返回，iOS 保留 Cupertino 路由/边缘返回。主 Tab 与路由是两套动效。
- 普通路由和 Tab 已处理 `disableAnimations`；迁移后仍需检查局部动画，不能推断所有动画均已覆盖系统减少动画偏好。
- 画廊显式 PageRouteBuilder / Hero 独立保留；显隐控件不能修改全屏 PageView 约束。不要用全局路由主题替换图库动画。
- 触感复用 HapticSplashFactory / HapticFeedbackUtil 的开关、冷却及去重；按最终调用链核对，不能额外重复震动。

## 4. 可直接复制给 Codex 的提示词

先替换尖括号中的应用名和路径。全文提供给目标项目，或让 Codex 读取本文件；短口号不能替代源码访问。

```text
请开发/修改 <目标应用名> 的 UI。目标是复现 Review 指定基线的视觉与交互，不进行重新设计。
参考项目：D:\App\Review
目标项目：<目标项目绝对路径>
UI 规范：D:\App\Review\docs\REVIEW_UI_REUSE_SPEC.md
完整开发文档：D:\App\开发文档\Review.md

1. 先读目标项目的 AGENTS.md/开发文档，再读 Review UI 规范、当前开发说明与工程复盘中的 UI 防回归记录。以指定基线的实际源码及最终调用参数为准；历史 Miuix、液态玻璃、旧 ShaderMask 顶栏方案不能作为当前实现。
2. 开工前固定参考快照：记录 Review HEAD、工作区改动、Flutter SDK/锁文件，以及需迁移 UI 文件的快照或哈希。不要只用版本号标识参考。读取本地工作区，不能自动改用远程 main 或升级后的默认 M3。
3. 先列“目标页面 → Review 对应页面 → 共享组件 → 允许替换的业务内容”映射。按规范第 2 节读取主题、入口接线、页面壳、导航、设置卡片和行、对应业务页、反馈/触感。追踪调用处覆盖，不能只复制 ThemeData。
4. 同为 Flutter 时，直接迁移需要的 UI 实现和必要依赖，保持组件树、最终颜色角色、padding/margin、圆角、字体/行高、图标状态、阴影、分割线、系统栏、键盘避让和动效参数。允许改 import、类名、业务模型、文案、资源和回调；不能凭审美替换控件、合并不同卡片样式、重新排版或加入“更现代”的设计。按依赖边界接入目标业务，不搬入微博认证、接口、凭据和无关功能。
5. 分别复用默认 264×64 悬浮底栏和 68dp 贴底底栏；设置分组 24dp 无边框无阴影；默认信息流卡片 22dp、8/4 margin、elevation 1；磨砂顶栏 Material alpha 0.45 + 顶部 0.95→底部 0 渐变 + 裁剪内 sigma 20。其他细节全部按规范和最终源码，不推广成全局统一值。
6. 主 Tab 保活及双页 260ms 平移、普通路由 320/220ms 覆盖式转场、图库 Hero、弹窗 60ms 原地淡入分别接入。保留返回手势、RTL、系统减少动画、触感开关和防重复反馈。局部滤镜保持裁剪，列表缓存和分页不因 UI 迁移退化。
7. 固定验收环境：相同设备/模拟器、屏幕逻辑尺寸和 DPR、系统字体及缩放/字重、locale、系统导航方式、主题种子色/动态取色、明暗/纯黑、悬浮底栏开关、卡片样式、内容数据和滚动位置。先用动态取色关闭、经典红、默认字重、默认 card_rounded 建立可重复基线；若参考真机采用其他设置，则两端一起对齐。
8. 对应页面至少比较首页、设置首页、设置子页、搜索/输入、弹窗/底部面板和相关详情；覆盖浅色/深色/纯黑、悬浮/贴底、滚动顶栏、键盘和大字体。使用相同模拟业务内容做截图并排/叠加检查，转场用录屏；列出实际差异并修正。有对应场景的 Review widget 回归测试应一并迁移/适配；补充有必要的目标布局测试。编译成功不能作为视觉一致证明。
9. 没有参考页面、入口数变化、跨框架能力不同或无设备导致无法比较时，明确列出适配和未验证项，先完成不依赖它们的工作，不自行宣称逐像素一致。不要为缺少截图而擅自登录或写入真实账号。保留触控范围、文字缩放、语义标签和安全区，不能为截图相似压缩可访问性。
10. 将最终映射、实现差异、参考快照、验证证据和已知限制保存到目标开发文档。若涉及 Android 功能/UI 修改，按目标发布流程构建并静态核验主线 APK，保留回退；本次若只整理文档则无需构建。完成报告必须区分源码复用、测试/构建通过与设备视觉验收。

请立即按以上约束执行。先建立对应页面与共享组件，再接入业务；未完成视觉对照的部分标记待验收。未经我明确要求，不进行额外的设计优化。
```

## 5. 验收边界与长期维护

- 提示词能减少自由发挥，不能单独保证一致。可靠链路是固定源码快照、直接复用实现、固定渲染环境、同内容画面对照及转场录屏。跨框架还受字体栅格化、组件实现和模糊合成差异影响。
- `test/review_frosted_app_bar_test.dart`、`test/review_refresh_header_test.dart`、`test/chaohua_center_page_test.dart` 提供顶栏和覆盖式几何的现有回归；其他页面测试按实际组件搜索，不能声称已有全应用像素级测试。
- 当前本机 SDK 元数据为 Flutter 3.47.1 / Dart 3.13.1；这是提炼时的环境记录，不等同当前 APK 的构建来源证明。其他 SDK 版本的默认组件、字体或生成色板变化需重新比较。
- 后续改主题、导航、设置、卡片或动效时，同步修订本规范并运行 `tool/sync_review_documentation.ps1`。目标应用应保留自己的参考快照；不能让后续 Review 改动无审查地传播到目标应用。
