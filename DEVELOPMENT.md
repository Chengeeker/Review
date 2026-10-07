# Review 开发与技术架构文档

> 本文档是 Review 当前源码的开发说明，内容以代码和当前可验证的行为为准。文档更新日期：2026-10-07；当前应用版本：`3.0.0+156`。
>
> `README.md` 用于项目介绍；本文档维护当前实现，不记录登录 Cookie、Token、密码或其他凭据。

本地完整开发文档统一保存在 `D:\App\开发文档\Review.md`，完整汇入本说明、[变更记录](docs/CHANGELOG.md)、[工程复盘](docs/RETROSPECTIVE.md)和[磨砂顶栏设计规范](docs/FROSTED_TOP_BAR_DESIGN_SPEC.md)。本仓库保留这些分主题源文件以便版本管理；修改任一源文件后应运行同步脚本。截至 2026-09-23 的旧版综合手册已从当前汇编中移出，原件仍保存在 `docs/archive/Review-legacy-2026-09-23.md` 供追溯，不作为现行规则；当前行为以源码、测试和本文档为准。

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

- 主题、动态取色、纯黑模式、悬浮底栏、触感反馈、字体粗细调整、屏幕刷新率和预设应用图标。
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
3. **设置**：主题、微博样式、存储、账号和关于应用。

时间线顶部可以打开侧边栏、切换微博分组、进入搜索和快捷发布。标准页面统一使用 `ReviewFrostedAppBar`；设置首页不显示仅有标题、没有操作的独立顶栏，设置子页面仍保留标准返回顶栏。所有标准顶栏以及时间线、热搜自定义栏、超话详情 SliverAppBar 共用同一材质参数与 `ReviewFrostedBackdrop`：主题 AppBar 色（缺省时回退 Scaffold 背景色）以 alpha 0.45 直接设置在 AppBar Material；上方叠加同色纵向渐变，顶部 alpha 0.95、边界 alpha 0，顶端合成约 0.9725，状态栏一侧更接近不透明、越靠底部分界越透明；`forceMaterialTransparency` 关闭。模糊层按 `ClipRect → BackdropFilter(sigma 20) → 渐变 DecoratedBox` 的顺序直接绘制，不使用 `ShaderMask` 或独立 blur alpha 遮罩；顶部高不透明度色层遮住大部分模糊，向边界透明度渐增，因此模糊观感自然显现。不能仅凭 widget 中存在滤镜判断有效：在适用的页面上还需确认滚动内容确实延伸到顶栏后方。`ClipRect` 限定滤镜范围，不启用全屏 shader 或全局液态玻璃。不能只在 `flexibleSpace` 绘制底色，否则 AppBar Material 透明时部分页面会实际呈现透明。滚动结构安全的页面让内容延伸至顶栏下方，并为列表/滚动内容补回安全区与工具栏高度，使滚动内容经过顶栏时可见磨砂；分组管理、赞和收藏、关注/粉丝列表等使用此布局。超话中心的搜索框和固定分类栏属于顶栏组成，磨砂背景覆盖至分类栏下沿，滚动结果从该边界以下开始；底部边界由顶栏整体材质与下方内容的交界表达，该页关闭标签行下方额外的浅色细线，避免出现双重边界。除上述超话中心外，登录表单、聊天输入区、内嵌网页/视频、其他固定搜索栏或复杂 pinned sliver 页面保持原内容几何，仅复用顶栏材质，避免键盘遮挡、控件重叠和滚动位置变化。时间线分组下拉面板仍是独立的局部面板，不属于顶栏渐变；它使用同主题底色、82% 不透明度和 sigma 20 模糊，区域由 `ClipRRect` 限定。热搜列表首项仍预留状态栏、标题栏和分类 Tab 高度，空/加载状态居中布局不变。覆盖式顶栏下 EasyRefresh 的安全 inset 不得重复加到触发距离：`reviewFrostedAppBarRefreshHeader` 保持 70dp 阈值并只将 ClassicHeader 指示器下移至完整顶栏以下；全局默认 header 与非覆盖式页面行为不变。应用使用 Material 3，底部导航支持贴底栏和标准材质悬浮栏，可在个性化设置中开关悬浮底栏。可迁移至其他应用的顶栏设计、Flutter 实现步骤和防错验收清单见[磨砂顶栏设计规范](docs/FROSTED_TOP_BAR_DESIGN_SPEC.md)。

顶栏模糊只使用一个 sigma 20 的 `BackdropFilter`，由外层 `ClipRect` 限定范围；其 child 绘制固定 flexibleSpace 内容和纵向主题色渐变。不套 `ShaderMask`，也不指定 `BlendMode.src`。颜色层从状态栏侧 alpha 0.95 过渡至分界线侧 alpha 0；叠加 AppBar Material alpha 0.45 后，顶部底色合成约 0.9725 不透明，边界处保留 0.45。因为渐变色层覆盖在模糊结果上，状态栏侧只透出极少背景，边界侧磨砂更明显；这是颜色叠层带来的视觉变化，不是第二个模糊遮罩。

### 2.2 时间线和微博卡片

- 登录后先读取 `/ajax/feed/friendstimeline`；首屏请求失败或为空时，才尝试 `/ajax/feed/unreadfriendstimeline` 作为当前代码的兼容回退。两者都无内容时，只有没有完整 Cookie 的访客才回退公开热门流；已有完整 Cookie 的账号不把公域内容伪装为关注流。
- 支持微博已有的“全部关注”“特别关注”“好友圈”以及微博账号已有的个人分组和热门频道。应用不会把本地虚构分组当成微博云端分组，分组管理页对不能写入官方的本地新分组会明确提示不支持。
- 首页首次请求遇到空响应时只做一次短延迟重试；刷新得到空响应时不覆盖已有内容，避免短暂网络问题把可用时间线替换为“暂无微博内容”。加载更多使用 `max_id` 继续向历史分页，并做去重和屏蔽用户过滤。
- 卡片支持微博文本、富文本链接、表情、图片九宫格、视频、Live Photo、投票、超话标识、橙色热搜话题、转发微博、长文展开和操作菜单。
- 超过 9 张配图的列表卡片（含转发、主页和浏览记录）固定显示前 9 张，第 9 张叠加深色蒙层与 `+剩余数量`；点击该格从第 9 张进入完整画廊，不展开列表、不显示图片“展开全文”。详情仍直接显示全部图片，画廊始终接收完整列表。`continue_tag` 不作为长文字标记；旧快照误标长文且超过 9 图的短正文少于 140 字、没有省略号/展开标记、也没有全文数据时，列表不显示无依据的文字展开入口，源端全文补全与详情补取不变。已标记长文默认保留微博 `text_raw` 预览；只有标准化全文实际更长时显示“展开全文”，点击后才展开，主微博和转发微博一致。文字展开按钮放在正文与附件内容下方，只控制文字。`pic_ids` 有完整 PID 但 `pic_infos` 只含前 9 张时，用已有 PID 图片地址回退保留后续图片。详情和列表补全以桌面配图顺序为准，并合入移动端独有图片；生日/荣誉卡片继续按图层合并规则处理。
- 可见范围行（详情页始终预留；普通卡片仅非公开微博显示）保持 24dp 固定布局槽，图标和文字在槽位内上移 4dp，增加与作者头像的视觉间距，不改变卡片总高度。
- 微博头像、图片网格、视频封面、搜索/超话图片等网络图片统一复用 `extended_image` 的磁盘缓存；同一完整 URL 命中缓存时，应用重启后可从临时缓存读取，不保证不同尺寸、域名或查询参数的 URL 共享缓存。启动后异步整理 `getTemporaryDirectory()/cacheimage`，仅处理该目录下 MD5 命名的缓存文件：超过 60 天或总量超过 512 MiB 时按文件修改时间从旧到新清理，跳过最近 1 分钟写入的文件。不会清理已保存到相册的媒体、账号资料或其他临时目录。系统仍可自行清除临时缓存；图片显示加载占位不等于实际重新下载。
- 微博自动生成的荣誉/会员/活动网页卡片，会识别官方 `url_objects[].object.object` 的 `pic_url`/`image.url`，以及桌面时间线/详情中的 `url_struct`（`url_type=39`）经移动端状态接口补充的 `page_info.page_pic`。这类卡片可能由透明前景图和 `media_pic_url`/嵌套 `pic_info.pic_big` 背景图组成；分层卡片的列表比例优先采用背景画布的宽高，缺少尺寸时按常见横向卡片比例回退，避免拿透明前景的窄长尺寸裁切整张卡片。列表图层使用等比完整显示，透明卡片使用白色画布，详情画廊也等比完整显示。对应短链接从正文中移除，点击卡片只打开渲染后的图片，不再跳回个人主页。主页解析使用最多 6 路并发和按微博 ID 的内存缓存，避免这些卡片逐条串行请求。带真实视频播放地址的卡片仍走视频播放器，超话等普通主题卡片不转成图片。
- 投票微博保留现有原生选项卡和投票交互，不将投票链接的占位封面/投票图表加入图片网格。按同条微博解析出的 `WeiboPollModel` 与该网页卡片自身的 `type/object_type/title/投票 URL` 关联判定；只过滤相匹配的投票网页缩略图，不因微博中存在投票就清除 `pic_infos` 里的真实配图，也不影响文章封面、生日/荣誉卡片及非投票链接。
- 微博文章封面与自动动态图片区分：从官方文章链接或明确的 article 对象提取文章 ID，封面模型保留 `articleUrl/articleTitle`，点击复用已有 `WeiboArticlePage` 原生阅读页；兼容桌面 `/ttarticle/p/show` 与移动 `/article/m/show/id/`，不将外站或普通网页对象猜成文章。链接图片、`url_objects`、`page_info` 及浏览记录快照使用同一规则；旧快照同地址封面补上目标而不重复图片。只有点击封面才请求文章内容，生日/夺金卡片继续打开图片画廊。
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

- 搜索建议使用微博 `/ajax/side/search?q=...`；用户精确匹配必要时使用 `/ajax/profile/info?screen_name=...`。
- 微博搜索优先读取网页搜索页 `https://s.weibo.com/weibo?q=...`，解析网页卡片后再用 `/ajax/statuses/show` 补齐状态；接口失败时才回退到 `/ajax/statuses/search`。
- 话题搜索使用微博建议接口的 `type=topic` 数据；超话选择使用 `/ajax/stopic/list?keyword=...&page=...`。
- 热门搜索使用 `/ajax/side/hotSearch`，必要时回退 `/ajax/statuses/hot_band`，保留官方返回顺序，并把官方置顶数据放在列表顶部。
- 热搜分类使用官方接口映射：我的、热搜、文娱、社会、科技、生活、体育、ACG。没有对应网页端接口的分类不使用本地拼接或伪造榜单。
- 微博热搜榜保留官方置顶标记、排名颜色、火焰排名标记和不在排名内的定位热搜标记。定位热搜使用实心点替代排名数字，并显示定位标识。
- 热搜页重新点击已选中的底栏“热搜”会平滑回到当前分类顶部；双击会回顶并仅重新请求当前选中分类。热搜页顶栏双击在列表离顶时回顶，在顶部时刷新当前分类，不会同时刷新隐藏的其他分类。
- 榜单前三不再额外使用特殊粗体；排名框、火焰图标和颜色仍按官方数据保留。词条、序号和顶栏分栏字重统一接受应用的字体粗细设置，顶栏只保留选中/未选中的相对层级，避免全局调到最粗时层级反转。
- 搜索页热门搜索支持双列和单列切换。双列展示前 9 条，单列展示前 10 条；两种布局都保留“更多热搜”入口。单列使用与双列相同的字号并增加行间距。热门搜索不再对前三条单独加粗，所有文字跟随全局字体粗细设置，但排名颜色和官方排名图标保留。

### 2.4 微博详情、互动和用户页面

- 详情页读取长文、状态详情、转发列表、评论列表、二级评论、点赞列表、评论图片和编辑历史。
- 评论支持发表评论、回复、删除自己有权限删除的评论；评论列表支持刷新和分页。
- 一级评论中的楼中楼只作为首段预览渲染；当接口返回回复总数时显示“共 N 条回复”入口，点击后打开独立的回复面板。回复面板调用微博网页端的 `/ajax/statuses/buildComments`，使用 `fetch_level=1`、首请求 `max_id=0`，并严格沿用服务端返回的外层 `max_id` 分页游标和 `is_mix` 续页标记，直到没有更多回复；不会把首段通常只有两三条的 `comments` 数组当成完整楼中楼。面板底部同时提供明确的“加载更多回复”入口，避免只有少量预览行时无法触发滚动分页。
- 回复面板中的头像、昵称、认证/博主标签、时间/IP、正文、图片和点赞数按回复数据渲染；右侧点赞数和图标使用固定操作列，避免昵称、认证标识或数字长度造成位置偏移。点击回复整行或正文都打开现有回复操作菜单，@、话题和链接仍保留各自的跳转行为。
- 评论和楼中楼回复均使用微博返回的用户头像、昵称和认证信息；当评论/回复用户 UID 与当前微博作者 UID 一致时显示“博主”标签，不根据昵称本地猜测身份。评论、完整楼中楼和“收到的评论”列表还会读取评论用户的 `user.fansIcon.icon_url`（兼容 `fans_icon`）并显示微博返回的铁粉等级图标；直接复用带磁盘缓存的图片组件，不新增评论接口或补查用户资料。不同等级的底色/图案以微博提供的图标资源为准，不本地重绘；接口未返回铁粉图标时不推断等级。微博[官方铁粉等级说明](https://kefu.weibo.com/faqdetail?id=21662)确认标识可在博主正文页评论区显示，若评论本身已有超话等级标识则两者只显示其一，客户端以接口实际返回为准。
- 点赞、取消点赞、收藏、取消收藏、转发入口和删除操作都以微博响应成功为准，界面中的即时变化属于乐观显示，失败时回滚或提示。
- 消息中心的群聊按消息时间正序显示，较早消息在上、最新消息在下；首次打开定位到最新消息。群聊顶部下拉调用 `query_messages.json` 的 `max_mid` 读取更早历史，不再把固定首屏请求当成刷新，也不在上拉方向加载旧消息。私信维持原有独立会话路径。
- 群聊列表、群信息和群成员页预热会话用户缓存，供聊天页首帧复用头像与昵称；完整群公告另由 `query_user_bulletin.json` 读取，不能仅依赖可能截断公告的 `query.json`。
- 消息中心的未读清除基线持久化，避免重新拉取 contacts 后旧数恢复；打开某个私信/群聊会话时只将该会话标为本地已读，其他会话角标保留，新消息仍从 1 开始累计；打开 @、赞、收到的评论分类时只清除对应分类的本地计数，不会打开“我的消息”总览就一并清掉所有消息。会话未读数只显示在各自头像右上角，群免打扰气泡灰显，并排除于侧边栏聚合数与后台私信通知。“私信与群聊”标题不展示接口 `totalNumber`，以免清除后留下无法清理的误导总数。侧边栏聚合数来自 `/ajax/remind/unread` 与 WebIM contacts，前者是网页兼容接口且响应可能变化，解析失败时保留上次数值。Android 后台通知经 WorkManager 联网周期轮询（至少 15 分钟，实际可能更晚），首次轮询仅建立基线、不提示历史未读。
- 聊天发送不再把任何 HTTP 2xx 都显示成已送达：检查业务响应并回读服务器会话；若无法确认，不显示合成气泡。`/webim/groupchat/send_message.json` 与 `/webim/2/direct_messages/new.json` 是未由微博公开接口契约/测试账号确认的兼容请求，本项目不使用用户账号发送测试消息。
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
- `ThemeProvider` 与 `WeiboStyleProvider` 分别维护应用主题、悬浮底栏开关、触感/字体/刷新率和微博卡片排版偏好。主题支持明暗模式、Material 3 预置色与 Android Monet 动态色。
- 页面层只根据状态渲染；服务端操作完成后再更新状态。网络失败、未登录或服务端未返回字段时，需要保留可解释的错误/空状态，而不是创建本地假数据。

## 6. 网络、会话与接口边界

### 6.1 基础地址和会话

```text
微博网页端:   https://weibo.com
微博登录:     https://passport.weibo.com
微博移动端:   https://m.weibo.cn
```

`WeiboDioClient` 负责 Cookie、XSRF、请求头和响应错误处理；`VisitorTokenEngine` 负责未登录公开内容所需的访客 Sub Token。网页登录产生的 Cookie 只保存在本地会话存储，不写入开发文档、不进入个性化备份。

认证失败处理包括 XSRF 刷新和有限重试。401/432 等鉴权响应最多进行受控重试，不允许拦截器递归重试；凭据检测的模糊失败显示“暂时无法验证”，只有服务端明确失效时才显示失效状态，避免“检测失效—自动登录—再次检测失效”的循环。

### 6.2 主要接口矩阵

以下是当前代码实际使用的接口类别；接口字段可能随微博网页端变化，新增调用必须先核对网页端响应，不得只根据本地模型名称推断成功。

| 功能 | 当前接口 |
| --- | --- |
| 关注流/热门流/分组流 | `/ajax/feed/friendstimeline`；首屏失败或为空时尝试 `/ajax/feed/unreadfriendstimeline`；访客可回退 `/ajax/feed/hottimeline`；分组使用 `/ajax/feed/groupstimeline`、`/ajax/feed/allGroups` |
| 用户微博/状态详情/长文/编辑历史 | `/ajax/statuses/mymblog`、`/ajax/statuses/show`、`/ajax/statuses/longtext`、`/ajax/statuses/editHistory` |
| 发布/编辑/删除 | `/ajax/statuses/update`、`/ajax/statuses/modify`、`/ajax/statuses/destroy` |
| 评论/回复/二级评论 | `/ajax/statuses/buildComments`（一级评论使用 `fetch_level=0`，楼中楼使用 `fetch_level=1`，均使用响应外层 `max_id` 分页）、`/ajax/comments/create`、`/ajax/comments/reply`、`/ajax/statuses/destroyComment` |
| 点赞/收藏 | `/ajax/statuses/setLike`、`/ajax/statuses/cancelLike`、`/ajax/statuses/createFavorites`、`/ajax/statuses/destoryFavorites` |
| 投票/投票结果 | `/ajax/statuses/setVote`、`m.weibo.cn/api/statuses/show`，网页结果读取回退 `/ajax/statuses/show` |
| 关注关系/关系列表 | 桌面端 `/ajax/friendships/create`、`/ajax/friendships/destroy`；移动端取消关注兼容路径拼作 `/api/friendships/destory`。关系列表使用 `/ajax/friendships/friends?uid=<uid>&page=<page>`；粉丝列表额外使用 `relate=fans` 和 `type=fans`，不附加 `fansSortType` 或本地数量参数，禁止把默认关注响应当成粉丝响应 |
| 关注的超话 | `/ajax/profile/topicContent?tabid=231093_-_chaohua&page=<page>`；请求通过关注页 Referer 指定目标 UID，列表必须来自 `data.list` 等真实列表字段 |
| 私信/群聊 | `/webim/2/direct_messages/conversation.json`、`/webim/groupchat/query_messages.json`；群聊首屏使用 `max_mid=0`，顶部历史使用当前最早消息的 `max_mid`，本地按消息时间统一升序渲染 |
| 热搜/建议/搜索 | `/ajax/side/hotSearch`、`/ajax/statuses/hot_band`、`/ajax/side/search`、`/ajax/statuses/search` |
| 地点/超话/电影 | `/ajax/statuses/place`、`/ajax/stopic/list`、`/ajax/movie/hot_top` 或 `/ajax/movie/hot_search` |
| 发布配置/内容声明 | `/ajax/getSpaConfig`、`/ajax/statuses/config` |
| 图片/视频发布媒体 | `picupload.php`、`/ajax/multimedia/mediaGroupInit`、`/ajax/multimedia/dispatch` 及分片完成校验接口 |
| 独立微博视频播放 | 优先使用状态响应 `url_objects[*].object.object.urls` 中的官方签名 CDN 媒体地址；没有直接地址时使用 `https://h5.video.weibo.com/api/component?page=/show/{fid}`（显式 POST 表单字段 `data`，其值为包含 `Component_Play_Playinfo.oid` 的 JSON，并带 `PAGE-REFERER: /show/{fid}`；先公开请求，失败后回退登录会话） |

网页 HTML 解析、移动端状态接口和网页 Ajax 接口均是兼容层。优先使用能返回当前真实状态的网页端接口；回退请求只能用于补齐同一条状态或兼容旧响应，不能把回退结果混成另一条内容。

## 7. 交互、手势和原生通道

### 7.1 Material 3 与触感

- 个性化页面提供跟随系统/浅色/深色、纯黑深色、Material 3 预置主题色与 Monet 动态取色选项。关闭动态取色时使用用户选定的预置色；打开后使用 Android 提供的动态色，未提供时回退到预置色。
- 底部导航使用 Material 3，可在贴底栏与标准材质悬浮栏之间切换。历史 Miuix/玻璃材质偏好不再读取或导出；升级后按“使用悬浮底栏”开关渲染对应的 Material 3 样式。
- Material 水波纹通过 `HapticSplashFactory` 提供全局一次轻触；业务回调会消费同一次手势的自动反馈，不会重复震动。取消点击不会额外触发，Live 图播放/暂停按钮使用普通水波纹并只在动作入口触发一次轻触。
- 触感工具保留约 40ms 的硬件抖动冷却，并使用 300ms 的同手势消费窗口，避免全局反馈与业务反馈叠加；没有 Material 水波纹的 GestureDetector 仍可由业务回调独立触发。公共头像组件的点击入口会消费全局水波纹反馈，确保只触发一次轻触；微博正文 `@用户` 使用内联点击识别器，因此在其跳转回调中调用 `HapticFeedbackUtil.light()`，遵守全局触感开关和防重复规则；所有下拉刷新入口统一通过 `HapticFeedbackUtil.refresh` 触发一次轻触。发布页定位按钮不再在业务方法开头重复触发轻触；成功选中地点后仅保留一次中等反馈。
- 公共头像点击区域至少为 48dp，并声明头像按钮语义；头像占位符按 Unicode code point 取首字符。Toast 根据安全区和键盘高度调整位置，并通过 live region 向读屏器公布内容。
- 搜索页与热搜榜共用 `HotSearchBadge`；搜索页嵌套的热搜 ListView/GridView 显式使用零 padding，避免默认继承顶部安全区而在榜单卡片内产生空白；设置首页使用私有 `_SettingsSectionCard`，设置子页及其他分组页面继续使用 `AppSectionCard`。统一使用 `showAppDialog` 的确认弹窗，设置/存储路径底部菜单使用主题的圆角、背景和拖动条。
- 时间线底栏单击支持回顶/返回上次位置，双击回顶并刷新；时间线顶栏双击支持回顶和二次刷新。
- 热搜底栏再次单击回到当前分类顶部，双击回顶并刷新当前分类；热搜顶栏双击不在顶部时回顶、已在顶部时刷新当前分类。手势使用现有的 300ms 单/双击判定，不新增依赖。
- 用户主页顶栏也使用相同的双击判定：不在顶部时双击平滑回顶，已经在顶部时再次双击刷新当前用户微博；单击不改变原有标题、搜索和分享操作。
- 文章详情顶栏支持双击平滑回到文章顶部，单击不改变返回键和更多操作。

### 7.2 图片画廊

顶部返回、页码/Live Photo 和下载控件与底部缩略条共用所在路由的动画状态：push 期间透明且不可交互，路由进入 completed 后以 140ms 淡入；pop 一开始立即禁用点击并淡出。顶部按钮含 `BackdropFilter` 和 fragment shader，禁止把整组按钮包进 `Opacity`/`AnimatedOpacity` 透明合成层，以免磨砂滤镜采样到黑色中间层；应分别渐变按钮图标透明度、玻璃底色和模糊强度。该处理只作用于叠层控件，不改变 Hero 尺寸、主图 PageView 视口/约束、定位几何或图片手势。

`ImageGalleryPage` 支持双击放大、捏合缩放、横向分页、Live Photo 播放切换、下载原图/Live 视频和合并保存到系统相册。Live Photo、普通视频和 GIF 必须互斥分类：实际非 GIF 的 `video_url`、`videoUrl` 或 `video` 字符串/URL 字段才进入视频播放器；视频类型标记本身不能启动一个缺少播放地址的空播放器。GIF 按媒体类型或图片 URL 扩展名识别；当没有真实视频直链时，GIF URL 优先于冲突的旧 `fid`/Live Photo 元数据，继续作为图片画廊资源显示。只有明确 Live Photo 元数据、`livephoto_video` 或 `/livephoto/` 媒体地址且资源不是 GIF 时才走手动播放控制器。进入 Live Photo 默认暂停，顶部按钮负责播放/暂停。

- 从微博图片网格点击普通图片时，通过 Flutter `Hero` 将对应缩略图连续放大到全屏画廊；返回时反向缩回来源位置。配对标识按来源网格实例、媒体下标和图片身份生成，只有当前画廊页挂载 Hero，避免缓存邻页一起飞回。普通图片回程读取两端实际 `ExtendedRenderImage` 或 `RenderImage` 的解码像素、fit、alignment、布局变换及圆角；手势图使用已绘制的 destinationRect/layoutRect 保存当前缩放和平移，先去除绘制偏移再映射到 Hero 坐标。冻结完整图片平面后，逐帧插值图片四边与裁切圆角，让图片在途中逐渐收敛到来源的实际 cover 区域；不再重新布局手势子树并叠加统一缩放。临时 image.clone() 只共享既有像素句柄，飞行卸载即 dispose，不新增请求或缓存。未解码时保持原子树回退；自动网页卡片保留完整显示分支，视频不参与该 Hero。现有路由、分页、滚轮和媒体生命周期不变，无新增动画依赖。回归使用正式画廊路由及 ExtendedRawImage，对横图/竖图和放大平移状态逐像素比较回程起点与圆角目标；设备观感仍须真机复测。
- 所有多图/混合媒体画廊（2 项及以上，不限于超过 9 张）显示横向缩略图滚轮：当前项正常显示并有白边，其他项覆盖半透明白色蒙层，视频叠加播放图标。缩略图仅限制解码宽度 160px、高度按原图比例计算，再以 `BoxFit.cover` 裁切。滚轮使用 `ClampingScrollPhysics` 和关闭逐页吸附；手指拖动及松手后的惯性期间，主图直接镜像滚轮的连续页位置，不把多页变化放入逐页动画队列，因此快滑到末尾时主图不会在后面慢慢追赶。主图每次跨过一张图时触发 `HapticFeedbackUtil.selectionTick()`；该滚动专用触感使用 12ms 节流，不改变全局普通操作 40ms 节流。停稳时主图和滚轮同步用 `easeOutCubic` 在 120ms 内吸附到最近项；滚动期间暂停视频/Live Photo 的激活，最终选中后才恢复，避免快滑时逐个初始化媒体。主图手动翻页会接管同步并打断旧滚轮惯性。缩略条位于底部安全区上方 32dp，高 64dp；`ExtendedImageGesturePageView` 始终使用全屏视口，顶栏和缩略条只叠加在图片上层。控件显隐不再改变视口尺寸，因此不会重置图片缩放、平移或中心位置。缩略条监听所在路由动画：push 期间透明且不可交互，路由动画完成后以 140ms 淡入；pop 状态一开始即透明并禁用命中，再于退场过程中淡出。这个动画只包围缩略条，不改变 Hero 尺寸、主图 PageView 视口/约束、定位几何或图片手势。手势缩放最低为 fit 尺寸 1.0，避免缩到适配尺寸以下后重置居中造成多余空白；统一居中初始对齐以保留手指焦点缩放。单项不显示缩略条；单张静态图片按整个屏幕居中。收起控件时只隐藏叠层，继续惰性构建、复用缓存，不预加载全部原图/视频。
- 图片夹视频复用现有 `WeiboVideoPlayerPage` 的嵌入模式，不另写播放器：从网格点击图片或视频进入同一完整媒体顺序；当前项为视频时使用真实视频地址播放，非当前视频只展示封面。显式当前下标通知确保分页保留的屏外子项也卸载播放器，初始化回调检查 mounted 和控制器身份，避免切走后后台自动播放。嵌入模式不重复显示返回栏、不修改画廊屏幕方向；单视频仍可独立打开。播放器横滑进度手势移除，横滑交给画廊切换内容；进度条、双击快进/快退及纵滑亮度/音量继续保留。离开视频后释放播放资源，视频保存使用视频地址而不是封面。
- 图片自身不再因斜向滑动误触发“滑出销毁”；单指横向分页由页面处理。
- 画廊主图视口始终覆盖整个屏幕；顶栏按钮在状态栏安全区内叠加，缩略条在底部安全区上方 32dp 叠加。显示或隐藏这些控件不会重新约束主图，因此图片保持当前屏幕位置、缩放和平移；单张静态图片也按整个屏幕居中。
- 返回和下载按钮各为 44dp 圆形半透明灰色玻璃控件，保留 48dp 点击区域，带柔和的浅色高光描边。Impeller 上仅在圆形裁切内以 `BackdropFilter` 轻微模糊并用局部 fragment shader 作凸面折射；shader 用空气/玻璃折射率与球冠法线的 Snell 角计算位移，并限制在 0.45 个 shader 单位内。不会逐帧截屏或处理全屏纹理；shader 不支持或加载失败时回退到原生模糊和描边。
- 预览屏幕按宽度分为左、中、右三等份：点击中间区域切换清屏，点击左右区域退出预览。
- 清屏时隐藏返回键、页码/Live 状态、下载按钮和 Android 顶部状态栏；再次点击中间区域恢复。系统底部导航栏保持可用。
- 退出时恢复 edge-to-edge 状态。由于目标 SDK 为 36，顶部状态栏通过 `MainActivity` 的 `WindowInsetsController` 原生通道控制，不能只依赖 Flutter 的 `SystemUiMode.manual`。

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
- 备份文件包含应用主题（明暗模式、动态取色、M3 主题色和悬浮底栏开关）、微博样式、分组偏好、媒体存储路径、搜索历史等允许导出的个性化设置。
- 明确不导出：微博 Cookie、SUB/SUBP、访问 Token、登录标记、UID/昵称/头像等账号凭据，以及 WebDAV 密码。
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

## 9. 设置页当前范围

- **设置首页布局**：主设置页不显示仅有“设置”标题的独立顶栏，内容在状态栏安全区外再留 20dp 顶部间距；各设置子页面保留可返回的磨砂顶栏。
- **设置首页视觉**：分为“偏好与功能”“存储与备份”“账号设置”“关于与支持”，沿用 `ReviewPreferenceTile` 与页面私有 `_SettingsSectionCard`；设置行标题使用当前主题 `titleMedium`（Material 3 默认 16sp），分组标题使用 `titleSmall`（默认 14sp），辅助内容使用 `bodyMedium`（默认 14sp），不再硬编码更大的字号或覆盖主题文字样式。图标与箭头 24dp；卡片零默认外边距、低层级 `surfaceContainerLow`（纯黑主题使用 `surfaceContainer`）、24dp 圆角且无阴影/描边。卡片内分割线缩进 56dp，对齐文字起点（屏幕坐标 72dp = 页面外边距 16dp + tile 内边距 16dp + 24dp leading + 16dp gap）；不得沿用 Lurk 曾出现的父级 padding 与卡片 margin 双重外扩。标题已说明用途的行不重复显示说明；保留 WebDAV 的备份范围提示、动态凭据有效状态和应用版本等重要辅助信息。保留至少 8dp 垂直触控留白、状态栏安全区和悬浮底栏底部空间；不修改账号/备份回调或全局 CardTheme。
- **个性化**：明暗模式、Material 3 预置色与 Monet 动态取色、纯黑深色模式（开关仅显示名称）、悬浮底栏、触感反馈、字体粗细和屏幕刷新率。
- **微博样式**：相对/绝对时间、星期/年份/时区/秒数、发布设备、卡片背景布局、正文字号、行间距、链接颜色、备注和名字、主页背景图、用户活动图标、大图片模式、图片圆角、菜单位置、IP 属地显示方式、主页赞过的微博。
- **存储**：图片/视频保存路径和本地历史数据；当前不提供“退出时自动清理缓存”或“立即清理缓存”入口。
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

### 10.3 版本规则

- 功能更新：次版本号加 1，修订号归零，例如 `1.0.0 → 1.1.0`；即使当前是 `1.0.1`，功能更新也进入 `1.1.0`。
- Bug 修复：修订版本号加 1，例如 `1.0.0 → 1.0.1`。
- 每次发布都递增 Android `versionCode`。
- 必须同步检查 `pubspec.yaml`、`lib/core/constants/api_constants.dart`、`android/app/build.gradle.kts` 和设置页关于应用；当前版本只在本文档开头标注一次，发布前仍以源码和 APK 元数据复核。
- APK 文件名必须是应用名加版本名，例如 `Review_v2.4.0.apk`。根目录不保留过时的交付包。

## 11. 后续开发约束

1. 新增微博功能前，先确认微博网页端是否真实存在对应字段和读写接口，再确认项目是否已有模型、仓库和 UI 入口；不能因为本地有一个枚举或旧接口就宣称功能已完成。
2. 任何“同步”“收藏”“备份”“发布成功”文案，都必须对应服务端真实响应；本地缓存和乐观状态只能作为显示优化。
3. 优先复用现有的 Dio、Riverpod、`image_picker`、`video_player`、WebView 和原生 MethodChannel，不重复引入已有能力的库。
4. 修复网络问题时保留原微博内容，避免空响应、鉴权歧义或回退接口覆盖有效数据；对重试设置明确上限。
5. 修复交互时检查全局 Ink 触感是否已经提供反馈，避免在业务回调中再次震动；涉及 Android 系统栏、定位、媒体或相册时同时检查原生通道和 Flutter 页面退出清理。
6. 修改后至少执行相关测试、`flutter test`、`git diff --check`，并核对版本、APK 元数据、README 是否保持用户要求的状态。
7. 开发文档的本地统一成稿是 `D:\App\开发文档\Review.md`，必须包含当前说明、变更记录、工程复盘、可迁移设计规范与历史手册的完整正文；更新任何分主题源文件后运行 `tool/sync_review_documentation.ps1` 同步成稿，不能将统一文档退回成只有链接的索引页。

### 磨砂顶栏规范维护

- [磨砂顶栏设计规范](docs/FROSTED_TOP_BAR_DESIGN_SPEC.md) 是可单独复用的完整规范，也是统一开发文档中的组成部分；修改顶栏材质、固定内容布局、分隔线或验收标准时，同步维护该文件并重建 `D:\App\开发文档\Review.md`。
- 超话中心采用覆盖式滚动：列表视口从屏幕顶部开始绘制在整个磨砂顶栏后方；固定搜索/分类区为 108dp（搜索框布局 62dp、分类行 38dp、标签下方 8dp 磨砂留白）。首项 padding 在视口内部补齐状态栏安全区、工具栏、固定区和 4dp 内容间距；合计 inset 保持原布局不变，标签下沿与磨砂边界之间则有清晰余量。不要把列表视口放在顶栏下方的 `Column`/外层 `Padding` 中，否则滚动内容无法穿过完整顶栏，模糊会像从标签下方才开始。
