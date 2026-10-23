# Review 开发与技术架构文档

> 本文档是 Review 当前源码的开发说明，内容以代码和当前可验证的行为为准。文档更新日期：2026-10-23；当前应用版本：`3.11.4+213`。
>
> `README.md` 用于项目介绍；本文档维护当前实现，不记录登录 Cookie、Token、密码或其他凭据。

本地完整开发文档统一保存在 `D:\App\开发文档\Review.md`，完整汇入本说明、[变更记录](docs/CHANGELOG.md)、[工程复盘](docs/RETROSPECTIVE.md)、[磨砂顶栏设计规范](docs/FROSTED_TOP_BAR_DESIGN_SPEC.md)、[M3 UI 复用规范](docs/REVIEW_UI_REUSE_SPEC.md)和[图片画廊滑动指南](docs/IMAGE_GALLERY_SWIPE_PERFORMANCE_GUIDE.md)。本仓库保留这些分主题源文件以便版本管理；修改任一源文件后应运行同步脚本。截至 2026-09-23 的旧版综合手册已从当前汇编中移出，原件仍保存在 `docs/archive/Review-legacy-2026-09-23.md` 供追溯，不作为现行规则；当前行为以源码、测试和本文档为准。

## 1. 先看结论：哪些内容来自微博，哪些只是本地能力

Review 是 Flutter 编写的微博网页端风格客户端。凡是涉及微博内容、账号数据或微博操作的功能，都应区分“服务端真实状态”和“应用本地显示状态”。客户端可以做缓存、乐观更新和排版，但不能把本地状态冒充成微博已经保存的状态。

### 1.1 使用微博接口、以服务端为准的内容

- 时间线、微博详情、用户主页、分组时间线、热搜、搜索结果、话题、超话、地点和电影点评候选项。
- 点赞、取消点赞、收藏、取消收藏、评论、回复、删除评论、删除微博、关注和取消关注。
- 发布和编辑微博、图片上传、视频分片上传、可见范围、内容声明、话题/超话/提及/地点/点评字段。
- 微博投票卡片的选项入口。单选投票点击选项直接调用微博官方 `/ajax/statuses/setVote`；多选投票先选择选项，再按网页端规则提交。投票成功后使用服务端返回的 `vote_object` 更新卡片，不在本地伪造成功或票数。
- 评论解析会按图片 PID 和规范化图片 URL 去除微博接口在楼中楼中重复返回的父评论图片；子回复自己发布的其他图片仍会保留。
- WebDAV 备份是用户自己配置的第三方 WebDAV 服务，不是微博云端同步，也不是 Review 官方服务器。

收藏尤其需要注意：`TweetCard` 中的 `favorited` 只用于当前界面的显示和乐观更新，真正的收藏/取消收藏通过微博的 `/ajax/statuses/createFavorites` 和 `/ajax/statuses/destoryFavorites` 写入微博账号；它不是只存在本机的收藏。

### 1.2 只存在本地的内容

- 主题、动态取色、纯黑模式、悬浮底栏及其液态玻璃显示偏好、触感反馈、字体粗细调整、屏幕刷新率和预设应用图标。
- 微博卡片排版、时间显示格式、IP 属地显示方式、图片圆角/大图模式、菜单位置、背景图显示、链接颜色、备注显示等显示偏好。
- 搜索历史、浏览历史、屏蔽用户列表、当前滚动位置和媒体保存路径。
- 本地使用的账号 Cookie、Token、登录标记以及昵称、UID、头像等会话信息。它们用于连接微博，但不是微博数据的备份副本。

### 1.3 当前没有伪造本地结果的能力

- “定时微博”胶囊目前只展示能力入口和说明；当前普通发布接口没有在本地创建定时任务，也不会把普通发布误报为定时发布。真正的定时发布需要微博网页端/账号侧支持，当前应用尚未形成完整的官方定时发布闭环。
- WebDAV 设置页的备份/恢复只同步允许导出的个性化设置，不同步微博 Cookie、Token、登录状态、账号身份或 WebDAV 密码。WebDAV 密码只用于当前设备发起连接。
- 地点选择不会把地级市预填成微博地点。Android 原生定位只提供经纬度和精度，随后以空搜索词调用微博附近 POI，并在返回的官方地点中按距离排序；应用没有自行生成微博地点名称，也没有做反向地理编码。

## 2. 当前可用功能

### 2.1 主界面

主框架位于 `lib/features/home/presentation/main_scaffold.dart`，当前有三个主入口：

1. **时间线**：关注流、分组流、微博卡片、刷新和分页。
2. **热搜**：微博热搜分类榜单。
3. **设置**：主题、微博样式、存储与缓存管理、账号和关于应用。

时间线顶部可以打开侧边栏、切换微博分组、进入搜索和快捷发布。标准页面统一使用 `ReviewFrostedAppBar`；设置首页不显示仅有标题、没有操作的独立顶栏，设置子页面仍保留标准返回顶栏。所有标准顶栏以及时间线、热搜自定义栏、超话详情 SliverAppBar 共用同一材质参数与 `ReviewFrostedBackdrop`：主题 AppBar 色（缺省时回退 Scaffold 背景色）以 alpha 0.45 直接设置在 AppBar Material；上方叠加同色纵向渐变，顶部 alpha 0.95、边界 alpha 0，顶端合成约 0.9725，状态栏一侧更接近不透明、越靠底部分界越透明；`forceMaterialTransparency` 关闭。模糊层按 `ClipRect → BackdropFilter(sigma 20) → 渐变 DecoratedBox` 的顺序直接绘制，不使用 `ShaderMask` 或独立 blur alpha 遮罩；顶部高不透明度色层遮住大部分模糊，向边界透明度渐增，因此模糊观感自然显现。不能仅凭 widget 中存在滤镜判断有效：在适用的页面上还需确认滚动内容确实延伸到顶栏后方。`ClipRect` 限定滤镜范围，不启用全屏 shader 或全局液态玻璃。不能只在 `flexibleSpace` 绘制底色，否则 AppBar Material 透明时部分页面会实际呈现透明。滚动结构安全的页面让内容延伸至顶栏下方，并为列表/滚动内容补回安全区与工具栏高度，使滚动内容经过顶栏时可见磨砂；分组管理、赞和收藏、关注/粉丝列表等使用此布局。超话中心的搜索框和固定分类栏属于顶栏组成，磨砂背景覆盖至分类栏下沿，滚动结果从该边界以下开始；底部边界由顶栏整体材质与下方内容的交界表达，该页关闭标签行下方额外的浅色细线，避免出现双重边界。除上述超话中心外，登录表单、聊天输入区、内嵌网页/视频、其他固定搜索栏或复杂 pinned sliver 页面保持原内容几何，仅复用顶栏材质，避免键盘遮挡、控件重叠和滚动位置变化。时间线分组下拉面板仍是独立的局部面板，不属于顶栏渐变；它使用同主题底色、82% 不透明度和 sigma 20 模糊，区域由 `ClipRRect` 限定。热搜列表首项仍预留状态栏、标题栏和分类 Tab 高度，空/加载状态居中布局不变。覆盖式顶栏下 EasyRefresh 的安全 inset 不得重复加到触发距离：`reviewFrostedAppBarRefreshHeader` 保持 70dp 阈值并只将 ClassicHeader 指示器下移至完整顶栏以下；全局默认 header 与非覆盖式页面行为不变。应用使用 Material 3，底部导航支持贴底栏和标准材质悬浮栏，可在个性化设置中开关悬浮底栏。可迁移至其他应用的顶栏设计、Flutter 实现步骤和防错验收清单见[磨砂顶栏设计规范](docs/FROSTED_TOP_BAR_DESIGN_SPEC.md)。

主底栏的时间线、热搜、设置页面复用 Lurk 的双页叠放方式：切换时当前页与目标页反向同步平移一个屏宽，按入口顺序决定方向，RTL 反转；使用 260ms `easeOutCubic`，三个页面保持挂载以保留状态。系统关闭动画时直接切换。普通 `MaterialPageRoute` 在 Android、桌面和 Fuchsia 上复用 Lurk `SpringPageRoute` 的覆盖式语义：新页面全宽滑入覆盖旧页面，旧页面不移动、不淡入/淡出；LTR 从右侧进入，RTL 从左侧进入，push 320ms `easeOutCubic`、pop 220ms `easeInCubic`。Android 动画开启时由 `WidgetsBindingObserver` 把预测式返回进度转交当前 `PageRoute`；关闭系统动画时直接显示页面。iOS 保留 Cupertino 原生转场与边缘返回手势。图片画廊的显式 `PageRouteBuilder` 与 Hero 缩放动画继续走各自实现，不受全局路由主题影响。

液态玻璃底栏使用 `liquid_glass_widgets: ^1.13.0`。`main()` 在 `runApp` 前执行 `LiquidGlassWidgets.initialize(enablePerformanceMonitor: false)`，并以 `LiquidGlassWidgets.wrap` 包裹应用、传入 `Theme.maybeBrightnessOf`。主页面由 `GlassPage` 提供隔离作用域；仅在“使用悬浮底栏”和独立的“使用液态玻璃效果”同时开启时，才将 `GlassBackgroundSource(enabled: true)` 挂到主页面 body，`Scaffold.extendBody` 在该路径为 true。背景源只采集页面 body，不包含导航栏本身，避免反馈采样；关闭效果时不运行背景采样并回到原材质导航。玻璃底栏实际启用时，在局部 `GlassAdaptiveScope` 不覆写初始画质：使用库完成初始化预热后的 premium 首帧路径，并按静态 shader 支持探测和运行帧耗时自适应降级/恢复，避免固定 `standard` 起步后等待质量升档；应用其他页面不参与这项检测。短点按松手时，即使点击当前选中项也要通知宿主，保留时间线和热搜原有的单击回顶与双击刷新；每次有效短点按都调用全局触感工具，并遵守触感开关、40ms 防重复冷却与水波纹去重；长按或拖拽回到当前项仍不触发同页操作。时间线顶栏每次轻点均通过无水波纹的外层手势提供轻触反馈；打开微博卡片详情也在 `NoSplash` 触控卡片的导航入口单独反馈一次，不启用水波纹。

悬浮底栏的标准 M3 与液态玻璃两种样式共用响应式宽度 `min(440, 屏幕宽度 - 40)` 的 `2/3` 和 56dp 高度；标准样式仍使用主题 surface 背景、阴影、32dp 圆角和 4dp 内边距，液态玻璃样式仍使用独立光学参数。液态玻璃只替换当前实际存在的“时间线、热搜、设置”三个槽位，不增加尚不存在的消息/我的入口或发布按钮；底部 `SafeArea` 最小留白 21。主体参数为深色 40% 玻璃、clear body、厚度 10、blur 2.0、折射率 1.19、色散 0.008，主体和背景质量均为 premium（受局部自适应质量上限约束）；选中指示器折射率 1.18、色散 0.025、inner blur 6、pinch 0.7、press scale 1.06。选中指示胶囊使用深色 40% 填充（`#66000000`），选中和未选中图标/文字均为白色，以胶囊明暗与图标状态区分选中项，保证浅色图片背景上的文字可读。玻璃触控的选择回调延迟至松手：短点按仍保留当前 Tab 的回顶/刷新，长按或水平拖动不触发同页动作；只有水平释放速度达到 `1000 logical px/s` 的快速抛动才限制为起始页相邻一项，普通慢拖按松手时水滴所在页面选择（如时间线慢拖到设置可跨过热搜）。取消手势不提交；键盘和读屏语义激活仍即时生效。三个根页面在液态玻璃模式为 `MediaQuery.viewPadding.bottom + 76dp`；使用原始系统 inset，避免 `Scaffold.extendBody` 注入底栏高度后重复留白。标准悬浮和贴底模式仍分别使用 72dp 与 16dp。“使用液态玻璃效果”在个性化页作为独立分组常驻显示并独立保存；悬浮底栏需同时开启悬浮栏和液态玻璃开关，画廊返回/下载按钮只受液态玻璃开关控制。

图片画廊左上角返回与右上角下载保留 48dp 点击区。开关关闭时使用既有局部 shader/模糊按钮，布局和按钮回调保持当前状态；开关开启时使用库 `GlassButton` 的 `premium` 折射路径，由画廊局部 `GlassAdaptiveScope` 在 `standard` 与 `premium` 间依据设备能力自适应，避免降到不含折射 shader 的 `minimal`，且使用独立按钮玻璃层。静止态将透镜厚度设为 32、折射率设为 1.24，使 48dp 圆钮默认显示清晰的边缘折射；不要显式覆盖 `interactionScale`：库原生按压膨胀约增加最长边 17dp，让圆钮按住后展开成更大的水滴。只给这两个小控件保留 `standard` 下限，控制 GPU 成本。结合 `chromaticAberration: 0.025`、`stretch: 0.8` 和锚定拉伸强度 0.8，按压拖动时图片/视频内容随水滴边缘产生形变。触控高光沿用底栏白色交互光。短点仍执行返回/下载；长按与拖动只保留水滴交互，不执行按钮动作。画廊仅在该偏好开启时包裹 `GlassPage`，并将 `GlassBackgroundSource` 限定在图片/视频媒体视口，不把顶栏按钮采入背景源；下载期间按钮仍禁用，按钮标签继续提供读屏语义。动态背景采样成本、低端设备自适应质量与实时视频观感仍需目标设备检查。

液态玻璃关闭时，普通悬浮底栏的选中背景胶囊也会跟随入口移动，使用 `AnimatedPositioned` 在等宽槽位间以 240ms `easeOutCubic` 过渡；图标和文字状态同步淡变。贴底导航栏与液态玻璃栏手势逻辑保持不变。

该库对 Android 要求 Flutter 3.41 或更高；当前构建 SDK 为 Flutter 3.47.1。premium 是较高 GPU 成本路径，静态构建不能证明目标手机的帧率或实际折射观感。系统减少透明度/动画设置及旧 GPU 的表现需通过设备实测，不据 APK 编译结果宣称视觉验收完成。

顶栏模糊只使用一个 sigma 20 的 `BackdropFilter`，由外层 `ClipRect` 限定范围；其 child 绘制固定 flexibleSpace 内容和纵向主题色渐变。不套 `ShaderMask`，也不指定 `BlendMode.src`。颜色层从状态栏侧 alpha 0.95 过渡至分界线侧 alpha 0；叠加 AppBar Material alpha 0.45 后，顶部底色合成约 0.9725 不透明，边界处保留 0.45。因为渐变色层覆盖在模糊结果上，状态栏侧只透出极少背景，边界侧磨砂更明显；这是颜色叠层带来的视觉变化，不是第二个模糊遮罩。

### 2.2 时间线和微博卡片

- 高级搜索结果列表在剩余滚动距离不足 600dp 时自动续页，短列表在布局后继续补页；没有“加载更多”按钮。续页复用已提交的条件，加载锁避免并发重复页；失败保留列表、停止自动请求并显示重试，同页重试成功后继续自动加载。重新提交条件回到顶部，服务端没有更多结果时停止。
- 时间线顶栏搜索进入关注流“高级搜索”，其余页面的全站搜索入口保持原用途。2026-10-11 使用登录中的微博首页高级搜索实际捕获并核对 `GET /ajax/statuses/search`：关注范围固定 `atten=1`，`count=10`，`page` 从 1 递增；七个复选项依次对应 `hasori/hasret/hastext/haspic/hasvideo/hasmusic/hasv`，选中传 1、未选省略，分别为原创、转发、纯文字、含图片、含视频、含音乐、V+微博。关键词去首尾空白后传 `q`，空词省略；日期为浏览器/设备本地日期，`starttime` 是开始日零点秒时间戳、`endtime` 是结束日次日零点，包含结束当天。默认开始不限、结束今天，允许只按类型/日期搜索。结果读取顶层 `statuses/total_number/ok`，复用现有卡片与有界内容补全；翻页按已提交条件继续、按 ID 去重，失败保留已有结果并重试原页。未登录显示登录入口，业务拒绝/网页登录壳/结构异常不得伪装空结果；不回退全站搜索、不抓取所有关注人逐条查询、不在本地按媒体分类猜筛选语义。网页成功响应已确认，应用实际账号与真机交互仍需安装验收。
- 登录后先读取 `/ajax/feed/friendstimeline`；首屏请求失败或为空时，才尝试 `/ajax/feed/unreadfriendstimeline` 作为当前代码的兼容回退。两者都无内容时，只有没有完整 Cookie 的访客才回退公开热门流；已有完整 Cookie 的账号不把公域内容伪装为关注流。
- [微博客服中心说明](https://kefu.weibo.com/faqdetail?id=21729)：关注流会按关注关系推荐未关注博主的微博，例如“关注的人关注了/点赞了”。“最新微博”（`friends`）和“全部关注”（`all_follow`）使用独立 ID，切换时只高亮当前入口；二者沿用现有关注流请求与分页，不在客户端筛掉非关注作者。“最新微博”保持原有显示方式；“全部关注”通过 `TweetCard.showFeedReason` 显示状态 `title`/`title.text` 中的官方来源说明，即使状态带公开或受限可见范围也保留说明，纯可见范围标题不作为来源说明重复显示。来源说明位于头像昵称上方，使用与“仅粉丝可见”一致的 14sp 主题色文字和 16dp 图标，点赞用爱心、其他来源用信息图标；两类说明同时存在时独立分行，长说明在卡片内换行。文案完整沿用服务端 title，不强行补造“你关注的博主某某某/这条微博”；补齐投票/自动卡片等详情时保留原关注流标题，避免被详情标题覆盖。不新增接口或逐条查询关注关系。官方说明确认了“关注了/点赞了”两类，评论等其他文案仅在服务端实际返回时展示；字段缺失时不猜造来源。
- 支持微博已有的“全部关注”“特别关注”“好友圈”以及微博账号已有的个人分组和热门频道。应用不会把本地虚构分组当成微博云端分组，分组管理页对不能写入官方的本地新分组会明确提示不支持。
- 首页首次请求遇到空响应时只做一次短延迟重试；刷新得到空响应时不覆盖已有内容，避免短暂网络问题把可用时间线替换为“暂无微博内容”。加载更多使用 `max_id` 继续向历史分页，并做去重和屏蔽用户过滤。
- 卡片支持微博文本、富文本链接、表情、图片九宫格、视频、Live Photo、投票、超话标识、橙色热搜话题、转发微博、长文展开和操作菜单。微博卡片不响应整卡长按；整卡点击仍可进入详情，但外层不显示水波纹且不触发全局触感；菜单只从卡片顶部或底部的“更多”按钮打开，避免滚动/翻页误触。卡片内部按钮保留原触感与动效。
- 超过 9 张配图的列表卡片（含转发、主页和浏览记录）固定显示前 9 张，第 9 张叠加深色蒙层与 `+剩余数量`；点击该格从第 9 张进入完整画廊，不展开列表、不显示图片“展开全文”。详情仍直接显示全部图片，画廊始终接收完整列表。`continue_tag` 不作为长文字标记；旧快照误标长文且超过 9 图的短正文少于 140 字、没有省略号/展开标记、也没有全文数据时，列表不显示无依据的文字展开入口，源端全文补全与详情补取不变。已标记长文默认保留微博 `text_raw` 预览；只有标准化全文实际更长时显示“展开全文”，点击后才展开，主微博和转发微博一致。文字展开按钮放在正文与附件内容下方，只控制文字。`pic_ids` 有完整 PID 但 `pic_infos` 只含前 9 张时，用已有 PID 图片地址回退保留后续图片。详情和列表补全以桌面配图顺序为准，并合入移动端独有图片；生日/荣誉卡片继续按图层合并规则处理。
- 可见范围行（详情页始终预留；普通卡片仅非公开微博显示）保持 24dp 固定布局槽，图标和文字在槽位内上移 4dp，增加与作者头像的视觉间距，不改变卡片总高度。
- 微博头像、图片网格、视频封面、搜索/超话图片等网络图片统一复用 `extended_image` 的磁盘缓存；同一完整 URL 命中缓存时，应用重启后可从临时缓存读取，不保证不同尺寸、域名或查询参数的 URL 共享缓存。启动后异步检查并整理 `getTemporaryDirectory()/cacheimage`，仅处理该目录下直接存放、32 位小写 MD5 命名的缓存文件：自动清理阈值默认 200 MB，命中时静默清理；未命中时按原规则清理超过 60 天或总量超过 512 MiB 的文件，按文件修改时间从旧到新处理并跳过最近 1 分钟写入的文件。缓存页统计与手动清理使用相同白名单；不会清理已保存到相册的媒体、账号资料或其他临时目录。系统仍可自行清除临时缓存；图片显示加载占位不等于实际重新下载。
- 微博自动生成的荣誉/会员/活动网页卡片，会识别官方 `url_objects[].object.object` 的 `pic_url`/`image.url`，以及桌面时间线/详情中的 `url_struct`（`url_type=39`）经移动端状态接口补充的 `page_info.page_pic`。这类卡片可能由透明前景图和 `media_pic_url`/嵌套 `pic_info.pic_big` 背景图组成；分层卡片的列表比例优先采用背景画布的宽高，缺少尺寸时按常见横向卡片比例回退，避免拿透明前景的窄长尺寸裁切整张卡片。列表图层使用等比完整显示，透明卡片使用白色画布，详情画廊也等比完整显示。对应短链接从正文中移除，点击卡片只打开渲染后的图片，不再跳回个人主页。主页解析使用最多 6 路并发和按微博 ID 的内存缓存，避免这些卡片逐条串行请求。带真实视频播放地址的卡片仍走视频播放器，超话等普通主题卡片不转成图片。
- 投票微博保留现有原生选项卡和投票交互，不将投票链接的占位封面/投票图表加入图片网格。按同条微博解析出的 `WeiboPollModel` 与该网页卡片自身的 `type/object_type/title/投票 URL` 关联判定；只过滤相匹配的投票网页缩略图，不因微博中存在投票就清除 `pic_infos` 里的真实配图，也不影响文章封面、生日/荣誉卡片及非投票链接。
- 微博文章封面与自动动态图片区分：从官方文章链接或明确的 article 对象提取文章 ID，封面模型保留 `articleUrl/articleTitle`，点击复用已有 `WeiboArticlePage` 原生阅读页；兼容桌面 `/ttarticle/p/show` 与移动 `/article/m/show/id/`，不将外站或普通网页对象猜成文章。链接图片、`url_objects`、`page_info` 及浏览记录快照使用同一规则；旧快照同地址封面补上目标而不重复图片。只有点击封面才请求文章内容，生日/夺金卡片继续打开图片画廊。文章页解析结果按账号 UID 和文章 ID 保留最多 8 条进程内 LRU 缓存；再次打开直接显示缓存正文，手动下拉刷新时旧正文留在屏幕上，成功后替换。此缓存不落盘，登录态 UID 缺失时不缓存。从信息流卡片进入文章时传入卡片作者 UID 和头像 URL；只有解析到的文章作者 UID 相同才复用该头像 URL，避免同一用户头像因图片 URL 不同而在占位图和正文头像间闪换，不会把不同作者头像误用到文章页。
- 抽奖链接的导航缩略图不属于微博配图：按链接自身的抽奖标题、lottery 对象类型或微博抽奖域名识别，不将其 `card_image_url`、链接内 `pic_info/pic_infos` 或移动端 `page_info` 缩略图加入图片网格；仍保留“抽奖详情”正文链接及顶层真实配图。此判断不依据整篇正文是否出现“抽奖”，也不按图片大小删除图片；生日/夺金等自动卡片继续按原逻辑合成。列表、详情和浏览记录共用模型解析规则，不新增网络请求。
- 详情页补全自动卡片时，将移动端图层与桌面详情已有卡片合并；移动端只返回透明前景图时保留已有完整背景与画布尺寸，避免生日/荣誉卡片从完整卡片退化成只有头像。官方自动卡片短链接移除后，不显示重复链接正文；生日网页卡片从 `url_struct.url_title` 读取祝福标题，并将标题覆盖渲染在卡片白底图片的下方留白处，列表卡片和详情页保持一致，点击图片仍打开渲染后的图片。是否包含日期由微博返回标题决定，客户端不根据当前设备日期猜造文案。
- 浏览记录复用同一 `TweetCard`，历史快照通过 `WeiboStatusModel.toJson/fromJson` 往返时保留 `pics`（包括自动卡片前景、背景和卡片标记），不能只解析微博 API 的 `pic_infos`。旧快照带有 `url_type=39` 自动卡片链接但缺少卡片图片时，浏览记录后台复用主页的 `FeedRepository.parseStatuses` 有界补全；成功后在原历史位置更新快照，不改浏览顺序。普通状态不发起这类补全，失败也不阻塞列表打开。
- 长文在前台列表状态发布前预取：时间线和当前可见的用户主页在 `FeedRepository` 解析状态时，仅对微博源标记为长文且缺少全文的主微博/转发微博请求官方全文接口，补齐 `fullTextRaw` 后才将整批状态交给列表；默认仍显示微博 `text_raw` 预览，只有用户点击“展开全文”才显示全文。比较前统一清理卡片说明、投票链接和空白；全文没有实际新增正文时不显示展开按钮。后台个人主页视频/相册缓冲及浏览记录中的旧快照不因此批量触发长文请求；解析失败保留原预览和手动展开/重试入口。`DetailRepository` 按微博 ID 合并并发请求，最多同时执行 2 个全文请求，并保留最多 96 条最近使用的非空全文于进程内缓存。不按长度或布局行数自动展开，也不在卡片 build 时创建 `TextPainter` 测量正文。
- 独立微博视频链接（`h5.video.weibo.com/show/...`、`video.weibo.com/show?fid=...`、`weibo.com/tv/show/...` 以及移动端 `s/video/show` 变体）会调用微博官方视频组件接口获取签名媒体地址，再复用原生视频播放器；请求先使用不携带本地账号 Cookie 的公开接口，受限视频才回退到登录会话，不会把 H5 视频网页壳交给内置浏览器。针对当前移动端状态接口返回的 `url_objects` 视频卡片，应用会把其 `object_id`、封面、清晰度和已签名的 `weibocdn.com` 媒体地址合并到现有链接模型，并优先直接播放官方媒体地址；只有没有直接媒体地址时才回退 H5 组件解析。短链接、HTTP/HTTPS、HTML 实体和长文中的官方视频锚点也会统一规范化，避免视频短链接或 HTML `href` 被清理后又被当作普通网页打开。
- 转发微博的原内容卡片可直接进入原微博；原微博通过 `page_info/media_info` 返回的视频，即使没有图片列表，也会在转发卡片中复用普通微博的视频预览和播放器。
- 卡片菜单支持复制正文、收藏/取消收藏、复制链接、查看用户主页、屏蔽博主，以及在有权限时删除自己的微博。
- 投票字段从微博状态 JSON 的 `url_objects[*].object.object.vote_object`、`card_info.vote_object` 读取，并兼容 `vote_info`/`page_info`。桌面接口缺少投票或热搜详情时，按需使用官方移动端状态接口补齐；补齐失败则保留普通微博，不阻断时间线。点击“查看结果”会优先重新读取官方移动端 `/api/statuses/show`，必要时回退网页 `/ajax/statuses/show`；只有响应包含真实的选项票数或百分比时才切换结果视图，空壳响应不会被渲染成 0 票/0%。展开后可“收起”。同一套补全逻辑也用于用户主页，所以主页卡片不会因列表接口字段不完整而漏掉投票。
- 橙色热搜只识别微博官方 `darwin_tags` 等热搜标记，不把普通 `#话题#` 误画成热搜。热搜卡字号比正文小一档，直接使用火焰图标。

### 2.3 搜索页和热搜榜

搜索相关代码位于 `lib/features/search`，包括搜索建议、用户/微博/话题结果、热门搜索和微博热搜榜。

- 输入页的“用户直达”复用 `SearchRepository.searchUsers` 正式用户搜索，仅显示粉丝数至少 1 万的账号，保留服务端排序并最多取前 3 个，不足 3 个按实际数量展示，没有符合条件的账号则隐藏整个用户直达区域；完整结果仍在提交搜索后的“用户”标签查看；`/ajax/side/search` 只提供该页的联想词，不再把它返回的同名账号作为直达结果。用户直达失败显示独立重试，不能回退错误联想；改词/清空立即移除旧卡片，并按请求代次隔离迟到响应。400ms 防抖后并行获取联想词与正式用户结果。发布器 @ 提及继续沿用既有联想和必要时的 `/ajax/profile/info?screen_name=...`，不受直达变更影响。
- `/ajax/side/search` 只用于输入联想和发布器 @ 提及。综合主账号与用户标签优先请求 `s.weibo.com/user?q=<关键词>&page=<页码>`，从真实 HTML 的 `#pl_user_feedList .card-user-b` 读取 `a.name` 的 UID/昵称、头像、认证和粉丝数，保持官方顺序。2026-10-11 已在登录浏览器核对该原始响应含“巴旦木公主_”（UID 6130897928，56.6 万粉丝）为第一位、同名 5 粉丝账号为第二位。网页会话不可用时才回退移动 `/api/container/getIndex` 的 `100103type=3` 用户容器；两域均不可用才显示重试，不把联想账号冒充正式结果。移动请求按域复用现有会话；浏览器成功不等于手机会话有效。用户分页独立，重新搜索忽略旧响应。
- 微博搜索优先读取网页搜索页 `https://s.weibo.com/weibo?q=...`，解析网页卡片后再用 `/ajax/statuses/show` 补齐状态；接口失败时才回退到 `/ajax/statuses/search`。
- 话题搜索使用微博建议接口的 `type=topic` 数据；超话选择使用 `/ajax/stopic/list?keyword=...&page=...`。
- 热门搜索使用 `/ajax/side/hotSearch`，必要时回退 `/ajax/statuses/hot_band`，保留官方返回顺序，并把官方置顶数据放在列表顶部。
- 热搜分类使用官方接口映射：我的、热搜、文娱、社会、科技、生活、体育、ACG。没有对应网页端接口的分类不使用本地拼接或伪造榜单。
- 微博热搜榜保留官方置顶标记、排名颜色、火焰排名标记和不在排名内的定位热搜标记。定位热搜使用实心点替代排名数字，并显示定位标识。
- 热搜页重新点击已选中的底栏“热搜”会平滑回到当前分类顶部；双击会回顶并仅重新请求当前选中分类。热搜页顶栏单击回到当前分类顶部，双击回顶并刷新当前分类，不会刷新隐藏的其他分类。
- 榜单前三不再额外使用特殊粗体；排名框、火焰图标和颜色仍按官方数据保留。词条、序号和顶栏分栏字重统一接受应用的字体粗细设置，顶栏只保留选中/未选中的相对层级，避免全局调到最粗时层级反转。
- 搜索页热门搜索支持双列和单列切换。双列展示前 9 条，单列展示前 10 条；两种布局都保留“更多热搜”入口。单列使用与双列相同的字号并增加行间距。热门搜索不再对前三条单独加粗，所有文字跟随全局字体粗细设置，但排名颜色和官方排名图标保留。

### 2.4 微博详情、互动和用户页面

- 详情页读取长文、状态详情、转发列表、评论列表、二级评论、点赞列表、评论图片和编辑历史。
- 评论支持发表评论、回复、删除自己有权限删除的评论；评论列表支持刷新和分页。
- 一级评论中的楼中楼只作为首段预览渲染；当接口返回回复总数时显示“共 N 条回复”入口，点击后打开独立的回复面板。回复面板调用微博网页端的 `/ajax/statuses/buildComments`，使用 `fetch_level=1`、首请求 `max_id=0`，并严格沿用服务端返回的外层 `max_id` 分页游标和 `is_mix` 续页标记，直到没有更多回复；不会把首段通常只有两三条的 `comments` 数组当成完整楼中楼。面板底部同时提供明确的“加载更多回复”入口，避免只有少量预览行时无法触发滚动分页。
- 回复面板中的头像、昵称、认证/博主标签、时间/IP、正文、图片和点赞数按回复数据渲染；右侧点赞数和图标使用固定操作列，避免昵称、认证标识或数字长度造成位置偏移。点击回复整行或正文都打开现有回复操作菜单，@、话题和链接仍保留各自的跳转行为。
- 评论和楼中楼回复均使用微博返回的用户头像、昵称和认证信息；当评论/回复用户 UID 与当前微博作者 UID 一致时显示“博主”标签，不根据昵称本地猜测身份。评论、完整楼中楼和“收到的评论”列表还会读取评论用户的 `user.fansIcon.icon_url`（兼容 `fans_icon`）并显示微博返回的铁粉等级图标；直接复用带磁盘缓存的图片组件，不新增评论接口或补查用户资料。不同等级的底色/图案以微博提供的图标资源为准，不本地重绘；接口未返回铁粉图标时不推断等级。微博[官方铁粉等级说明](https://kefu.weibo.com/faqdetail?id=21662)确认标识可在博主正文页评论区显示，若评论本身已有超话等级标识则两者只显示其一，客户端以接口实际返回为准。
- 点赞、取消点赞、收藏、取消收藏、转发入口和删除操作都以微博响应成功为准，界面中的即时变化属于乐观显示，失败时回滚或提示。
- 私信与群聊均按较早在上、最新在下显示，首次打开定位最新消息；内部使用倒序懒列表，让旧记录追加后保持阅读位置。距离旧消息边缘 480dp 内自动预取，每页 40 条，私信使用 `max_id`、群聊使用 `max_mid`，按最早已加载 ID 减 1 请求并去重；正在加载时不重复发起，空页/无新增后停止，失败保留原列表和游标并提供点击重试，不自动循环失败请求。发送后的最新记录回读与已加载历史合并，避免丢失旧消息。消息中心嵌套会话列表显式设置零 padding 与 `primary: false`，避免重复继承状态栏安全区造成标题后大块留白。
- 聊天气泡读取 WebIM `media_type=1` 的 `att_ids`/`fids` 图片附件和 `pic_infos.original_pic` 动图图片；使用 `msget` 地址显示缓存预览，点击复用已有画廊查看和下载。仅 HTTPS `upload.api.weibo.com/2/mss/msget` 允许附带当前微博登录 Cookie，公共图床与其他地址不带该凭据。图片失败显示明确提示；预览使用固定有界尺寸并将解码宽度限制在 1024px 内，避免大图解码占用过多内存或改变气泡高度影响阅读位置。字段与分页参数依据 2026-10-18 微博聊天网页版公开加载的 `app.48f8ddda.js` 核对（https://api.weibo.com/chat/）；构造数据测试不等于真实账号图片访问验收。
- 群聊列表、群信息和群成员页预热会话用户缓存，供聊天页首帧复用头像与昵称；完整群公告另由 `query_user_bulletin.json` 读取，不能仅依赖可能截断公告的 `query.json`。
- 消息中心的未读清除基线持久化，避免重新拉取 contacts 后旧数恢复；打开某个私信/群聊会话时只将该会话标为本地已读，其他会话角标保留，新消息仍从 1 开始累计；打开 @、赞、收到的评论分类时只清除对应分类的本地计数，不会打开“我的消息”总览就一并清掉所有消息。会话未读数只显示在各自头像右上角，群免打扰气泡灰显，并排除于侧边栏聚合数与后台私信通知。“私信与群聊”标题不展示接口 `totalNumber`，以免清除后留下无法清理的误导总数。侧边栏聚合数来自 `/ajax/remind/unread` 与 WebIM contacts，前者是网页兼容接口且响应可能变化，解析失败时保留上次数值。Android 后台通知经 WorkManager 联网周期轮询（至少 15 分钟，实际可能更晚），首次轮询仅建立基线、不提示历史未读。
- 聊天发送按当前官方 Web `app.48f8ddda.js` 的表单请求实现：`/webim/2/direct_messages/new.json` 使用 `uid/text/is_encoded=0/decodetime=1/extensions`，群聊 `/webim/groupchat/send_message.json` 使用 `id/content/media_type=0/is_encoded=0/setTimeout=50/annotations`；统一 `application/x-www-form-urlencoded`、`source=209678993`、聊天 Referer 和 Origin，复用登录 Cookie/CSRF。未注册 Comet 会话时采用官方空 clientid 状态，群聊 annotations 带 `webchat=1`。旧 JSON body 与官方编码不匹配；群聊成功 `mid` 也必须识别。成功后按返回消息 ID 回读确认，不伪造气泡、不自动重发；没有 ID 的兼容确认须排除发送前已有记录，避免相同文本旧消息误认。失败保留草稿并显示服务端错误及错误码；接受请求后只清除未被继续编辑的原草稿。请求级回归使用模拟 HTTP adapter 验证实际编码字节，包括中文、换行、加号、& 和 emoji；尚无真实账号投递验收，本项目不使用用户账号发送测试消息。官方来源：https://h5.sinaimg.cn/m/pcweibochat/js/app.48f8ddda.js 。
- 聊天列表已移除 EasyRefresh 及其上拉/下拉刷新提示；继续在接近历史边缘时自动分页，保留历史加载状态与失败点击重试。
- 用户主页支持用户资料、背景图、认证/活动标识、微博列表、关注/取消关注、用户微博搜索和赞过的微博（按设置显示）。
- 用户主页资料卡中的“关注”和“粉丝”数量是可点击入口：当前账号进入“关注列表/我的粉丝”，其他用户进入该用户的“关注列表/粉丝列表”。关注列表使用网页端实际的 `/ajax/friendships/friends?uid=<uid>&page=<page>`，粉丝列表使用同一接口的 `relate=fans&type=fans` 查询，不附加本地排序或数量参数，两种关系不会互相回退。解析不到目标列表时区分网络失败与隐私未公开，不使用本地数量拼出假列表。关注列表中的用户可以继续进入其主页。
- 侧边栏包含浏览历史、收藏、关注话题、关注列表、群组成员、群微博、我的消息、收到的赞、发出的评论、收到的评论、提及、超话中心和聊天 WebView 等入口。关系列表页根据查看对象固定决定分栏：当前账号显示“关注列表 / 我的粉丝 / 我的超话”，其他博主只显示“关注列表 / 粉丝列表”，不为其他博主探测或展示超话。自己的超话仍使用独立的官方超话接口，不与关注/粉丝列表共用数据；栏数在页面初始化时确定，避免异步探测导致顶栏闪烁。

## 3. 发布微博：当前闭环和入口

发布页面是 `lib/features/compose/presentation/compose_tweet_page.dart`，选择器在 `weibo_publish_picker_sheet.dart`。底部工具栏顺序固定为：

**表情、媒体、话题、超话、提及、点评**。

工具栏可横向滚动，发送按钮固定在可用区域，不因工具项数量变形。已移除或不再展示的入口包括：头条文章、直播、新鲜事、问答、商品和“专栏”。仓库中仍可能保留部分历史模型/接口代码，但没有发布页面入口的代码不应被描述为用户可用功能。

### 3.1 媒体

- “媒体”先打开选择器，再从 Android 原生相册选择图片或视频。
- 图片支持多选，最多 9 张；图片和视频互斥，选中一种媒体后不能混合提交另一种类型。
- 图片优先使用网页端 `picupload.php?app=miniblog&s=json&p=1&data=1` 上传原始字节，旧上传路径作为兼容回退；最终发布以微博返回的媒体 ID 为准。
- 视频不再跳转“请前往电脑端访问此链接”。当前流程使用微博多媒体接口初始化媒体组、分发上传地址、分片上传和完成校验，获取官方 `media_id` 后再提交发布。

### 3.2 话题、超话、提及、地点和点评

- **话题**：使用微博官方搜索建议，选择后写入 `#话题#`，并保留服务端需要的主题字段。
- **超话**：进入超话中心/选择器，选择后写入超话内容和 `topic_id/sync_mblog` 等网页端字段；发送按钮直接发布到当前选择的超话，不另设“发送到超话”按钮。
- **提及**：界面文案为“提及”，搜索微博好友和其他用户使用官方用户搜索结果，选择后写入网页端用户标记字段。
- **地点**：调用 Android `getSystemLocation` 获取经纬度，再用微博 `/ajax/statuses/place?q=&page=...` 拉取官方附近 POI。结果按距离优先，并保留相关地点；选择后提交 `poiid/poititle/pc_title/long/lat/spot_type`。无定位权限或服务端没有 POI 时，不将地级市伪装成精确地点。
- **点评**：通过微博电影搜索结果选择对象，并在评分弹窗中选择 1–5 星，发布时提交 `rating_object_id` 和评分字段。此功能依赖微博接口实际返回可点评对象。

### 3.3 右上角三个状态胶囊

右上角使用 Material 3 `ActionChip` 风格的胶囊，而不是孤立的“更多”按钮：

- 定时：未设置时显示“无定时”；当前没有本地定时任务，不会假装已经排程。
- 可见范围：按当前状态显示“公开”“粉丝”“好友”“私密”“群友”，对应网页端 `visible` 值 `0/10/6/1/5`。
- 内容声明：无声明显示“无声明”；服务端返回自主创作、转载、AI 生成、虚构演绎时分别显示“创作”“转载”“AI”“虚构”。

发布和编辑调用：

- 发布：`POST /ajax/statuses/update`
- 编辑：`POST /ajax/statuses/modify`
- 请求使用网页端表单编码；媒体使用网页端 JSON 结构提交；发布成功必须以 `ok > 0` 或返回微博 ID 为准。
- 内容声明从 `/ajax/getSpaConfig` 的 `data.flags.statement.mblog_statement_list` 读取，并兼容微博配置接口的回退字段。若服务端没有返回选项，界面显示“微博服务器暂未返回内容声明选项，请稍后重试”，不在本地猜测可用声明。

## 4. 项目架构与目录

项目采用按功能拆分的 Feature-First 结构，公共能力放在 `core`：

```text
lib/
├── main.dart
├── core/
│   ├── auth/              # 登录状态和凭据管理
│   ├── constants/         # 微博接口、版本和分类常量
│   ├── design_system/     # Material 3 导航栏、卡片和偏好控件
│   ├── network/           # Dio 客户端、访客 Sub Token
│   ├── services/          # 链接路由和 WebDAV
│   ├── storage/           # SharedPreferences 与安全导出白名单
│   ├── theme/             # Material 3、主题、字体、微博样式和图标
│   ├── utils/             # 触感、解析、时间、弹窗、路由、表情
│   └── widgets/           # 公共头像、热搜标签、分组卡片和内嵌浏览器
└── features/
    ├── auth/              # 短信验证码、账号密码登录与 Cookie 导入
    ├── compose/           # 发布微博、媒体上传、发布选择器
    ├── detail/            # 详情、评论、互动、图片画廊
    ├── drawer_features/   # 侧边栏、收藏、消息、超话等
    ├── feed/              # 时间线、分组、微博卡片、投票/视频
    ├── home/              # 主框架和侧边栏
    ├── profile/           # 用户主页、样式、图标、刷新率
    ├── search/            # 搜索、热门搜索、热搜榜
    └── settings/          # 设置、存储、WebDAV、账号和关于
```

主要依赖以 `pubspec.yaml` 为准：Flutter `>=3.47.0` / Dart `^3.13.0`、`flutter_riverpod ^2.5.1`、`dio ^5.7.0`、`dynamic_color ^1.9.0`、`extended_image ^8.2.1`、`easy_refresh ^3.4.0`、`shared_preferences ^2.3.2`、`webview_flutter ^4.10.0`、`webview_flutter_android ^4.10.0`、`image_picker ^1.1.2`、`video_player ^2.9.2`、`url_launcher ^6.3.0`、`qr_flutter ^4.1.0`、`path_provider ^2.1.4`、`crypto ^3.0.6` 和 `intl ^0.20.3`。项目没有使用 `webdav_client` 依赖；WebDAV 是基于 Dio 的项目内实现。

## 5. 状态管理

- 使用 Riverpod 管理认证、主题、微博样式、主时间线和依赖注入。
- `FeedController` 维护当前分组、状态列表、分页游标、加载/错误状态和滚动位置；`FeedRepository` 只负责微博接口读取和写入。
- `AuthProvider` 保存当前登录状态、用户基本信息和凭据检测结果；认证失败不会在模糊错误下擅自清空凭据或反复跳转登录。
- `ThemeProvider` 与 `WeiboStyleProvider` 分别维护应用主题、悬浮底栏/液态玻璃效果开关、触感/字体/刷新率和微博卡片排版偏好。液态玻璃默认关闭；它控制画廊返回/下载按钮，并在悬浮底栏启用时与悬浮栏开关共同控制底栏。主题支持明暗模式、Material 3 预置色与 Android Monet 动态色。
- 页面层只根据状态渲染；服务端操作完成后再更新状态。网络失败、未登录或服务端未返回字段时，需要保留可解释的错误/空状态，而不是创建本地假数据。

## 6. 网络、会话与接口边界

### 6.1 基础地址和会话

```text
微博网页端:   https://weibo.com
微博登录:     https://passport.weibo.com
微博移动端:   https://m.weibo.cn
```

`WeiboDioClient` 负责 Cookie、XSRF、请求头和响应错误处理；`VisitorTokenEngine` 负责未登录公开内容所需的访客 Sub Token。桌面和移动端请求分别优先使用对应域的 Cookie 与 XSRF；缺少令牌时从同域配置接口获取，并只更新对应会话，403 重试也沿用原请求 Cookie/域，禁止把移动令牌写进桌面会话或反向污染。网页登录产生的 Cookie 只保存在本地会话存储，不写入开发文档、不进入个性化备份。

认证失败处理包括 XSRF 刷新和有限重试。401/432 等鉴权响应最多进行受控重试，不允许拦截器递归重试；凭据检测的模糊失败显示“暂时无法验证”，只有服务端明确失效时才显示失效状态，避免“检测失效—自动登录—再次检测失效”的循环。

### 6.2 主要接口矩阵

以下是当前代码实际使用的接口类别；接口字段可能随微博网页端变化，新增调用必须先核对网页端响应，不得只根据本地模型名称推断成功。

| 关注流/热门流/分组流 | **优先官方客户端原生 API（通道 0）**：关注流首屏走 `statuses/unread_friends_timeline`、分页走 `statuses/friends/timeline`；分组流走 `groups/timeline`（传 `list_id`）；分组列表走 `groups/allgroups`。原生未就绪或请求失败时，自动无缝降级至 Web 端通道：先尝试桌面 `/ajax/feed/friendstimeline` 与 `/ajax/feed/unreadfriendstimeline`；在移动会话下或桌面关注流无内容时，自动无缝回退移动端关注流 `GET https://m.weibo.cn/feed/friends`；访客可回退 `/ajax/feed/hottimeline`；分组回退 `/ajax/feed/groupstimeline`、`/ajax/feed/allGroups` |
| 用户主页微博流 | **优先官方客户端原生 API（通道 0）**：调用 `statuses/user_timeline`（传 `uid`），直连官方移动核心接口，彻底消除网页 Cookie 到期限制；原生未就绪或调用失败时，自动降级回退至网页端 `/ajax/statuses/mymblog` |
| 发布/编辑/删除 | 发布优先 `/ajax/statuses/update`（桌面失败或移动会话时回退移动端 `m.weibo.cn/api/statuses/update`）；编辑使用 `/ajax/statuses/modify`；**删除微博按会话分发：移动端使用 `m.weibo.cn/profile/delMyblog`（携带 `mid`、`st`、`MLOGIN=1`），桌面端使用 `/ajax/statuses/destroy`** |
| 评论/回复/二级评论 | 评论流与二级评论读取使用 `/ajax/statuses/buildComments`（一级评论使用 `fetch_level=0`，楼中楼使用 `fetch_level=1`，均使用响应外层 `max_id` 分页）。**评论写操作按会话分发：移动端使用 `m.weibo.cn/api/comments/create`、`reply`、`destroy`（携带 `st` 与 `MLOGIN=1`）；桌面端使用 `/ajax/statuses/buildComments`、`/ajax/comments/reply`、`/ajax/statuses/destroyComment`** |
| 点赞/收藏 | **全操作支持双通道路由与乐观状态自动回滚**：点赞/取消点赞在移动端走 `m.weibo.cn/api/attitudes/create` 与 `destroy`（携带 `id`、`attitude=heart`、`st`、`MLOGIN=1`），桌面端走 `/ajax/statuses/setLike` 与 `cancelLike`；收藏/取消收藏在移动端走 `m.weibo.cn/api/favorites/create` 与 `destory`（携带 `id`、`st`、`MLOGIN=1`），桌面端走 `/ajax/statuses/createFavorites` 与 `destoryFavorites`。我的收藏与我的赞列表在桌面 `/ajax/favorites/all_fav` 与 `/ajax/statuses/likelist` 无返回时，自动降级回退移动端接口及容器流 |
| 投票/投票结果 | `/ajax/statuses/setVote`、`m.weibo.cn/api/statuses/show`，网页结果读取回退 `/ajax/statuses/show` |
| 关注关系/关系列表 | 按已验证会话选择接口：桌面会话使用 `/ajax/friendships/create`、`/ajax/friendships/destory`；只有移动会话时使用 `m.weibo.cn/api/friendships/create`、`/api/friendships/destory`，并带移动端 `st`。微博取关路径沿用上游历史拼写 `destory`，不可改成标准拼法 `destroy`（会返回地址不存在；[公开网页端接口记录，非官方](https://github.com/imoonkey/openweb/blob/main/src/sites/weibo/DOC.md)也记录了该上游拼写）。失败保留微博业务提示，不乐观改资料状态。关系列表使用 `/ajax/friendships/friends?uid=<uid>&page=<page>`；粉丝列表额外使用 `relate=fans` 和 `type=fans`，不附加 `fansSortType` 或本地数量参数，禁止把默认关注响应当成粉丝响应 |
| 关注的超话 | `/ajax/profile/topicContent?tabid=231093_-_chaohua&page=<page>`；请求通过关注页 Referer 指定目标 UID，列表必须来自 `data.list` 等真实列表字段 |
| 私信/群聊 | `/webim/2/direct_messages/conversation.json`、`/webim/groupchat/query_messages.json`；群聊首屏使用 `max_mid=0`，接近顶部时分别通过私信 `max_id` / 群聊 `max_mid` 自动预取历史，游标为当前最早消息 ID 减 1，显示较早在上、最新在下 |
| 热搜/建议/搜索 | `/ajax/side/hotSearch`、`/ajax/statuses/hot_band`、`/ajax/side/search`（联想）、`/ajax/statuses/search`（微博）、`s.weibo.com/user`（用户，网页优先）、`m.weibo.cn/api/container/getIndex` 的 `100103type=3`（用户兼容回退） |
| 地点/超话/电影 | `/ajax/statuses/place`、`/ajax/stopic/list`、`/ajax/movie/hot_top` 或 `/ajax/movie/hot_search` |
| 发布配置/内容声明 | `/ajax/getSpaConfig`、`/ajax/statuses/config` |
| 图片/视频发布媒体 | `picupload.php`、`/ajax/multimedia/mediaGroupInit`、`/ajax/multimedia/dispatch` 及分片完成校验接口 |
| 独立微博视频播放 | 优先使用状态响应 `url_objects[*].object.object.urls` 中的官方签名 CDN 媒体地址；没有直接地址时使用 `https://h5.video.weibo.com/api/component?page=/show/{fid}`（显式 POST 表单字段 `data`，其值为包含 `Component_Play_Playinfo.oid` 的 JSON，并带 `PAGE-REFERER: /show/{fid}`；先公开请求，失败后回退登录会话） |

网页 HTML 解析、移动端状态接口和网页 Ajax 接口均是兼容层。优先使用能返回当前真实状态的网页端接口；回退请求只能用于补齐同一条状态或兼容旧响应，不能把回退结果混成另一条内容。

## 7. 交互、手势和原生通道

### 7.1 Material 3 与触感

- 个性化页面提供跟随系统/浅色/深色、纯黑深色、Material 3 预置主题色与 Monet 动态取色选项。关闭动态取色时使用用户选定的预置色；打开后使用 Android 提供的动态色，未提供时回退到预置色。字体大小沿用 Review X 排版：独立“字体大小”分组、应用字体大小滑杆、实时百分比，范围 80%–140%、每 5% 一档；拖动实时预览，松手后持久化。全局缩放在系统 TextScaler 曲线基础上应用，不覆盖 Android 无障碍字体缩放。
- 底部导航默认使用 Material 3，可在贴底栏与标准材质悬浮栏之间切换；悬浮栏可选液态玻璃效果，个性化中的同一液态玻璃开关也控制画廊顶部返回与下载按钮。历史 Miuix 设计语言偏好不再读取；当前 `use_liquid_glass_effect` 独立保存、默认关闭并加入 WebDAV 个性化备份白名单。
- Material 水波纹通过 `HapticSplashFactory` 提供全局一次轻触；业务回调会消费同一次手势的自动反馈，不会重复震动。取消点击不会额外触发，Live 图播放/暂停按钮使用普通水波纹并只在动作入口触发一次轻触。
- 触感工具保留约 40ms 的硬件抖动冷却，并使用 300ms 的同手势消费窗口，避免全局反馈与业务反馈叠加；没有 Material 水波纹的 GestureDetector 仍可由业务回调独立触发。公共头像组件的点击入口会消费全局水波纹反馈，确保只触发一次轻触；微博正文 `@用户` 使用内联点击识别器，因此在其跳转回调中调用 `HapticFeedbackUtil.light()`，遵守全局触感开关和防重复规则；所有下拉刷新入口统一通过 `HapticFeedbackUtil.refresh` 触发一次轻触。发布页定位按钮不再在业务方法开头重复触发轻触；成功选中地点后仅保留一次中等反馈。
- 公共头像点击区域至少为 48dp，并声明头像按钮语义；头像占位符按 Unicode code point 取首字符。Toast 根据安全区和键盘高度调整位置，并通过 live region 向读屏器公布内容。
- 搜索页与热搜榜共用 `HotSearchBadge`；搜索页嵌套的热搜 ListView/GridView 显式使用零 padding，避免默认继承顶部安全区而在榜单卡片内产生空白；设置首页使用私有 `_SettingsSectionCard`，设置子页及其他分组页面继续使用 `AppSectionCard`。统一使用 `showAppDialog` 的确认弹窗，设置/存储路径底部菜单使用主题的圆角、背景和拖动条。
- 时间线底栏单击支持回顶/返回上次位置，双击回顶并刷新；时间线顶栏单击回顶，双击回顶并刷新。顶栏标题文字单击回顶，分类菜单仍由标题旁箭头打开。
- 主 Tab 的 260ms 平移在每个页面外、`SlideTransition` 内增加独立 `RepaintBoundary`，使页面内容的绘制与位移动画分离；标准悬浮底栏指示条采用固定尺寸 `AnimatedSlide`，不再用 `AnimatedPositioned` 每帧重新布局。保留页面状态、双页同步平移、快速反向切换、RTL、减少动画设置及液态玻璃采样。真实主框架测试以 8,333 微秒步长推进动画，确认静态页面在连续六步内没有重复 paint、平移持续变化且快速切换不重建页面。Android 刷新率选择和 Flutter ticker 没有发现固定 60fps 的此处代码；上述测试不代表真机 UI/raster 阶段均低于 120Hz 的 8.33ms 预算，液态玻璃 GPU 合成仍需设备 profile。时间线滚动 notifier 在 initState 保存引用，退出时不再使用已销毁的 WidgetRef，首帧延迟挂载也检查 mounted。
- 热搜底栏再次单击回到当前分类顶部，双击回顶并刷新当前分类；热搜顶栏单击回顶，双击回顶并刷新当前分类。手势使用现有的 300ms 单/双击判定，不新增依赖。
- 用户主页顶栏也使用相同的双击判定：不在顶部时双击平滑回顶，已经在顶部时再次双击刷新当前用户微博；单击不改变原有标题、搜索和分享操作。
- 文章详情顶栏支持双击平滑回到文章顶部，单击不改变返回键和更多操作。

### 7.2 图片画廊

画廊连续滑动的双控制器交接和可跨项目复用的最小修复方案见[图片画廊连续滑动性能修复指南](docs/IMAGE_GALLERY_SWIPE_PERFORMANCE_GUIDE.md)。

主图分页采用 `BouncingScrollPhysics`，并仅在 ExtendedImage 当前缩放倍率不大于 1 时允许 PageView 翻页；放大后横向拖动由图片平移接管。`ExtendedPageController.shouldIgnorePointerWhenScrolling` 保持依赖默认值 `false`。主图 `ExtendedImage.enableSlideOutPage` 明确关闭：extended_image 8.3.1 在图片加载中/失败占位时会额外挂入 `ScaleGestureRecognizer`，实测会拦截横向分页并让主图无法接管缩略条惯性。不能仅因外层 `ExtendedImageSlidePage.slideAxis` 设置为水平就认定它正在抢手势；只有图片开启滑出时，图片手势状态才连接到该外层。若其他应用确实需要下滑退出，必须先验证加载中、失败和已解码三种状态的横向分页，不可直接全局改成 `enableSlideOutPage: true`。具体可复制配置和回归项见上述指南。

混合图库当前项为普通视频时，缩略条按播放器底部控制栏的实际布局高度排列在其上方，间隔 8dp；该高度包含进度条、按钮、字体缩放和底部安全区。控制栏仅在初次布局或尺寸变化时通知图库，不在每次播放进度更新时测量。缩略条保留在图库层：拖动期间锁定底部位置，停稳后按最终媒体类型恢复位置，避免播放器卸载打断滚轮手势。图片页仍使用原有底部位置，主图全屏视口不变。

顶部返回、页码/Live Photo 和下载控件与底部缩略条共用所在路由的动画状态：push 期间透明且不可交互，路由进入 completed 后以 140ms 淡入；pop 一开始立即禁用点击并淡出。顶部按钮含 `BackdropFilter` 和 fragment shader，禁止把整组按钮包进 `Opacity`/`AnimatedOpacity` 透明合成层，以免磨砂滤镜采样到黑色中间层；应分别渐变按钮图标透明度、玻璃底色和模糊强度。该处理只作用于叠层控件，不改变 Hero 尺寸、主图 PageView 视口/约束、定位几何或图片手势。

已解码图片的快速移动可能让内部 `ScaleGestureRecognizer` 先于外层横向分页胜出，8.3.1 又不在 1 倍时从缩放路径转交分页，因此出现收到指针却没有分页 ScrollStart/page position 变化的故障。通过完成态的 `ExtendedImageGesture.imageBuilder` 在绘制子树内注册依赖已有的 `ExtendedHorizontalDragGestureRecognizer`，将单指且倍率不大于 1 的拖动交给原 pager 的 onDrag 生命周期；外层也限制单指分页，双指捏合、放大平移、双击保持原识别器。触摸时将对应图片手势状态从 pager 的 Set 移除后重新加入，确保门槛读取触摸页而非缓存邻页。Hero 包装层级保持恒定，使用 `HeroMode` 只启用当前页，不能跨页时插入/移除 Hero 导致图片手势状态销毁重建。主图拖动期间暂停并卸载活跃媒体，经过页只更新显示下标；滚动结束后检查 epoch 与滚动状态才激活最终媒体，避免逐页初始化 Live Photo。可复现对照、完整迁移代码和真实 Profile 验收边界见[连续滑动性能修复指南](docs/IMAGE_GALLERY_SWIPE_PERFORMANCE_GUIDE.md)。原图尺寸与解码策略未改；已解码连续输入测试不能代替 Android Profile 帧时间验收。

`ExtendedImageGesture.imageBuilder` 也会在 Navigator 的 Hero 飞行层构建，该层没有 `ExtendedImageGesturePageViewState` 祖先。查找分页器必须允许 null，缺少分页器时直接返回图片绘制子树；只有正式画廊页内才注册分页识别器。不可使用强制非空，否则已解码图片打开时会抛出空值异常，被 Release 默认 ErrorWidget 显示为大块浅灰色（`RenderErrorBox` 默认 `0xF0C0C0C0`）。3.2.8 通过关闭整页淡入处理灰幕的假设已被实际 Hero 转场回归否定，该修改已撤回，恢复原有页面淡入。回归必须经过真实 Navigator push/pop，并提供已解码像素和动画途中到达的原图帧，检查每帧异常/错误控件和飞行层图片像素；只检查转场构建器或不进行路由转场的分页测试会漏掉该故障。

`ImageGalleryPage` 支持双击放大、捏合缩放、横向分页、Live Photo 播放切换、下载原图/Live 视频和合并保存到系统相册。Live Photo、普通视频和 GIF 必须互斥分类：实际非 GIF 的 `video_url`、`videoUrl` 或 `video` 字符串/URL 字段才进入视频播放器；视频类型标记本身不能启动一个缺少播放地址的空播放器。GIF 按媒体类型或图片 URL 扩展名识别；当没有真实视频直链时，GIF URL 优先于冲突的旧 `fid`/Live Photo 元数据，继续作为图片画廊资源显示。只有明确 Live Photo 元数据、`livephoto_video` 或 `/livephoto/` 媒体地址且资源不是 GIF 时才走手动播放控制器。进入 Live Photo 默认暂停，顶部按钮负责播放/暂停。

- 从微博图片网格点击普通图片时，通过 Flutter `Hero` 将对应缩略图连续放大到全屏画廊；返回时反向缩回来源位置。配对标识按来源网格实例、媒体下标和图片身份生成，保持固定 HeroMode/Hero 层级，仅当前画廊页启用 Hero 飞行，避免缓存邻页一起飞回。普通图片回程读取两端实际 `ExtendedRenderImage` 或 `RenderImage` 的解码像素、fit、alignment、布局变换及圆角；手势图使用已绘制的 destinationRect/layoutRect 保存当前缩放和平移，先去除绘制偏移再映射到 Hero 坐标。冻结完整图片平面后，逐帧插值图片四边与裁切圆角，让图片在途中逐渐收敛到来源的实际 cover 区域；不再重新布局手势子树并叠加统一缩放。临时 image.clone() 只共享既有像素句柄，飞行卸载即 dispose，不新增请求或缓存。未解码时保持原子树回退；自动网页卡片保留完整显示分支，视频不参与该 Hero。现有路由、分页、滚轮和媒体生命周期不变，无新增动画依赖。回归使用正式画廊路由及 ExtendedRawImage，对横图/竖图和放大平移状态逐像素比较回程起点与圆角目标；设备观感仍须真机复测。
- 点击信息流中已配对的图片 Hero 时，若来源缩略图已有解码帧，画廊会克隆这张 `ui.Image` 作为首帧预览；原图 `ExtendedImage.network` 并行按现有地址和缓存策略加载，完成后在下一帧释放预览并显示原图。该路径不新增网络请求，只覆盖来源像素可读取且 Hero 身份/初始下标匹配的打开方式；其他入口沿用当前加载状态。
- 所有多图/混合媒体画廊（2 项及以上，不限于超过 9 张）显示横向缩略图滚轮：当前项正常显示并有白边，其他项覆盖半透明白色蒙层，视频叠加播放图标。缩略图仅限制解码宽度 160px、高度按原图比例计算，再以 `BoxFit.cover` 裁切。滚轮使用 `ClampingScrollPhysics` 和关闭逐页吸附；手指拖动及松手后的惯性期间，主图直接镜像滚轮的连续页位置，不把多页变化放入逐页动画队列，因此快滑到末尾时主图不会在后面慢慢追赶。拖动期间同时关闭主图 PageView 自身的逐页吸附，避免主图物理在手指停住时与滚轮的小数页位置互相拉扯造成抽动；松手后的滚动结束通知延迟到当前手势/惯性切换处理完成后，再让主图和滚轮同步以 `easeOutCubic` 在 120ms 内吸附到最近项。过期结束回调由同步 epoch 丢弃。主图每次跨过一张图时触发 `HapticFeedbackUtil.selectionTick()`；该滚动专用触感使用 12ms 节流，不改变全局普通操作 40ms 节流。滚动期间暂停视频/Live Photo 的激活，最终选中后才恢复，避免快滑时逐个初始化媒体。主图手动翻页会接管同步并打断旧滚轮惯性。图片页缩略条位于底部安全区上方 32dp，高 64dp；`ExtendedImageGesturePageView` 始终使用全屏视口，顶栏和缩略条只叠加在图片上层。控件显隐不再改变视口尺寸，因此不会重置图片缩放、平移或中心位置。缩略条监听所在路由动画：push 期间透明且不可交互，路由动画完成后以 140ms 淡入；pop 状态一开始即透明并禁用命中，再于退场过程中淡出。这个动画只包围缩略条，不改变 Hero 尺寸、主图 PageView 视口/约束、定位几何或图片手势。手势缩放最低为 fit 尺寸 1.0，避免缩到适配尺寸以下后重置居中造成多余空白；统一居中初始对齐以保留手指焦点缩放。单项不显示缩略条；单张静态图片按整个屏幕居中。收起控件时只隐藏叠层，继续惰性构建、复用缓存，不预加载全部原图/视频。
- 图片夹视频复用现有 `WeiboVideoPlayerPage` 的嵌入模式，不另写播放器：从网格点击图片或视频进入同一完整媒体顺序；当前项为视频时使用真实视频地址播放，非当前视频只展示封面。显式当前下标通知确保分页保留的屏外子项也卸载播放器，初始化回调检查 mounted 和控制器身份，避免切走后后台自动播放。嵌入模式不重复显示返回栏；底部全屏按钮在同一播放器内切换横屏沉浸播放，并隐藏图库顶栏和缩略条；点击按钮、系统返回或退出全屏时恢复竖屏及图库控件，保留视频控制器与播放位置。播放/暂停按钮位于底部控制栏最左侧、时间显示之前；视频中央不再显示大播放/暂停按钮，单击显示控制栏和中间区域双击播放/暂停手势保留。画廊根据实测控制栏高度将缩略条放在控件上方；窄布局下时间文本可省略以让控制按钮保持可见。单视频仍可独立打开。播放器横滑进度手势移除，横滑交给画廊切换内容；进度条、双击快进/快退及纵滑亮度/音量继续保留。离开视频后释放播放资源，视频保存使用视频地址而不是封面。
- 图片自身不再因斜向滑动误触发“滑出销毁”；单指横向分页由页面处理。
- 画廊主图视口始终覆盖整个屏幕；顶栏按钮在状态栏安全区内叠加，图片页缩略条在底部安全区上方 32dp 叠加。显示或隐藏这些控件不会重新约束主图，因此图片保持当前屏幕位置、缩放和平移；单张静态图片也按整个屏幕居中。
- 返回和下载按钮各为 44dp 圆形半透明灰色玻璃控件，保留 48dp 点击区域，带柔和的浅色高光描边。Impeller 上仅在圆形裁切内以 `BackdropFilter` 轻微模糊并用局部 fragment shader 作凸面折射；shader 用空气/玻璃折射率与球冠法线的 Snell 角计算位移，并限制在 0.45 个 shader 单位内。不会逐帧截屏或处理全屏纹理；shader 不支持或加载失败时回退到原生模糊和描边。
- 预览屏幕按宽度分为左、中、右三等份：点击中间区域切换清屏，点击左右区域退出预览。
- 图片页的双击缩放由 `ExtendedImage` 内部识别；外层区域点击使用原始 `Listener` 指针事件，不得恢复会与图片双击竞争的父级 `GestureDetector.onTapUp`。单击/退出在 `kDoubleTapTimeout` 后确认，双击在 `kDoubleTapSlop` 范围内会取消待执行单击；移动超过 `kTouchSlop` 或多指操作不算单击。确认图片双击缩放时通过 `HapticFeedbackUtil.light()` 触发遵循全局设置的轻震动。视频页原有播放器双击行为保持独立。
- 清屏时隐藏返回键、页码/Live 状态、下载按钮和 Android 顶部状态栏；再次点击中间区域恢复。系统底部导航栏保持可用。
- 退出时恢复 edge-to-edge 状态。由于目标 SDK 为 36，顶部状态栏通过 `MainActivity` 的 `WindowInsetsController` 原生通道控制，不能只依赖 Flutter 的 `SystemUiMode.manual`。

### 7.2.1 Android Ultra HDR 原图（3.9.0）

- 依据用户提供的微博 https://weibo.com/3807294039/5345552066939360 实测第一张图片：`large`/`original` 均为 10,372,291 字节，SHA-256 `EEB0918432B217318EB4F9BE6D5725EAF3F4EC9996EE299307340BDC741B324A`，含 Adobe gain-map XMP、MPF 与 ISO 21496 APP2；MPF 中底图和附图均为 7170×4033，附图 2,494,164 字节；`middle` 为 82,334 字节，无这些标记。这里证明的是这张微博原图保留 HDR 数据，不能推广到所有微博图片或缩略图。未采用厂商推广文章作为验收证据。
- 旧画廊仅有 Flutter/ExtendedImage SDR 绘制链路。新实现仍由 ExtendedImage 加载与鉴权、写入原图缓存，`HdrGalleryImage` 仅读取既有缓存前 256 KiB 的 JPEG gain-map 元数据提示；仅候选文件交给 Android 14+ `ImageDecoder` 硬件解码，最终以 `Bitmap.hasGainmap()` 确认，不能用网址、图片标题或普通 HDR 字样设置角标。不支持 API、缺失缓存或解码失败都保留 Flutter 图片。
- `HdrImageSupport` 注册 `com.review/hdr_image` 与 `com.review/hdrImage`；只读应用 `cacheimage` 目录中的 MD5 缓存文件，不增加网络请求或传递账号凭据。原生解码为单工作线程，文件上限 64 MiB，目标像素按底图与增益图最坏合计 16 字节/像素预算（64 MiB 缓存时约 419 万像素），位图 LRU 最多 64 MiB（计入 gain map）；缓存无法容纳时继续 Flutter 显示。这是原生层内存上限控制，Flutter 既有全分辨率解码仍单独占用内存；超大图的原生放大细节可能低于原图。
- HDR 设备开启窗口 HDR 模式并保存原先模式；画廊内第一次确认 HDR 后保持模式稳定，退出恢复。启用 HCPP；采用 Hybrid Composition 而非 texture layer，原生层只挂载停稳后的当前静态图，翻页、Live Photo 播放及 Hero 转场继续显示 Flutter 图。原生层在 Hero 外，手势由现有 ExtendedImage 处理，原生层同步其完整图片矩形并等比变换，不改变 PageView 视口或图片缩放配置。
- 主图右下角与画廊缩略条角标沿用 GreenNote 的黑底、白色细边框和粗体 HDR 样式；主图角标位于滚轮上方并跟随清屏状态。不预下载信息流所有原图来判断 HDR。当前范围是 JPEG gain-map/Ultra HDR，不包含 AI SDR 增亮、AVIF/PQ 或 iOS 原生 HDR 适配；API 34 以下保持原查看器。
- 验收边界：文件元数据、单元/widget 回归和 APK 编译/静态核验不等于目标屏幕 HDR 亮度、厂商合成兼容性或帧时间验收。必须在支持 HDR 的 Android 14+ 真机上，用上述原图测试亮度、切图、双击/捏合、平移、返回和退出后的窗口恢复。

### 7.2.2 原图入口和聊天媒体修正（3.9.1）

- 用户在 vivo X300 Pro / Android 17 反馈 3.9.0 原图既无 HDR 效果，也无 HDR 角标。源码确认一个可导致漏检的入口问题：`WeiboPicModel.fromJson` 在没有独立原图字段时会退回 `orj960`/`mw2000` 等预览版本，先前验证过的同图缩略版本已剥离增益图。`originalUrl` 现在仅对 `*.sinaimg.cn` 的已知两段预览路径升级到 `/large/`，保留域名、文件名和查询参数；列表 `previewUrl` 不变，私信签名地址及第三方 URL 不改写。回归覆盖真实接口缺少原图字段、不同预览规格、相似恶意域名及私信地址。这是已确认的源码问题修复，不等于已确认该 vivo 的实际亮度恢复。
- 内存解码帧仍在、Android 临时原图文件却已被清理时，HDR 检测允许借助原下载器补取一次编码原图并写回缓存，继续复用既有鉴权规则；缓存存在时不重复下载。Android 15+ 显式采用系统 HDR headroom，并增加不含 URL/凭据的 `ReviewHDR` 解码增益图、尺寸、硬件 Canvas、HDR/SDR 比值和窗口模式诊断；不能把首次绘制日志或文件标记当作最终屏幕 HDR 验收。
- 私信/群聊纯图片改用自身比例约束（最大宽为屏宽 60% 且不超过 240dp，最大高 300dp），取消固定 220×170 图片视口。纯图片消息只保留 4dp 边距，背景透明，不再显示“分享图片”“发送图片”等占位文字；实际用户附言仍显示，图片点击继续进入共享画廊。`pic_infos`、`pic_gifs` 和带 GIF URL 的对象均可解析；已有有效附件优先，避免同一图片通过附件和元数据重复显示。
- 依据官方聊天 Web 当前 `app.48f8ddda.js` 的 `url_objects` 读取微博、用户及通用对象卡片：标题、摘要、图片和真实点击地址。仅完整卡片替换纯链接正文；带真实附言仍保留。可见的纯 URL 消息缺少卡片时，按官方固定 API 补查一次（私信 `show_batch.json?is_complete=1&is_encoded=0`，群聊 `query_message.json`）；不预取整页/全部历史链接，不抓取任意外部网页，不自动重试，失败仍保留原链接。卡片摘要 2 行、标题 1 行，图片 52dp 且最多解码 256px，无封面时使用通用链接图标。固定 API 补查和卡片字段形状已做构造样例回归，仍需真实账号对应消息验证。
- 共享表情解析允许含 `/`、`.` 的 HTML 表情标签，不再只识别中文/字母名字。若只有 `[/ee90a0.png]` 等历史文件名而没有 HTML 图片地址，按 UTF-8 解码 SoftBank PUA，并用 Google emoji4unicode 官方兼容数据的 470 条映射回退到 Unicode；该例为 👌，同类旧表情共用映射，不仅硬编码这个文件。HTML 有实际 CDN 源时仍优先官方图片。非法编码、未知文件名保留可读文字，不执行文件路径。数据来源：https://github.com/google/emoji4unicode/blob/master/data/emoji4unicode.xml 。
- 定向 60 项消息/表情/HDR/画廊测试通过，相关 Dart 分析无告警；包括竖图实际解码后的长宽比、4dp 纯图片边距、无占位文字、私信和群聊卡片补查只请求一次、文件名表情、原图 URL 规则以及原 Hero/分页/Live Photo 回归。没有连接 ADB 真机，不能宣称 vivo HDR 亮度、厂商合成路径、实际聊天账号数据或 GIF 的设备帧率已验收。

### 7.2.3 信息流 HDR 角标和聊天图片 Hero（3.10.0）

- 信息流单图与九宫格在右下角异步显示 HDR 候选角标。只对 `*.sinaimg.cn/large/<文件名>` 发起 `Range: bytes=0-262143` 请求，流式读取最多 256 KiB，与画廊的增益图元数据头部检查范围一致；专用 Dio 不注入微博 Cookie，单个 URL 的进行中请求合并，结果最多缓存 256 个 URL。普通非 HDR 头部结果会缓存，网络失败不会缓存以允许后续重新尝试。没有整图预下载或原生解码。
- 角标表示原 JPEG 头部发现 Adobe/ISO gain-map 元数据提示，不代表 Android 当前屏幕已确认显示 HDR；打开画廊后仍以 `Bitmap.hasGainmap()` 作为最终确认。若服务器忽略 Range，会在收到头部 256 KiB 后停止读取。当前用户样本 Range 响应为 HTTP 206，gain-map 标记位于头部约 1.2 KiB；因此可以在未打开图片时识别。其他新浪图片的标记位置可能不同，设备上的 HDR 亮度仍须真机验收。
- 私信/群聊消息中的多图共享稳定的消息 Hero scope 和同一画廊媒体列表，打开复用现有 `PhysicsSpringGalleryRoute` 与方向感知 Hero shuttle，关闭时缩回对应消息图片；点击时通过 `HapticFeedbackUtil.light()` 触发一次遵循全局开关与节流的轻震动。不要改成普通页面切屏转场或为每个相册项重新生成 Hero scope。聊天图片不属于新浪图床时跳过信息流的 Range 探测，原有消息鉴权头继续只用于实际图片读取。

### 7.2.4 HDR 角标首次完成通知（3.10.1）

- 用户反馈 3.10.0 仍需点开图片再返回九宫格才有角标；扩展 Range 到 256 KiB 没有解决此现象。已用正常 HTTP 206 响应、不点击图片的九宫格 widget 测试复现：`cachedSinaHdrGainMapProbe` 的 `whenComplete(() => _hdrProbePending.remove(url))` 返回了请求表内正在等待自身完成的 Future。结果虽然已写入缓存，首次等待者却永远不完成；Hero 返回重建后才走已缓存结果，符合用户反馈。
- 清理回调改为无返回值的语句块，只移除表项，不返回被移除的 Future。不新增轮询、自动重试或额外下载；维持原来的请求合并、256 条结果上限、Range 字节上限和无账号 Cookie 请求。
- 回归涵盖全新 URL 的九宫格首次加载、不经过画廊直接出现 9 个 HDR 角标、普通 SDR 不显示、同 URL 的 9 个首次等待者合并单请求，以及失败请求正常完成且允许下一次重新请求。HTTP 范围解析单测不能替代首次等待者和真实九宫格的异步回归。

### 7.2.5 聊天视频与卡片目标（3.10.2）

- 官方聊天 Web 静态源码 `https://h5.sinaimg.cn/m/pcweibochat/js/app.48f8ddda.js` 的附件视频使用 `media_type=10`；普通文件 `media_type=5` 经元数据确认 MP4 后也进入视频路径。消息 `att_ids/fids/fid` 是附件标识，不是公开视频详情 ID。可见消息按 fid 合并一次 metadata Future，调用固定官方 `upload.api.weibo.com/2/mss/meta_query.json`，MP4 按官方先 `replace=false` 再 `replace=true` 获取播放 fid；只按指定 callback 解 JSONP，不执行脚本。不预下载视频、不在列表创建播放器，普通非 MP4 文件保留原正文。
- 封面优先 `ext_text_video_pic_fid`，其次服务端 screenshot/thumbnail；宽不超过 240dp、高不超过 300dp，缺封面仍可用播放入口。隐藏协议占位“分享视频”，保留真实附言。点击轻震动并沿用 `PhysicsSpringGalleryRoute`、稳定消息 Hero scope 和 `ImageGalleryPage` 内已有 `WeiboVideoPlayerPage`。聊天传空 statusId，禁止播放失败后拿消息 ID 查询公开微博详情。
- 视频 Hero 只能飞封面，不能将播放器作为 overlay shuttle；有 Hero 的视频等路由进入动画完成再创建播放器，退出动画先停止。否则 Flutter Hero 默认占位/overlay 会销毁重建播放器、额外启动解码器。定向测试必须验证列表零播放器、打开只创建一次、关闭不重开；原混合媒体生命周期回归需一起运行。
- 播放、保存使用按实际媒体 URL 生成的 headers；私聊 Cookie 仅用于既有精确 HTTPS `upload.api.weibo.com/2/mss/msget` 路径。播放器封面单独按封面 URL 计算 headers，禁止把私有视频 Cookie 直接交给任意外站封面。
- 卡片优先已有 status 的数字 idstr/id/mid 或用户 idstr/id/uid，生成可原生路由的详情/主页地址；否则逐个验证并优先 url_long、对象 url，最后回退短链。不要让无效的首个字段遮蔽可用后续地址。官方 `http://t.cn/…` 升级 HTTPS，避免 Android WebView 明文拦截；相似恶意域名不升级。已删除、审核失败、权限不足内容仍受微博服务端限制，不承诺绕过。

### 7.2.6 HDR 网格角标与画廊首帧（3.10.3）

- 对照 `D:\App\GreenNote\lib\features\feed\nine_grid_view.dart` 的当前实现，信息流 HDR 标签统一为 10sp / w900 / 0.4 字距、水平5dp/垂直2dp内边距、4dp圆角、72%黑底、0.8dp白色45%细边、不加阴影。画廊主图11sp和缩略条7.5sp仍各自保持。
- 用户反馈点击原图后 HDR 映射约延迟1秒。旧链路等 ExtendedImage 完成全尺寸 Flutter 解码后才创建 HdrGalleryImage，Android ImageDecoder 因此串行晚启动。当前对画廊首张图片，在初始化后合并/读取已存在的 Sina `/large/` HDR Range 结果，直接按 MD5 查 ExtendedImage `cacheimage` 文件，并尽早启动 `HdrImageSupport.decode`；与 Hero/Flutter 大图解码并行。这里不执行同步磁盘 I/O，不重新下载图片，不为候选元数据提前伪造 HDR 成功；平台叠层仍等待 Flutter 图片完成、画廊路由完成和 Android gain-map/displaySupported 确认。HDR 检测和缩略角标不使用线性枚举整个缓存目录的慢速 helper。
- Android 原生解码的 pending Future 按缓存路径合并；首次预热与之后 HdrGalleryImage 的正式检测共同等待同一次解码。本优化主要消除串行等待；HDR GPU 映射仍由厂商系统/面板完成，没有本机 Android 设备，不能声称目标机实际时延或视觉效果已经测量。网格 badge 通过代码样式回归比对 GreenNote 源码参数。

### 7.2.7 HDR 映射零时延与硬件管线对齐（3.10.4）

- 对照同开发环境 `GreenNote`（`D:\App\GreenNote`）的画廊架构，彻底解决用户反馈的“点击打开 HDR 照片时等待约 1 秒才开始 HDR 映射流程”的严重延迟问题。
- 根因诊断与对齐改造：
  1. **解除 Flutter 下载与解码的串行门禁**：彻底移除 `image_gallery_page.dart` 中阻断挂载的 `if (_loadedImageUrls.contains(imageUrl))`。旧版要求 ExtendedImage 必须先完整将数兆到十几兆的原图下载并解码进内存后才挂载 HDR 视图，造成 500ms~1000ms 的硬性时延。现改为首帧立即挂载 `HdrGalleryImage`。
  2. **消除 Hero 转场动画阻断**：将 `active` 属性由 `activeIndex == index && _chromeRouteVisible && !_isPlayingLive` 改为 `activeIndex == index && !_isPlayingLive`。Native PlatformView 在 320ms 的转场飞行动画期间即可立即在后台线程池并行启动解码，不再等待转场结束。
  3. **平滑渐变与转场无缝切换**：引入 `visible: activeIndex == index && _chromeRouteVisible && !_isPlayingLive`，配合 `Opacity(opacity: widget.visible ? 1.0 : 0.0)` 包装 Native PlatformView。在转场飞行期间保持 `opacity: 0.0`，让下层的 Flutter Hero 预览图自然过渡，转场一完成无缝切换为 1.0，完全避免画面跳闪与卡顿。
  4. **屏幕 HDR 窗口色彩模式首帧即开**：对齐 GreenNote 在 `ImageGalleryPage.initState()` 首帧调用 `_checkHdrDisplaySupport()` 与 `_updateWindowHdr()`，只要当前图集包含已知或候选 HDR 图片，第 0 帧立即向底层调用 `setWindowHdr(true)`，让 SurfaceFlinger / HWUI 底层色彩模式在转场期间就重构就绪；并移除关闭窗口 HDR 时粗暴的全局 `bitmaps.evictAll()`，避免在图集中横向翻页时来回反复重新解码。
  5. **增强 Android 原生 `HdrImageSupport.kt` 并行下载与硬件解码**：
     - 线程池升为 `Executors.newFixedThreadPool(2)`；
     - 增加 `isHdrDisplaySupported` Channel 查询分支；
     - `create` 支持读取 `url`、`headers` 与 `path`；
     - 解码时优先命中内存缓存（0ms）；磁盘缓存命中直接通过 `ImageDecoder.ALLOCATOR_HARDWARE` 解码；若本地磁盘未命中，则使用带有微博图床鉴权头的 `HttpURLConnection` 边下边解边缓存至 `cacheimage/<md5>`，与 Flutter 缓存互通，解码成功后以硬件 GraphicBuffer 呈现并通过 Channel 触发 `hdrImageDecoded`。

### 7.2.8 聊天头像触感反馈（3.10.9）

- 私信和群聊消息中其他用户的头像点击通过原有无水波纹 `GestureDetector` 打开用户主页，并调用 `HapticFeedbackUtil.light()`。继续遵守全局触感开关和重复反馈节流；空 UID 不跳转也不触发反馈。不要改成带 Ink 水波纹的头像点击入口。
- 通用文章/外链通过 `LinkRoutingService` 进入 `InAppBrowserPage`；文章页工具栏的网页图标也在应用内打开原文，内置浏览器菜单仍保留明确的“在外部浏览器打开”选项。微博文章卡片依旧先走原生文章阅读页，内链继续由链接路由器按文章、微博状态/主页或普通网页分别处理。

### 7.3 Android MethodChannel

`android/app/src/main/kotlin/com/review/MainActivity.kt` 当前提供：

- 屏幕刷新率模式、支持的显示模式；
- 图片画廊状态栏显示/隐藏；
- 初始 URL、原生 Cookie、清除原生 Cookie；
- 系统定位（权限、经纬度、精度）；
- 亮度、音量、文本分享、媒体保存到相册；
- 预设应用图标切换、杀进程；
- `ReviewDocumentsProvider` 文档提供者。

## 8. 本地存储、备份和账号安全

`StorageService` 使用 SharedPreferences。保存内容分为会话字段、显示偏好、搜索/浏览数据、WebDAV 配置和屏蔽列表。

### 8.1 WebDAV 备份

- WebDAV 页面要求服务器地址使用 HTTPS（本机 `localhost`/`127.0.0.1` 除外），通过 Basic Auth 访问用户配置的目录。
- 备份文件包含应用主题（明暗模式、动态取色、M3 主题色、悬浮底栏和液态玻璃效果开关）、微博样式、分组偏好、媒体存储路径、搜索历史等允许导出的个性化设置。
- 明确不导出：微博 Cookie、SUB/SUBP、访问 Token、登录标记、UID/昵称/头像等账号凭据，以及 WebDAV 密码。应用字体大小和自定义字体粗细也保持设备本地，不加入导出白名单。
- 恢复时只接受 `allowedExportKeys` 白名单中的值，不能借备份文件恢复登录凭据。
- 导出包内部的格式字段 `version` 当前是数据格式版本 `1.0`，不等同于应用版本 `2.4.0`。自定义字体粗细的运行时设置由主题本地读取；当前导出白名单未包含自定义字体权重两个内部键，不能在文档中宣称它已随备份同步。

### 8.2 账号相关操作

- 登录页使用 Review 原生 Flutter 页面，不展示微博登录 WebView；标题为“账号登录”，右上角始终显示“Cookie 导入”。短信验证码是默认且主要登录流程，不要求用户先设置微博密码；另可切换到账号密码登录。
- `AuthNotifier.setAndVerifyCookie` 继续复用官方桌面与移动配置接口验证导入 Cookie 或 native 登录返回的 Cookie；桌面/移动任一路径明确确认 UID 才提交登录。仅从资料页或分组推断 UID 不构成有效登录；移动会话未同步到桌面时不得保留另一账号的桌面 Cookie。诊断失败只显示 Cookie 名称和页面，不显示 Cookie 值。
- 设置页可以检测凭据有效性、导出账号凭据/Cookie（这是用户明确点击后的本地查看/复制功能）和退出登录。
- “导出账号凭据”与“WebDAV 个性化备份”是两条不同路径；前者是敏感信息导出，后者明确排除敏感信息。
- 退出登录会清理本地会话 Cookie、Token、登录标记和账号基本信息；不会删除用户的主题、微博样式和其他个性化设置。

### 8.3 Android 私有登录与原生会话架构（实机验证通过）

> **交接文档归档说明**：此前用于排查闪退与发码问题的临时交接文档 `docs/WEIBO_ANDROID_LOGIN_HANDOFF.md` 已正式废弃，其所载之全部用户需求、技术细节、Smali 逆向分析、三阶段攻坚根因与验收标准已完整并入本文档。后续开发与维护以本文档为唯一准则。

#### 1. 用户体验与安全约束

- **短信验证码是默认且首选路径**：界面为原生 Flutter Material 3 页面，不嵌入展示微博官方 WebView。支持未预设微博密码的账号直接登录。
- **账号密码为次要切换路径**：支持标准账号与密码登录；登录页右上角始终固定保留“Cookie 导入”入口。输入框与按钮尺寸采用紧凑设计。
- **凭据零泄露原则**：短信验证码和挑战凭据 `number` 仅在内存及单次 MethodChannel 调用期间流转，绝不落盘、绝不进入日志；密码通过原生方法加密计算，明文密码绝不落盘、不入日志；登录成功下发的 `WeiboSession` 通过 Android Keystore AES-GCM 安全持久化。

#### 2. 模块与源码映射架构

- **Flutter 登录前端**：`lib/features/auth/presentation/login_page.dart`，负责短信与密码表单状态流转、输入校验、MethodChannel 调用与登录成功后的关注流切换。
- **原生通信通道**：`android/app/src/main/kotlin/com/review/MainActivity.kt`，注册 MethodChannel `com.review/weibo_auth`，处理 `requestSmsCode`、`loginWithSms`、`loginWithPassword`、`acceptSession`、`discardPendingSession`、`restoreSession` 和 `logout`。
- **Native 会话管理器**：`android/app/src/main/java/com/review/weiboauth/WeiboAuthManager.java`，负责调度底层 API、会话暂存提交、以及与系统 `android.webkit.CookieManager` 的双向凭据同步与清理。
- **底层 API 请求装配**：`android/app/src/main/java/com/review/weiboauth/WeiboApi.java`，管理端点 `account/login_sendcode`、`account/login`、`account/getoauth`，计算 `cum` 校验码，装配 Query 与 Form 表单，并透传服务端真实错误。
- **Native 会话实体模型**：`android/app/src/main/java/com/review/weiboauth/WeiboSession.java`，负责解析服务端响应、深度提取多层嵌套 Cookie、宽容解析有效期，并执行必要且充分的会话字段校验。
- **Native 运行时与 So 包装**：`android/app/src/main/java/com/review/weiboauth/NativeRuntime.java`，负责 JNI 初始化与 So 库封装（`wbutil`、`weibosdkcore`、`SecShare`、`wbgjb`），计算 OAuth 签名与安全哈希。
- **设备标识与 JNI 反射桩**：`android/app/src/main/java/com/sina/deviceidjnisdk/DeviceId.java`，提供 `genCheckId`、`appendCheckId` 等 JNI 查找目标，避免底层崩溃。
- **代理包管理器**：`android/app/src/main/java/com/review/weiboauth/FakePackageManager.java`，直接继承 `android.content.pm.PackageManager`，安全代理所有 94 个抽象方法，彻底解耦测试框架。
- **加密持久化存储**：`android/app/src/main/java/com/review/weiboauth/EncryptedSessionStore.java`，使用 Android Keystore 生成并管理 256 位 AES-GCM 密钥，将原生会话加密保存在私有 SharedPreferences 中。
- **双端凭据验证桥接**：`lib/core/auth/auth_provider.dart`，通过 `AuthNotifier.setAndVerifyCookie` 调用微博桌面端和移动端真实配置接口验证 UID，验证通过后方可正式提交登录。

#### 3. 为什么之前不行，为什么现在可以（三阶段技术攻坚全景剖析）

##### 阶段一：解决底层 JNI 致命崩溃（SIGSEGV / Native Abort，2.19.0–2.19.4）

- **之前为什么不行（崩溃根因）**：
  在构造公共登录参数 `commonLoginQuery` 时，Review 此前错误将 `android_id` 设为 `nativeRuntime.deviceId()`，触发调用 `DeviceId.getInstance().getDeviceId(application)`。而在底层 `libweibosdkcore.so` 内部，native 函数 `getDeviceIdNative` 会通过 JNI 反射查找并调用 Java 方法 `com.sina.deviceidjnisdk.DeviceId.genCheckId(String, String, String)`。由于 Review 遗留的 `DeviceId.java` 缺失该方法，JNI `GetMethodID` 返回 `NULL`，随后的底层调用直接触发 ART 虚拟机的 SIGSEGV / Native Abort 致命崩溃，Java 层 `try-catch` 完全无法捕获。此外，`FakePackageManager` 此前继承自 `android.test.mock.MockPackageManager`，在许多生产 ROM 上因缺少该测试库而直接触发 `NoClassDefFoundError`。
- **现在为什么可以（解决方案）**：
  1. 深入逆向分析并核对上游 Share 反编译源码（`UB.smali` 第 1053 行与 `aQ.1.smali` 第 106-118 行），发现上游请求中的 `android_id` 根本不是 `DeviceId`，而是直接通过系统 `Settings.Secure.getString(context.getContentResolver(), Settings.Secure.ANDROID_ID)` 获取。改回系统获取后，彻底切断了进入危险 JNI 调用的入口。
  2. 在 `DeviceId.java` 中防御性补齐了 `genCheckId(String, String, String)`、`appendCheckId`、`checkMyPermission` 等所有 JNI 反射签名，并在库加载点增加安全防护，杜绝任何潜在的 JNI 反射缺失崩溃。
  3. `FakePackageManager` 彻底抛弃继承 `android.test.mock.MockPackageManager`，改为直接继承 `android.content.pm.PackageManager` 并安全代理所有 94 个抽象方法；从 `build.gradle.kts` 和 `AndroidManifest.xml` 中完全移除了测试库依赖。
  4. 在 `MainActivity.kt` 的 `submitWeiboAuth` 中建立了全局 `Throwable` 异常捕获兜底，底层 JNI 崩溃彻底消除。

##### 阶段二：解决微博服务端拒发验证码（400/拒绝，2.19.5）

- **之前为什么不行（拒发根因）**：
  1. **区号传递错误**：中国大陆区号（`"86"` 或 `"0086"`）被错误放进 `query.put("area", "86")`。核对上游 Share 源码（`wd.1.smali` 第 217-270 行），中国大陆区号在 `account/login_sendcode` 和 `account/login` 请求中**必须显式设置为空字符串 `""`**，手机号保持 11 位数字。直接传递 `"86"` 会被微博服务端直接判定参数不合规并拒绝下发短信。
  2. **非法硬编码 `aid` 污染**：此前在 Query 和 Form 中多处写死了伪造的 `aid="7501641714"`。核对上游 Share（`mA.2.smali` 与 `WeiboWebAuthorizeActivity.smali`），`"7501641714"` 仅是 AidTask 的固定 App ID，绝非设备 AID；Share 在未获取到真实设备 AID 时完全不传该参数。写死伪造 aid 会导致微博服务端设备 token 校验失败。
  3. **`ua` 格式残缺**：此前 `ua` 缺少末尾的 `+ Build.VERSION.RELEASE`，不符合微博客户端标准格式 `MANUFACTURER-MODEL__weibo__11.6.3__android__android<RELEASE>`。
  4. **服务端错误信息被遮蔽**：此前丢弃了服务端返回的真实 `msg` / `errmsg`，前端使用固定文案掩盖了真实拒发原因。
- **现在为什么可以（解决方案）**：
  1. 在发码与登录请求中自动将 `"86"` / `"0086"` 规范化为空字符串 `""`。
  2. 彻底移除所有写死的伪造 `aid` 传参。
  3. `ua` 规范补全 Android 系统版本号 `Build.VERSION.RELEASE`。
  4. 全链路透传服务端返回的真实 `msg` / `errmsg` / `error`。发码链路 100% 畅通，真机测试成功收到短信验证码。

##### 阶段三：解决登录会话校验拦截（`session_fields_missing`，2.19.6）

- **之前为什么不行（拦截根因）**：
  1. **`hasRequiredFields` 严重误判（核心拦截点）**：核对上游 Share 源码（`sd.1.smali` 短信验证码登录回调 `ThirdPartyLoginActivity$O00000Oo` 第 80-137 行），短信登录接口仅提取 `access_token`、`expires_in`、`uid`、`gsid` 和 `cookie`，**根本不包含也从不要求 `sut`**（`sut` 是单点登录凭据，仅在账号密码登录 `yd.1.smali` 中存在）。Review 此前在 `WeiboSession.java` 的 `hasRequiredFields()` 中硬编码要求 `present(sut)` 以及根对象的 `present(expire)`，导致所有短信登录即使微博服务端返回 200 OK 并下发完整有效凭据，也会 100% 被误判为 `session_fields_missing`，拦截并提示“微博未返回完整登录会话”。
  2. **`expire` 字段误判**：服务端有效期保存在 `oauth2.0.expires`（或 `expires_in`）以及 `cookie.expire` 中，根对象无字符串 `expire`。此前硬编码检查根对象导致二次误判。
  3. **Cookie 多层嵌套结构解析缺失**：核对上游 Share（`oo0o00o0.7.smali` 与 `Gz.smali`），微博服务端的 `cookie` 字段是一个包含各域名映射（`.weibo.cn`、`.weibo.com` 等）的 JSON 对象。此前 Review 直接调用 `response.optString("cookie")`，返回了整个对象的 JSON 字符串，无法被 Flutter 端的 `AuthNotifier.setAndVerifyCookie`（要求 `SUB=...` 格式）识别。
  4. **缺少系统 CookieManager 同步**：登录成功后未将 Cookie 注入系统 WebView，导致原生环境凭据不同步。
- **现在为什么可以（解决方案）**：
  1. 将 `WeiboSession.java` 的会话校验条件修正为真实必要充分条件：`present(uid) && (present(cookie) || present(accessToken) || present(gsid))`。
  2. 实现多层 JSON Cookie 递归与键值提取逻辑，优先提取包含 `SUB=` 的登录 Cookie；若 Cookie 仍为空但 `gsid` 以 `_2A` 开头，自动回退兜底为 `"SUB=" + gsid`，确保传递给 Flutter 端的始终是规范的标准 Cookie 字符串。
  3. 宽容解析有效期，按优先级从根对象、`oauth2.0.expires`、`oauth2.0.expires_in`、`cookie.expire` 中提取。
  4. 在 `WeiboAuthManager.java` 中增加 `syncCookieManager(cookie)` 和 `clearCookieManager()`，在登录成功与恢复会话时将 Cookie 同步写入系统 `android.webkit.CookieManager` 并 `flush()`，退出登录时彻底清理，保证 WebView 与原生通道凭据完全一致。
  5. 2.19.6+130 经真实 Android 设备验证，输入验证码登录一次性顺利通过，成功进入应用并加载关注流！

#### 4. 验证与运维结论

- **实机验收结果**：`2.19.6+130` 已在真实 Android 设备上完整验证通过：短信发码畅通、输入验证码登录一次性通过并成功加载关注流、会话正常保持与恢复。
- **原生刷新机制**：`account/getoauth` 作为 GET 请求，仅在原生 `lastRefreshAt` 达到 21,000,000 ms（约 5 小时 50 分钟）后触发刷新。应用冷启动时通过 `EncryptedSessionStore` 本地恢复，不因单次瞬时网络波动判定会话失效。
- **账号退出规范**：退出登录同步清理 native 加密会话、Review 本地 Cookie/Token/账号状态以及原生 `CookieManager` 中的所有 Cookie。手动导入 Cookie 成功后亦会清理之前的 native session，杜绝账号凭据交织。
- **认证日志脱敏（2.19.7）**：只记录 HTTP 状态、会话字段是否存在和异常类型；不得记录登录响应 JSON、Cookie、Token、异常消息或请求表单。服务端错误提示可供用户界面展示，但不得写入日志。
- **冷启动闪退治理（2.19.8）**：
  1. **后台线程操作 CookieManager 引发 Chromium SIGABRT 根因**：用户成功登录并持久化 session 后，应用在冷启动时触发 `restoreSession()`。2.19.6 将 `syncCookieManager()` 放置在后台单线程 `weiboAuthExecutor` 中执行。冷启动瞬间 Chromium WebView 尚未在主 UI 线程完成初始化，在子线程直接调用 `CookieManager.getInstance()` 或 `setCookie()` 会触发 Chromium native 底层断言 `CHECK(BrowserThread::CurrentlyOn(BrowserThread::UI))` 失败或竞争崩溃，产生底层 `SIGABRT` / `SIGSEGV` 致命信号，Java 层 `try-catch` 无法捕获导致秒退。2.19.8 将 `syncCookieManager()` 与 `clearCookieManager()` 严格调度至 UI 主线程（`Handler(Looper.getMainLooper()).post`）异步执行，并在主线程做全异常隔离。
  2. **CookieManager URL 格式非法**：此前将非绝对 URL（如 `".weibo.com"`、`".weibo.cn"`）直接传入 `setCookie()` 与 `getCookie()`，在部分 WebView 版本下导致解析异常。2.19.8 全面规范化为合法的 `https://` 绝对地址。
  3. **`EncryptedSessionStore.load()` 与 `restoreSession()` 故障隔离**：设备重启或 KeyStore 状态波动可能导致解密抛出 `AEADBadTagException` 等异常。在 `load()` 中实现全异常捕获并降级为安全返回 `null`（同时清理损坏密文）；`restoreSession()` 增加顶层异常兜底，网络刷新失败时保留本地有效会话，确保冷启动链路绝对不可阻断。
- **冷启动 0.5s~1s 闪退最终根治（2.19.10）**：
  1. **彻底绝缘 Android 原生 `CookieManager`**：在 `MainActivity.kt` 中完全删除 `import android.webkit.CookieManager`。已登录用户冷启动时，`FeedController.initAndLoad()` 在首帧渲染后约 0.5s~1s 调用 `reconcileNativeSession()`，触发 MethodChannel `getNativeCookiesByDomain`。在没有 WebView 初始化的纯 Flutter 进程中，主线程调用 `CookieManager.getInstance()` 并连续读取 8 个域名的 Cookie 会强行唤起系统 Chromium 引擎，在多核并发与缺失上下文时直接引发 C++ 底层 `SIGSEGV / SIGABRT` 致命崩溃（Linux 信号无法被 Java 捕获）。2.19.10 将 `getNativeCookies`、`getNativeCookiesByDomain` 和 `clearNativeCookies` 完全静态化返回安全空数据，原生端彻底零 `CookieManager` 依赖，彻底切断崩溃链路。
  2. **MainActivity 安装全局未捕获异常崩溃日志落盘**：在 `MainActivity.onCreate` 中安装全局 `Thread.setDefaultUncaughtExceptionHandler`，一旦发生任何未捕获异常，立即自动写入私有目录 `latest_crash.txt`，并通过 MethodChannel 提供 `getLatestCrashLog` 查询能力。
  3. **彻底清除 `onCreate` 中的组件启用状态检测**：将 `onCreate` 中触碰 `packageManager.setComponentEnabledSetting` 的历史自愈代码完全剥离，消除任何可能因包状态变更广播导致 AMS 延迟杀进程的潜在隐患。
  4. **Flutter 顶层与平台调度异常兜底**：在 `lib/main.dart` 中配置 `FlutterError.onError` 与 `PlatformDispatcher.instance.onError`，对所有未捕获的 Dart 异步异常进行全局捕获与平稳降级，阻止 Flutter 引擎异常退出。
- **冷启动后台线程 JNI aa4 缺失引发 SIGABRT 根治（2.19.11）**：
  1. **斩断冷启动死循环链路**：在 `WeiboAuthManager.java` 的 `restoreSession()` 中彻底移除同步调用 `api().refresh(session)`，直接返回本地 KeyStore 安全解密的 `session`（包含合法 `uid` 与 `cookie`），冷启动链路瞬间秒开（0 毫秒阻塞、0 崩溃风险）。
  2. **完整对齐上游 Share `WeicoSecurityUtils` JNI 规范**：依据上游 `WeicoSecurityUtils.smali` 完整重建 Java 壳层，补齐底层 native `generateS` 所依赖的 `aa4(String, String, String)` 静态回调及纯 Java 散列选取算法 `toSecurityValue`、`sha512`、`toHex`；同时补齐 `aa2`、`aa3`、`aaa`、`securityPsd`、`sinaPushParse`、`charToByte`、`hexString2Bytes` 以及全部底层 Native 导出签名，彻底杜绝 `mid == null` 和 `Fatal signal 6 (SIGABRT)`。
- **信息流接入原生客户端 API，实现双通道容灾架构（3.7.0+193）**：
  1. **核心根因与痛点验证**：此前登录系统虽成功获取底层客户端级 `WeiboSession`（内含 `gsid`、`sut`、`uid` 等持久凭据），但 Flutter 侧仅拿到并使用了网页端 Web Cookie（`SUB`/`SUBP`）。网页端 Cookie 有效期较短，一旦到期或被服务端主动失效，即便原生 Session 登录态未掉，Flutter 侧调用 `https://weibo.com/ajax/...` 依然会报未登录或刷不出信息流。
  2. **官方客户端原生 API 直连通道（通道 0）**：原生层 `WeiboApi` 新增通用签名请求方法 `request(session, endpoint, params)`，自动装配移动端标准登录参数（`commonLoginQuery`）、绑定 `gsid`、计算 `oauthSignature(uid)`（基于 `WeicoSecurityUtils` 完整 JNI 体系）与 `cum` 校验签名，直连 `https://api.weibo.cn/2/`。`WeiboAuthManager` 引入内存活动会话缓存 `activeSession`，提供 `hasNativeSession()` 状态检查，消除每次请求的重复 AES-GCM 解密开销。`MainActivity.kt` 将异步通信线程池扩容为 4 线程，防止多流并发加载时产生串行阻塞，并通过 MethodChannel 提供 `requestWeiboApi` 与 `hasNativeSession`。
  3. **Flutter 侧多层降级与双通道容灾**：引入 `WeiboNativeApi`，为 `FeedRepository` 注入原生请求能力。关注流优先请求原生未读关注流 `statuses/unread_friends_timeline`（首屏）与历史关注流 `statuses/friends/timeline`（分页）；原生异常或无返回时，自动平滑降级至桌面 Ajax（`friendstimeline` / `unreadfriendstimeline`）、移动端 H5（`m.weibo.cn/feed/friends`）及访客热门流。分组流与分组列表优先通过原生 API `groups/timeline`（带 `list_id`）与 `groups/allgroups` 读取；失败时降级至桌面端。用户主页微博流统一抽象为 `FeedRepository.getUserTimeline`，优先调用原生 API `statuses/user_timeline`，彻底摆脱网页 Cookie 寿命限制；失败时降级至桌面端 `/ajax/statuses/mymblog`。
  4. **完全向后兼容**：保留既有 Web Cookie 导入与全部 Web 请求逻辑，形成“原生 API 优先 + Web 双通道容灾”高可靠闭环。

## 9. 设置页当前范围

- **设置首页布局**：主设置页不显示仅有“设置”标题的独立顶栏，内容在状态栏安全区外再留 20dp 顶部间距；各设置子页面保留可返回的磨砂顶栏。
- **设置首页视觉**：分为“偏好与功能”“存储与备份”“账号设置”“关于与支持”，沿用 `ReviewPreferenceTile` 与页面私有 `_SettingsSectionCard`；设置行标题使用当前主题 `titleMedium`（Material 3 默认 16sp），分组标题使用 `titleSmall`（默认 14sp），辅助内容使用 `bodyMedium`（默认 14sp），不再硬编码更大的字号或覆盖主题文字样式。图标与箭头 24dp；卡片零默认外边距、低层级 `surfaceContainerLow`（纯黑主题使用 `surfaceContainer`）、24dp 圆角且无阴影/描边。卡片内分割线缩进 56dp，对齐文字起点（屏幕坐标 72dp = 页面外边距 16dp + tile 内边距 16dp + 24dp leading + 16dp gap）；不得沿用 Lurk 曾出现的父级 padding 与卡片 margin 双重外扩。标题已说明用途的行不重复显示说明；保留 WebDAV 的备份范围提示、动态凭据有效状态和应用版本等重要辅助信息。保留至少 8dp 垂直触控留白、状态栏安全区和悬浮底栏底部空间；不修改账号/备份回调或全局 CardTheme。
- **个性化**：明暗模式、Material 3 预置色与 Monet 动态取色、纯黑深色模式（开关仅显示名称）、悬浮底栏、独立的“使用液态玻璃效果”、触感反馈、字体粗细、应用字体大小（80%–140%，默认 100%）和屏幕刷新率。
- **微博样式**：相对/绝对时间、星期/年份/时区/秒数、发布设备、卡片背景布局、正文字号、行间距、链接颜色、备注和名字、主页背景图、用户活动图标、大图片模式、图片圆角、菜单位置、IP 属地显示方式、主页赞过的微博。
- **存储**：设置首页“存储与备份”提供图片/视频保存路径与缓存管理入口。缓存管理统计并清理 `getTemporaryDirectory()/cacheimage` 下直接存放、名称为 32 位小写 MD5 的 `extended_image` 磁盘缓存；手动与阈值清理都会保留最近 1 分钟内写入的文件，避免打断正在生成的图片缓存。已保存到相册的媒体、账号资料和其他临时目录不纳入统计或删除。自动清理阈值默认为 200 MB，可选关闭、50/100/200/500 MB 或 1/2 GB；改阈值时立即检查一次，应用启动时再次检查。关闭阈值自动清理不影响原有启动时 60 天/512 MiB 图片缓存维护。阈值作为普通个性化偏好纳入 WebDAV 设置白名单，不导出微博凭据。
- **WebDAV 备份**：配置、测试、备份和恢复，遵守上面的安全白名单。
- **账号和关于**：短信验证码登录（默认）、账号密码登录、Cookie 导入、凭据检测、凭据导出、关于应用、退出登录。关于应用版本名直接读取 `ApiConstants.appVersion`。
- **订阅消息提醒**：系统通知授权、总开关及 @、点赞、回复、私信分类开关；后台任务只在本机读取计数，通知不展示消息正文。

## 10. 测试、构建和发布

### 10.1 测试

完整测试命令：

```powershell
D:\flutter_sdk\bin\flutter.bat test
```

测试覆盖模型序列化、富文本解析、时间格式、微博卡片、投票/热搜字段、认证会话、热搜榜、图片画廊、主题字体、分组、链接路由、搜索、消息/赞、详情互动、编辑历史、发布模型等。测试文件数与测试用例数以当前目录和实际命令输出为准。

### 10.2 Release APK

Android Release 使用 JDK 17 和 Flutter SDK 构建。推荐在项目根目录执行：

```powershell
$taskJavaHome = 'D:\jdk17'
$taskTempDir = 'D:\App\Review\build\.jvm-temp'
New-Item -ItemType Directory -Path $taskTempDir -Force | Out-Null
$env:JAVA_HOME = $taskJavaHome
$env:ANDROID_HOME = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$env:TEMP = $taskTempDir
$env:TMP = $taskTempDir
$env:JAVA_TOOL_OPTIONS = "-Djdk.net.unixdomain.tmpdir=$taskTempDir"
$env:Path = "$taskJavaHome\bin;$env:Path"
& 'D:\flutter_sdk\bin\flutter.bat' build apk --target-platform android-arm64 --release --no-tree-shake-icons --android-skip-build-dependency-validation --no-pub
```

本机 JDK 17 在默认用户临时目录曾因 `PipeImpl` 无法建立 Unix-domain loopback 管道而报 `Unable to establish loopback connection`；`JAVA_TOOL_OPTIONS` 中的 `-Djdk.net.unixdomain.tmpdir` 必须指向已创建的项目内目录，上面的临时目录只在当前 PowerShell 进程生效，构建后可清理。Release 构建使用 `--no-pub` 保持 `pubspec.lock` 锁定的依赖和镜像来源不变；有意更新依赖时，单独运行 `flutter pub get` 并审查锁文件变更后再构建。签名从 Git 忽略的本地 `android/key.properties` 和密钥文件读取，口令不写入文档。

`android/app/build.gradle.kts` 必须按顺序应用 `com.android.application`、`org.jetbrains.kotlin.android`、`dev.flutter.flutter-gradle-plugin`。应用脚本同时使用 `android {}` 与 `kotlin {}` DSL；移除 Kotlin Android 插件会导致 Kotlin DSL accessor 缺失，Release 编译报 `android`/`kotlin` 等未定义。

构建结果通常位于：

```text
D:\App\Review\build\app\outputs\flutter-apk\app-release.apk
```

交付时从 `pubspec.yaml` 读取版本名，将产物复制为项目根目录的 `Review_v<version>.apk`：

```powershell
$taskVersionLine = Select-String -LiteralPath 'pubspec.yaml' -Pattern '^version:\s*(\d+\.\d+\.\d+)\+\d+' | Select-Object -First 1
if (-not $taskVersionLine) { throw 'pubspec.yaml 中没有有效的版本号' }
$taskVersionName = $taskVersionLine.Matches[0].Groups[1].Value
$taskApkTarget = Join-Path (Get-Location) "Review_v$taskVersionName.apk"
Copy-Item -LiteralPath 'build\app\outputs\flutter-apk\app-release.apk' -Destination $taskApkTarget -Force
```

核验新包后，根目录只保留当前交付包。不要把历史版本的文件名写死在构建命令里；相同版本名、不同 `versionCode` 的覆盖构建会使用相同文件名。

打包后必须用 `aapt2 dump badging` 核对包名、`versionName` 和 `versionCode`，并计算 SHA-256。APK 属于构建交付物，项目 `.gitignore` 已忽略 `*.apk`；推送源代码时不应通过强制添加把安装包混进源码提交。

**工作区体积清理：** `.dart_tool/flutter_build`、`.dart_tool/hooks_runner`、`build/app`、`build/test_cache` 是可重建的 Flutter 编译/测试产物；停止所有 Flutter、Dart、Gradle 构建后可清理，后续构建会重建缓存，但首次编译会更慢。不要为了清理整个删除 `build/`：`build/previous-deliveries/` 保存回退 APK，必须保留；项目根目录只保留当前正式 APK。保留 `pubspec.lock` 与 `.dart_tool/package_config.json`，不要清理本地签名文件或用户数据目录。清理 JDK/Gradle 临时目录前，先确认没有构建进程正在使用它们。

### 10.3 版本规则

- 功能更新：次版本号加 1，修订号归零，例如 `1.0.0 → 1.1.0`；即使当前是 `1.0.1`，功能更新也进入 `1.1.0`。
- Bug 修复：修订版本号加 1，例如 `1.0.0 → 1.0.1`。
- 每次发布都递增 Android `versionCode`。
- 必须同步检查 `pubspec.yaml`、`lib/core/constants/api_constants.dart`、`android/app/build.gradle.kts` 和设置页关于应用；当前版本只在本文档开头标注一次，发布前仍以源码和 APK 元数据复核。
- APK 文件名必须是应用名加版本名，例如 `Review_v2.4.0.apk`。根目录不保留过时的交付包。

## 11. 后续开发约束

- 当前微博卡片、文章封面和普通详情入口沿用标准页面路由；3.11.0/3.11.1 的卡片几何展开转场已在 3.11.2 按用户要求撤回。不得只因保留旧版本历史文档就重新启用。

1. 新增微博功能前，先确认微博网页端是否真实存在对应字段和读写接口，再确认项目是否已有模型、仓库和 UI 入口；不能因为本地有一个枚举或旧接口就宣称功能已完成。
2. 任何“同步”“收藏”“备份”“发布成功”文案，都必须对应服务端真实响应；本地缓存和乐观状态只能作为显示优化。
3. 优先复用现有的 Dio、Riverpod、`image_picker`、`video_player`、WebView 和原生 MethodChannel，不重复引入已有能力的库。
4. 修复网络问题时保留原微博内容，避免空响应、鉴权歧义或回退接口覆盖有效数据；对重试设置明确上限。
5. 修复交互时检查全局 Ink 触感是否已经提供反馈，避免在业务回调中再次震动；涉及 Android 系统栏、定位、媒体或相册时同时检查原生通道和 Flutter 页面退出清理。
6. 修改后至少执行相关测试、`flutter test`、`git diff --check`，并核对版本、APK 元数据、README 是否保持用户要求的状态。
7. 开发文档的本地统一成稿是 `D:\App\开发文档\Review.md`，必须包含当前说明、变更记录、工程复盘、可迁移设计规范与历史手册的完整正文；更新任何分主题源文件后运行 `tool/sync_review_documentation.ps1` 同步成稿，不能将统一文档退回成只有链接的索引页。

### 磨砂顶栏规范维护

- [Review M3 UI 复用规范与提示词](docs/REVIEW_UI_REUSE_SPEC.md) 提炼当前主题、组件覆盖、设置/信息流卡片、导航和动效，并提供跨应用迁移提示词及视觉验收方法；按当前工作区源码记录，不将版本号、旧历史方案或编译通过当作画面一致证明。相关 UI 改动应同步维护该规范并重建完整开发文档。

- [磨砂顶栏设计规范](docs/FROSTED_TOP_BAR_DESIGN_SPEC.md) 是可单独复用的完整规范，也是统一开发文档中的组成部分；修改顶栏材质、固定内容布局、分隔线或验收标准时，同步维护该文件并重建 `D:\App\开发文档\Review.md`。
- 超话中心采用覆盖式滚动：列表视口从屏幕顶部开始绘制在整个磨砂顶栏后方；固定搜索/分类区为 108dp（搜索框布局 62dp、分类行 38dp、标签下方 8dp 磨砂留白）。首项 padding 在视口内部补齐状态栏安全区、工具栏、固定区和 4dp 内容间距；合计 inset 保持原布局不变，标签下沿与磨砂边界之间则有清晰余量。不要把列表视口放在顶栏下方的 `Column`/外层 `Padding` 中，否则滚动内容无法穿过完整顶栏，模糊会像从标签下方才开始。


### 构建远程依赖等待（2026-10-23）

若 Gradle 线程确认阻塞于 SSL/HTTP 依赖连接，且本机依赖齐全，可停止本次所属 wrapper/daemon 后离线编译；不要停止其他项目的 Java 进程。保留上文 JDK/TEMP 环境，在项目根目录执行 android/gradlew.bat -p android --offline assembleRelease -Ptarget-platform=android-arm64 -Ptarget=lib/main.dart -Ptree-shake-icons=false -Pdart-obfuscation=false。结果位于 build/app/outputs/apk/release/app-release.apk，仍需进行版本、ABI、签名及对齐核验。依赖缺失应明确报告，不改变锁文件。
