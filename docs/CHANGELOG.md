# Review 变更记录

这里记录已经完成的版本变更及当次验证结果。当前行为和发布命令以 [DEVELOPMENT.md](../DEVELOPMENT.md) 为准；历史测试数量不代表以后构建的测试结果。更早、更细的实施记录保存在[旧手册归档](archive/Review-legacy-2026-09-23.md)。

## 2.14.5+103（2026-10-05）

- 重做普通图片 Hero 返回的裁切交接：读取实际 `ExtendedRenderImage`（同时兼容 Flutter `RenderImage`），冻结已解码像素及当前缩放/平移的绘制区域，以来源缩略图实际 cover 区域和圆角为终点。完整图片平面与裁切边界分别连续插值，不在飞行中重新布局手势图片，也不在落点再次填充；保留当前图片唯一 Hero、自动网页卡片和视频的既有分支。
- 不增加网络请求或依赖。临时克隆图片句柄共享已解码像素，退出飞行时释放。新增使用实际图片组件和正式画廊路由的像素级回归，横图/竖图、普通/放大平移状态分别比较返回起点和终点；不再仅验证缩放数值。
- `flutter test --no-pub` 全量 220 项通过（含 19 项画廊测试）；改动文件 `dart analyze` 无问题。全项目分析无 error/warning，保留 51 条 info；`git diff --check` 通过。arm64 Release APK 构建成功，核验 `com.review`、`2.14.5`、versionCode 103、arm64-v8a 和 v2 签名。产物 `Review_v2.14.5.apk`（31,764,600 字节），SHA-256：`EC75A7CC2FD7BCA5D19EE7B31287D1F9D5B3B68FAADDA2DC8CEEFA804C3BE773`；旧根目录 APK 已移入 `build/previous-deliveries/Review_v2.14.4.apk`，可恢复。真机动画需复测，不能把测试通过等同于设备视觉验收。

## 2.14.4+102（2026-10-05）

- 修正多图 Hero 返回动画的末帧跳变：微博图片模型宽高可能缺失/不准，上一版会按错误比例计算缩略图 cover 缩放，最后一帧交接给来源网格时内容突然放大裁切。现在优先使用来源缩略图已解码的实际像素比例，模型比例仅作为回退；没有新增图片请求或依赖。
- 新增实际 Hero 路由回归测试，故意让模型尺寸缺失、解码图为 2:1，并验证动画末帧使用真实来源裁切比例。
- `flutter test --no-pub` 全量 217 项通过（含 16 项画廊测试）；改动的画廊实现与测试文件单独 `dart analyze` 无问题。全项目 `flutter analyze --no-pub` 无 error/warning，保留 51 条 info 级提示；`git diff --check` 通过。arm64 Release APK 构建成功；核验包名 `com.review`、版本 `2.14.4`、`versionCode` 102、ABI `arm64-v8a` 和 APK v2 签名。产物 `Review_v2.14.4.apk`（31,764,600 字节），SHA-256：`240B0DE31609DDFC729E0B0A9E304BF33C7BADB8EC5501287CB4F1D08FFEC877`。旧版 `Review_v2.14.3.apk` 已移入 `build/previous-deliveries/`；未安装到真机验收。

## 2.14.3+101（2026-10-05）

- 修复多图画廊返回动画重复飞回的问题：分页缓存的邻接图片不再挂载 Hero，仅当前显示的图片与来源缩略图配对；即使连续浏览多张再返回，也只对停留的那张执行 Hero 回程。
- 新增路由回归测试：打开 3 张图的画廊并依次停留在第 1、2、3 张，逐一确认唯一的画廊 Hero 只与当前索引的来源图配对。
- `flutter test --no-pub` 全量 216 项通过（含 15 项画廊测试）；改动的画廊实现与测试文件单独 `dart analyze` 无问题。全项目 `flutter analyze --no-pub` 无 error/warning，保留 51 条 info 级提示；`git diff --check` 通过。arm64 Release APK 构建成功；核验包名 `com.review`、版本 `2.14.3`、`versionCode` 101、ABI `arm64-v8a` 和 APK v2 签名。产物 `Review_v2.14.3.apk`（31,764,600 字节），SHA-256：`EAA220C8ED3E76046A15508C8FE1F3A0E09BB29065F120314C9ACFC56113375F`。旧版 `Review_v2.14.2.apk` 已移入 `build/previous-deliveries/`；未安装到真机验收。

## 2.14.2+100（2026-10-05）

- 进一步修复非方形图片的 Hero 返回动画：外框回缩时，画面从全屏 `contain` 状态连续缩放到来源缩略图的 `cover` 裁切状态；不再在开始或到达缩略图时突然变形。方图在方形网格中缩放因子为 1；微博自动网页卡片仍按完整比例显示，不套用 cover。
- 复用正在飞行的画廊子树及图片缓存，无新图片请求或依赖。竖图回程中点/近终点缩放插值断言通过；画廊相关 14 项、全量 215 项测试通过。`flutter analyze --no-pub` 无 error/warning，保留 51 条 info 级提示；`git diff --check` 通过。arm64 Release APK 构建成功；核验包名 `com.review`、版本 `2.14.2`、`versionCode` 100、ABI `arm64-v8a` 和 APK v2 签名。产物 `Review_v2.14.2.apk`（31,764,600 字节），SHA-256：`12153D0CA6581B42604D30E98AC63F78135335F261F920774B09F9748ACE68FA`。旧版 `Review_v2.14.1.apk` 已移入 `build/previous-deliveries/`；未安装到真机验收。

## 2.14.1+99（2026-10-05）

- 修复图片画廊 Hero 返回动画：Flutter 默认 shuttle 在 pop 时采用目标缩略图子树，可能让正在全屏显示的图片在收缩前突然切成缩略图的尺寸/裁切效果。现在返回飞行期间保留全屏画廊子树，动画结束后再显露源缩略图；进入方向保持使用全屏目标子树。
- 新增路由级 Widget 回归测试，验证 pop 飞行期间仍展示画廊子树，飞行完成后才恢复缩略图。`flutter test --no-pub` 全量 215 项通过（含 14 项画廊测试）；`flutter analyze --no-pub` 无 error/warning，保留 51 条 info 级提示；`git diff --check` 通过。arm64 Release APK 构建成功；核验包名 `com.review`、版本 `2.14.1`、`versionCode` 99、ABI `arm64-v8a` 和 APK v2 签名。产物 `Review_v2.14.1.apk`（31,764,596 字节），SHA-256：`E5885A3723BFE061B4DA94BD801D62DCB35DD09E7B3C2C081601262AA91BC047`。旧版 `Review_v2.14.0.apk` 已移入 `build/previous-deliveries/`；未安装到真机验收。

## 2.14.0+98（2026-10-05）

- 为微博图片网格接入 Flutter 共享元素 `Hero` 动画：点击图片时从原缩略图位置放大进入全屏画廊，返回时缩回来源位置。来源网格使用独立 scope 和媒体身份配对，避免相同微博/图片误配；视频仍使用既有播放器行为，不引入新依赖。
- `flutter test --no-pub` 全量 214 项通过，含共享 Hero 标签路由回归；`flutter analyze --no-pub` 无 error/warning，保留 51 条 info 级提示；`git diff --check` 通过。未做真机动画观感验收。
- arm64 Release APK 构建成功；核验包名 `com.review`、版本 `2.14.0`、`versionCode` 98、ABI `arm64-v8a` 和 APK v2 签名。产物 `Review_v2.14.0.apk`（31,764,600 字节），SHA-256：`EED4733E548C9F8A41C029CB2393122AC5C477DFBF49DEE97F45371A9DB297B3`。旧版 `Review_v2.13.1.apk` 已归档至 `build/previous-deliveries/`；未安装到 Android 真机验收。

## 2.13.1+97（2026-10-05）

- 修复快速滑动底部缩略图时主图逐页动画排队、落后于手势的问题：主图实时镜像缩略滚轮的连续页位置，松手后两边同步吸附到同一目标页。滚动期间不逐个初始化视频/Live Photo，只在最终停留媒体上恢复播放。
- 主图跨页时使用滚动专用 12ms 触感节流，让快速连续切换的触感跟随页面变化，同时保留普通操作的全局 40ms 防连击。
- `flutter test --no-pub` 全量 213 项通过，覆盖 Android/iOS 双方向快速 fling、拖动中位置同步、松手吸附和主图打断滚轮惯性。`flutter analyze --no-pub` 无 error/warning，保留 51 条 info 级提示；`git diff --check` 通过。未做真机触感或视频播放验收。
- arm64 Release APK 构建成功；核验包名 `com.review`、版本 `2.13.1`、`versionCode` 97、ABI `arm64-v8a` 和 APK v2 签名。产物 `Review_v2.13.1.apk`（31,764,600 字节），SHA-256：`7FADDCA2D1114AC65B735556BBC1654B61DC426F74FFB11732376BB6EA1A8DD5`。旧版 `Review_v2.13.0.apk` 已归档至 `build/previous-deliveries/`；未安装到 Android 真机验收。

## 2.13.0+96（2026-10-05）

- 缩略图手指拖动和惯性滚动过程中，主图按经过的缩略项逐张过渡；每张内容切换时触发一次统一的轻触觉反馈。每页使用 easeInOutCubic 曲线，积压时缩短单项时长以追上滚动；停稳后的缩略条仍以 easeOutCubic 平顺对齐。Flutter 当前 ClampingScrollPhysics 的惯性采用 Android SplineOverScroller 幂函数曲线（曲线减速，非标准二次抛物线）。
- 修正投票微博将专用的默认蓝色封面当作普通大图显示的问题：只过滤与该微博 poll 元数据匹配的投票链接缩略图，现有原生投票选项和真实配图保留。
- 版本显示更新为 `2.13.0+96`；本轮未运行测试。全量 Dart 分析无 error/warning、保留 51 条既有 info，`git diff --check` 通过。arm64 Release APK 构建成功；核验包名 `com.review`、版本 `2.13.0`、`versionCode` 96、ABI `arm64-v8a` 和 APK v2 签名。产物 `Review_v2.13.0.apk`（31,764,600 字节），SHA-256：`230FDCBB562867877100FA71F7304A108B9C0EE5907274CFF10A5FC0B557B484`。旧版根目录安装包归档到 `build/previous-deliveries/`。用户提供的投票微博无法匿名访问，图片规则仍需真机验收。

## 2.12.0+95（2026-10-05）

- 修复缩略图变形：只限制解码宽度，保持原始比例后裁切；快速拖动/惯性滚动停稳才一次性切换主内容，取消逐页弹簧吸附和双向反馈引起的内容倒退。
- 图片夹视频统一进入画廊，复用既有真实播放器嵌入播放，左右滑切换媒体；删除横滑调整进度手势，保留进度条、双击进度操作和纵滑亮度/音量。显式卸载屏外播放器，初始化晚到不能后台开播；单视频入口保留。
- 功能版本同步为 `2.12.0+95`，全量 212 项测试通过，包含 2/8/18 图、快速惯性两方向、主图中断惯性、真实播放器后端替身生命周期、横滑不 seek 和初始化竞态。测试不等同于真机视频解码/实际网络验收。
- 最终 arm64 Release APK 构建成功（305.5 秒）；完整分析无 error/warning，51 条既有 info；本次画廊、网格、播放器和测试文件单独分析无提示，`git diff --check` 通过。核验包名 `com.review`、版本 `2.12.0`、`versionCode` 95、ABI `arm64-v8a`、APK v2 签名；产物 `Review_v2.12.0.apk`（31,764,596 字节），SHA-256：`CEF319FDB77EB2EC7C38CF15FE6A7A93C2E512EC71CDAD35B8AA5383B12B23E7`。根目录只保留新版，旧版 2.11.0 已移至 `build/previous-deliveries/`，未进行真机验收。

## 2.11.0+94（2026-10-05）

- 更正多图展示：列表固定前 9 张，第 9 张叠加 `+剩余数量`，点击从第 9 张进入完整画廊，删除图片“展开全文”。文字展开仅控制正文，入口移到正文与附件内容下面；超过 9 图的短完整正文在旧快照误标长文、缺少全文时不再显示无意义的按钮。源端补文、详情完整图片、自动生日/荣誉和文章封面路由保持原实现。
- 新增所有多图（2 张及以上）画廊的横向缩略图滚轮，主图与滚轮双向同步、当前图高亮、其他图白色蒙层；底部安全区上方独立放置，与主图留出间距。复用磁盘缓存、惰性构建与现有分页/Live Photo 切换，缩略图解码限制 160px，清屏恢复保留选中位置。
- 按功能更新规则升至 `2.11.0+94`；全量 203 项测试通过，静态分析无 error/warning，保留 51 条既有 info 提示；最终 5 个本次交互改动文件 `dart analyze` 无任何提示。回归覆盖 2/8/18 图滚轮点击、滑动、主图联动、清屏恢复、短正文/转发没有假展开，以及第 9 张进入第 9 张完整画廊。官方示例页本次仍无法匿名访问，网页布局以用户提供截图为参照；尚未真机验收。
- arm64 Release APK 构建成功（234.8 秒），核验包名 `com.review`、版本 `2.11.0`、`versionCode` 94、ABI `arm64-v8a` 与 APK v2 签名。产物 `Review_v2.11.0.apk`（31,764,600 字节），SHA-256：`2F7AEA5B0B571821D5321F87497E25BA2EDCA19A46C1E778C1B3335BE75B2FB8`。上一版根目录安装包移至 `build/previous-deliveries/Review_v2.10.1.apk` 保留。

## 2.10.1+93（2026-10-05）

- 修复多图微博的展开逻辑：列表仅显示前 9 张，图片下方“展开全文”本地展开全部图片，可收起；详情和画廊直接使用完整图片列表。主微博/转发/主页/浏览记录复用同一网格，图片展开与长文字展开独立。
- 去除 `continue_tag` 对长文字的误判；`pic_infos` 不完整时保留完整 `pic_ids`；详情补全不再用移动端 9 张图片覆盖桌面完整列表，自动生日/荣誉卡片继续使用既有图层合并。
- 修复微博文章封面点击只能打开图片的问题：保留官方文章目标与标题，复用已有原生文章阅读页；兼容桌面/移动文章 URL、链接图片、`url_objects`、`page_info` 和浏览记录快照。生日/荣誉卡片继续打开画廊，文章内容仅在点击后请求。
- 修订版本升至 `2.10.1`，Android `versionCode` 升至 93。新增 20 项多图/文章封面解析、数据合并与交互回归；全量 `flutter test --no-pub` 198 项通过，`flutter analyze --no-pub` 无 error/warning，保留 51 条既有 info 提示；`git diff --check` 通过。示例微博匿名接口返回 HTML，尚未取得可用于验收的实时 JSON，未进行 Android 真机验收。
- 最终 arm64 Release APK 构建成功（356.2 秒），`aapt2 dump badging` 确认包名 `com.review`、版本名 `2.10.1`、`versionCode` 93、ABI `arm64-v8a`；APK v2 签名校验通过。产物 `Review_v2.10.1.apk`（31,699,060 字节），SHA-256：`E13EDAA0E5DF637F3ACF8CB6BEACB69F4EB687FCF863BB9F534CAFF6BDE5157C`。旧版 2.10.0 安装包保留到 `build/previous-deliveries/`，未进行 Android 真机安装验收。

## 2.10.0+92（2026-10-05）

- 补充评论用户铁粉等级标识：解析官方评论用户 `fansIcon.icon_url`（兼容 `fans_icon`），并在微博详情评论、完整楼中楼及收到的评论页面显示服务器提供的图标。图标使用现有磁盘缓存，不增加评论/用户资料请求；各级图案与颜色直接采用微博资源，不在客户端硬编码。微博客服中心[官方说明](https://kefu.weibo.com/faqdetail?id=21662)确认博主正文页评论区属于标识展示场景，并注明超话等级标识与铁粉标识互斥。
- 按功能更新规则将版本名从 `2.9.12` 升至 `2.10.0`，Android `versionCode` 从 91 升至 92。针对 5 个改动 Dart 文件执行 `dart analyze`，无 error/warning，保留 3 条 info 级提示；未运行自动化测试。
- arm64 Release APK 构建成功（307.7 秒），`aapt2 dump badging` 确认包名 `com.review`、版本名 `2.10.0`、`versionCode` 92、ABI `arm64-v8a`；APK Signature Scheme v2 校验通过。产物 `Review_v2.10.0.apk`（31,699,064 字节），SHA-256：`8CDA5AD5E5CA8A5C2468569DCE203BC57E4595A5FC3BDD75B940A09499B78869`。旧版 `Review_v2.9.12.apk` 已保留至 `build/previous-deliveries/`。未安装到 Android 真机验收。

## 2.9.12+91（2026-10-04）

- 修复抽奖链接缩略图被当作第三张微博配图的问题：在共享解析层排除抽奖链接图片及自动卡片补全资格，保留正文链接与真实配图，生日/夺金卡片保持原逻辑。
- 新增两种接口结构（`url_struct`/`url_objects`）及浏览记录往返的回归测试；全量 `flutter test --no-pub` 178 项通过，`flutter analyze --no-pub` 无 error/warning，仍有 51 条 info 提示。未取得示例微博实时接口响应、未进行真机验收。
- arm64 Release APK 已通过 `aapt2 dump badging` 和 APK v2 签名校验：包名 `com.review`、版本 `2.9.12`、`versionCode` 91、ABI `arm64-v8a`。产物 `Review_v2.9.12.apk`（31,699,064 字节），SHA-256：`A037E48ABA7194F5D3688C8A77A32F05B2B0AFA2E133E354A96F5EFEFBC948D1`。2.9.11 APK 已移入 `build/previous-deliveries`；未进行 Android 真机安装验收。

## 2.9.11+90（2026-10-04）

- 详情/受限微博卡片的可见范围图标与文字在原 24dp 固定槽位内上移 4dp，拉开与头像的视觉距离，同时保持卡片布局高度稳定。
- 按补丁版本规则将版本名升级至 `2.9.11`、Android `versionCode` 升至 90；本次未运行 Flutter 测试。
- arm64 Release APK 已通过 `aapt2 dump badging` 与 APK v2 签名校验：包名 `com.review`、版本名 `2.9.11`、`versionCode` 90、ABI `arm64-v8a`。产物 `Review_v2.9.11.apk`（31,699,064 字节），SHA-256：`3B864E9B2B0498DD5FFDE61D45845DB0FAC7228190417CEB53AC0B0AC4F0085F`；签名证书 SHA-256：`3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`。未进行 Android 真机验收。

## 2.9.10+89（2026-09-30）

- 修复 2.9.9 中仍会出现的长文跳变：仅在卡片侧延迟应用或检查滚动状态无法覆盖“全文回包早于下一次滚动事件”的竞态。本版在时间线/前台主页将微博源标记的长文在 `FeedRepository` 解析阶段补齐，再把已完成状态交给列表；卡片不再后台自动补取并替换正文。过短/临界长文仍首帧直接显示全文，真正长文首帧显示折叠全文和展开入口。
- 复用现有全文请求合并、2 路并发和 96 条进程内缓存；后台视频/相册缓冲不拉取长文。失败或旧快照继续显示预览，用户主动展开仍可补取，避免把失败变成丢帖或无限加载。
- 全量 `flutter test --no-pub` 176 项通过；`flutter analyze --no-pub` 无 error/warning，有 51 条 info 级 lint 提示。新增回归覆盖仓库发布前补齐主/转发全文、后台路径退出长文预取、补取失败保留原卡片，以及滚动时不再自动替换卡片正文。
- arm64 Release APK 通过 `aapt2 dump badging` 和 APK v2 签名核验：包名 `com.review`、版本名 `2.9.10`、`versionCode` 89、ABI `arm64-v8a`。产物 `Review_v2.9.10.apk`（31,699,064 字节），SHA-256：`722A1456BA4BBBD01E051EB1C3FDA51A9CB68746FED54AB57E97B88574338DDE`；签名证书 SHA-256：`3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`。上一版 2.9.9 已归档至 `build/previous-deliveries/Review_v2.9.9.apk`；未安装到 Android 真机验收。

## 2.9.9+88（2026-09-30）

- 修复快速滚动时自动补全文回包立即替换微博预览，造成卡片高度突变、正文突然展开的问题。请求期间若滚动位置变化或卡片离开视口，先保留现有预览并让全文进入已有仓库缓存；待卡片重新可见且停稳 500 毫秒后再应用缓存正文，等待期间不显示跳动的加载/重试行。失败重试提示也只在卡片可见并停稳后显示。
- 新增延迟全文回包与滚动重叠的 widget 回归测试：滚动中不替换预览，回到卡片并停稳后使用缓存结果显示全文。全量 Flutter 测试 173 项通过；`flutter analyze --no-pub` 无 error/warning，有 51 条 info 级既有 lint 提示。arm64 Release APK 通过 `aapt2 dump badging` 与 APK v2 签名核验：包名 `com.review`、版本名 `2.9.9`、`versionCode` 88、ABI `arm64-v8a`。产物 `Review_v2.9.9.apk`（31,699,060 字节），SHA-256：`9B01727785A060B9320D8DF43F37001AE123CFEF724599E8DBC46D57D7456C58`；签名证书 SHA-256：`3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`。2.9.8 旧包已归档至 `build/previous-deliveries/Review_v2.9.8.apk`；未安装到 Android 真机验收。

## 2.9.8+87（2026-09-30）

- 修复 2.9.7 测试包遇到长微博卡片时的列表卡顿：不再随卡片构建批量触发全文请求。主微博和转发微博都只在进入可视区域且停止滚动 500 毫秒后自动补全文，屏外卡片不请求；滚动会取消等待。详情页仍直接补主微博全文。
- 全文请求并发限制为 2；自动补取期间不显示加载行，避免滚动列表因为加载提示反复改变布局；失败仍能手动重试。新增屏外/停稳触发、转发按需加载和仓库并发限制回归测试。
- 全量 Flutter 测试 172 项通过。`flutter analyze --no-pub` 无 error/warning，有 51 条 info 级 lint 提示。arm64 Release APK 通过 `aapt2 dump badging` 和 APK v2 签名核验：包名 `com.review`、版本名 `2.9.8`、`versionCode` 87、ABI `arm64-v8a`。产物 `Review_v2.9.8.apk`（31,699,060 字节），SHA-256：`CEF79C113E6C3DED63DBFC27E31EFEB45C6D4DEEA1AE53DE621D0507FF991C17`；签名证书 SHA-256：`3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`。2.9.7 卡顿测试包已移入 `build/previous-deliveries/Review_v2.9.7-test-prefetch-regression.apk`；未安装到 Android 真机验收。

## 2.9.7+86（2026-09-30）

- 修复自动微博卡片仍要求点击“展开全文”才能显示全文的问题：主微博和转发微博卡片在遇到未补齐的长文时异步获取全文，普通长度与临界长度直接显示全文；只有确实较长、遗漏内容足够多且排版增加至少 5 行时才保留展开控件。加载过程不阻塞列表，加载失败仍可手动重试。
- 后续在 2.9.7 测试包中确认上述自动获取触发过早，长微博卡片密集出现时会拖慢列表。此测试包已由 2.9.8+87 取代，归档于 `build/previous-deliveries/Review_v2.9.7-test-prefetch-regression.apk`，不建议继续使用。
- `DetailRepository` 为全文请求增加按微博 ID 的并发合并与最多 96 条的进程内 LRU 缓存，减少滚动和卡片重建时的重复请求；新增主微博、转发微博、长文阈值与请求缓存回归测试。
- 全量 Flutter 测试 170 项通过。改动文件静态分析无 warning/error；`DetailRepository` 有 7 条原有 `avoid_print` info。arm64 Release APK 通过 `aapt2 dump badging` 和 APK v2 签名核验：包名 `com.review`、版本名 `2.9.7`、`versionCode` 86、ABI `arm64-v8a`。产物 `Review_v2.9.7.apk`（31,699,064 字节），SHA-256：`339D24F8E9F185DFEA763A8D3B9648AE6AE4973E66EBB7D5321E115645C22BDB`。上一版 `Review_v2.9.6.apk` 已归档至 `build/previous-deliveries/`；未安装到 Android 真机验收。

## 2.9.6+85（2026-09-29）

- 再次调整长文折叠门槛：普通及临界长度全文直接显示；只有全文至少 360 字符、预览省略至少 100 字符且视觉上多出至少 5 行时才折叠。列表按需取回全文后也用同一规则，避免“展开”只露出短尾句再变为“收起”。
- 新增 390dp 手机宽度下多行但总长度适中的尾部补取回归测试；真正长文仍验证可折叠、展开完整正文。全量 Flutter 测试 168 项通过，修改文件静态分析无问题。arm64 Release APK 构建成功并通过 `aapt2 dump badging` 与 APK v2 签名核验：包名 `com.review`、版本名 `2.9.6`、`versionCode` 85、ABI `arm64-v8a`。产物 `Review_v2.9.6.apk`（31,699,064 字节），SHA-256：`4569B57C6B96C8F7A95EB1C593A05A7DB6D7E837A957F950F9581A6699C68FCB`。上一版已归档至 `build/previous-deliveries/Review_v2.9.5.apk`；未安装到 Android 真机验收。

## 2.9.5+84（2026-09-29）

- 再次修正长文展开阈值：全文只比预览多一行时直接显示完整正文，不再因一小截尾句显示展开/收起；至少多两行才提供展开控件。手机逻辑宽度 390dp 的回归用例在旧的“一行即展开”逻辑下会失败。
- 修正浏览记录回读快照丢失微博图片的问题：`WeiboStatusModel.fromJson` 在没有接口 `pic_infos` 时回读其自身 `toJson` 输出的 `pics` 列表；旧的自动卡片记录只在缺少网页卡片图片时复用主页补全并原位更新。
- 全量 Flutter 测试 167 项通过；本次修改文件静态分析无 warning/error，保留 1 条原有 `prefer_conditional_assignment` info。手机宽度下的小尾句回归用例在恢复旧的“一行即展开”逻辑时按预期失败，在修复后通过。arm64 Release APK 构建成功并通过 `aapt2 dump badging` 与 APK v2 签名核验：包名 `com.review`、版本名 `2.9.5`、`versionCode` 84、ABI `arm64-v8a`。产物 `Review_v2.9.5.apk`（31,699,064 字节），SHA-256：`5E5CCB65678EBFF68B98D67BF8BC9BFDDE7874AEB1C39260667012CD91653421`。未安装到 Android 真机验收。

## 2.9.4+83（2026-09-29）

- 修正长文展开按钮只切换为“收起”却没有视觉变化的问题：按卡片实际可用宽度比较预览和全文的富文本行数。新增文字仍在同一可见行时直接显示全文并隐藏按钮；确实增加可见行时才保留展开控件。主微博和转发微博一致处理。
- 修正生日自动卡片祝福语仅在详情页显示、且位于图片外的问题：从微博 `url_title` 读取文案并叠加到渲染图片内部的白底留白处，列表卡片和详情页一致显示；从正文去除同一条重复文案。
- 全量 Flutter 测试 165 项通过，改动文件静态分析无问题。arm64 Release APK 构建并通过 `aapt2 dump badging` 和 APK v2 签名验证：包名 `com.review`、版本名 `2.9.4`、`versionCode` 83、ABI `arm64-v8a`。产物 `Review_v2.9.4.apk`（31,699,064 字节），SHA-256：`62476D237A5D090DBBA1B4C7A89FE376629A6A2BD7367EDACE61F5E89253C65F`。原 `Review_v2.9.3.apk` 已保存在 `build/previous-deliveries/`；未安装到 Android 真机验收。

## 2.9.3+82（2026-09-29）

- 修正长文卡片将预先返回的全文直接当作已展开、但仍显示“展开全文”的问题。按清理后的实际正文差异决定控件；无新增正文时隐藏，转发微博同样处理。若长文接口补取后返回相同内容，按钮也会消失。
- 修正自动生日/荣誉卡片的详情补全可能用不完整移动端前景图覆盖原完整卡片的问题：保留已有背景层及画布尺寸，并避免空白移动端正文覆盖已有非链接正文。详情生日卡片读取微博 `url_title` 显示祝福语。
- Flutter 全量 163 项测试通过，新增的长文展开、生日卡片与详情补全回归测试均通过；针对改动文件的静态分析无 warning/error，保留 7 条既有 `avoid_print` info。arm64 Release APK 构建并通过 `aapt2 dump badging` 与 APK v2 签名校验，包名 `com.review`、版本名 `2.9.3`、`versionCode` 82、ABI `arm64-v8a`。产物 `Review_v2.9.3.apk`（31,699,064 字节），SHA-256：`CDD6C31B3E8EDE3DAF88D14C52F6ACC8A4D568AE7993C8E7CE3143400393B200`。微博匿名实时接口返回 432，本次按合成响应夹具验证；未进行 Android 真机验收。

## 2.9.2+81（2026-09-29）

- 热搜页支持重新点击已选中的底栏“热搜”回到当前分类顶部；双击回顶并刷新当前分类。顶栏双击在未到顶部时回顶、已在顶部时刷新当前分类。复用分类接口与现有手势时序，不刷新其他隐藏分类，也不新增依赖。
- Flutter 全量测试 157 项通过；本次修改涉及的 Dart 文件静态分析无问题。arm64 Release APK 构建成功，包名 `com.review`，版本名 `2.9.2`、`versionCode` 81，原生 ABI 为 `arm64-v8a`，APK v2 签名验证通过。产物 `Review_v2.9.2.apk`（31,699,064 字节），SHA-256：`E0822AF379B150F067377F6828FD1FFF4211ACE63E0C0E0A3663BFA88B451448`。构建使用已缓存 Gradle 依赖离线完成，`pubspec.lock` 保持未修改；未安装到 Android 真机验收。

## 2.9.1+80（2026-09-28）

- 修复微博正文中点击 `@用户` 跳转主页时没有触感反馈的问题；通过现有 `HapticFeedbackUtil` 触发轻触，继续遵守全局触感开关和重复反馈抑制。版本名改为 `2.9.1`，Android `versionCode` 从 79 提升至 80。
- 文本解析测试 10 项通过，针对修改文件的静态分析无问题；arm64 Release APK 构建成功，包名 `com.review`，版本名 `2.9.1`，`versionCode` 80，APK v2 签名验证通过。产物 `Review_v2.9.1.apk`（31,699,064 字节），SHA-256：`4A6A8B92299BE3ECB9EDD4E25196A8F65AEEE1BC61A1CFE6B820402350A47034`。未进行 Android 真机振动验收。

## 2.9.0+78（2026-09-28）

- 修正个人主页等列表中的微博自动荣誉卡片比例：优先采用分层卡片背景画布尺寸，缺失时回退到横向卡片比例；图片图层完整等比显示，避免透明前景图尺寸导致内容横向裁切。
- 版本名保持 `2.9.0`，Android `versionCode` 提升至 78。本次验证：arm64 Release APK 构建成功，包名 `com.review`，APK v2 签名验证通过；产物 `Review_v2.9.0.apk`（31,699,064 字节），SHA-256：`A48293A42A561F9514AD6A233E0CBE9099334634982DED7C0E844949E640A1FF`。本次未重跑自动化测试，未进行 Android 真机验收。

## 2.9.0+77（2026-09-25）

- 将仍使用进程内图片缓存的网络图片入口接入现有 `extended_image` 磁盘缓存；启动后异步整理其临时缓存目录，只清理过期或超过容量上限的可重新下载图片文件，不触碰相册媒体与账号资料。
- 版本名保持 `2.9.0`，Android `versionCode` 提升至 77；Android 真机冷启动网络流量和缓存占用仍待实测。
- 本次验证：Flutter 全量 154 项测试通过；静态分析无 warning/error，仍有 51 条既有 info；arm64 Release APK 构建完成，包名 `com.review`、版本名 `2.9.0`、`versionCode` 77，APK v2 签名验证通过。产物：`Review_v2.9.0.apk`（31,699,064 字节），SHA-256：`C0769B30C042D7EDC40010FD2FAD2C9792A286C7C640C51971D7E0FDBE65F4B0`。

## 2.9.0+76（2026-09-23）

- 打开一条私信或群聊时，只把该会话当前计数记为本地已读；打开 @、收到的赞、收到的评论时，只清对应类别。“我的消息”总览及“发出的评论”不清其他类别。
- 本地基线保留新消息重新从 1 计数的行为，并与后台通知水位对齐，避免已浏览的旧通知延迟弹出。应用显示版本名保持 `2.9.0`，Android `versionCode` 提升至 76。
- 当次记录：Flutter 152 项测试通过；静态分析无 warning/error，仍有 51 条 info；arm64 Release APK 完成签名校验。Android 真机通知尚未验收。

## 2.9.0+75（2026-09-23）

- 每条会话的角标只显示在其头像右上角；免打扰群角标显示灰色，其余会话显示红色。移除“私信与群聊”标题旁无法随清除操作归零的 `totalNumber` 气泡。
- 清除未读后按每会话持久化基线计算，重新打开消息页不再显示清除前的旧计数。版本名仍为 `2.9.0`，`versionCode` 提升至 75。
- 当次记录：Flutter 150 项测试通过，静态分析无 warning/error；arm64 Release APK 完成签名校验。Android 真机通知尚未验收。

## 2.9.0+74（2026-09-23）

- 消息类别和会话分别保存本地未读基线；侧边栏角标排除免打扰群，免打扰设置只影响 Review 本地提醒。
- 增加按类别订阅的 Android WorkManager 后台轮询通知。周期至少 15 分钟，实际执行可能更晚；首次运行或账号切换只建立基线。
- 私信及群聊发送不再以 HTTP 2xx 直接显示本地合成消息；需要业务响应和会话回读共同确认。两个 WebIM 发送兼容路径未经过公开契约或测试账号验证，本次没有使用用户账号发送测试消息。
- 当次记录：Flutter 149 项测试通过，静态分析无 warning/error；arm64 Release APK 完成签名校验。Android 真机通知尚未验收。

## 2.8.9+73

- 收紧登录检测的并发与超时处理：手动重试可在自动轮询期间发起，超时通过 Dio `CancelToken` 取消实际请求，避免慢响应晚到后覆盖状态。
- 当次记录：arm64 Release APK 构建和签名校验通过；该次没有运行自动化测试、静态分析或 Android 真机验收。

## 2.8.8+72

- 完成网页端登录后的凭据同步与多候选验证，兼容 SSO 回跳和不同域的 Cookie。详细边界见 [DEVELOPMENT.md 的会话章节](../DEVELOPMENT.md#61-基础地址和会话)与旧手册归档的 4.58 节。

## 更早记录

- 2.6.2 和 2.6.3：修复旧 Cookie 分域迁移、有效候选回退与凭据检测响应兼容（旧手册 4.56–4.57）。
- 2.5.x：修复深度文章链接、HTML 请求隔离、短链接解析和原生渲染（旧手册 4.50–4.53）。
- 2.4.x 及此前：评论与楼中楼、视频、图片画廊、搜索、图标等历史实现与修复保留在[旧手册归档](archive/Review-legacy-2026-09-23.md)。这些记录供追溯，不作为当前实现说明。
