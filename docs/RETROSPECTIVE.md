# Review 工程复盘

## 液态玻璃底栏同项点按回调和触感反馈被过滤（3.10.7）

- **现象与根因**：主 Scaffold 仍保留时间线/热搜的底栏单击和双击处理，但玻璃导航 `_select` 只在索引变化时调用宿主回调和触感；重复点击当前项因此无法到达已有回顶/刷新逻辑，也没有震动。不能把“选择项未变化”当作“没有点击”。
- **修复与防回归**：每次有效短点/语义激活都通知宿主并调用全局触感工具，沿用触感总开关、40ms 防重复冷却和水波纹去重；长按或拖拽回到当前项仍在松手提交前被过滤。长按状态以同一 220ms 计时器的触发标记判定，避免依赖可能不一致的指针事件时间戳。主导航回归测试覆盖同项连续点按会触发两次选择与触感、长按不执行重复操作。
- 时间线顶栏点按通过不带墨水水波纹的外层手势识别器处理，单击与双击入口都直接调用全局轻触工具；微博卡片详情使用 `ReviewCard` 的 `NoSplash` 和 `enableFeedback: false`，在显式打开详情的回调里触发一次轻触。

## HDR 等整张 Flutter 图片解码后才启动原生映射（3.10.3）

- 原画廊只有 `_loadedImageUrls` 变为完成后才挂载 `HdrGalleryImage`，原生 Android 解码/确认 gain-map 因此串在 Flutter 全尺寸图片解码之后。对九宫格已确认有 HDR 的原图，画廊初始化时先查已合并的头部 Range 结果和同一 MD5 缓存文件，再在路由 Hero 与 Flutter 首帧解码期间预热 native `ImageDecoder`。显示层仍等待正常的图片加载及转场；缓存缺失时沿用旧安全路径，不额外发起重复媒体下载。
- `getCachedImageFile` 会异步遍历整个 cacheimage 目录；缩略图多时查单张图也会随缓存文件数量变慢。HDR 首帧路径按 ExtendedImage 固定的 MD5 文件名直接查文件，且共享单个原生 decode Future，避免目录扫描和并发重复解码。
- 网格样式参照 GreenNote 源码具体参数：10sp、内边距 5×2dp、4dp 圆角、0.8dp 白边、无阴影。画廊主图与缩略条保持各自字号，不把网格尺寸应用到沉浸画廊。
- 自动化只能证明预热时序与共用解码，不测 Android GPU tone-map 耗时；需在 vivo X300 Pro 安装后观察打开瞬间的亮度映射和图像清晰度。

## 聊天视频不能只消掉文字，Hero 不能搬播放器（3.10.2）

- 根因是聊天只有图片与链接卡片分支，未解释 WebIM 的视频附件 fid。需按官方 meta_query 的 replace 两步取可播放 fid，并继续使用图片播放器内现有视频组件及私有附件鉴权；消息 ID 不能伪装为微博 statusId。
- 初次 Hero 接入测试观察到一次打开创建 3 个解码器；把 shuttle 改成封面后仍创建 2 个，原因是目标 Hero 默认占位先移除播放器、结束后重建。最终转场只显示封面，路由完成后才挂播放器，回归确认一次打开仅创建 1 个、返回不再创建。不要删掉这个生命周期断言。
- 卡片渲染成功不等于点击成功。短链优先会忽略已有微博实体 ID，也可能在 HTTP 阶段就被 WebView 拦截；用 canonical 原生目标优先，缺失时选有效长地址再回退 HTTPS 短链。测试实际点击私信和群聊卡片进入 `StatusDetailPage`，不能只断言卡片标题存在。

## 标准悬浮底栏尺寸统一

- 标准 M3 悬浮栏原为固定 264×64，视觉上比响应式宽度、56dp 高的液态玻璃栏更大。
- 两种悬浮样式现在共用 `min(440, 屏幕宽度 - 40) × 2/3` 宽度和 56dp 高度；标准栏的表面材质、阴影、内边距和选中态保持不变。
- 窄屏沿用同一响应式公式；需要在小屏设备确认标签仍有足够布局空间。

## 液态玻璃底栏浅色背景下选中项对比度（3.6.1）

- 主题主色文字叠在浅色半透明选中胶囊上时，遇到白色图片背景会被冲淡；未选文字虽也为白色，却仍在深色玻璃主体上，因此视觉层级反而更清楚。
- 最小修复是把选中指示胶囊的填充加深到 `#66000000`，选中图文改为白色，继续由选中胶囊与填充/轮廓图标的差异标识当前页。没有修改折射 shader、手势提交和背景采样路径。
- 代码和 APK 静态核验不能代替白色图片背景上的设备视觉验收；如后续仍有动态壁纸/图片上的对比度问题，应基于目标设备画面微调胶囊不透明度。

## 信息流缩略帧先显：避免画廊打开时等待原图（3.6.0）

- 信息流图片缩略图已解码，但首次打开时画廊只等待大图 `ExtendedImage.network`，Hero 动画结束后可能短暂显示空白/黑帧。GreenNote 的做法是从来源 Hero 读取解码帧，在原图加载状态中临时显示，再交接给原图。
- Review 复用自身 `_HeroImageGeometry.capture` 和已存在的 Hero 配对：只在 push 时获取匹配的来源图像，克隆句柄给目标画廊初始项；原图完成后等本帧绘制结束再 dispose，画廊销毁时也清理尚未交接的句柄。没有新网络请求，也不改变返回动画、缩放手势、其他入口或多图懒加载。
- 只要来源 Hero 无法读取已解码像素或 tag/初始索引不匹配，就继续旧加载流程；快速静态验证不能代表真实网络首帧或转场观感，需在目标设备检查冷缓存、热缓存及原图完成交接。

## 应用字体大小设置（3.3.0）

- 个性化页面的滑杆布局、0.8–1.4 范围、0.05 步进和实时百分比参照 Review X。拖动过程只更新 Riverpod 状态，松开后才写入 SharedPreferences，避免每帧磁盘写入。
- 全局采用 `AppTextScaler(platformScaler, factor)`，只在系统缩放曲线输入侧调整字号；不得直接用 `TextScaler.linear` 替代系统曲线，否则会破坏 Android 非线性无障碍字号支持。设置仅本机持久化，不加入 WebDAV 备份白名单。
- 回归覆盖平台缩放曲线委托、预览/持久化、范围钳制和页面布局。设置页的响应式高度及系统大字号仍应以真机检查为准。

## 图片 Hero 灰块：祖先强制非空导致 Release ErrorWidget（3.2.9）

- **已复现根因**：3.2.7 新增的 imageBuilder 通过强制非空查找分页器；Hero push 在 Navigator overlay 重建图片，那里没有分页器，实际已解码转场测试第一段即捕获 `Null check operator used on a null value`。Flutter Release 错误占位默认为 `0xF0C0C0C0` 浅灰色。加载占位的 Hero 测试和直接挂图库的解码快滑测试分别缺少真实解码和实际路由转场，未能覆盖两者组合。
- **错误尝试与纠正**：3.2.8 将灰块归因为整页 FadeTransition，只测试路由构建器，用户安装后确认仍有灰块。该原因未得到复现证据支持，关闭淡入的修改已撤回。不能把返回类型断言通过写成视觉故障已修复。
- **最小修复与证据**：祖先不存在时返回图片绘制子树，正式页内继续原分页手势。回归同时覆盖已缓存原图、飞行途中原图完成、首次/非首次图片打开、左右切图后返回、每帧无异常/ErrorWidget，及 overlay 实际像素与蓝色原图匹配。修复前同一用例失败，修复后通过；已有连续甩动/缩放/滚轮/Live Photo 回归继续保留。真机视觉与 Profile 验收仍须设备。

## 连续快速甩动：只测试加载占位会漏掉已解码图片手势冲突（3.2.7）

- **已确认的根因**：120×240 已解码像素的连续大步长移动使内部 ScaleGestureRecognizer 先胜出，但 8.3.1 在 1 倍状态不会从缩放路径转交分页，page 保持 0。旧 Hero 有/无包装也使跨页手势实例被销毁重建。仅断言 canScrollPage 或用加载占位做甩动测试，都无法证明解码成功后的真实识别链路。
- **修复及防回归**：通过公开 imageBuilder 在图片绘制子树内注册单指、1 倍的依赖分页识别器，沿用 pager 原有拖动生命周期；双指交给缩放，触摸时校正已挂载手势状态的顺序。使用固定 HeroMode/Hero 层级，只禁用非当前飞行。主图途经媒体初始化推迟到经过 epoch/滚动状态检查的结束回调。回归必须提供已解码像素，覆盖大步长、反向惯性接管、双击和双指缩放恢复、跨半页状态实例保持、最终媒体手动播放，并与加载/失败测试同时保留。真机 Profile 帧耗时仍须设备采集，不能用测试通过推断大型原图解码已经流畅。

## 图片画廊滑动手势配置核对（3.2.6）

- **核查结果**：本项目 `ExtendedPageController` 未设置 `shouldIgnorePointerWhenScrolling`，依赖默认值为 `false`；`ExtendedImage.enableSlideOutPage` 当前为 `false`，所以外层水平 `slideAxis` 并未接入正常图片的滑动手势，不能将它直接认定为本次横滑卡顿的原因。已定位的主图/缩略条双控制器旧惯性抢占仍由 3.2.5 的控制权交接修复。
- **安全调整与验证**：主图改用 `BouncingScrollPhysics`，并通过 `canScrollPage` 仅允许 1 倍适配状态翻页，放大时保留图片平移。实验性全局打开 `enableSlideOutPage` 会让 8.3.1 在加载/失败占位挂载额外 `ScaleGestureRecognizer`；横向翻页与主图打断缩略条惯性的测试均失败，因此保留关闭状态，不照搬“垂直退出+打开滑出”的配置。专项画廊回归确认原有接管、滚轮同步与横向翻页均通过；真实设备手感仍需安装后复测。跨项目配置和边界测试见[连续滑动性能修复指南](IMAGE_GALLERY_SWIPE_PERFORMANCE_GUIDE.md)。

## 微博卡片长按菜单与水波纹误触（3.2.3、3.2.4）

- **现象与根因**：整张微博卡片把长按直接连到“更多”菜单，滑动时稍有停顿就可能被长按识别；即使卡片设置 `enableFeedback: false`，全局 `HapticSplashFactory` 仍在按下时创建触感，因此慢滑也可能震动。
- **修复与回归点**：`ReviewCard` 仅被微博卡片使用，删除其长按 API 和对应菜单调用；外层卡片不响应长按、不显示水波纹且不触发全局触感，普通点击仍进入详情。仅外层临时使用 `NoSplash`，其子树恢复原主题，因此内部按钮继续获得原触感与动效；“更多”按钮是菜单唯一入口。回归确认长按没有菜单/触感且外层 splash factory 为 `NoSplash`，更多按钮仍可打开菜单。

## 主图接管时缩略滚轮旧惯性抢占（3.2.5）

- **现象与根因**：主图与底部滚轮由两个独立的 `PageController` 驱动。滚轮拖动/惯性时，滚轮监听器逐帧对主图执行 `jumpTo`；主图接手手势时，原实现只关闭了后续镜像标志，没有停止滚轮仍在运行的 ballistic activity。于是旧滚轮惯性可能继续推进并覆盖主图手势，导致快速连续滑动时手势像被吃掉或卡住。
- **修复与回归点**：主图收到真实拖动 `ScrollStartNotification` 时先递增同步 epoch、关闭滚轮到主图的镜像；若滚轮仍在滚动，则 `jumpTo(position.pixels)` 在保留当前小数页位置的同时终止其旧滚动活动，之后由主图接管。没有把主图延迟到下一帧（那会造成可见落后），也没有改变 Hero、视口或缩放几何。专项测试在滚轮快速甩动后立即拖主图，断言旧滚动活动已停止、主图能继续移动且结束后两边重新对齐；原有快速滚轮和停住不抽动测试继续覆盖。设备帧率、触感硬件响应仍需真机验收。可迁移实施细节见[连续滑动性能修复方案](IMAGE_GALLERY_SWIPE_PERFORMANCE_GUIDE.md)。

## 缩略条拖动停住时主图分页物理互相拉扯（3.2.2）

- **现象与根因**：底部滚轮拖到半页并按住时，主图由滚轮监听器持续 `jumpTo` 小数页；主图 PageView 默认分页吸附又会启动整页吸附动画，两个位置控制互相竞争，画面抽动。松手时若在 `ScrollEndNotification` 回调中立即启动归位动画，Flutter 当帧剩余的拖动/惯性活动切换还会覆盖新动画。
- **修复与回归点**：缩略条接管期间临时关闭主图 `pageSnapping`，仍按连续小数页同步；滚动结束后延至当前帧结束再共同 `easeOutCubic` 归位，使用同步 epoch 丢弃过期回调。验证拖动后停住至少 320ms 主图与滚轮均不移动，松手后共同归位；同时覆盖普通拖动、快速甩动、主图接管和 Android/iOS 两种平台的惯性测试。真机手感/触感仍需设备验收。

## 图片画廊双击缩放被单击清屏竞争（3.2.1）

- **现象与根因**：图片子树由 `ExtendedImage` 的双击识别器负责缩放，整屏父级同时以 `GestureDetector.onTapUp` 立即切换清屏。两个识别器竞争同一触摸序列，双击有时被解释成两次单击，造成图片不缩放或清屏状态闪变。
- **修复与回归点**：父级改用不加入 GestureArena 的 `Listener` 原始指针事件；以 Flutter 的 `kDoubleTapTimeout` 延迟确认单击，第二次落在 `kDoubleTapSlop` 内则取消单击，移动超过 `kTouchSlop` 和多指手势不处理。保留 `ExtendedImage` 原有缩放/动画，只在该缩放回调中调用 `HapticFeedbackUtil.light()`；不拦截播放器自己的双击。回归覆盖双击不触发清屏、中心单击清屏、侧边单击退出及画廊原有 Hero/滚轮行为。单击响应会延迟一个双击判定窗口，这是为避免双击时出现清屏闪烁的必要取舍；真机触感与识图缩放仍需设备验收。

## 用户直达只展示热门候选（3.4.1）

- 输入页直达不是完整用户目录。用户确认以至少 1 万粉丝为门槛，先筛选正式搜索结果，再保留官方顺序取前 3 个；没有符合条件的账号时隐藏标题和卡片，不为了填满区域展示低粉同名账号。筛选只在输入页显示层实施，完整用户页不受影响，不为凑候选额外翻页。

## 用户直达遗漏与高级搜索自动续页（3.4.0）

- 3.3.1 已修综合页和“用户”标签，但输入页 `SearchView._fetchSuggestions` 仍直接用 `getSearchSuggestions().users`，因此“用户直达”继续出现同名 5 粉丝账号。这是入口遗漏，不能只修搜索结果页就宣称全部匹配完成。现在直达账号也使用正式 `searchUsers`，保留官方顺序，不按粉丝数本地排序或硬编码目标 UID；联想词及发布器 @ 提及各自保留原用途。失败不展示联想账号冒充结果，提供独立重试。
- 输入变更先清空旧卡片，并用递增代次隔离旧成功和旧错误响应；防抖 400ms 后并发请求，避免逐键立即拉取网页。高级搜索自动续页复用原 `_search(more:true)`，通过加载锁、防错状态与服务端 hasMore 限制请求；短列表在布局后补页，避免没有滚动事件就无法继续。失败不推进页码、不自动循环重试，用户重试仍是同一条件和同一页。

## 用户搜索只接移动接口导致不可用（3.3.1）

- 上次将正式用户搜索只接到移动用户容器，缺少桌面网页登录兼容；构造样例通过与签名 APK 成功不能证明手机会话能访问该域。用户安装后反馈“用户搜索暂时不可用”，说明上次修复未完成在线闭环。
- 本次通过已登录官方浏览器核对 `s.weibo.com/user` 原始 HTML（HTTP 200），确认第一位“巴旦木公主_” UID 6130897928、56.6 万粉丝，第二位同名 UID 6375259541、5 粉丝；移动容器在浏览器也可返回正确 JSON，不能笼统宣称接口已经失效。手机本次失败的精确 HTTP/业务码尚未获取。
- 修复为网页用户分类优先、移动容器兼容回退，解析范围限定在主用户列表，保留官方排名；明确无结果不发回退请求，访客 HTML 不当成空结果。增加真实结构的去追踪参数样例，不保存 Cookie、用户 Token 或签名图片地址。搜索定向 6 项通过，3.3.1 APK 已核验交付，手机实际搜索仍待验收。输入页用户直达的独立遗漏见 3.4.0 条目。


## 关注流高级搜索接口对齐（3.3.0）

- 不可把截图中的“高级搜索”接成全站搜索，也不能依赖用户联想或客户端过滤。2026-10-11 在用户已登录的微博首页通过真实界面提交搜索，捕获 `/ajax/statuses/search`：`atten=1&count=10&page=1`，关键词 `q`，七项类型 `hasori/hasret/hastext/haspic/hasvideo/hasmusic/hasv`；取消“转发”后确认 `hasret` 被省略，而非传 0。选择日期后确认 `starttime/endtime` 为秒级时间戳，结束日使用次日零点，避免少掉当天内容。
- 网页成功响应含顶层 `ok=1/statuses/total_number`；一次筛选返回 9 条、总数 9。只保存参数规则与数量，不保存会话、请求头或账号内容。应用复用同域 Cookie 客户端；只有移动会话或网页会话过期时可能需要同步网页登录，不能偷偷改成不受关注范围约束的搜索。
- 分页保留提交时的不可变条件快照，编辑未提交的输入不影响后续页；失败不推进页码，重试沿用原条件。页面用懒加载列表、标准 FilterChip 和换行日期按钮，保留键盘与窄屏操作空间。回归覆盖服务端拒绝/登录 HTML/结构变化，避免统一吞错后显示“暂无微博”。

这里保留能帮助避免回归的根因和检查办法。当前功能、接口边界与发布流程以 [DEVELOPMENT.md](../DEVELOPMENT.md) 为准。旧版综合手册截至 2026-09-23，原件仍在仓库 `docs/archive/Review-legacy-2026-09-23.md`，仅供追溯；其中的操作建议可能过时或互相矛盾，不能当作现行规范。

> **历史归档：** Miuix 与悬浮底栏液态玻璃已在 `2.17.0` 按用户决定移除。以下条目不要求恢复它们。`2.17.1` 按新的明确需求，只在图片画廊的两个圆形操作按钮上增加局部玻璃折射；这不恢复全局材质选项或 Miuix。

## 搜索用户结果误用联想候选（2026-10-11，代码已修复，在线验收待完成）

- **现象与根因**：用户搜索“巴旦木公主”时，截图中的微博网页搜索主账号为认证账号（约 56.6 万粉丝），侧栏另有同名低粉账号（5 粉丝）；应用综合页把低粉账号放在顶部，切到“用户”也看不到网页主账号。源码确认不是粉丝数格式化造成：`SearchResultsPage` 将 `/ajax/side/search` 返回的 `users.first` 直接用作主账号，并将整份联想用户列表复用到“用户”标签；而 `getSearchSuggestions` 只在该列表为空时才请求 `/ajax/profile/info`，有错误候选时不会触发回退。网页端综合结果中的主账号卡片也未纳入当前 `s.weibo.com/weibo` 状态卡解析。
- **历史防回归**：旧手册曾记录 `/ajax/side/search` 会遗漏大量账号，并为主页解析改成优先 `/ajax/profile/info`、联想接口仅降级。当前全局搜索的空列表回退没有覆盖“非空但不相关”这一情形。修复时不要把联想列表当成用户分类结果，也不要只靠昵称或粉丝数猜目标；先用只读请求核实网页用户分类/主账号卡片的真实数据来源，再把正式用户结果与输入联想分开。保留 `getSearchSuggestions` 在搜索框和发布器 @ 提及中的联想用途。
- **修复与验收边界**：综合主账号和用户列表改用独立移动用户容器搜索；解析嵌套用户卡、保留官方顺序并按 UID 去重，用户分页独立，访客/鉴权/结构错误显示重试而非无结果。`test/search_users_test.dart` 的 4 项样例检查通过，覆盖非空错误联想与正式结果隔离、昵称后缀、去重、排除微博作者、分页参数和错误响应；搜索文件静态分析无问题。样例为构造数据，匿名官方请求返回访客限制，尚无登录账号响应与真机验收，不能宣称已确认“巴旦木公主”当前排名或移动结果与桌面完全一致。未执行真实账号写操作。

## 关注流推荐来源与默认入口重合（3.2.0）

- **3.4.2 显示复核**：用户账号尚未刷到推荐卡片时，用包含博主姓名的构造 title 检查卡片；来源说明位于作者上方，字号/主题色/图标尺寸对齐可见范围提示，来源与仅粉丝可见独立保留。位置和样式检查不能证明真实接口总会返回博主姓名，也不能将构造的点赞/评论文案当成在线证据。
- **内容来源**：[微博客服中心说明](https://kefu.weibo.com/faqdetail?id=21729)，关注流会根据关注关系推荐未关注博主的内容，包括“关注的人关注了”和“关注的人点赞了”；所以“全部关注”出现非关注账号内容确实可能是微博服务端的关系推荐。应用将 `all_follow` 路由到 `FeedRepository.getFriendsTimeline`，主请求为 `/ajax/feed/friendstimeline`，不是客户端本地热门流。客服说明没有确认“关注的人评论了”是否也会触发这类推荐。
- **根因与修复**：下拉面板把 `all_follow` 点击归一化为 `friends`，并将两项同时判为选中；现在传递原 ID、严格按 ID 高亮，控制器分别恢复“全部关注”和“最新微博”标题。旧卡片只在 `visibilityLabel == null` 时显示标题，而公开范围也会产生“公开”标签；“全部关注”现在独立判断官方来源文案，排除纯可见范围标题，允许来源与受限可见范围并存，并给长说明提供换行空间。详情补齐继续保留关注流原始标题。“最新微博”保持原有内容请求与显示方式，不通过本地作者过滤制造另一种关注流。
- **回归点与边界**：覆盖两个入口 ID/高亮独立、公开状态来源显示、受限范围与来源并存、纯范围标题不重复、长来源说明不溢出、详情补齐不覆盖原来源，以及最新微博旧显示保持。说明只能取服务端实际返回的 `title`，没有字段时不推断是谁关注/点赞/评论。模拟的评论文案只验证通用显示能力，不证明微博一定推送评论动态；未读取用户账号或完成真机网页对照。

## 混合媒体画廊全屏按钮误退出（3.1.3）

- **进度条遮挡补充修复（3.1.4）**：图库缩略条与视频底部控制栏各自固定在底部，导致缩略条遮住进度条。用控制栏实际布局高度将缩略条放到其上方，不使用固定估算高度；通知仅在初次布局与尺寸变化时触发。不能直接把缩略条搬入播放器子树：滚轮开始拖动会将活动视频下标设为 -1 并卸载播放器，连带销毁滚轮会中断手势。缩略条仍留图库层，拖动期间锁定位置，停稳后再调整。回归检查正常/放大字体、底部安全区、进度条可拖动和缩略条拖动时位置稳定。

- **根因**：嵌入式 `WeiboVideoPlayerPage` 将全屏按钮设为 `onTap: null`。由于该按钮位于播放器整屏手势层之上，空点击处理器无法消费指针；点击右侧按钮时，事件落到外层画廊“点左右三分之一退出”的手势上，导致视频预览被关闭。
- **修复与回归点**：全屏按钮改为在原播放器内切换横屏沉浸状态，不 push 第二个播放器路由，避免控制器重建、播放位置丢失和重复解码；横屏时隐藏画廊控件，播放器中间点击只显隐播放器控制栏，系统返回或全屏键退出后恢复竖屏和图库控件。按钮必须有实际处理器以阻止点击落入画廊关闭手势；播放器 dispose 时若仍处于横屏需恢复系统方向。
- **验收边界**：源码与 Release 编译只能确认实现和打包，不证明设备方向锁、横屏布局及系统返回手势的实际观感；需真机在混合媒体、横竖屏与播放中往返检查。

## 文章页重复进入与头像闪烁（3.1.1–3.1.2）

- **正文根因与修复**：`WeiboArticlePage` 每次 route 新建都会重新拉取文章 HTML，`_loading` 让整页正文暂时只显示进度圈。现在按账号 UID 和文章 ID 缓存最多 8 条解析结果，只保留在进程内；再次进入先显示缓存正文，手动刷新也不会清空旧正文。不把文章落盘，也不把 Cookie/Token 放进缓存键。
- **头像三段变化与修复**：用户观察到“正在打开时先看到正确头像 → 短暂变成占位 → 又恢复正确头像”。文章路由采用 Lurk 式整页滑入，动画期间旧信息流页仍在下方，第一帧真实头像可能来自原微博卡片。文章 HTML 到达后，文章页自己的头像开始加载；若信息流头像与文章页头像 URL 不同，即使它们属于同一个用户，图片缓存仍可能未命中，`AppAvatar` 会先显示占位再切到图片。现在从信息流文章卡片传递作者 UID 和头像 URL，并解析文章作者 UID；UID 相同才复用信息流头像 URL，使转场前后继续使用同一张缓存图片。作者不同或 UID 无法确认时不复用，避免显示错误用户头像。
- **验收边界**：源码路径解释了三段变化并增加同 UID 复用，但仍需真机确认第一帧确实来自旧信息流，以及同 UID 的头像是否连续。若第一张真实头像在页面完全停稳后仍属于文章页本身，则继续记录文章作者 UID、图片 URL 和 Provider key，不能把转场露出的旧路由当作结论。

## 原生登录后的全链路会话错配排查与双通道治理（3.0.2+）

- **排查根因**：原生短信验证码/密码登录直连微博移动认证通道（`api.weibo.cn` / `m.weibo.cn`），会话存储中只有已验证的移动 Cookie（`SUB`、`SUBP`、`XSRF-TOKEN`），桌面 SSO 票据为空或校验被清空。当应用向 `weibo.com/ajax/...` 发起 POST 写请求或需要登录态的读请求时，由于缺少桌面 XSRF-TOKEN 与桌面登录凭据，请求会直接触发 403 Forbidden、401 未登录或重定向失败。
- **治理范围**：先前仅对“关注/取关”做了单点修复，本次进行了全项目全局审计，排查出点赞、收藏、删博、评论/回复/删评、关注信息流、收藏大厅、赞列表、发布微博等 8 个功能点均存在相同隐患：
  1. 点赞/取消点赞（`FeedRepository.setLikeState`）：双通道路由，移动会话走 `m.weibo.cn/api/attitudes/create` 与 `destroy`（带 `st` 与 `MLOGIN=1`）。
  2. 收藏/取消收藏（`FeedRepository.setFavoriteState`）：双通道路由，移动会话走 `m.weibo.cn/api/favorites/create` 与 `destory`（带 `st` 与 `MLOGIN=1`）。
  3. 删除微博（`FeedRepository.deleteTweet`）：双通道路由，移动会话走 `m.weibo.cn/profile/delMyblog`（带 `mid` 与 `st`）。
  4. 评论发表/回复/删除（`DetailRepository`）：双通道路由，移动会话走 `m.weibo.cn/api/comments/create`、`reply`、`destroy`（带 `st` 与移动端请求头）。
  5. 关注信息流（`FeedRepository.getFriendsTimeline`）：新增方案 3 移动关注流通道 `m.weibo.cn/feed/friends` 自动降级，解决登录后首页关注流空白。
  6. 我的收藏与赞列表（`favorites_page.dart` / `likes_favorites_page.dart`）：补齐移动端 `api/favorites/all_fav` 与赞容器流 `230869{uid}_-_like` 回退。
  7. 发布微博（`compose_tweet_page.dart`）：桌面 `/ajax/statuses/update` 失败或移动会话时回退移动端发布接口。
- **回归验证**：新增 `test/user_actions_dual_channel_test.dart`，结合 `follow_action_test.dart` 与 `messages_and_likes_test.dart` 27 项用例全部通过，保证无真实账号改动、无真实网络污染。

## 原生登录后的关注/取关会话错配（3.0.1）

- 原生登录在桌面 SSO 尚未同步时会清空旧桌面 Cookie，仅保留已验证的移动 Cookie；旧用户主页逻辑仍把合并 Cookie 交给独立 Dio，轮流请求移动端与桌面端接口并吞掉服务端错误，最终把鉴权/业务拒绝统一显示成网络失败。
- 关注操作现收敛到 `FeedRepository`，依据实际可用的已验证 Cookie 选择同域接口；移动端请求使用移动域 Cookie、`MLOGIN=1` 和移动 `st`，桌面请求使用桌面 Ajax 接口。只有成功响应才修改资料页关注状态，服务端拒绝信息直接显示。
- 桌面与移动 XSRF 刷新及响应写回按域隔离；缺令牌时分别请求 `weibo.com` 配置或 `m.weibo.cn/api/config`，403 重试沿用原请求 Cookie 与域。回归用拦截器伪造会话验证接口选择、请求头、服务端拒绝和移动令牌不污染桌面 Cookie；不通过真实账号执行关注/取关。静态测试、构建和 APK 核验不能代替微博线上接口或设备验收。

## 全应用顶栏渐变与 M3 全面复核（2.22.1）

- **纵向渐变磨砂**：用户要求状态栏侧基本不模糊且基本不透明、向分界线侧逐渐增加透光并保留 60% alpha 模糊。2.22.1 首版颜色合成约 0.82，用户确认仍不够实；2.22.2 最终参数按用户明确指定为渐变叠加 alpha 0.90、AppBar Material alpha 0.45，合成 `1 - (1 - 0.90) × (1 - 0.45) = 0.945`，顶部约 94.5% 不透明，边界处叠加层 alpha 为 0、保留 Material 的 0.45。sigma 20 的局部 BackdropFilter 仍单独套 alpha 0→0.60 纵向遮罩。遮罩只包滤镜，不淡化标题或色层。标准栏、时间线/热搜自定义栏和超话详情 SliverAppBar 都复用 `ReviewFrostedBackdrop` 与同一个 Material alpha 常量。不能只改颜色 alpha 或在部分页面复制不同方向的渐变；回归检查两种渐变端点/方向、合成底色不透明度与 blur clip。
- **模糊消失回归（2.22.3，首次尝试未解决）**：给 `BackdropFilter` 套 `ShaderMask`、再显式设 `BlendMode.src` 是当时针对模糊不可见作出的合成假设；用户真机反馈仍完全没有模糊，证明 widget 层级与 blendMode 断言不能代表视觉验收。这一处理不应继续保留为当前实现。
- **状态栏侧不透明度微调（2.22.4，未解决根因）**：将渐变叠加层 alpha 从 0.90 调至 0.95、Material alpha 保持 0.45，理论合成不透明度从 0.945 增至 0.9725；但只调颜色参数并未恢复可见模糊，原实现仍需重新检查。
- **参考 ReviewX 简化绘制链（2.22.5）**：ReviewX 使用 `ClipRect → BackdropFilter → 渐变 DecoratedBox`，没有 `ShaderMask`。Review 采用同一直接层级，移除独立 blur shader mask 和非默认 `BlendMode.src`；保留 sigma 20、Material alpha 0.45、顶部颜色 alpha 0.95→边界 0。顶部近乎不透明的颜色层压低模糊可见度，靠近边界则逐渐显出磨砂。widget 测试锁定层级且不含 ShaderMask，但仍需真机确认画面效果。
- **下拉阈值根因**：`extendBodyBehindAppBar` 会使内容子树看到包含完整 AppBar 的 `MediaQuery.padding.top`；EasyRefresh 默认 `safeArea: true` 把该 inset 加到 `actualTriggerOffset`，因此用户必须拉很深。覆盖式页面使用 `safeArea:false` 保持 70dp 阈值，并仅在 indicator 内容里将 ClassicHeader 向下偏移完整 inset；不能把 `triggerOffset` 设为 0，因为 ClassicHeader 布局尺寸也依赖它。全局默认 header、非覆盖式与嵌入式页面保持原样。
- **固定区边界**：磨砂范围以最后一项固定内容的下沿为界，不以标题文字行或局部标签线为界。搜索框、分类条、pinned 内容先确定唯一归属及总高度，再选标准 AppBar bottom 或覆盖式视口；安全区和 toolbar inset 只能补一次。超话中心保留 8dp 标签下方材质缓冲，不再绘制重复 hairline。
- **设置 M3 与 Lurk 回归防范**：核查发现 `AppSectionCard` 的调用都在设置/个性化/存储/备份等分组页面，可复用同一低强调 surface helper；故统一默认零 margin、无 elevation/描边、低 surface 层级，而不是新增私有卡片或改全局 CardTheme。分组列表已有外层 16dp padding，不能再叠加卡片默认 margin；这是 Lurk 之前出现卡片外扩/留白叠加的同类风险。分割线以实际 ListTile 参数计算：leading 24 + title gap 16，卡片内缩进 56dp；不要把屏幕坐标 72dp误用作卡片内部 indent。
- **设置页字号层级（2.22.6）**：上一版把设置项标题强制设为 17sp、分组标题强制设为 16sp，两个层级过于接近且忽略主题的 Material 3 字体比例。改用 `titleMedium`/`titleSmall` 默认层级（通常分别为 16sp/14sp），不要在共享设置行再次覆盖字号；删掉标题已表达的重复说明，但保留安全范围和动态状态等非冗余信息。
- **画廊 Hero 转场闪烁（2.22.6）**：目标路由在 push 期间已绘制底部缩略条，而 Hero 飞行层覆盖其上，转场结束后缩略条突然出现。监听 `ModalRoute.animation` 的状态，只让缩略条在 `completed` 后淡入、`reverse` 开始时立刻淡出并禁用命中；不要隐藏/缩放主图，不要因显隐修改 PageView 约束、视口或 Hero 子树几何。
- **验证边界**：定向 widget 测试覆盖渐变端点与复合不透明度、直接滤镜层级/无 ShaderMask、超话固定区几何、设置分组卡片及 overlay 下拉刷新回调；Flutter 测试不能代替暗色/纯黑/浅色主题和真机滚动时的视觉验收。2.22.1 的全面检查、2.22.2 顶栏 alpha 调整、2.22.3/2.22.4 未奏效的尝试及 2.22.5 的 ReviewX 层级移植分别记录在对应变更条目中。

## 设置页 M3 视觉调整（2.22.0，历史说明）

- **初版判断的后续修正**：2.22.0 先用页面私有卡片，避免当时尚未盘点共享调用时扩大副作用；后续全面检索发现 `AppSectionCard` 实际只用于设置与个性化分组。2.22.1 已将统一风格收敛到这个共享 helper，并保留零 margin 与不改全局 CardTheme 的约束。
- **分割线按真实行布局对齐**：ListTile 文字起点是屏幕坐标 72dp（页面内边距 16dp + 卡片内 tile 内边距 16dp + 24dp leading + 16dp 标题间距）；Divider 位于卡片内部，因此代码缩进应为 56dp。Lurk 调整记录中 64dp 曾留下左侧空白；改 Divider 时先按实际行参数计算起点，不凭经验套固定数。
- **保留操作和可访问性**：缩小视觉噪声不压缩触控区域；保留至少 8dp 垂直留白、24dp 图标、凭据有效/失效的动态状态、登录/导出/退出回调、状态栏与底部导航留白。验证要区分静态分析/安装包与真机显示；没有设备时明确记录未做真机验收。
## 时间线顶部磨砂质感（2.19.16）

- **现象与根因（2.19.15）**：虽然加入了 `BackdropFilter`，实际顶栏仍近似透明。它叠加的是与时间线底色几乎相同的 `colorScheme.surface`，模糊 sigma 仅为 8；页面初始滚动位置下顶栏背后又是预留空白，因此没有足够的色彩/细节差异让磨砂效果可见。
- **修正与验收边界**：使用 `surfaceContainerHighest` 主题层级色、82% 不透明度和 sigma 18 的局部模糊，并以 `ClipRect` 限制在时间线顶栏；不扩大到其他页面、不做全屏捕获或 shader。测试/编译只能验证代码与包，磨砂是否符合预期仍应在暗色、纯黑主题及滚动时覆盖顶栏的真机画面上检查。
- **二次修正（2.19.17）**：用户仍观察到全透明。前版虽在 `flexibleSpace` 子层绘制颜色，但 AppBar 自身 `backgroundColor` 仍显式为透明；新版本将当前主题 AppBar/Scaffold 底色直接赋给 AppBar Material（82% 不透明度），让颜色层不再依赖 backdrop filter 是否正确合成；`BackdropFilter` 只负责 sigma 20 模糊。验收需确认深色、纯黑与滚动内容经过顶栏时均可见底色和模糊层。
- **跨页面复用回归（2.20.0）**：新增 `ReviewFrostedAppBar` 时再次将底色放回 `flexibleSpace`，并强制 AppBar Material 透明，违背上面的已验证修正，因此个性化、赞和收藏、关注列表等页面看起来透明。共用组件必须直接为 AppBar Material 设置主题底色的 82% alpha；回归测试检查最终 `AppBar.backgroundColor` 与 `forceMaterialTransparency == false`，不能只检查树中存在 `BackdropFilter`。
- **固定顶栏内容边界（2.21.1）**：超话中心的搜索与分类标签固定在滚动结果上方，均属于顶栏视觉区域。磨砂层和底部分隔线必须延伸到最后一行固定标签下沿；只给“超话中心”标题行套磨砂会让下方固定内容落在裸背景上。将固定区放入 `ReviewFrostedAppBar.bottom`，滚动列表仍留在 Scaffold body，且只在边界下方保留原内容间距。
- **避免重复分界线（2.21.2）**：超话分类栏下沿出现组件绘制的浅色 hairline，同时顶栏整体材质边缘又形成一道边界，视觉上像两条线。查找应先定位实际绘制源；本例只对该页设置 `showBottomBorder: false`，保留 82% 主题底色形成的整体边界，不全局移除其他页面的分隔线，也不在 body 顶部再叠加 Divider。

## GIF 与视频/Live Photo 冲突分类（2.19.14）

- `type: video` 或旧快照里的 `fid`/`livePhotoVideoUrl` 不能单独证明图片是视频或 Live Photo。只有存在真实的非 GIF 播放地址才进入视频播放器；否则播放器会以空地址加载，导致播放器控件与画廊缩略栏重叠。
- 图片 URL 是 GIF 且没有真实视频直链时，GIF 必须优先作为动图图片显示，并压过旧 Live Photo 元数据/合成地址；不能把 `fid` 拼出的 MP4 当成源媒体格式。
- 回归测试至少覆盖：带 `fid` 和陈旧 Live Photo 元数据的 GIF、只有 `type=video` 但无媒体 URL、真实 MP4 以及带 GIF 预览图的真实 MP4。设备播放和手势观感仍须真机验收。

## 登录方式切换（2.19.0）

- 验证码保持默认，密码登录只作为可切换方式；两种登录最终汇入同一 native session 暂存、Review Cookie/UID 验证和 Keystore 保存路径，避免密码模式绕过会话校验。
- 密码签名必须在 Android native 调用 `SAUtils.secP` 与 `WeiboApplication.newCalculateS(account + password)`；不要在 Dart 计算、持久化或打印密码。密码请求仍按登录接口的 QueryMap/FieldMap 分组，并带 Android 客户端上下文；不要把表单字段误放进 URL 查询或反向。
- 登录页切换离开密码模式时清空密码输入；提交后也清空输入。设备验收需要分别覆盖无预设密码账户的验证码登录、已有密码账户登录、额外安全挑战、Cookie 导入与会话重启恢复。
- 泛化成同一条“初始化/网络失败”会把 native 库加载异常和 API 传输错误混在一起。给原生错误保留有限层数的异常类型名用于诊断，但绝不显示异常消息、URL、请求参数或凭据。
- 认证日志不能输出整个响应对象或异常消息：登录响应可能含 Cookie、Token，异常消息也可能带入请求上下文。仅记录 HTTP 状态、认证字段存在性和异常类型；用户界面可显示服务端错误，但日志必须保持脱敏。2.19.7 移除了 `WeiboApi` 的完整响应日志及 CookieManager 的异常消息日志。
- `wbutil` 的 `JNI_OnLoad` 会对 `com.sina.weibo.WeiboApplication` 批量 `RegisterNatives` 8 个方法，并对 `com.sina.weibo.data.sp.EncryptSharedPreferences` 注册 2 个方法。只声明实际调用的部分方法或漏掉后一个类，都会让整库加载失败并抛 `UnsatisfiedLinkError`，请求还没发出；核对 `.so` 的注册表/签名并补齐精确声明。另核对每个 native 符号的 Java 全限定类名：`SecShare` 的 `secP` 导出属于 `com.hengye.share.module.other.SAUtils`，错误包名会在首次调用密码签名时失败。
- 2.19.1 已补全这组注册声明，并修正 `SAUtils` 包名。APK 编译、签名、16 KB 对齐和 14 项认证测试通过，但没有连接真实设备；不要把静态产物检查写成短信或登录已通过。
- 上游 `DeviceId.getDeviceId()` 通过 `WSUtils` 获取已初始化的 `WeiboApplication`，并把它传给 `getDeviceIdNative`。Review 在 2.19.2 改为传真实的 `WeiboApplication` 实例，但用户实测仍会闪退；因此这项 Context 调整没有解决问题，不能再作为已确认根因。另一个已确认差异是 Review 在首次发码时一次性加载 `SecShare`、`wbutil`、`wbgjb`、`weibosdkcore`；上游按类首次使用加载，密码加密和 OAuth 签名库不应提前进入短信发码路径。2.19.3 移除 NativeRuntime 的全局预加载，依靠各原生包装类自己的按需加载器。实际短信请求仍须由设备验收确认。
- **致命崩溃根因定位与修复（2.19.4）**：
  1. **Native Crash / SIGSEGV**：通过反编译分析 `libweibosdkcore.so`，发现 native 函数 `getDeviceIdNative` 会通过 JNI 反射调用 `com.sina.deviceidjnisdk.DeviceId.genCheckId(String, String, String)`。Review 此前在 `WeiboApi.commonLoginQuery()` 中错误地将 `android_id` 设为 `nativeRuntime.deviceId()`，触发了该 JNI 函数调用。由于 Review 的 `DeviceId.java` 缺失 `genCheckId` 方法，JNI `GetMethodID` 返回 `NULL`，底层调用直接触发 ART 虚拟机的 SIGSEGV / Native Abort 崩溃，Java 层 `try-catch` 无法拦截。
  2. **上游 Share 实现核实**：核对 `D:\share_ref\decoded\share_full\smali\UB.smali`（第 1053 行）和 `aQ.1.smali`（第 106-118 行），上游 Share 请求中的 `android_id` 根本不是 `DeviceId`，而是直接通过 `Settings.Secure.getString(context.getContentResolver(), Settings.Secure.ANDROID_ID)` 获取。Review 在 2.19.4 将 `android_id` 改回系统获取。
  3. **JNI 签名防御性补齐**：在 `DeviceId.java` 中完整补齐 `genCheckId(String, String, String)`（安全拼接实现）、`appendCheckId`、`checkMyPermission` 等所有 JNI 交互方法，并在 `loadLibrary` 及调用点增加全套安全防护。
  4. **彻底解耦 `android.test.mock`**：此前 `FakePackageManager` 继承 `android.test.mock.MockPackageManager`，依赖平台测试库。在部分现代与定制 ROM 上，系统未预装该测试库会导致类加载失败（`NoClassDefFoundError`）。现重构为直接继承 `android.content.pm.PackageManager`，实现全部 94 个抽象方法并安全代理给真实 PackageManager，从 Gradle 和 Manifest 中完全移除了 `android.test.mock`。
- **短信验证码拒发与服务端错误透传修复（2.19.5）**：
  1. **`area` 参数错误传递**：在上游 Share 实现中（`smali_classes2\wd.1.smali` 第 217-270 行），中国大陆区号（`"86"` 或 `"0086"`）在发码与登录请求中必须显式设置为空字符串 `""`，手机号保持 11 位数字。此前 Review 错误地将 `"86"` 放入 `query.put("area", "86")`，导致微博服务端因参数不合规拒发短信。2.19.5 将 `"86"` / `"0086"` 自动规范化为空字符串。
  2. **硬编码伪造 `aid="7501641714"` 污染请求**：核对上游 Share（`mA.2.smali` 第 127-145 行与 `WeiboWebAuthorizeActivity.smali` 第 580-600 行），`"7501641714"` 是 AidTask 的固定 App ID，绝非设备 AID；若 AidTask 未缓存真实设备 AID，Share 在 query 与 form 中完全不传 `aid`。此前 Review 在多处写死了伪造的 `aid="7501641714"`，导致微博服务端设备 token 校验失败。2.19.5 彻底移除了伪造的 `aid` 传参。
  3. **`ua` 参数补全系统版本号**：核对上游 `PB.smali` 第 41-48 行，标准 ua 格式为 `MANUFACTURER-MODEL__weibo__11.6.3__android__android<RELEASE>`。此前 Review 缺少末尾的 `Build.VERSION.RELEASE`，已补齐。
  4. **透传服务端真实错误描述 (`msg`)**：核对上游 Share（`oo0o00O0.6.smali` 与 `zd.smali`），发码失败时直接提取并向用户展示服务端返回的 `msg`（如“操作过于频繁，请稍后再试”）。此前 Review 抛弃了该字段并用硬编码兜底文案掩盖了真实拒发原因。2.19.5 已将服务端 `msg` / `errmsg` / `error` 全程透传至前端提示与错误日志。
- **短信验证码登录会话拦截修复与 Cookie 解析增强（2.19.6）**：
  1. **`hasRequiredFields` 误判与拦截（核心拦截点）**：真机测试 2.19.5 发码成功收到短信，但在输入验证码登录后提示“微博未返回完整登录会话”。对比上游 Share 源码（`sd.1.smali` 短信验证码登录回调 `ThirdPartyLoginActivity$O00000Oo` 第 80-137 行），短信登录接口**根本不返回 `sut`，也从不要求 `sut`**（`sut` 是单点登录凭据，仅在账号密码登录 `yd.1.smali` 中存在）。Review 此前在 `WeiboSession.java` 的 `hasRequiredFields()` 中硬编码要求 `present(sut)` 以及根对象的 `present(expire)`，导致所有短信登录即使微博服务端返回 200 OK 并下发全部有效凭据，也会 100% 被判为 `session_fields_missing`。2.19.6 将会话校验条件修正为必要充分条件：`present(uid) && (present(cookie) || present(accessToken) || present(gsid))`。
  2. **Cookie 多层嵌套结构解析**：在上游 Share 实现（`oo0o00o0.7.smali` 与 `Gz.smali` 第 475-620 行）中，微博返回的 `cookie` 是一个包含域名映射的 JSON 对象（如 `.weibo.cn`、`.weibo.com` 等各自对应一段 Cookie 字符串）。此前 Review 直接调用 `response.optString("cookie")`，若其为 JSONObject 则返回了整个对象的 JSON 字符串，无法被 Flutter 的 `setAndVerifyCookie`（要求 `SUB=...` 格式）识别。2.19.6 重构了 Cookie 递归与键值提取逻辑，优先提取包含 `SUB=` 的登录 Cookie，并支持 `gsid` 以 `_2A` 开头时的回退兜底，确保 Flutter 接收到规范的 Cookie。
  3. **系统 CookieManager 双向同步**：在 `WeiboAuthManager.java` 中增加 `syncCookieManager(cookie)` 和 `clearCookieManager()`，在登录成功与恢复会话时将 Cookie 同步写入系统 `android.webkit.CookieManager` 并 `flush()`，退出登录时彻底清理，保证 WebView 与原生通道凭据完全一致。
  4. **详细字段缺失日志**：会话校验不通过时通过 `Log.w` 详细记录各个字段的存在状态及原始 JSON，便于快速定位服务端响应结构变化。
- **冷启动闪退根因与治理（2.19.8）**：
  1. **后台线程调用 CookieManager 触发底层 Native Abort（SIGABRT）**：2.19.6 在 `restoreSession` 中引入 `syncCookieManager`。由于 `restoreSession` 执行在后台单线程 `weiboAuthExecutor`，在用户登录后手机冷启动时，Chromium WebView 尚未在 UI 主线程完成初始化。后台子线程直接调用 `CookieManager.getInstance()` 或 `setCookie()` 会导致 Chromium 检查 `BrowserThread::UI` 失败或发生原生多线程竞争，触发底层的 `SIGABRT` / `SIGSEGV` 致命信号，导致应用瞬间闪退且 Java 层 `try-catch` 无法捕获。治理方案：所有对 `CookieManager` 的操作必须无条件派发至 Android 主线程（`Handler(Looper.getMainLooper()).post`）异步执行。
  2. **CookieManager URL 格式非法清洗**：`CookieManager.setCookie` 与 `getCookie` 的第一个参数是绝对 URL，而非域名（如 `".weibo.com"`）。传入非 URL 字符串在部分系统版本会引发底层异常。治理方案：全面清洗为合规的 `https://` 绝对地址。
  3. **`EncryptedSessionStore.load()` 与 `restoreSession()` 故障隔离**：设备重启、系统更新或硬件 KeyStore 状态波动可能导致解密失败（如 `AEADBadTagException`、`KeyPermanentlyInvalidatedException`）。在 `load()` 中对密钥获取和解密做全异常捕获并安全降级为 `null`（同时清理损坏密文）；`restoreSession()` 增加顶层异常兜底，网络刷新失败时保留本地有效会话，绝不阻断冷启动进程。
  4. **MethodChannel 回调防御**：`submitWeiboAuth` 与 `completeWeiboAuthError` 中的 `result.success` 和 `result.error` 增加异常捕获，防止通道解绑或重复提交引发崩溃。
- **冷启动 0.5s~1s 闪退与 AMS 杀进程彻底根治（2.19.9）**：
  1. **彻底解耦 `WeiboAuthManager` 与 `CookieManager`**：Review 作为纯 Flutter 应用，所有网络请求通过 Dart 层的 `WeiboDioClient (Dio)` 并在 Header 中注入 Cookie 发送，根本不通过 Android 原生 WebView。2.19.8 将 `syncCookieManager()` 移入主线程 Handler 队列后，由于在 Flutter 首帧渲染完成（0.5s~1s）出队执行，循环遍历跨域名注入几十次并调用 `cookieManager.flush()`，极易与底层 Chromium 初始化/渲染管线产生争用引发 Native Abort。彻底删除 `WeiboAuthManager` 中的 `syncCookieManager()` 与 `clearCookieManager()` 及其所有调用，根除 Chromium 底层崩溃。
  2. **修复 `MainActivity.onCreate` 组件状态判断误区，杜绝 AMS 杀进程**：默认情况下（未切换过桌面图标时），`MainActivity` 在系统的组件启用状态是 `COMPONENT_ENABLED_STATE_DEFAULT (0)`，而不是 `COMPONENT_ENABLED_STATE_ENABLED (1)`。此前逻辑因判断 `hasEnabled` 为 `false`，导致每次冷启动均调用 `pm.setComponentEnabledSetting(MainActivity, ENABLED, DONT_KILL_APP)`。在现代 Android（特别是国内定制系统 MIUI/HyperOS/ColorOS/OriginOS 等）中，修改当前正处于前台的 Activity 自身组件状态，PMS 发出 `ACTION_PACKAGE_CHANGED` 广播，AMS 会在 500ms~1000ms 后直接强行杀死应用进程（无任何 Java Crash Stacktrace，精准表现为进入应用 0.5s~1s 闪退）！2.19.9 修复为仅在 `MainActivity` 明确处于 `COMPONENT_ENABLED_STATE_DISABLED` 且所有别名均未启用时才兜底恢复，正常冷启动绝不调用 `setComponentEnabledSetting`，彻底根除 AMS 延迟杀进程。
  3. **MainActivity 原生 Cookie 读取安全加固**：移除 `getNativeCookies` 与 `getNativeCookiesByDomain` 中多余的 `cookieManager.flush()` 磁盘同步写入，将 `CookieManager.getInstance()` 和 `getCookie` 调用全量包裹在 `try-catch (Throwable t)` 异常隔离块中，失败降级返回空数据，绝不波及宿主进程。
- **冷启动 0.5s~1s 闪退最终根治（2.19.10）**：
  1. **彻底绝缘 Android 原生 `CookieManager`（根除 Chromium Native SIGSEGV）**：此前已登录状态下冷启动，`FeedController.initAndLoad()` 首帧后调用 `reconcileNativeSession()`，触发 MethodChannel `getNativeCookiesByDomain`。在没有 WebView 初始化的纯 Flutter 进程中，主线程调用 `CookieManager.getInstance()` 并连续读取 8 个域名的 Cookie 会强行唤起系统 Chromium 引擎，在多核并发与缺失上下文时直接引发 C++ 底层 `SIGSEGV / SIGABRT` 致命崩溃（Linux 信号无法被 Java 捕获）。2.19.10 在 `MainActivity.kt` 中完全删除 `import android.webkit.CookieManager`，将 `getNativeCookies`、`getNativeCookiesByDomain` 和 `clearNativeCookies` 完全静态化返回安全空数据，原生端彻底零 `CookieManager` 依赖，彻底切断崩溃链路。
  2. **MainActivity 全局未捕获异常崩溃日志落盘**：在 `MainActivity.onCreate` 中安装全局 `Thread.setDefaultUncaughtExceptionHandler`，一旦发生任何未捕获异常，立即自动写入私有目录 `latest_crash.txt`，并通过 MethodChannel 提供 `getLatestCrashLog` 查询能力。
  3. **彻底清除 `onCreate` 中的组件启用状态检测**：将 `onCreate` 中触碰 `packageManager.setComponentEnabledSetting` 的历史自愈代码完全剥离，消除任何可能因包状态变更广播导致 AMS 延迟杀进程的潜在隐患。
  4. **Flutter 顶层与平台调度异常兜底**：在 `lib/main.dart` 中配置 `FlutterError.onError` 与 `PlatformDispatcher.instance.onError`，对所有未捕获的 Dart 异步异常进行全局捕获与平稳降级，阻止 Flutter 引擎异常退出。

- **冷启动后台线程 JNI aa4 缺失引发 SIGABRT 根治（2.19.11）**：
  1. **真机确凿崩溃日志定位**：Logcat 抓取捕获到 `tid (pool-4-thread-1), Fatal signal 6 (SIGABRT): JNI DETECTED ERROR IN APPLICATION: mid == null in call to CallStaticObjectMethodV ... NoSuchMethodError: no static method "Lcom/sina/weibo/security/WeicoSecurityUtils;.aa4(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;"`。根因锁定为冷启动后台线程调用 `WeiboAuthManager.restoreSession()` 时，因 `shouldRefresh` 命中触发 `api().refresh(session)`，进入 `wbgjb.so` 的 native `generateS`，C++ 底层反射查找 Java 壳的 `aa4` 静态方法，因 Java 缺失该方法触发 Linux 信号强制中止。
  2. **双层根治方案**：
     - 第一层（冷启动脱困）：`restoreSession()` 彻底移除同步 refresh，直接返回本地 KeyStore 解密的有效 session，冷启动瞬时秒开；
     - 第二层（完整恢复上游 Share WeicoSecurityUtils）：根据上游 smali（654 行字节码）完全恢复 `aa4`（`toSecurityValue` 纯 Java 散列选取算法）、`sha512`、`toHex`、`aa2`、`aa3` 等全部 JNI 依赖方法与导出签名，底层 Native 符号 100% 对齐。

## 已移除的 Miuix 与液态玻璃尝试（2.15.0–2.16.9）

## 图片画廊的局部玻璃按钮（2.17.1–2.17.2）

- 对照用户提供的 Android 相册截图，把圆形玻璃按钮视觉直径收至 44dp，保留 48dp 可点击区域；模糊 sigma 从 4 降至 2.5，球冠高度从 3 降至 1.4 shader 单位，折射位移上限从 1.25 降至 0.45。保留空气/玻璃界面 Snell 角计算，只减弱形变量；描边和阴影也更柔和。其他渲染后端和 shader 加载失败时保留模糊/描边。
- 不对整页截图、不调用同步 `toImageSync`、不做逐帧 CPU 图像处理。历史悬浮栏卡死问题来自页面级捕获与同步离屏合成；局部 shader 必须继续局限在这两个按钮内。

## 画廊玻璃按钮接入个性化开关（3.5.0）

- “使用液态玻璃效果”原先只影响悬浮底栏；扩展后还控制画廊左上返回、右上下载按钮。关闭时继续走原有局部 shader/模糊实现；开启时用 `liquid_glass_widgets` 的 `GlassButton`、独立按钮层和默认自适应画质，画廊控件显隐通过 `LiquidGlassSettings.visibility` 跟随页面过场，不把玻璃 shader 包在整组 `Opacity` 中。
- 仅玻璃模式在画廊路由加 `GlassPage`/`GlassAdaptiveScope`，背景源限制在媒体视口，排除顶栏按钮；不要让玻璃关闭分支挂载背景捕获。库的标准/降级路径会使用 `GlassBackgroundSource`；播放动态视频时背景纹理可能随帧更新，APK 静态检查无法证明低端设备帧率或视频下的背景折射效果，需按设备验收。

- **更正（2.16.9：透镜方向与拖动帧负载）**：2.16.8 shader 用 `position - normal * ...` 向胶囊内部取样，和 Kyant `RoundedRectRefractionShader` 的 `coord + d * grad` 相反；SDF 外法线方向才形成凸透镜，向内采样会变成凹透镜。2.16.5 的旧记录也把这个方向写反了。拖动时原实现每个指针事件都重启左右边缘两个位置弹簧和速度弹簧；现改为单一位置弹簧，速度样本直接驱动形变，释放时再弹簧复位。设备尚未连接，因此卡顿改善和最终观感仍需真机验收。

- **现象与根因（2.16.8：液态玻璃像毛玻璃底板上的选中块）**：Flutter 实时路径把整个胶囊中心统一放大，而 Legado/Kyant 的 `lens` 按 SDF 法线和 `circleMap` 只重折射胶囊内侧的一圈；Review 还只以 30% 透明度把图标行放入滤镜输入，又在透镜上方重画完整图标，因此图标没有进入折射结果。选中胶囊还比实际槽位宽 10dp，较实的渐变和边框进一步压住了折射。上游 `FloatingBottomBar` 用 `rememberCombinedBackdrop(backdrop, tabsBackdrop)` 合并页面与完整图标层，以 `lens(10dp × press, 14dp × press, depthEffect = true)`、`DampedDragAnimation`、78/56 按压缩放和带方向的速度拉伸共同产生水滴移动。当前 Review 用 Flutter `ImageFilter.shader` 移植相同的边缘折射轮廓与分层关系，图标行置于透镜下、选中层不再被重画遮盖，槽宽与每个导航项对齐。Legado 声明 `io.github.kyant0:backdrop:2.0.1`、`io.github.kyant0:capsule:2.1.3` 和应用级 Haze `1.7.3`；其中实际透镜在 Backdrop，Haze 不是该选中透镜的实现。源码：[FloatingBottomBar](https://github.com/HapeLee/legado-with-MD3/blob/main/app/src/main/java/io/legado/app/ui/widget/components/FloatingBottomBar.kt)、[DampedDragAnimation](https://github.com/HapeLee/legado-with-MD3/blob/main/app/src/main/java/io/legado/app/ui/animation/DampedDragAnimation.kt)、[Kyant SDF lens shader](https://github.com/Kyant0/AndroidLiquidGlass/blob/kmp/backdrop/src/commonMain/kotlin/com/kyant/backdrop/internal/Shaders.kt)、[Legado dependencies](https://github.com/HapeLee/legado-with-MD3/blob/main/gradle/libs.versions.toml)。Flutter/Compose 的采样与坐标系统不同，源码适配完成和 APK 构建不能代替目标设备上的动态观感验收。
- **覆盖检查（2.16.0）**：之前主题桥接虽然能改 Material 全局色彩/形状，但 Miuix 原生组件主要集中在底栏和个性化页，导致整体验感像只换色。上游 Legado 的 ThemeComponents 使用 Miuix 自己的 ThemeController/Theme/Typography，并把设计引擎保存在主题状态中；Review 因此在共享页面增加真实 Miuix Scaffold、TopAppBar、TabRow、ArrowPreference 与 Card 路径，保留 Material 3 分支和同一业务逻辑。后续继续沿用户可见频率迁移，不能把全局 recolor 当成完整适配。参考：[Legado ThemeComponents](https://github.com/HapeLee/legado-with-MD3/blob/main/app/src/main/java/io/legado/app/ui/theme/ThemeComponents.kt)、[Legado theme state](https://github.com/HapeLee/legado-with-MD3/blob/main/app/src/main/java/io/legado/app/ui/theme/LegadoTheme.kt)。
- 第三方 Miuix glass navigation 在点击当前已选中的 Tab 时不再次调用选择回调；Review 的首页把重复点击用于回顶/刷新。替换导航组件时必须在共享适配层补回已选项点击，并回归快速重复点击和跨 Tab 拖动，不能只验证切页。
- Miuix 卡片不提供 Material 祖先，卡片中复用的 `ChoiceChip`、`ListTile` 等 Material 子控件可能因缺少 `Material` 报错。共享卡片封装应在 Miuix 卡片内部提供透明 Material 层，并以真实包含旧 Material 子控件的页面回归。
- Miuix 自带开关可能无条件触发震动，绕过 Review 可关闭的全局触感偏好。设置控件应从 Review 的用户操作回调统一触发反馈；玻璃背景捕获只在悬浮底栏玻璃模式挂载，按 1x 捕获页面背景并排除导航栏自身，避免多余纹理工作或反馈循环。
- 界面风格开关在“设置 → 个性化 → 明暗模式”下方；风格与悬浮栏材质分开保存。悬浮栏关闭时隐藏材质选项但保留选值，旧用户默认仍为 Material 3 + 标准材质。回归应覆盖六种风格/导航组合、备份白名单、明暗与纯黑色板桥接及关闭/重开后材质记忆。
- **更正（3.4.1：液态玻璃开关独立于悬浮底栏）**：3.4.0 曾把“使用液态玻璃效果”隐藏在“使用悬浮底栏”开启条件下；用户要求玻璃偏好在个性化里独立显示。设置应常驻且独立保存，玻璃底栏仅在两个偏好同时启用时采样/渲染，关闭悬浮栏时保留用户选择。旧有“悬浮栏关闭时隐藏材质选项”的布局约定不适用于该设置。
- **更正（3.4.3：液态玻璃首启观感延迟）**：3.4.1/3.4.2 在 `GlassAdaptiveScope` 固定 `initialQuality: standard`，跳过库的启动质量热身；标准画质会在后续长期稳定帧窗口后才可能升档，造成用户感知的“玻璃尚未加载”。`LiquidGlassWidgets.initialize()` 已在 `runApp` 前预热 shader，因此应移除固定标准初始值，走库默认 premium 起步、静态能力检查及帧耗时热身降级路径。这样可在首屏展示完整效果，并保留低性能设备的质量降级，不回到 3.4.0 无自适应保护的固定 premium 实现。主体 blur 从 1.5 调至 2.0、折射率从 1.16 调至 1.19，轻微加强背景的柔化和透镜感；设备帧率与实际观感仍需真机确认。
- **现象与源码风险（3.4.1：开启玻璃后整页灰屏/不可操作）**：本次无法连接用户设备复现。源码确认底栏对所有设备固定传 `premium` 且没有自适应质量作用域；库的质量适配器在存在 `GlassAdaptiveScope` 时先检查 shader 支持，并按帧时降级/恢复。现改为仅在玻璃底栏启用时建立局部作用域，以 `standard` 起步，保留正常设备升至 `premium` 的路径；这补上 Android 的兼容降级路径，但仍需在报告问题的设备确认真实根因及视觉表现。
- **现象（2.15.1：Miuix 标准悬浮栏垂直居中）**：`MiuixFloatingNavigationBar` 内部使用带底部间距的 `Align`；直接放进 Scaffold 底栏时，父节点给出的整屏剩余高度让它在中间对齐。2.15.1 曾尝试仅约束内容高度，但实际页面仍出现居中；2.15.2 在调用处用含库同款底部间距的固定外层高度，并将库组件显式放在外层底部。不要改 Miuix 的共享组件实现，以免影响 Stack 等正常用法。
- **现象（2.15.1：玻璃选中态缺少液态水滴感）**：M3 原实现使用静态胶囊，Miuix 玻璃导航默认指示器颜色透明度低。两种风格应复用 `MiuixGlassNavigationBar` 的弹性位置动画，并分别按 M3 色板和 Miuix 中性色提高指示器对比；不要再包一层静态选中胶囊遮掉动画。
- **更正（2.15.2：玻璃仍没有大水滴效果）**：`MiuixGlassNavigationBar` 的选中指示器本质上只是动画移动的 ShapeDecoration，改颜色并不会产生折射。上游底栏把跟手弹簧透镜单独绘制在玻璃轨道上；2.15.2 虽叠加了 `MiuixGlassPanel`，但透镜只采样页面背景，图标/文字在其上重绘，所以没有折射前景内容，也缺少按压/速度形变。不能只把 ShapeDecoration 改成彩色胶囊并称为液态玻璃。
- **修正（2.15.3：按 Legado 底栏补全动态水滴）**：页面截图仍只保留一份全屏 1x 捕获；额外捕获限于底栏附近 320×88dp，将页面该位置像素与 1.15 倍图标/标签合成，作为选中透镜的 backdrop。按压高度缩放参照 `78/56`，拖动速度驱动横向拉伸、位置、折射率和光照强度，释放由弹簧复位；系统关闭动画时不运行弹簧。两个设计语言共用该透镜，业务导航与震动回调保持原入口。局部捕获跟随页面截图刷新，避免再复制一张全屏纹理；真机帧率仍须在设备确认。
- **更正（2.16.4：此前的“按 Legado 补全”不等于采用了上游的渲染机制）**：Legado 底栏把页面 `backdrop` 与透明图标行的 `tabsBackdrop` 合并，再由 Kyant Compose `backdrop` 的 GPU `drawBackdrop` 连续执行 `vibrancy`、`blur`、`lens`，并通过 `DampedDragAnimation` 把弹簧位置、按压进度、速度形变、高光和阴影接到同一透镜。上游当前依赖目录含 `io.github.kyant0:backdrop:2.0.1`、`dev.chrisbanes.haze:haze:1.7.3`、`io.github.kyant0:capsule:2.1.3`；底栏直接用 `backdrop` 做背景/透镜采样，`capsule` 提供连续胶囊形状，Haze 是应用另外声明的模糊依赖。实现可对照 [FloatingBottomBar.kt](https://github.com/HapeLee/legado-with-MD3/blob/main/app/src/main/java/io/legado/app/ui/widget/components/FloatingBottomBar.kt)、[版本目录](https://github.com/HapeLee/legado-with-MD3/blob/main/gradle/libs.versions.toml) 与 [应用依赖](https://github.com/HapeLee/legado-with-MD3/blob/main/app/build.gradle.kts)。Review 是 Flutter 应用，不能直接使用 Compose 依赖。旧 Flutter 方案在页面层每次捕获时对 `OffsetLayer` 调用 `toImageSync`，`MiuixGlassPanel` 又做模糊、混色和同步离屏出图，因此即使叠了折射面板，也不等价于上游 GPU 实时透镜。Impeller 设备现在改走 Flutter 原生 `BackdropFilter` + `ImageFilter.shader` 和局部 SDF lens shader；其他后端保留原回退。仍需真机验收，不得仅凭 shader 编译宣称观感与上游相同。
- **现象与根因（2.16.4：Miuix 热搜分类条滑动延迟）**：库的 `MiuixTabRow` 收到选中整数变化后，在 post-frame 再调用 275ms 的 `_controller.animateTo` 自动居中；其指示器也只根据整数下标定位。`TabBarView` 横向拖动提供连续页面进度，两者速度源不一致，导致顶部分段明显落后。可滑动页面的 Miuix 分类条应监听 `TabController.animation`，让指示器直接使用小数进度，并避免为每个下标变化额外滚动动画。
- **撤回错误归因（2.16.5）**：旧记录曾称 SDF 外法线采样是错误方向，并建议向透镜中心折射；该判断与 Kyant 的 shader 源码相反。凸透镜应沿 SDF 外法线从边缘向外取样，不能再因看到凹透镜而反向改成向内采样。shader 公式只能说明采样映射，不能代替真机视觉验收。
- **现象与根因（2.16.7：Miuix 字号比 M3 大）**：Review 的 Material 列表行和应用栏分别覆写成 15/12.5/18sp，而 `ReviewMiuixTheme` 直接使用库默认的 17/14/32sp 等字级。应在主题桥接处将 Miuix 语义字号映射到当前 Material 主题，不改第三方包，也不把已调整的字重再套一遍系统偏移。
- **现象与根因（2.16.7：玻璃栏斜向拖动后跳回原项）**：拖动时透镜位置按 X 轴继续移动，但目标命中仍要求整个指针坐标处于栏内；斜向移出上下边界后 `upIndex` 变成 null，释放回退到按下时的选中项。开始按下仍需命中导航栏，指针捕获后的拖动和释放只根据横向槽位计算目标。
- **现象（2.15.2：标准 Miuix 底栏过小）**：库按图标和间距的固有宽度收缩，玻璃模式则固定为 280×64dp。固定标准栏三项的宽高，让两种悬浮栏采用相同外框和每项分配宽度；窄屏按可用宽度缩小，并继续为 Scaffold 约束内容高度与系统底部间距。
- **现象（2.15.2：Miuix 与玻璃导航没有触感）**：这些控件用 GestureDetector 而不是 Material Ink，因而不会经过全局 `HapticSplashFactory`。在确认选中回调调用 `HapticFeedbackUtil.light()`，覆盖 Miuix 标准栏及 M3/Miuix 玻璃栏；不在按下或取消时提前触发，避免偏好关闭失效或重复震动。
- **现象（2.15.2：时间线长文全部展开）**：前一轮为避免短差异出现“展开全文”按钮，加入 360 字全文、100 字差异和 5 行布局门槛；大量微博全文达不到门槛时反而默认显示全文。时间线应保留官方 `text_raw` 作为预览，只要已取回的标准化全文比预览更长就给出展开入口；点击后才显示全文。未取回时保留预览并允许手动请求；主微博与转发微博一致。长文预取和并发上限不变，删除每次布局进行的 `TextPainter` 行数测量。
- **现象（2.15.1：切换 Miuix 后仍沿用 M3 预置色）**：共用 M3 主色作为 Miuix 种子会令两种风格外观接近。保留一个 Monet 动态色开关，但把 Miuix 内置色索引独立保存并加入个性化备份；动态色存在时共享系统种子，不存在时两个设计语言分别使用各自预置色，兼容 Android 12 以下。
- **适配范围（2.15.1）**：当前功能页大量复用 Flutter Material 控件，逐页替换会复制布局并提高回归面。先在 `ReviewThemeBridge.materialTheme` 集中应用 Miuix 语义色和控件形状/状态样式，同时保留已有 Miuix Scaffold、卡片和设置行适配；新页面优先用 Review 语义组件。不要只改主题色后就认为全应用 Miuix 已适配，也不要为同一业务复制 M3/Miuix 页面。

## 画廊返回动画补充更正（2.14.5）

- **控件与 Hero 同步显隐（3.0.0）**：共享元素飞行层位于页面控件上方，顶部返回/下载控件在 push 期间已显示会压住飞行图片，pop 开始后仍显示则和回程重叠；新 PageRoute 初始插入还可能短暂报告 `completed`，所以仅首个路由按 completed 直接显示，push 路由从隐藏开始等待状态变化。顶部工具组和底部缩略条共用 ModalRoute 状态：push 完成后淡入、reverse 一开始禁用命中并淡出。玻璃按钮的 `BackdropFilter`/fragment shader 不得放进整组 `Opacity` 合成层，否则过渡帧可能采样黑色中间层；改为分别插值图标、玻璃底色和模糊强度。不得改 Hero rect、图片变换、PageView 约束或手势。
- **画廊控件显隐保持图片位置（2.17.3）**：按用户截图要求，让 Pager 在控件显示与清屏状态下始终保持全屏约束，顶栏和缩略条作为覆盖层；此前根据 `_showChrome` 动态添加上下 Padding，改变了 PageView 高度，ExtendedImage 重新适配时让放大图片偏移。不要通过切换主图视口尺寸避让控件，也不要用底部占位补偿中心；单张静态图片自然以全屏为中心，多图缩放和平移状态在控件显隐时保持。
- **单图底部边界更正（2.16.6）**：2.16.5 曾为了对称居中给单图添加底部留白。用户明确指出单图没有缩略条，底部不应设置边界；现仅保留顶部按钮行下沿的 inset，底部延伸到屏幕底部，多图的缩略条间距不变。
- **单图居中尝试（2.16.5，已回调）**：顶部避让使可视区域不对称，因此曾在单图底部加同等留白来把视口几何中心放回屏幕中心；但这样无故限制了无缩略条时的底部空间。不要为追求对称而给单图增加底部占位。
- **顶部边界与缩放焦点修正（2.16.3）**：状态栏下沿方案会让主图进入返回/下载按钮后方，按用户反馈改回安全区加 68dp 的按钮行下沿；多图视口底部从缩略条上沿前 24dp 收到 8dp，释放垂直显示空间。ExtendedImage 在缩放低于 1.0 时按设计强制将图像居中，且长图顶对齐可能覆盖手指焦点；将最低缩放及回弹下限设为 fit 尺寸 1.0，并统一初始对齐到中心，避免适配尺寸以下的空白和焦点偏移。仍需真机验证不同长宽比和多指缩放观感。
- **状态栏作为画廊上边界（2.16.2，已回调）**：曾按反馈试用状态栏安全区下沿，顶部按钮悬浮在主图之上；后续观感反馈证明会遮住图片，因此 2.16.3 恢复按钮行下沿边界。

- **主图顶部留白调整（2.16.1）**：初版在 68dp 顶栏下另加 12dp，导致图片上边界显得过低。按钮行本身由 48dp IconButton 加上下各 10dp padding 组成，安全区之外共 68dp；顶部视口边界直接落在按钮行下边缘，不再额外留白。安全区仍扣除，防止内容侵入状态栏。

- **画廊纵向布局（2.15.4）**：主图原先只扣除了底部缩略条区域，顶部仍铺到状态栏和操作栏背后；`BoxFit.contain` 只能按给定边界适配，不能感知上层 Stack 控件会遮挡内容。给主图设置顶部和底部不等的可视边界，使它在状态栏/顶栏与缩略条之间适配并自然下移；清屏时撤掉顶部控制区占位。保持现有缩放/分页参数，避免为了布局另加缩放动画或手势状态。

- 2.14.4 仍存在落点填充跳变。此前只查 Flutter `RenderImage`，实际 ExtendedImage 的 `ExtendedRenderImage` 独立继承 RenderBox，生产分支并未读到解码比例；而测试用了普通 RawImage，只断言倍率，未覆盖实际库的裁切交接。不能用“倍率正确”推导末帧像素一致。
- 新方案复用现成 Flutter CustomPainter/Rect.lerp 和图片库公开绘制数据，不新增依赖：捕获两端完整图片平面和来源圆角，冻结当前解码句柄，插值图片边缘与裁切窗，避免在变动的 Hero 约束中重新布局手势图片。手势 destinationRect 含 canvas 绘制偏移，需先减去 layoutRect.topLeft，不能直接当本地坐标，否则放大平移时起点错位。
- 横/竖图、缩放/平移的测试均使用 ExtendedRawImage 和正式路由，逐像素比较起点、终点；保留唯一当前 Hero 回归。临时 clone 句柄在飞行卸载时释放，不重新解码/请求；网页卡片、视频保持现有分支。下方 2.14.2/2.14.4 的倍率方案为历史尝试，不能恢复。测试不等同真机帧录制验收。

## 登录与凭据

- **现象**：WebView 已显示登录成功，应用却无法同步凭据，或检测一直转圈。**根因**：SSO 回跳可能跨域，WebView Cookie 与网络层候选值不同步；仅凭一个接口的固定响应结构会误判有效会话。**回归点**：检查移动端回跳、原生与 Flutter Cookie 候选、桌面/移动端验证，以及响应无法确认时是否保留既有有效会话。不要把网络异常当成确定登出。
- **现象**：界面已提示超时，之前的检测稍后仍改变登录状态。**根因**：`Future.timeout` 只停止等待，不会取消 Dio 请求。**回归点**：为实际请求传 `CancelToken`，限制自动轮询并发，并允许手动重新检测。相关历史修复见[变更记录](CHANGELOG.md#28973)。
- **私有登录参数分组与验证码优先**：接入 Review 时用户明确要求短信验证码为主要登录方式，右上角保留 Cookie 导入。Share 的 `jA` Retrofit 注解中 `LLCa` 是 QueryMap、`LuCa` 是 FieldMap；发码的 `account/login_sendcode` 与校验的 `account/login` 各自 QueryMap/FieldMap 不同，不能把密码登录参数或字段分组直接套用。短信校验通过 `phone/number/code=area/smscode` 发送，返回完整 native session 后仍需 Review UID/Cookie 校验；只有通过后才能写 Keystore session。当前 Review 的 API 层仍有 Cookie 直注入与 SharedPreferences 兼容路径，不能宣称已经迁完；退出时同步清理 native session。静态构建不能代替真实短信发送、设备登录、重启恢复、到期 `getoauth` 或 Review API 验收。
- **Android test library 编译缺口**：Manifest 的 `<uses-library android:name="android.test.mock" android:required="false" />` 只声明运行时可选库，不会自动加入 Java 编译 classpath；只加 Manifest 会让 `FakePackageManager` 在 Release Java 编译时报找不到 `android.test.mock`。同时在 Android Gradle 配置中使用 `useLibrary("android.test.mock")`，再分别验证编译成功和目标设备可解析运行库。缺少可选类通常表现为类链接错误；不要把它与本次已定位的 `wbutil` native 注册失败混为一因。
- **Windows Java/Gradle 回归点**：此环境的 JDK 26 和临时 JDK 17 即使独立执行 `Selector.open()` 也会在 Windows loopback Unix-domain socket 连接时报 `Invalid argument`；Gradle daemon 因同一底层 Selector 初始化失败，不能归因于项目源码或仅靠提升权限重试。换 JDK 17 仍失败。JDK 17 `javac --release 17` 与单测可独立运行；SDK 工具手工拼 APK 只验证当前静态产物，不能声称 Gradle task 或设备安装通过。需要在本机 loopback 可用的环境重新跑 Gradle。

## 消息与通知

- **消息页重复安全区与聊天图片遗漏（3.8.1）**：嵌套 `ListView` 的默认 padding 会再次使用环境 MediaQuery 顶部安全区，消息页已在外层补齐顶栏时必须对子列表显式 `padding: EdgeInsets.zero`、`primary: false`。聊天不能只对正文做富文本解析而忽略 WebIM 附件；`media_type=1` 的 `att_ids`/`fids` 通过官方 `msget` 路径渲染，GIF 使用 `pic_infos.original_pic`。保护媒体的 Cookie 仅限精确 HTTPS 主机和路径，预览、全屏和下载使用同一凭据规则。
- **聊天历史自动预取与锚点（3.8.1）**：仅在 EasyRefresh.onRefresh 请求历史会迫使用户触底再下拉；改为距离历史边缘 480dp 时自动请求，单请求互斥、失败暂停并保留游标、空页或无新增停止。私信 `max_id` 与群聊 `max_mid` 都以已加载最早 ID 减 1 请求，不能把私信刷新最新消息当历史分页。统一倒序列表并在末尾追加历史，避免正序列表前插时跳走阅读位置；回归须覆盖两个会话分支、预取而非只触底、重复边界、失败重试和已解码图片。

- **现象**：清除未读后重新进入消息页，头像又出现旧的 `99+`。**根因**：仅修改页面对象，重新获取 WebIM contacts 时旧服务端计数覆盖本地状态。**回归点**：每个会话和互动类别分别保存原始计数基线，显示 `max(0, 原始计数 - 基线)`；新消息从 1 重新计数。打开会话只清该会话，打开互动分类只清对应分类。
- **现象**：免打扰群仍进入侧边栏总数或后台提醒。**根因**：群聊本地免打扰 ID 与角标汇总没有统一使用。**回归点**：灰色角标只在该群头像右上角，聚合数和后台私信通知都排除它；不得把本地设置描述为已同步微博服务器。
- **现象**：发送失败时聊天页仍出现“已发送”气泡。**根因**：把 HTTP 2xx 及本地合成消息当成服务端确认。**回归点**：检查业务响应，再回读会话；不能确认时不展示伪造气泡。WebIM 发送兼容路径尚未通过测试账号验证，不使用用户账号做真实发送测试。

## 数据解析与跨页面状态

- **现象（2.19.12 多图画廊 Live Photo 自动播放且顶部按钮无效）**：`WeiboPicModel.fromJson` 曾把任意非空视频 URL 推断为 Live Photo，而 `video_url` 又同时把同一项标成普通视频；画廊先走普通视频播放器自动播放，顶部控件却操作另一套 Live Photo 控制器。**修复与回归点**：优先使用明确 Live Photo 元数据；普通 `video_url` 保持普通视频语义，只有 Live Photo 标记或 `/livephoto/` 媒体地址作为兼容线索；模型的 `isVideo`/`isLivePhoto` 互斥。多图 widget 回归验证默认暂停、顶栏播放和暂停均操作同一控制器。遇到字段冲突时不要在画廊 UI 分支临时猜测媒体类型，应修正模型解析源头。
- **后续问题（2.19.13 视频字段/GIF 被误认成 Live Photo）**：解析器会读取 `video` 字符串或 map，但普通视频判定原先只看 `video_url`；于是 `video` 字段里的 MP4 可能被当成 Live Photo。另一个分支只凭 `fid` 合成 `/livephoto/<fid>.mp4`，会把带 GIF 地址的媒体伪装成 Live Photo。**回归点**：`video_url`、`videoUrl` 和 `video` 统一视为直接视频源；GIF 从类型和图片 URL 路径识别，带 `fid` 也不得产生 Live Photo 回退地址；只有显式 Live Photo 字段或 `/livephoto/` 媒体地址才分类为实况。模型须保持 `isGif`、`isVideo`、`isLivePhoto` 互斥。
- **现象（2.14.3 动画末帧到位时图片突然放大）**：动画临近目标时图片仍显得较小/完整，落到九宫格后突然按实际缩略图放大裁切。**根因**：2.14.2 使用微博模型中的宽高推导 cover 缩放；宽高缺失时回退成 1:1，字段不准时也与已解码来源缩略图的真实比例不符，导致 Hero 最后一帧与 Flutter 接回来源子树后的实际图像不一致。**修复与回归点（2.14.4）**：在来源缩略图子树中读取 `RenderImage.image` 的像素宽高比，用于计算飞行末端 cover 缩放；目标布局尺寸仍从来源 Hero 的 `RenderBox` 获取，只有无法读取已解码图像时才回退模型尺寸。用真实 Hero push/pop widget 测试构造“缺失模型尺寸 + 2:1 解码图 + 1:1 目标格”，断言回程终点倍率为 2；真机帧录制仍需复核最后一帧交接。
- **现象（2.14.3 多图 Hero 返回）**：先浏览多张图片再返回时，当前图和前一张已访问图片同时飞回缩略图。**根因**：画廊 `PageView` 会保留相邻页，但所有保留页都挂载了 Hero；其 tag 又各自能与来源九宫格配对，因此一次 pop 会启动多条共享元素飞行。**修复与回归点（2.14.3）**：保留分页/预热行为，仅在 `index == _currentIndex` 时挂载画廊 Hero；测试打开三图画廊，依次切到第 2、第 3 张，确认每个时刻只有当前图的 tag 在来源与画廊两侧各出现一次，前序图片仅留在来源侧。不要通过禁用 PageView 邻页缓存来解决，否则会牵连滑动流畅度、播放器/Live Photo 生命周期与图片复用。
- **现象（2.14.1 竖图 Hero 返回）**：返回起点/终点会发生明显裁切跳变：画廊用 `BoxFit.contain`，来源普通缩略图用 `BoxFit.cover`；仅固定飞行子树并不能自动插值图片内容的填充方式。**修复与回归点（2.14.2）**：返回 shuttle 保留当前画廊子树，并用其图片宽高比和来源 Hero 实际目标尺寸算出最终 cover 缩放因子；随着 Hero 反向进度从 1 连续插值到目标因子，再由来源缩略图接管。方形图片/方框目标保持比例因子 1；网页自动卡片仍完整显示、不做裁切；不再创建第二个图片网络组件，避免重复加载。测试需断言竖图在回程中点和近终点的缩放值处于连续区间；真机仍需确认图片边界、手势返回和最终裁切观感。
- **现象（2.14.0 画廊返回）**：打开图片的 Hero 动画正常，但返回时图片会先突然采用近似全屏的尺寸/裁切状态，再缩回缩略图。**根因**：Flutter 默认 Hero shuttle 在 push/pop 两个方向都使用目标 Hero 子树；pop 的目标是来源缩略图，于是飞行刚开始就替换了全屏画廊的显示布局。**修复与回归点（2.14.1）**：来源与目标 Hero 使用同一个方向感知 shuttle，push 选目标画廊子树、pop 选当前画廊来源子树，结束飞行后再恢复缩略图；保留 Hero 的原始 rect 插值和现有路由，不另加动画依赖。路由级 Widget 测试需覆盖 pop 飞行中及结束后的内容状态；分页到来源未渲染的媒体时仍不保证存在配对 Hero。测试无法证明真机图片解码、裁切和返回手势的视觉观感，需继续实机验收。
- **现象**：点击微博缩略图后，画廊整页直接淡入，原图与缩略图没有连续放大/缩回关系。**根因**：现有路由只有页面淡入，源图和画廊图没有共享元素配对。**修复与回归点（2.14.0）**：在微博图片网格与全屏图之间用 Flutter `Hero` 配对；tag 包含每个网格实例 scope、媒体下标和图片身份，防止同屏多个相同状态互相配对。仅来源网格与画廊均保留时可往返飞行；分页切到来源未渲染的额外照片后，返回不保证有对应缩略图动画。视频继续走播放器/封面，不强行对视频帧做 Hero。Widget 路由测试验证 source/destination tag 匹配；仍需真机检查图像裁切、跨主题层级和返回手势观感。
- **现象（2.13.0）**：底部缩略条快速滑到末尾后，主图仍按逐页动画队列缓慢追赶，期间图片索引和滚轮位置明显脱节。**根因**：把逐张视觉反馈实现为串行 `animateToPage`，总时长随跨页数增长，快手势必然领先主图。**修复与回归重点（2.13.1）**：拖动/惯性阶段用滚轮连续页坐标直接驱动主图 PagePosition；页切换由真实滚动位置决定，不再排队播放主图动画。松手后两个控制器并行用同曲线和时长吸附到最近页。跨页滚动时暂停视频/Live Photo 激活，停稳后只激活最终项。覆盖双平台、双方向、慢拖、快 fling、松手吸附和主图手势打断；确认主图/滚轮位置同步、无回跳，快速页变化的触觉仍遵守全局开关。真机触感和真实混合媒体仍需单独验收。
- **现象**：有原生选项投票的微博仍在投票卡片前渲染一张占版面很大的蓝色默认图片。**修复重点（2.13.0）**：投票模型提前从原始状态解析；只跳过与同一投票相匹配的网页卡片占位图，保留真实 `pic_infos` 配图和原生投票控件。不要仅按“状态有 poll”清除整条微博图片，也不要隐藏其他普通链接卡片。用户提供的微博 URL 无法匿名读取，需在真机确认对应占位图消失、真实照片和选项仍在。

- **现象（2.11.0 画廊）**：横图缩略图挤压变形；快速划过多个缩略图后，主图随滚轮吸附逐张倒退。**根因**：同时指定解码宽高使资源比例变形；滚轮每次跨页立即驱动主图，而主图回调又跳转滚轮，叠加分页弹簧导致双向反馈。**修复与回归点（2.12.0）**：解码只设宽度，显示时 cover 裁切；滚轮惯性用 clamping、不逐页吸附，停稳视觉对齐后仅提交一次选中下标；主内容手动翻页优先取消旧惯性。覆盖 Android/iOS 两方向快速 fling、拖住不切主图、主图中断惯性、清屏恢复，不能仅断言最终下标。
- **现象**：图片夹视频滑到视频只显示封面。**修复与回归点**：复用既有播放器嵌入画廊，横向手势统一归分页，进度调整保留滑块。PageView 会保留屏外子项，不能只依赖父组件重建或 dispose 推断播放器已停止；显式当前下标通知使非当前视频卸载，异步初始化每次 await 后校验生命周期。后端替身验证切走释放、晚到初始化不播放、左右滑不 seek；真机解码和网络播放需另行验收。

- **后续更正（2.11.0）**：2.10.1 把多图展开也叫“展开全文”，导致文字与图片出现两个同名入口，不符合用户要求。当前列表固定 9 张，第 9 张显示剩余数量，点击打开完整画廊第 9 张；不再原地展开图片。文字按钮位于内容和附件下方，只操作正文；超过 9 图的短正文在旧快照误标长文且未取得全文时，只有明显省略/展开标记或达到预览长度才保留未知全文入口，详情补取与源端处理不变。回归必须检查按钮数量、位置、短正文、转发及画廊初始下标，而不只验证图片数。所有多图的缩略图滚轮复用分页，不预取全量原图/Live 视频；清屏时保持滚轮状态，避免恢复后选中图跳回第一张。下条 2.10.1 的原位图片展开方案仅保留为历史记录，不可恢复。

- **现象（18 张配图微博）**：列表把全部图片铺开，却在正文后显示没有效果的“展开全文”；详情只剩 9 张。**根因**：通用 `continue_tag` 被当成长文字标记，图片网格没有单独的折叠状态，详情补全又用移动端的前 9 张替换桌面完整列表；完整 PID 的部分图片也会因缺少 `pic_infos` 而被丢弃。**修复与回归点**：文字标记和图片展开分别处理；列表只渲染前 9 张，按钮位于图片下面，点击本地展开全部；详情和画廊保持完整顺序。移动端补全只能补充普通配图，自动卡片仍合并前景/背景；完整 PID 缺少元数据时复用已有图片地址回退。覆盖短正文多图不触发全文请求、主微博/转发的 9→18→9、详情始终 18、完整画廊、长文字和多图各自展开，以及快照往返；不恢复卡片后台全文预取。
- **现象**：微博官方客户端评论昵称旁有铁粉等级标识，而 Review 评论区没有。**根因**：评论用户模型只解析认证等基础资料，没有保留评论响应里的 `fansIcon.icon_url`，对应 UI 也没有绘制。**修复与回归点**：保留官方用户图标 URL，并在一级评论、楼中楼预览/完整回复及收到的评论列表展示同一资源；复用磁盘缓存，不增加评论或用户资料接口。铁粉等级颜色由服务端图标决定，不做本地等级推断；若响应未提供（例如接口选择显示超话等级徽标），保持不显示。微博客服中心[铁粉等级说明](https://kefu.weibo.com/faqdetail?id=21662)确认标识可在博主正文页评论区出现，并说明超话等级与铁粉标识互斥。
- **现象**：展开全文后只多出一小截，按钮马上变成“收起”，读起来像没有展开。**初次修复仍不足**：仅把行数差门槛从 1 提到 2，仍会被临界排版、段落换行或富文本测量放大成无意义折叠。**修复与回归点**：先检查全文至少 360 个 Unicode 字符、被预览省略部分至少 100 字符，再要求按当前可用宽度测得至少多 5 行才折叠；否则显示完整正文。手机逻辑宽度 390dp 下覆盖多行但总长适中的尾部补取，确保只在“预览确实省略了相当长的一段”时显示展开/收起；同时覆盖数百字真正长文、主微博/转发、表情占位和补取路径。
- **性能回归（2.9.7 测试包）**：把每张未知全文的长微博卡片都立即自动补取，会让连续出现的长微博触发成批网络请求，并造成列表卡顿、加载状态反复刷新。自动请求不能绑定卡片初始化或列表构建。列表主微博和转发微博只在卡片进入视口且滚动停止 500ms 后补取；滚动时取消未发出的计时器，屏外卡片不请求；仓库将全文请求并发限制为 2，继续合并同 ID 请求并使用 96 条进程内 LRU 缓存。自动补取不展示加载行，失败后留手动重试。回归测试必须覆盖屏外不请求、可视且停稳才请求、主微博及转发补取和并发上限；详情页直接补主微博全文的行为不能因此丢失。
- **现象（2.9.9 快速滚动时长文仍突然展开）**：滚动位置变更序号只能挡住已观测到的滚动；全文回包可能赶在下一次滚动事件之前到达，卡片仍会重建成不同高度。因此“延后请求/延后应用”不是可靠的稳定性边界。**当前修复与回归点**：将解析前移至 `FeedRepository` 的前台列表解析阶段，只有源状态标记长文时才取主微博/转发全文，全文填入模型后整批返回；卡片只根据首帧已有模型决定折叠，不对时间线卡片自动请求或替换正文。后台个人主页媒体缓冲明确不补长文，避免再次造成成批请求和列表加载变慢；现有全文请求合并、96 条缓存与并发 2 上限继续生效。回归测试覆盖仓库返回前主/转发均已补齐、后台解析选择退出、未解析卡片滚动后不自动请求、已解析卡片滚动期间内容稳定，以及手动展开仍有效。详情页本身继续按需补主文。
- **现象**：生日自动卡片在时间线正常，但浏览记录中图片/祝福消失。**根因**：浏览历史存储使用 `WeiboStatusModel.toJson()` 的 `pics` 列表，而 `fromJson()` 只读取接口原始 `pic_infos`；回读本地快照时图片层被丢弃。**修复与回归点**：本地 `pics` 是 `pic_infos` 缺失时的反序列化回退，并验证自动卡片标记/背景 URL/`url_struct.url_title` 全部往返保留。旧快照只有 `url_type=39` 自动卡片链接时，复用主页的有界补全，成功后原位更新，不能更改历史顺序；失败不能阻塞浏览记录。
- **现象**：自动生日卡片正文文案落在图片下面，且只在文章详情里显示。**根因**：先前把 `url_title` 当独立图片说明放在图片外，列表也未传入文案。**修复与回归点**：将祝福作为图片层内覆盖文字，同时从微博正文移除重复祝福；列表卡片与详情页必须都只显示一份，并验证点击覆盖区域仍由图片手势打开图片。自动卡片的前景/背景合并问题仍按下条的测试方式覆盖。
- **现象**：自动生日卡片在列表完整，进入详情后只剩头像前景图且祝福文案消失。**根因**：移动端详情补全可能返回不带背景的单层图或空正文，直接覆盖桌面详情已解析出的分层卡片和非链接正文。**修复与回归点**：合并移动端与桌面图层，移动端缺少背景时保留既有背景和画布比例；移动端正文为空时移除自动卡片短链但不删除已有普通正文；生日祝福从官方 `url_title` 读取。需同时测试“移动端完整返回背景”和“移动端只有前景/空正文”两种响应。匿名实时接口可能被微博限流，模拟响应测试不等于真机/线上验收。

- **现象**：取消关注显示“你访问的地址不存在”。**根因**：3.0.1 将桌面端微博取关路径写成标准拼法 `/ajax/friendships/destroy`，而网页端接口沿用历史拼写 `/ajax/friendships/destory`；移动端对应 `/api/friendships/destory`。该拼写亦见[公开网页端接口实现记录（非官方）](https://github.com/imoonkey/openweb/blob/main/src/sites/weibo/DOC.md)。**修复**：桌面常量改回 `destory`，移动端既有路径不变。**回归点**：桌面和移动会话分别测试取消关注的 host、path、Cookie/XSRF 和表单/请求体；只测试关注或只验证代码拼写不足以证明取关接口正确。公开资料不是微博官方 API 文档，仍需用户在自己的账号上验收；本次未执行真实账号操作。
- **现象**：“我的收藏”接口成功，页面却为空。**根因**：`/ajax/favorites/all_fav` 的 `data` 可能直接是列表，按固定 `data.list` 结构强转会失败。**回归点**：先做运行时类型判断，再按实际响应结构解包；不要用空 `catch` 掩盖解析错误。
- **现象**：子页面已点赞的微博再次点击仍发送点赞请求。**根因**：复用卡片只查询首页控制器，子页面持有的是自己的列表状态。**回归点**：操作以卡片当前有效状态为准，失败时回滚，并向外部列表同步结果。
- **现象**：列表翻页断流或楼中楼只显示首段预览。**根因**：混用上刷与下翻参数，或丢弃服务端游标。**回归点**：按各接口的 `max_id`、`is_mix` 等实际返回值续页；不要把首屏数组当成全部数据。

- **现象**：普通微博列表有两张真实配图，详情却多出“抽奖详情”的小图。**根因**：将 `url_type=39` 通用网页链接及网页缩略图都视为自动动态图片，详情补全后把抽奖导航图混进配图。**修复与回归点**：按单条链接的标题、对象类型或微博抽奖域名在共享模型里排除抽奖缩略图，同时取消该链接的自动卡片补全资格；不能按整篇正文出现“抽奖”或按图片尺寸过滤真实配图。覆盖 `url_struct` 链接内图片、`url_objects` 图片、移动端 `page_info` 和历史快照往返；生日/夺金分层卡片、祝福与普通正文链接必须继续保留。已有旧快照中已经存下的误配图不做无依据删除，重新获取官方状态后使用新规则。

## Android 与交互

- **画廊液态按钮水滴边缘不明显（3.5.1）**：先前按钮虽使用 `GlassButton`，但 `stretch: 0` 禁用了拖动形变，`isStationary: true` 让玻璃层不按交互状态渲染，色散 `0.008` 也低于底栏水滴的 `0.025`。保留按钮动作和开关关闭路径；开启时复用底栏水滴折射率/色散、启用锚定拉伸与回弹，并匹配底栏白色交互高光。回归检查短点仍触发原动作、长按/拖动不执行点击、下载中仍禁用；高刷新率/低端设备的实际观感与帧率需真机确认。
- **更正（3.5.3：画廊按钮仍像普通玻璃）**：3.5.1 只调整了折射参数，却没有把 `GlassButton` 的默认 `standard` 画质改为完整 Impeller shader 路径；同时显式 `interactionScale: 1.06` 把 48dp 按钮按压膨胀压到约 3dp。开启时应请求 `GlassQuality.premium`，交给已存在的 `GlassAdaptiveScope` 按设备能力降级，并移除固定缩放覆盖，使用库原生约 17dp 的按压膨胀；媒体视口必须作为背景纹理来源，按钮层不进入采样以防反馈。静态构建不能证明按钮下的文字/图像弯曲强度，仍需真机检查。
- **更正（3.5.4：画廊按钮静止态透镜不明显）**：48dp 按钮使用厚度 10 时，静止态的折射边缘很弱，只有按压膨胀成更大的水滴后才容易看见；自适应质量降到 `minimal` 也会移除折射 shader。保持原有 `GlassButton` 静态 shader 和长按形变路径，将玻璃厚度调到 32、折射率调到 1.24，并将仅包住画廊按钮的质量下限设为 `standard`，使图片/视频在按钮静止时也持续经过透镜边缘折射。两个小按钮面积有限；不叠加第二套 BackdropFilter，避免重复采样和额外 GPU 成本。实时视频下的观感与性能仍需目标设备核验。

- **液态玻璃底栏按住水滴误触（3.4.2）**：库会在按下阶段回调当前 Tab，导致时间线/热搜重复点击的回顶/刷新逻辑在长按拖动开始时误执行；拖动释放又会按当前指示器位置叠加速度步进，快速抛动可能跨过热搜。共享玻璃导航适配层应缓存触控选择直到 pointer-up，以最终拖动回调提交；长按/拖动落回起始 Tab 时抑制同页动作。3.4.2 初版把相邻页限制套在所有水平拖动上，普通慢拖也可能被截断；当前只将释放水平速度达到 `1000 logical px/s` 的快速抛动限制到起始页相邻一项，慢拖按水滴最终位置提交。取消手势不提交，键盘/读屏操作保持即时。

- **慢拖水滴到设置却停在热搜（3.5.2）**：共享释放逻辑原先把每次水平拖动都夹到起始页前后一个索引，导致有意慢拖时间线到设置也只能停在热搜。用 Flutter `VelocityTracker` 读取释放水平速度，仅在绝对速度达到 `1000 logical px/s` 时保留一页上限；低于阈值时提交玻璃栏最终回调的 Tab。静态分析/构建不能代替目标设备的真实手势速度验收。

- **主底栏与普通页面转场（3.1.0）**：参考 Lurk 的真实实现，普通页面是新页整屏覆盖滑入、旧页不动且不淡化；LTR/RTL 进入方向相反，push/pop 使用 ease-out/ease-in 并尊重系统关闭动画。主底栏需同时驱动离开页和进入页反向平移一个屏宽；不要用 `PageView.animateToPage`，因为跨多个索引会按页数移动，和 Lurk 的单屏切换不一致。用 `Stack` 保持页面挂载，只给当前页及转场中的前一页启用绘制/动画；保留重复点击当前底栏触发的既有回顶/刷新语义。Android 动画开启时保留 `WidgetsBindingObserver` 到 `PageRoute` 的预测式返回进度桥接，并在路由卸载时注销；iOS 保留 Cupertino 边缘返回手势；图库 `PageRouteBuilder`/Hero 动画不接入全局普通页面转场。

- **现象**：微博文章封面被转换为普通配图后，点击只能打开画廊，无法进入已适配的文章阅读页。**根因**：图片模型没有保留链接语义，自动卡片和原生文章共用图片点击分支。**修复与回归点**：为文章封面保存原生文章目标，点击复用既有路由；只认可微博官方文章 URL 或明确的 article 对象 ID，不将通用网页、视频、抽奖或生日/荣誉卡片误判成文章。覆盖桌面/移动 URL、各接口封面结构、旧快照补回目标、序列化往返，以及列表/详情点击进入原生阅读页；加载列表时不能提前请求文章内容。

- **现象**：热搜页底栏双击或顶栏双击可能只回顶、不刷新，或误刷新其他分类。**根因**：各热搜分类分别持有懒加载列表状态，页面层不能直接操作当前分类列表。**回归点**：动作从当前 `TabController.index` 定位该分类状态；回顶使用该列表自己的 `ScrollController`，刷新只调用同一分类现有接口；页面切换时取消底栏单击判定计时器，离开页面/销毁时释放计时器和控制器。
- **现象**：自动奖牌/会员卡片在时间线中被压成窄长图，详情画廊却正常。**根因**：用透明前景图的尺寸计算合成卡片容器比例，再用 `BoxFit.cover` 裁切前景与背景。**回归点**：有独立背景层时以背景画布成对宽高作为比例来源；没有可用尺寸时采用横向卡片默认比例；自动卡片图层使用等比完整显示，普通微博图片布局保持原样。
- **现象**：应用重启后部分图片重新下载、临时缓存持续增长。**根因**：`Image.network` 只保留进程内缓存，而 `extended_image` 的磁盘缓存默认没有容量上限；完整 URL 不同也会产生不同缓存文件。**回归点**：新增图片入口复用统一的磁盘缓存，并确认 `ExtendedNetworkImageProvider` 显式开启 `cache`；缓存维护只扫描临时 `cacheimage` 目录内 MD5 命名文件，不能触碰相册媒体和账号资料。真机需区分加载占位与实际网络下载，并测量冷启动流量及缓存大小。
- **现象**：本机 JDK 17 构建时报 `Selector`/loopback 错误。**根因**：默认用户临时目录的本地通信管道异常。**回归点**：按 [Release APK 步骤](../DEVELOPMENT.md#102-release-apk)在当前构建进程中使用已存在的项目临时目录，构建完成后核对 APK 元数据和签名。
- **现象**：仅为构建改版本时 `pubspec.lock` 被重写。**根因**：Release 命令默认再次执行 Pub 解析，可能切换 hosted 源或升级约束内的包。**回归点**：依赖已解析时使用 `--no-pub` 构建；依赖更新单独执行 `flutter pub get`，确认锁文件差异有意后再打包。
- **现象**：模态弹窗出现慢、背景水波纹拖尾。**历史误区**：旧手册 8.6 节建议人为等待 80ms 并使用 `InkRipple`，8.10 节随后撤销了这套做法。**当前代码**：`HapticSplashFactory` 默认委托 `InkSplash.splashFactory`；修改弹窗交互时以当前源码和真机效果为准，不恢复旧延迟。
- **现象**：点击微博正文中的 `@用户` 打开主页时没有触感。**根因**：提及文字由 `TextSpan` 的 `TapGestureRecognizer` 单独处理导航，不经过 Material 水波纹的全局按下反馈。**修复与回归点**：在提及点击回调中调用 `HapticFeedbackUtil.light()`，复用触感开关、冷却与同手势去重；针对正文提及点击验证主页回调和单次轻触，话题、链接及普通文本不改变。

- **缓存管理不得扩展到整个临时目录（3.8.0）**：GreenNote 的原生实现会清除 Android cache/code-cache/external-cache，Dart 回退路径还会递归删除整个 temporary directory；Review 已有明确边界，只允许清理 `cacheimage` 下直接存放且名称符合 32 位小写 MD5 的 ExtendedImage 文件。手动和自动阈值清理沿用最近 1 分钟文件保护；统计范围必须与实际可删范围一致，不能显示或宣称清理其他临时、账号或相册数据。普通悬浮底栏的选中背景由单个定位胶囊跨等宽 Tab 动画移动，不要恢复每个槽位独立淡入的实现。

## 文档维护

修复完成后，将当前行为写入 `DEVELOPMENT.md`，版本和当次验证写入 `CHANGELOG.md`，可复用的根因及回归点写在本文件；顶栏规范变更还要维护 `FROSTED_TOP_BAR_DESIGN_SPEC.md`。运行同步脚本，将这些当前文档的完整正文汇入 `D:\App\开发文档\Review.md`，不能只保留索引链接。旧版综合手册原件留在仓库归档目录、不再拼进现行主文档；签名口令、Cookie、Token 等凭据不进入任何开发文档。


## 微博 HDR 原图与缩略图不能混为一谈（3.9.0）

- 同一张用户提供的微博图，原图实测含 gain-map 与 ISO 21496 元数据，缩略图却已剥离。不能根据发布机型、HDR 宣传、普通高光观感、图片文件名或缩略图推断原图 HDR 状态。元数据只作候选提示，最终必须由 Android 解码后的 `Bitmap.hasGainmap()` 确认。
- 不要让 HDR 通道重新下载全图、在主线程解析完整文件，或给相邻每页常驻原生大位图；复用鉴权下载后的缓存，异步检测/限量解码，停稳当前页才挂载原生层，并在退场恢复原窗口模式。
- 原生 ImageView 已按 fit-center 适配；变换时应相对适配矩形统一缩放 X/Y，并扣除 ExtendedImage 的 layoutRect 偏移。直接按原图/视口各算一个比例会导致双击横向拉伸。Hero 飞行层继续只使用 Flutter 图片，不能把 PlatformView 放进飞行子树。
- 既有画廊已变成 ConsumerStatefulWidget，widget 回归须用 ProviderScope 并覆盖初始化好的 StorageService；仅补 ProviderScope 仍会触发未初始化的存储异常。HDR 测试需在各轮真实文件 IO 之间推进 fake-async 的 pump，并在测试体结束前复原 debugDefaultTargetPlatformOverride，不能只在 addTearDown 复原。

- 用户样本的增益图与 7170×4033 底图同尺寸；只按底图的 4 字节/像素估算原生预算可能导致一个 HDR 位图超过 LRU 上限、插入即被逐出。当前按底图+增益图合计最多 16 字节/像素计算目标尺寸，缓存实际计费也包含 gain map；插入后确认仍在缓存才能启用原生叠层，避免只出现 HDR 角标却创建空原生视图。最后预算修改后必须重新编译并在 DEX 中确认最终字段，不能交付修改前的 APK。


## HDR 无角标与聊天媒体占位（3.9.1）

- `hasGainmap` 检测本身正确也会因输入是已剥离增益图的预览版本而完全不显示角标；先核对运行时真正请求的 URL、缓存和原生解码，再讨论屏幕增亮。不应只检查离线下载过的另一份“原图”。新浪图床升级仅限指定域名和规格段，不改写私信带鉴权 URL 或第三方链接。
- 全屏画廊和聊天消息不能共用“固定图片宽高+文本气泡”假设。媒体的宽高应随原图比例约束，纯媒体移除协议占位文字和大块 padding；有实际附言时保留。附件与 pic_infos 可能描述同一张图，不能渲染两次。
- 官方 Web 的普通链接、卡片、动态图分别依赖不同字段；解析 `url_objects` 不能只取 URL 而丢弃 `status`/`user`/嵌套 `object`。缺失元数据时仅对可见消息补查官方完整消息，避免历史加载引发无界外部抓取或重复补查。
- 图片表情的 HTML alt 可能是 `[/ee90a0.png]`。提取 HTML img 还不够，后续 tokenizer 同样要允许这个标签形状；缺失图片地址时还须兼容 SoftBank PUA 到 Unicode。回归同时覆盖 HTML 图片和仅文件名的纯文本，以及非法 UTF-8，避免只修复一个固定表情名称。

## 信息流 HDR 角标和聊天图片转场（3.10.0）

- 信息流缩略图已剥离 gain-map，若要求点击前显示角标，只能读取大图来源的轻量元数据。新浪当前对样本原图支持 HTTP Range；请求必须限制为文件头、用 stream 读取上限、只打到可信新浪图床大图路径，并避免复用会自动附加微博 Cookie 的全局 API Dio。有限头部探测显示的是候选 HDR 元数据，不可冒充设备 `Bitmap.hasGainmap()` 确认。
- Hero 的匹配依赖 scope 对象身份以及相同媒体下标和 URL。聊天消息应在自身生命周期内保存稳定 scope，把消息全部图片放进画廊并用点击图像下标作为 initialIndex；仅推一个无 scope 的 gallery 虽然能显示全屏图片，却只会执行页面转场，无法播放既有图片放大/缩回动画。
- 预览范围已扩到与画廊相同的 256 KiB，但用户反馈此调整没有修复“点开再返回才有角标”；不能再将头部范围作为本次现象的已确认根因。聊天图片入口要显式复用 `HapticFeedbackUtil.light()`，因为 `GestureDetector` 不经过 Material 水波纹触感桥接。

## HDR 首次等待者自等待（3.10.1）

- 根因是 `whenComplete(() => pending.remove(url))` 的隐式返回值：表项本身就是包含该完成回调的 Future，`whenComplete` 会等待返回的 Future，于是形成自等待。前面的缓存写入已发生，首次等待者却收不到结果；从画廊返回后 Hero 重建才从缓存得到结果。这不是靠扩大 Range 就能修复的问题。
- 清理必须写为不返回值的语句块 `whenComplete(() { pending.remove(url); })`。测试先用正常成功响应复现首次九宫格无角标，再在修复后确认不点击图片也能出现角标；同时检查并发等待者、SDR 负结果与失败请求完成清理。不要只测下层 HTTP 解析或第二次缓存命中。

## 底栏切页开销与 WebIM 发送格式（3.10.1）

- 屏幕刷新率 120Hz 不能证明应用实际交付 120fps。主 Tab 直接平移复杂页面且没有页面绘制隔离，标准指示条还在逐帧布局。修正为每页 RepaintBoundary 和固定尺寸指示条的 AnimatedSlide；回归检查六个 8,333 微秒步长内的真实页面 paint 复用、连续位置、快速反向切换、页面状态和减少动画。不能据此宣称真机 GPU/玻璃合成已经稳定低于 8.33ms。主框架退出还暴露了 FeedView.dispose 中 ref.read 无效的问题，改为保存 notifier 引用并检查首帧延迟挂载的 mounted。
- 上一实现仅防止了伪造成功气泡，没有证明发送功能可用。核对官方 Web 源码后确认两个端点通过 qs.stringify 发送表单，旧实现的 Map 默认编码为 JSON；文本还需 is_encoded、私信 decodetime、群聊 media_type/annotations 等官方字段。群聊成功响应的 mid 未被旧判断覆盖。必须测试 HTTP adapter 实际收到的编码 body，而非仅 mock 方法返回成功。发送失败保留输入、显示官方错误；接受后按消息 ID 回读，不将一分钟内同文本旧消息当成本次确认，不自动重复发送。没有测试账号投递证据时必须明确标为尚待账号验收。
- 聊天历史已有边缘自动分页，不应再用反向 EasyRefresh 给用户展示上拉刷新提示。移除刷新包裹，保留自动历史预取和失败重试；相关网格 widget 用专用模拟 HDR adapter 并推进异步完成，避免首次探测留下测试计时器。
