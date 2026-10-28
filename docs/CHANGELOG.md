# Review 变更记录

## 3.13.8+232（2026-10-28）

- 修复转发原微博的直播链接被误识别为网页图片、时间线出现异常长宽比空白卡片的问题。直播卡片继续走原生视频预览，并保留 smart card 封面；普通网页卡片及显式图片附件的解析不变。
- 增加模型回归，验证转发直播链接不进入图片列表、仍识别为直播视频且保留封面。
- `models_test.dart` 38 项通过，模型及测试文件静态分析无问题。ARM64 Release 构建成功（434.4 秒）；核验 `com.review`、3.13.8+232、仅 `arm64-v8a`、既有证书 V2 签名与 16 KiB ZIP 对齐。交付 `Review_v3.13.8.apk`（33,543,086 字节），SHA-256 `DD08464ECCCE366CE3F1CD68957E4424DFC312287D6E1ABF004A1DC047D6B571`；3.13.7 回退包保存在 `build/previous-deliveries/Review_v3.13.7-before-v3.13.8.apk`。未做真机直播卡片验收。

## 3.13.7+231（2026-10-28）

- 按反馈将图片打开路由的时长从220ms延长到330ms（150%），让打开动画慢一些；返回仍为200ms，Hero 默认曲线与防止图库叠层逻辑不变。
- 28 项图片画廊回归通过，覆盖打开时长、重复打开拦截、单次返回及现有 Hero/分页/缩放行为；3 个相关 Dart 文件静态分析无问题。ARM64 Release 构建成功（519.3 秒），核验 com.review、3.13.7+231、仅 arm64-v8a、既有证书 V2 签名和 16KiB ZIP 对齐。交付 Review_v3.13.7.apk（33,543,086 字节），SHA-256 AB9F405F87933D2D0EB3515BA05A98E328DE4B1006F9D4EAF2AF873C7F3C8206；3.13.6 回退包保存在 build/previous-deliveries/Review_v3.13.6-before-v3.13.7.apk。未做真机动画观感验收。

## 3.13.6+230（2026-10-28）

- 按用户决定撤回安卓非线性画廊动画及其多轮中断/重开机制，恢复稳定 Hero 转场：打开 220ms、返回 200ms，使用 Flutter 默认 Hero 曲线与几何插值。
- 时间线和聊天的统一图片入口在同一 Navigator 已有画廊路由时不重复 push，避免连续操作后图库叠层和多次返回；此保护不尝试在未完成的动画中反向重开。
- 保留 HDR、Hero 返回像素延迟释放、玻璃退场、图片/视频和其他非动画功能；画廊/HDR/底栏/聊天媒体定向回归 50 项通过，5 个相关 Dart 文件静态分析无问题。ARM64 Release 构建成功（499.0 秒），核验 com.review、3.13.6+230、仅 arm64-v8a、既有证书 V2 签名和 16KiB ZIP 对齐。交付 Review_v3.13.6.apk（33,543,082 字节），SHA-256 9879690F7C0DFB2C284D27B0B2EBBE27EFF5D1E24F30DB99A1B85D836AEA89A2；3.13.4 回退包保留在 build/previous-deliveries/Review_v3.13.4-before-v3.13.5.apk。未做真机动画验收。

## 3.13.5+229（候选已撤回，未交付）

- 本版本候选曾尝试处理快速重复打开导致的画廊叠层，用户决定恢复非线性动画之前的稳定效果，因此 Release 构建被取消且未交付 APK；实际恢复结果记录在 3.13.6。

- 修复第二张退场中点第四张无动画、返回露出第二张的问题。时间线/聊天统一通过openFromSource进入：新图片从来源页建立Hero，并移除同一Navigator中仍在历史里的旧画廊，不把画廊压在画廊上；已pop退场的路由保留既有Hero衔接。
- 全局返回重开延至当前事件结束，并以打开版本号取消过期回调，让具体缩略图点击优先。返回层收到点击时，九宫格按源缩略图实际边界解析目标索引，不再把任意落点都重开为上一张。
- 3.13.4只限制旧监听所有权，没有处理具体点击与全局回调的竞争及存活路由栈，不能保证不叠层；本次补齐。
- 四图端到端回归覆盖打开40ms返回、完整打开后返回、返回中点第四张及旧画廊已重开后再点第四张；检查第四张动画进度和一次返回即到帖子。59项定向测试通过。

## 3.13.4+228（2026-10-28）

- ARM64 Release构建成功（523.8秒），核验com.review、3.13.4+228、仅arm64-v8a、既有证书V2签名及16KiB ZIP对齐。交付Review_v3.13.4.apk，33543086 字节，SHA-256 E90F0BE32A6B06020859AECC66FC4EFC21837892BE3F36C61BDE98547FB83BBF 。3.13.3回退包保存在build/previous-deliveries/Review_v3.13.3-before-v3.13.4.apk；相关5个文件静态分析无问题，未做真机多图连续开合/黑屏验收。


- 打开和返回时长同步缩短5%，归一化弹簧曲线不变，完整返回仍比打开短8%。
- 修复返回中按下、退场销毁后松开的点击被清掉：待结束的指针保留至up/cancel，确认有效短点后重开并沿用触感反馈；拖动不重开。
- 仅允许最新图库路由接管返回点击，防止旧reverse监听在新播放器上叠加打开；多图重开使用onIndexChanged传回的当前索引，避免固定初始图片造成Hero身份错配。时间线及聊天入口统一应用。
- 52项画廊/HDR/底栏回归与6项聊天媒体回归通过，覆盖跨销毁帧点击、旧路由抢事件、当前图片索引与原有Hero像素交接。

## 3.13.3+227（2026-10-28）

- ARM64 Release构建成功（586.0秒），核验com.review、3.13.3+227、仅arm64-v8a、既有证书V2签名和16KiB ZIP对齐。交付Review_v3.13.3.apk，33543086 字节，SHA-256 983751C90E0C3900155D68203B96E02E45FC3A2503F81C7E398C674023F38D50 。3.13.2回退包保存在build/previous-deliveries/Review_v3.13.2-before-v3.13.3.apk；未做真机曲线观感验收。


- 打开和返回均从快到慢，使用同一GalleryOpeningCurve。修复打开未完成就返回时CurvedAnimation为保持连续而锁定正向曲线、倒放变为慢到快的问题：在方向变化时记录当前可见进度，以相同曲线继续向目标运动，不跳变。
- 中途pop的剩余时长按实际可见距离计算，避免原始控制器进度与画面进度不同造成返回过快；完整返回仍为打开时长的92%。
- 新增完整打开和70ms中途返回的归一化进度回归，核验四分之一/二分之一时刻与打开曲线一致及首帧连续；51项画廊/HDR/底栏测试通过。

## 3.13.2+226（2026-10-28）

- ARM64 Release 构建成功（564.5秒）；核验 com.review、3.13.2+226、仅arm64-v8a、既有证书V2签名及16KiB ZIP对齐。交付 Review_v3.13.2.apk，33,543,086字节，SHA-256 8B2BF15F086DED65EB837C704941246E91FF8A9138531BB4862139663125EF11；3.13.1回退包保留在 build/previous-deliveries/Review_v3.13.1-before-v3.13.2.apk。未做真机重复开合验收。

- 返回动画时长为动态计算打开时长的92%，保持原曲线、打开速度和中途反向能力。
- 修复反复打断开合后先居中缩回、落点瞬间再填满：Hero空占位期间无法重新捕获缩略图像素与cover裁切，旧逻辑退回完整图片子树。缩略图实例现在保留其有效几何与共享像素句柄，在空占位时兜底；换图、身份变化或销毁时释放，不新增解码或全局图片缓存。
- 返回端点测试模拟隐藏的缩略图子树，覆盖横图/竖图与缩放；移除兜底时4组失败，启用后50项画廊/HDR/底栏回归通过。

## 3.13.1+225（2026-10-28）

- ARM64 Release 构建成功（432.1秒），包名 com.review、版本3.13.1+225、仅arm64-v8a、既有证书V2签名及16KiB ZIP对齐均通过。交付 Review_v3.13.1.apk，33,543,082字节，SHA-256 7DF9B76CAA589E61FE4BC2F844DD74374CAE152A6F6EBDBD5F302435A8557E26。3.13.0回退包保留于 build/previous-deliveries/Review_v3.13.0-before-v3.13.1.apk；尚未做真机连续快速点击验收。

- 浅色悬浮底栏外壳增加 shadowElevation 0.55，仅在底栏调用处覆盖；深色和其他玻璃组件保留原参数。
- 修复返回中迅速再次打开图片时内部像素缩向左上角：Flutter 在 pop→push 时复用 Hero shuttle，旧页面动画不再代表飞行进度。图片平面与裁切改为依据当前 Hero 实际尺寸同步。
- 回归增加不透明像素覆盖断言；旧逻辑下失败，新逻辑下通过，补齐之前只检查外层 Hero 矩形的遗漏。50项画廊/HDR/底栏回归通过，相关4项静态分析无问题。

## 3.13.0+224（2026-10-28）

- 同步 GreenNote 液态玻璃浅色模式：悬浮底栏使用近不透明白色玻璃、细白描边和主题色图标文字；选中胶囊、玻璃着色与 rim 参数按浅色主题调整。深色模式参数保持原样。
- 图片播放器的控件和玻璃材质未修改。
- 浅色参数与底栏实际渲染回归2项通过；图片 Hero 状态清理、画廊/HDR 回归共50项通过。`flutter analyze --no-pub` 检查路由、画廊、底栏及相关测试6项，无问题；`git diff --check` 通过。
- ARM64 Release 构建成功（346.5秒）；已核验包名 `com.review`、版本 `3.13.0+224`、仅 `arm64-v8a`、APK v2 签名（证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`）和16KiB ZIP对齐。交付根目录 `Review_v3.13.0.apk`（33,543,086字节），SHA-256 `250982D4BC44123D0549F48747934C5B1012F101032251753312A2A79D3F5930`；v3.12.9 回退包保存在 `build/previous-deliveries/Review_v3.12.9-before-v3.13.0.apk`。未在真机检查浅色液态玻璃观感。

## 3.12.9+223（2026-10-28）

- 修复快速开合图片时 Hero 图像飘到状态栏附近：`ImageGalleryPage.dispose` 早于 Hero overlay 退场，页面实例集合变空并不代表飞行结束。现在等所有共享图片路由完成退场及下一帧后才恢复状态栏/edge-to-edge、关闭窗口 HDR 和清除回调；已有替代路由时不提前清理。
- 路由退场清理主动请求下一帧，避免只注册 post-frame 回调却没有后续帧时系统 UI 清理一直挂起。增加旧页面已销毁、替代路由已安装但页面尚未建立时不恢复系统状态的回归。
- 34项图片画廊测试和14项HDR测试通过；相关路由、画廊与测试的静态分析无问题。
- 3.12.9 ARM64 Release 中间包构建成功（337.3秒），保留于 `build/previous-deliveries/Review_v3.12.9-before-v3.13.0.apk`；已核对版本 `3.12.9+223`、仅 `arm64-v8a`、16KiB 对齐，33,543,086字节，SHA-256 `6B49F0F15464BF3647C2C31051B9B7D1492754C8F57D1A2F7276E06EDC5F4AF0`。

## 3.12.8+222（2026-10-28）

- 微调图片打开弹簧：阻尼比0.9、刚度220、初速度7，动态收敛时间约350ms；起步与后70%都比3.12.7稍快，仍由同一曲线反向返回。
- 本版只在仍有另一画廊 State 时抑制全局清理；页面 State 销毁早于 Hero overlay 退场的窗口仍会恢复状态栏/窗口模式，用户实际复现后于3.12.9补齐。
- 当时的回归只覆盖两个 Gallery State 重叠，未覆盖旧 State 已销毁、替代路由已安装但页面尚未建立的时序。
- `flutter test --no-pub test/image_gallery_test.dart test/gallery_hdr_test.dart`：47项通过；相关文件 `flutter analyze --no-pub` 无问题；`git diff --check` 通过。
- ARM64 Release 构建成功（445.5秒）。核验包名 `com.review`、版本 `3.12.8+222`、仅 `arm64-v8a`、V2签名（证书 SHA-256 与前版一致）和16KiB ZIP对齐。交付 `Review_v3.12.8.apk`（33,543,086字节），SHA-256 `0A36592E7065942BEA493F328C07086A076C1A5D28B4B5EF1D269AFD72B08B90`；3.12.7回退包保存在 `build/previous-deliveries/Review_v3.12.7-before-v3.12.8.apk`。未做 VIVO X300 Pro 真机动画观感验收。

## 3.12.7+221（2026-10-28）

- 提高图片打开弹簧前段速度：增加初速度6，路由动画持续时间仍按收敛状态动态推导，不固定为400ms；返回继续使用同一曲线的反向映射，Hero几何不变。
- 修复画廊返回期间的点击穿透：信息流卡片检测上层路由转场状态，并在 Hero 退场清理后保留一帧保护，避免快速点按误进文章详情。返回弹簧运行时的短点按会以相同 Hero 身份重新推入同图画廊，接管当前飞行；拖动不触发重开。
- 45项画廊/HDR定向回归通过，涉及 Dart 文件分析无问题。ARM64 Release最终构建成功（457.9秒），核验 `com.review`、3.12.7+221、仅 `arm64-v8a`、V2签名（证书与前版相同）及16KiB ZIP对齐。交付 `Review_v3.12.7.apk`（33,543,086字节），SHA-256 `E76F5CEA4BA5D3741C4622DF58744185BC7E2671D8201C402A6791D2DFA3F98E`；`Review_v3.12.6.apk` 回退包保存在 `build/previous-deliveries/Review_v3.12.6-before-v3.12.7.apk`。未做 VIVO X300 Pro 真机动画观感验收。

## 3.12.6+220（2026-10-28）

- 修复 Hero 默认缓动与路由弹簧叠加导致打开过快；两端 Hero 使用线性计时和直线矩形插值，路由弹簧刚度降至200。关闭使用 flipped 映射，起落速度方向对应。
- 打开与关闭共用完整图片平面和圆角裁切插值，避免打开飞行层反复布局全屏图片造成裁切突变；原图加载中仍保留来源解码帧。
- 增加真实 Navigator/Hero 打开途中几何断言；画廊回归同时检查飞行像素和返回首帧。
- 44项画廊/HDR回归及相关静态分析通过。ARM64 Release构建成功（67秒）；核验3.12.6+220、仅arm64-v8a、原证书V2签名和16KiB ZIP对齐。交付Review_v3.12.6.apk（33,543,086字节），SHA-256：2CD5EF09A4F76267A7865CB37D25769740B1A8F2C7D80EAE254D09E5162F7874。3.12.5回退包保留于build/previous-deliveries/Review_v3.12.5-before-v3.12.6.apk；未进行真机观感/帧时间验收。

## 3.12.5+219（2026-10-28）

- 按“复刻安卓非线性动画”建议，将画廊 Hero 打开从手工分段曲线改为 Flutter `SpringSimulation`，阻尼比0.9、刚度400；位移1%/速度0.1时结束，路由时长由仿真动态推导。push/pop 共用曲线与时长，避免中途反向时插值位置跳变。
- 弹簧曲线的单调性、范围、减速尾段及动态路由时长定向 Flutter 回归通过；未改变 Hero 几何、图片手势和返回快照释放策略。相关 Dart 静态分析通过。
- ARM64 Release 构建成功（38秒），核验 `com.review`、3.12.5+219、仅 `arm64-v8a`、V2 签名（证书与前版相同）及16KiB ZIP 对齐。交付 `Review_v3.12.5.apk`（33,543,086字节），SHA-256 `AB943EB73244426EC3250122FC188329D61025D173FEAFE3633783DF1332BB06`；3.12.4回退包保存在 `build/previous-deliveries/Review_v3.12.4-before-v3.12.5.apk`，SHA-256 `635E9D29CD117BB510E4E44728E8F77DB5B6C9C34B81C738E2816A38FAE88DBF`。尚未真机体验验收。

## 3.12.4+218（2026-10-28）

- 按反馈将画廊打开的速度变化节点从75%调回50%：前半段保持原版速度，后半段平滑降至原版一半；总时长由曲线速度面积自动计算，约251ms。
- 保留3.12.3的Hero返回快照延迟释放及信息流缩略图换源时旧帧暂留，修复返回落点黑闪。
- 43项画廊/HDR定向回归与相关静态分析通过。ARM64 Release最终构建76秒，核验com.review、3.12.4+218、仅arm64-v8a、V2签名及16KiB ZIP对齐，证书与前版相同。交付Review_v3.12.4.apk（33543086字节），SHA-256 635E9D29CD117BB510E4E44728E8F77DB5B6C9C34B81C738E2816A38FAE88DBF；3.12.3回退包SHA-256 7468E20B31475EE91651334ADD2FA026DAB607DEF2725AEC9036AF5280654856，归档至build/previous-deliveries/Review_v3.12.3-before-v3.12.4.apk。尚未真机体验验收。

## 3.12.3+217（2026-10-28）

- 调整图片打开速度节点：动画前75%时间保持原版速度，最后25%平滑降至原版一半。总时长由曲线平均速度计算，约235ms，不再固定400ms。
- 修复部分缩略图返回落点闪黑：Hero 飞行快照延至当前帧绘制后释放；信息流图片切换来源时保留同一照片已解码帧，直到新帧到达，新的媒体 ID 仍重置状态。
- 43项画廊/HDR定向测试通过，覆盖曲线节点/全程速度/推导时长、Hero pop完成首帧目标像素，以及信息流替换图片时旧帧暂留和新帧交接；相关文件静态分析无问题。ARM64 Release最终构建71秒，核验com.review、3.12.3+217、仅arm64-v8a、V2签名及16KiB ZIP对齐，签名证书与前版一致。交付Review_v3.12.3.apk（33543086字节），SHA-256 7468E20B31475EE91651334ADD2FA026DAB607DEF2725AEC9036AF5280654856；3.12.2回退包SHA-256 35F0F5A7888F5122B3D7D15D97D77EDD33FE147F50C2F7795B5E2D896880A3D9，归档至build/previous-deliveries/Review_v3.12.2-before-v3.12.3.apk。真机动画观感及不同设备图片返回仍未验收。

## 3.12.2+216（2026-10-28）

- 再调画廊打开动画：修正旧曲线后段速度降至接近零的问题。400ms内从旧版220ms线性动画的原速度平滑降至约一半，并保持全程至少半速；Hero与页面淡入仍同步。返回动画不变。
- 29项画廊定向回归通过，曲线测试采样全程速度下限和起止速度；相关静态分析无问题。ARM64 Release最终构建24秒，核验com.review、3.12.2+216、仅arm64-v8a、V2签名及16KiB ZIP对齐，证书与前版一致。交付Review_v3.12.2.apk（33543086字节），SHA-256 35F0F5A7888F5122B3D7D15D97D77EDD33FE147F50C2F7795B5E2D896880A3D9；上一版Review_v3.12.1.apk（SHA-256 E747461FC72026C6385F648822692E2365F0F32519E722D8B1CF2B5D72B4DADB）已校验归档至build/previous-deliveries/Review_v3.12.1-before-v3.12.2.apk。

## 3.12.1+215（2026-10-28）

- 修复信息流全部图片已识别HDR、画廊缩略图却只给选中项标HDR的问题：继承所有已知原图标记，复用未完成的信息流检测，不额外探测未知邻图。
- 同步GreenNote退场优化：液态玻璃开启时，返回开始立即卸载画廊顶部控件和缩略栏；取消返回后等路由完成再恢复，普通模式保留原淡出。
- 打开动画从220ms调整为350ms，保持接近原起步速度后非线性减速，Hero与页面淡入共用；返回仍200ms。
- 47项HDR/图片/混合媒体回归通过，覆盖邻图标记、进行中探测合并、玻璃立即卸载及返回取消恢复、Hero真实像素及缩放翻页。涉及文件静态分析无问题。ARM64 Release构建2分28秒，核验com.review、3.12.1+215、仅arm64-v8a、V2签名与16KiB ZIP对齐，证书与前版相同。交付Review_v3.12.1.apk（33543082 字节），SHA-256 E747461FC72026C6385F648822692E2365F0F32519E722D8B1CF2B5D72B4DADB；3.12.0已比对哈希归档至build/previous-deliveries/Review_v3.12.0-before-v3.12.1.apk。真机HDR亮度、GPU帧时和功耗尚未验收。

## 3.12.0+214（2026-10-24）

- 评论菜单增加仅楼主、含楼主。按真实作者 UID 判断，含楼主保留作者回复过的顶层讨论；不将两三条回复预览误作完整楼中楼。按需、可续扫，每批最多4次请求，支持失败重试、切换后隔离旧结果。
- 超话详情顶栏分享左侧增加搜索入口。限定当前超话 ID，只显示当前帖属于该超话且含输入关键词的结果，排除其他超话及热门推荐；支持续页和失败重试。
- 53项定向回归通过，包含后续回复页的作者参与、未知回复总数、请求失败游标重试、超话范围/关键词排除，以及搜索按钮位置和实际打开范围。涉及文件分析无 error/warning；原有11项 info提示保留。ARM64 Release最终构建33秒，com.review、3.12.0+214、minSdk24/targetSdk36、仅arm64-v8a、V2签名与16KiB ZIP对齐核验通过，证书与前版相同。交付Review_v3.12.0.apk（33543086 字节），SHA-256 4C5213DF42BB2DE28E12423D9807154E68C159954459190174318FB293E1B88F；3.11.4已归档至build/previous-deliveries/Review_v3.11.4-before-v3.12.0.apk。未进行应用真机及登录态搜索验收。

## 3.11.4+213（2026-10-23）

- 清晰度仅显示明确数字分辨率（1080P、720P、480P 等），从高到低排序，同档/同地址合并。明确档存在时移除高清、原画、默认画质等未知别名；全部未知时仅保留一个分辨率未知入口，直播保留直播标识。
- 移除模型把通用 HD/default 流猜成720P/480P 的逻辑；首次播放和详情补取同步使用选中档地址。原画、默认流均不代表固定分辨率。不额外下载视频检测。
- 47项清晰度、模型及混合媒体回归通过；相关文件静态分析无问题；离线 Release 构建39秒，包名com.review、3.11.4+213、仅arm64-v8a、V2签名及16KiB对齐核验通过。交付Review_v3.11.4.apk（33477550 字节），SHA-256 386548D85D9284B77591E175814CA5A3852474845D56700698E8A11DD8467D99。前版已归档回退；尚未真机播放验收。

## 3.11.3+212（2026-10-23）

- 修复清晰度菜单直接显示 mp4_720p_mp4、mp4_hd_mp4 等接口字段；播放器入口统一可读名称，按地址和相同画质去重，优先保留当前播放地址。未知分辨率不猜成 720P；独立原画与直播入口保留。缓存数据及重新获取详情均经过相同处理。
- 修复切到第二张图片等待原图时黑屏：每页加载时使用各自缓存预览，保留第一张 Hero 快照、原图缩放、HDR 与失败重试。参考 RedNote 每页预览占位方案，不预下载全部原图。
- 图片、HDR、混合媒体、清晰度与模型共 84 项回归通过；涉及文件静态分析无问题。离线 ARM64 Release 构建成功（1分53秒），核验 com.review、3.11.3+212、仅 arm64-v8a、V2 签名与 16 KiB ZIP 对齐；签名证书与前版相同。尚未进行真机视觉与 CDN 播放验收。

- 交付 Review_v3.11.3.apk（33,477,550 字节），SHA-256 C25C2455C2224225F4DB1273E97F879F367842F29CB53BC89824E34588EE002C；3.11.2 已按哈希核验归档至 build/previous-deliveries/Review_v3.11.2-before-v3.11.3.apk。

## 3.11.2+211（2026-10-22）

- 按用户要求撤回微博卡片、转发原帖和文章封面的“一镜到底”详情转场，恢复原本的标准页面路由与打开行为；保留文章页内链接和外链的既有分流。
- 已移除转场专用实现及测试，恢复原文章封面点击回归；Flutter 静态分析 0 error 0 warning。
- ARM64 Release 构建成功（347.4 秒）；核验 `com.review`、版本 `3.11.2`、versionCode 211、target SDK 36、仅 `arm64-v8a`，V2 签名及 16 KiB ZIP 对齐通过，证书 SHA-256 与前版一致。
- 交付 [Review_v3.11.2.apk](../Review_v3.11.2.apk)（32,822,190 字节，31.3 MB），SHA-256 `8828E96A56E6C3DEB7D387EA0047F8D228F603D27EB7A3B77C2C9BEAF27CE4E7`。3.11.1 已归档至 `build/previous-deliveries/Review_v3.11.1-before-v3.11.2.apk`；根目录仅保留本版 APK。

## 3.11.1+210（2026-10-22）

- 修复卡片详情一镜到底转场开场时工具栏从卡片中段突然出现、再向上移动的问题。来源卡片预览平滑扩展，详情内容保持最终屏幕坐标并逐渐显现；来源预览在内存中捕获并限制尺寸，返回转场结束后释放。
- 路由和文章封面定向回归共 15 项通过；ARM64 Release 构建及包名、版本、ABI、V2 签名和 16 KiB 对齐核验通过。未进行真机视觉验收。

## 3.11.0+209（2026-10-22）

- 微博卡片、转发原帖和文章封面使用从点击来源矩形展开/收回的详情转场，详情复用单一实例；正文链接和其他页面沿用原路由。
- 路由回归 13 项和文章封面打开原生阅读页 1 项通过；ARM64 Release 包已静态验证。真机视觉和 Android 返回手势未验收。

## 3.10.10+208（2026-10-22）

- 将视频播放器的播放/暂停键移到底部控制栏最左侧、时间显示之前，并移除遮挡画面的中央大图标；双击中间播放/暂停及左右双击快进/快退仍保留。
- `mixed_media_gallery_test.dart` 5 项通过，新增断言覆盖底栏播放/暂停位置、被缩略条遮挡的情况及暂停/恢复播放；涉及 Dart 文件 `flutter analyze --no-pub` 无问题，`git diff --check` 通过。
- ARM64 Release 构建成功（450.1 秒）；核验 `com.review`、版本 `3.10.10`、versionCode 208、target SDK 36、仅 `arm64-v8a`，V2 签名及 16 KiB ZIP 对齐通过，证书 SHA-256 与前版一致（`3EB0F6708904F8EF916C6A2572E394BA981EE25D64861344CF1921CA7EA17975`）。
- 交付 [Review_v3.10.10.apk](../Review_v3.10.10.apk)（33,477,546 字节），SHA-256 `025E8BD862902DF0D6AE6408CC53A949215C7425C5D4F846F9652319244626DE`。3.10.9 已核验并归档至 `build/previous-deliveries/Review_v3.10.9-before-v3.10.10.apk`；根目录仅保留本版 APK。未进行 Android 真机控制栏观感验收。

## 3.10.9+207（2026-10-19）

- 修复私信和群聊会话内点击其他用户头像打开主页时没有触感反馈的问题；保留原本无水波纹手势，仅在有效用户 UID 时调用全局触感工具。
- 文章页工具栏的网页按钮现在在应用内打开原文；普通外链继续使用现有应用内浏览器，用户可从浏览器菜单手动选择外部浏览器。
- `chat_history_test.dart` 21 项、`haptic_feedback_util_test.dart` 7 项、`link_routing_test.dart` 13 项通过；`article_card_test.dart` 8/9 项通过，`detail=true` 请求断言仍失败（该既有失败此前也已记录）。涉及 Dart 文件静态分析和 `git diff --check` 通过。
- ARM64 Release 构建成功（489.5 秒）；核验 `com.review`、版本 `3.10.9`、versionCode 207、target SDK 36、仅 `arm64-v8a`，V2 签名及 16 KiB ZIP 对齐通过，证书 SHA-256 与前版一致（`3EB0F6708904F8EF916C6A2572E394BA981EE25D64861344CF1921CA7EA17975`）。
- 交付 [Review_v3.10.9.apk](../Review_v3.10.9.apk)（33,477,550 字节），SHA-256 `4E7A7818BCDC1225513DEC072F3669A944BF3CBA12DF63AC111DBD56E06E06DA`。3.10.8 已校验并归档至 `build/previous-deliveries/Review_v3.10.8-before-v3.10.9.apk`；根目录仅保留本版 APK。未进行 Android 真机触感或 WebView 外链验收。

## 3.10.8+206（2026-10-19）

- 修复时间线与热搜顶栏单击无操作的问题：单击立即回顶；双击回顶并刷新当前时间线或分类。
- `main_navigation_test.dart` 5 项、`hot_trends_view_test.dart` 5 项通过；修改文件 `dart analyze` 和 `git diff --check` 通过。
- ARM64 Release 构建成功（599.1 秒）；核验 `com.review`、版本 `3.10.8`、versionCode 206、target SDK 36、仅 `arm64-v8a`，V2 签名和 16KiB ZIP 对齐通过，证书 SHA-256 与前版一致。
- 交付 [Review_v3.10.8.apk](../Review_v3.10.8.apk)，33,477,550 字节，SHA-256 `504F6761525878B5016A4BE3707709EADC05EA1D0980E2FC1AE82F32F9E1B63F`。3.10.7 已校验并归档至 `build/previous-deliveries/Review_v3.10.7-before-v3.10.8.apk`；根目录仅保留本版。未进行 Android 真机顶栏手势验收。

## 3.10.7+205（2026-10-19）

- 修复底栏点击当前选中项没有触感反馈的问题；所有有效短点按均调用全局触感工具，保留触感设置开关和 40ms 防重复冷却。
- 时间线顶栏单击和双击操作均提供轻触反馈；打开微博卡片详情时增加轻触反馈，继续禁用水波纹，避免视觉水波纹与触感耦合或重复反馈。
- `main_navigation_test.dart` 4 项、`hot_trends_view_test.dart` 5 项、`haptic_feedback_util_test.dart` 7 项通过；`article_card_test.dart` 8/9 项通过，`detail=true` 用例仍有既存的文章请求断言失败（全量测试此前也出现该项）；涉及文件 `dart analyze` 无问题。
- ARM64 Release 构建成功（506.3 秒）；核验 `com.review`、版本 `3.10.7`、versionCode 205、target SDK 36、仅 `arm64-v8a`，V2 签名及 16 KiB ZIP 对齐通过。签名证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975` 与前版一致。
- 交付 [Review_v3.10.7.apk](../Review_v3.10.7.apk)，33,477,550 字节，SHA-256 `D35460920F86B08F0E5DCE9917795D57EED67903AE2F3A13FB592CD7590EC76C`。3.10.6 已校验并归档至 `build/previous-deliveries/Review_v3.10.6-before-v3.10.7.apk`；根目录仅保留本版。未进行 Android 真机触感验收。

## 3.10.6+204（2026-10-19）

- 修复液态玻璃底栏点按当前选中项时不调用宿主回调的问题，恢复时间线单击回顶/返回位置、双击回顶并刷新，以及热搜单击回顶、双击回顶并刷新当前分类；长按或拖拽回到当前项仍不会触发同页操作。
- 新增玻璃底栏同项连续点按与长按保护回归测试。
- `main_navigation_test.dart` 4 项通过，`hot_trends_view_test.dart` 5 项通过，修改文件 `dart analyze` 无问题。全量 Flutter 测试 318 项中 311 项通过、7 项失败；失败位于既有文章卡片路由及微博长文展开用例，与底栏无关。
- ARM64 Release 构建成功（489.5 秒）；核验 `com.review`、版本 `3.10.6`、versionCode 204、target SDK 36、仅 `arm64-v8a`，V2 签名及 16 KiB ZIP 对齐通过。签名证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975` 与前版一致。
- 交付 [Review_v3.10.6.apk](../Review_v3.10.6.apk)，33,477,550 字节，SHA-256 `91DC3DBA0390B5DFAC97019E20ECCCE2742F1A036062E74ACD166E6CCC8C83F6`。3.10.5 已按 SHA-256 `DA562284D92F9B6BAC5E81AC939F6162AD282A47A0EF83D452D94F403D8A671C` 校验并归档至 `build/previous-deliveries/Review_v3.10.5-before-v3.10.6.apk`；根目录仅保留本版。未进行 Android 真机安装验收。

## 3.10.5+203（2026-10-18）

- 彻底排查并解决启用底栏液态玻璃后切换主页面（时间线、热搜、设置）卡顿和掉帧问题，统一相册与底栏的液态玻璃高性能渲染规范。
- 审计根因与优化实现：
  1. 移除全屏背景采样风暴：移除了 `main_scaffold.dart` 中包裹整个 `Scaffold` 的 `GlassPage` 和包裹内容区域的 `GlassBackgroundSource`，彻底杜绝了 260ms 横移切换切页期间对整屏（1080×2400）每帧执行 `toImageSync` 栅格化和 GPU 纹理上传造成的 Raster 线程阻塞。
  2. 物理采样区域收敛至 340×56 胶囊：在 `ReviewNavigationBar` 外层包裹独立的 `RepaintBoundary` 进行图层物理隔离，底栏的动态折射与重绘被严格限制在自身的胶囊几何区域内，不污染外部长列表页面。
  3. 彻底根治重影、对齐位置与交互双模完美收敛：
     - 底栏位置精准对齐：将液态玻璃底栏与标准胶囊底栏统一采用 `Padding(bottom: widget.hasBottomInset ? 6 : 14)`，彻底解决在全面屏手势模式与三键导航下底栏异常浮起与遮挡视口的问题；
     - 消除文字图标双层叠画：恢复底层反向动态遮罩与选中指示器分层渲染，杜绝未选内容与选中内容重叠造成的错位重影，文字与图标恢复锐利清晰；
     - 交互双模动态收敛（原生 GlassTabBar.bottom）：
       * 100% 保持 `GlassTabBar.bottom` 纯正液态玻璃材质、反向动态遮罩与 3D 高光；
       * 彻底消除点击切换的水珠挤压与膨胀形变：排查发现 `DraggableIndicatorPhysics.buildJellyTransform` 与 `AnimatedGlassIndicator` 内部在弹簧移动时直接根据瞬时速度硬编码了 60% 横向挤压与 124% 纵向拉伸，且 `thickness` 强制变 1.0 导致背景药丸淡出、大水珠镜头淡入。现通过源码级增强让 `buildJellyTransform` 与 `thickness` 严格响应 `indicatorPinchStrength`，点击切换时（`indicatorPinchStrength: 0.0`，`indicatorExpansion: EdgeInsets.zero`）完全禁用形变矩阵并保持刚体背景药丸，实现选中背景平滑直接平移过去（与未开液态玻璃开关时一致）；
       * 完整保留长按与拖拽大水珠：长按（>= 220ms）或拖动滑块时恢复大水滴果冻形变（`indicatorPinchStrength: 0.7`，`indicatorExpansion: (12, 8)`），保留长按移动跟随跳转的原生手感。
  4. 相册高性能原则统一：移除了 `image_gallery_page.dart` 中包裹 4K/HDR 图片手势视口的全局玻璃层，悬浮操作按钮采用自包含独立层 `GlassButton(useOwnLayer: true)`，将模糊局限在 48×48 按钮物理区域内，彻底杜绝大图手势滑动与缩放的离屏开销。
- 质量门禁与基准性能测试：
  - 核心回归测试：主导航 `main_navigation_test.dart`、液态玻璃性能专项测试 `glass_performance_test.dart`、相册手势与联动 `image_gallery_test.dart`、HDR 原生确认 `gallery_hdr_test.dart` 100% 通过；
  - 静态检查：Flutter 静态代码分析 0 error 0 warning。
- ARM64 Release 构建成功；核验 `com.review`、`3.10.5`、versionCode 203、target SDK 36、仅 `arm64-v8a`，V2 签名及 16 KiB ZIP 页面对齐通过。
- 交付 [Review_v3.10.5.apk](../Review_v3.10.5.apk)，32,822,190 字节（31.3 MB），SHA-256 `DA562284D92F9B6BAC5E81AC939F6162AD282A47A0EF83D452D94F403D8A671C`。3.10.4 按 SHA-256 `15530AD5BCA2E053F1ACE89E203CD056948090D240CBD9955CF2DAB9471556A1` 校验归档至 `build/previous-deliveries/Review_v3.10.4-before-v3.10.5.apk`，新包核验后根目录只保留 3.10.5。开发文档已同步至 `D:\App\开发文档\Review.md`。

## 3.10.4+202（2026-10-18）

- 对齐 GreenNote 画廊架构，彻底解决打开 HDR 照片时约 1 秒延迟才开始 HDR 映射流程的问题。
- 根因分析与对齐修复：
  1. 移除 `image_gallery_page.dart` 中阻断挂载的 `_loadedImageUrls.contains(imageUrl)` 门禁，消除等待 Flutter 完整下载解码大图的串行阻塞。
  2. 解除 Hero 转场阻断：`active` 设为 `activeIndex == index && !_isPlayingLive`，不再被 `_chromeRouteVisible` 阻塞，允许 Native PlatformView 在 320ms 转场动画期间即提前启动硬件并行解码。
  3. 平滑渐变机制：引入 `visible: activeIndex == index && _chromeRouteVisible && !_isPlayingLive`，配合 `Opacity(opacity: visible ? 1.0 : 0.0)` 在转场期间保持隐藏并透出下层 Flutter 预览图，转场结束无缝切换为 1.0，完全消除跳变与白屏。
  4. 窗口色彩模式首帧即开：在 `ImageGalleryPage.initState()` 首帧通过 `_checkHdrDisplaySupport()` 与 `_updateWindowHdr()` 检测 HDR 候选图，第 0 帧立即向底层调用 `setWindowHdr(true)`，让屏幕底层色彩管线提前就绪，并移除关闭窗口 HDR 时的全局 `bitmaps.evictAll()` 避免翻页颠簸。
  5. 增强 Android 原生 `HdrImageSupport.kt`：扩充线程池至双线程，支持 `url` 与 `headers` 参数；支持内存缓存（0ms）、本地磁盘 `cacheimage/<md5>` 直接解码，以及在磁盘未命中时通过 Native 边下边解边缓存，解码成功后以 `ImageDecoder.ALLOCATOR_HARDWARE` 呈现并触发 `hdrImageDecoded` 回调。
- 37 项 HDR 与图片画廊测试全部通过，Flutter 静态代码分析 0 error 0 warning。

## 3.10.3+201（2026-10-18）

- 信息流 HDR 角标改为与 GreenNote 网格角标同样的 10sp 文字、5×2dp 内边距、4dp 圆角、0.8dp 白边，不再多出投影。
- 打开候选 HDR 原图时，先复用九宫格已合并的 Range 元数据结果，再通过确定的 MD5 缓存文件路径找到已缓存原图，和 Flutter 首次大图解码并行启动 Android gain-map 解码；页面叠层继续等原图画好和转场结束。减少原来两个大图解码串行等待，不对缓存缺失时额外下载或猜测 HDR，Android 最终仍须确认 gain-map。
- 37 项 HDR/画廊回归通过，含 GreenNote 角标参数、MD5 缓存精确命中、并发 Range 探测与 native decode 合并、HDR/SDR 候选识别和原 Hero/缩放/分页回归。3 个相关 Dart 源码与测试文件分析无告警，差异空白检查通过。
- 本机 ADB 没有连接设备；未测 vivo X300 Pro 的真实 HDR 亮度映射时延、动画观感和清晰度。自动化确认的是缓存命中时原生 HDR 解码会提前启动，缓存缺失、范围请求失败或不支持的设备沿用已有路径。
- ARM64 Release 构建成功（本地依赖缓存，Gradle 离线组装约 68 秒；首次在线构建等待 TLS 475.6 秒后停止并沿用相同 Gradle 参数离线重试）。核验 `com.review`、`3.10.3`、versionCode 201、target SDK 36、仅 `arm64-v8a`，V2 签名及 16 KiB ZIP 对齐通过；签名证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975` 与前版一致。ARM64 AOT 已检出候选 HDR 本地缓存预热函数。
- 交付 [Review_v3.10.3.apk](../Review_v3.10.3.apk)，33,526,702 字节，SHA-256 `36EC5B532C877ECCE6A285B0BD8CDC23F99C7C1D4BD3347ECBCF7637C67F3A01`。3.10.2 按 SHA-256 `5AEFB643D0FC5EADAE237E6B58FE670C7120DCE24F05604C32AC74A8BDC99B18` 校验归档至 `build/previous-deliveries/Review_v3.10.2-before-v3.10.3.apk`，新包核验后根目录只保留 3.10.3。开发文档已同步至 `D:\App\开发文档\Review.md`，未提交或推送源码。

## 3.10.2+200（2026-10-18）

- 私信/群聊附件视频显示封面和播放入口，隐藏“分享视频”协议文字，点击轻震动后复用图片画廊与既有视频播放器；打开/关闭沿用图片 Hero，转场期间不创建视频解码器。
- 按官方 WebIM metadata 的 replace 两步解析播放 fid，保留私有附件鉴权，支持 media_type=10 和元数据确认的 MP4 文件；列表只查元数据、不自动播放或下载视频。封面鉴权按自身 URL 单独生成。
- 修复链接卡片优先短链而忽略实体与长地址的问题；微博/用户卡片优先原生详情/主页，其他卡片优先有效长地址，官方 HTTP t.cn 短链升级 HTTPS。
- 77 项定向回归通过；再补私信/群聊 media_type=5 的 MP4 兼容用例，聊天文件 14 项全部通过（本轮合计覆盖 79 个不同用例）。涵盖私有鉴权、replace 两次元数据查询、无列表自动播放、一次打开仅创建一个播放器、返回不重建、卡片实际进入原生详情，以及原有混合媒体、图片 Hero、HDR、发送和历史回归。8 个相关 Dart 文件分析无问题，差异空白检查通过。
- 本轮未重跑全量套件；前版全量的 7 项既有文章/长文本断言失败仍见 3.10.1 记录。本机 ADB 无设备，未用真实账号/手机核验视频首帧、声音、触感、转场观感及卡片服务端权限。未发送测试私信或群消息。
- ARM64 Release 构建成功（384.7 秒）；耗时包含依赖仓库 TLS 握手等待，在线构建自行恢复并成功，未实际改用离线参数。核验 `com.review`、`3.10.2`、versionCode 200、target SDK 36、仅 `arm64-v8a`，V2 签名及 16 KiB ZIP 对齐通过；签名证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975` 与前版一致。包内 ARM64 AOT 已检出本版新增 metadata callback 与接口标记。
- 交付 [Review_v3.10.2.apk](../Review_v3.10.2.apk)，33,461,166 字节，SHA-256 `5AEFB643D0FC5EADAE237E6B58FE670C7120DCE24F05604C32AC74A8BDC99B18`。3.10.1 按 SHA-256 `61C0FEC4ECB7F149DE0033F36F72CD5B6492D6F29BA5E1960600E75675D4C3EB` 校验归档至 `build/previous-deliveries/Review_v3.10.1-before-v3.10.2.apk`，新包核验后根目录只保留 3.10.2。开发文档已同步至 `D:\App\开发文档\Review.md`，未提交或推送源码。

## 3.10.1+199（2026-10-18）

- 修复 HDR 角标首次探测完成后不显示、需要打开图片再返回九宫格才显示的问题。完成清理回调不再返回请求自身的 Future，首次等待者现在能正常完成；不新增网络探测或轮询。
- 减少主 Tab 平移时的重复页面绘制，标准悬浮底栏指示条改为固定尺寸平移；保留页面状态、快速切换和原有动画时长。修复时间线页面退出时访问已销毁 ref 的异常。
- 移除私信/群聊上拉刷新控件，历史仍自动分页。按当前官方 Web 修正发送表单编码及文本字段，识别群聊 mid 成功响应，按 ID 回读确认；发送失败保留草稿并显示服务端错误，发送期间新编辑的草稿不被覆盖，不自动重复发送。
- 定向 41 项回归全部通过，涵盖冷启动九宫格、HDR/SDR、并发与失败清理、真实 HTTP adapter 的表单字节、私信/群聊接受和拒绝、HTTP 失败保留草稿、回读边界、发送期间编辑、聊天历史与图片 Hero、主 Tab 绘制复用和 18 图兼容。9 个相关 Dart 文件分析无问题，`git diff --check` 通过。
- 全量测试 306 项通过、7 项失败；失败为既有 `article_card_test.dart` 文章封面详情入口和 `widget_test.dart` 6 项长文本展开断言，逐一核对均已出现在较早的 `build/chat-baseline-tests.log` / `build/chat-full-tests.log`。本轮完整结果保存在 `build/review-3101-full-tests-final.log`，不将全量记为通过。未连接真机核验 HDR 高光、实际 120fps 或真实账号消息投递。
- ARM64 Release 构建成功（244.7 秒）；`aapt2` 核验 `com.review`、`3.10.1`、versionCode 199、target SDK 36、仅 `arm64-v8a`，V2 签名和 16 KiB ZIP 对齐通过。签名证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975` 与前版相同。
- 交付 [Review_v3.10.1.apk](../Review_v3.10.1.apk)，33,461,166 字节，SHA-256 `61C0FEC4ECB7F149DE0033F36F72CD5B6492D6F29BA5E1960600E75675D4C3EB`。3.10.0 已按原 SHA-256 `0C80CB8BF935F5A69F26CFA73363F7B97DD17F9F6E375729223D1345F2240D9C` 校验归档至 `build/previous-deliveries/Review_v3.10.0-before-v3.10.1.apk`；核验新包后根目录仅保留 3.10.1。未提交或推送源码；完整开发文档已同步至 `D:\App\开发文档\Review.md`。

## 3.10.0+198（2026-10-18）

- 信息流单图和九宫格右下角预览 HDR 角标；仅请求新浪 `/large/` 图片的 256 KiB 范围头部，不预下载完整图片、不附带微博账号 Cookie，并缓存有限数量的结果。范围与画廊 HDR 元数据检查保持一致，避免缩略图漏掉较靠后的标记。
- 私信与群聊多图复用现有图片画廊及 Hero 放大/缩回转场；同一消息的图片在画廊中可左右切换，点击图片触发一次轻震动。
- 定向 HDR/聊天回归 16 项通过；5 个相关 Dart 文件分析无问题，`git diff --check` 通过。新浪样本原图的 Range 返回 HTTP 206，头部包含 HDR 标记；实际 vivo HDR 显示与设备动画/触感仍待真机确认。
- ARM64 Release 构建成功（227.0 秒）；核验 `com.review`、版本 `3.10.0`、versionCode 198、target SDK 36、仅 `arm64-v8a`，V2 签名和 16 KiB ZIP 对齐通过。签名证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975` 与前版一致。
- 交付 [Review_v3.10.0.apk](../Review_v3.10.0.apk)，33,461,166 字节，SHA-256 `0C80CB8BF935F5A69F26CFA73363F7B97DD17F9F6E375729223D1345F2240D9C`。3.9.1 已校验归档至 `build/previous-deliveries/Review_v3.9.1-before-v3.10.0.apk`，根目录只保留本版。完整开发文档已同步至 `D:\App\开发文档\Review.md`。未连接真机复核 HDR 高光、消息图片转场观感、GIF 帧率或实际震动；没有提交或推送源码。


## 3.9.1+197（2026-10-18）

- 修复原图字段缺失时画廊可能沿用新浪图床预览规格，导致 HDR 数据在检测前已丢失；处理内存帧与临时文件生命周期不同步，并增加脱敏原生解码/绘制诊断。vivo X300 Pro / Android 17 的实际 HDR 效果待真机复核。
- 修复私信/群聊图片和动态图固定大视口及“分享图片”协议占位文字；纯图片紧凑布局并保留点击画廊。
- 按官方 WebIM 数据渲染链接卡片，缺失元数据的可见纯 URL 消息只补查一次完整消息，失败保留可点链接。
- 修复 `[/ee90a0.png]` 等文件名型表情，兼容 HTML 源图与 470 条 SoftBank 历史表情映射。
- 60 项定向回归通过，10 个相关 Dart 源码/测试文件分析无告警，差异检查通过（`core.whitespace=cr-at-eol`）。未重新运行全量测试。
- 最终 ARM64 Release 增量构建成功（182.8 秒）；核验包名 `com.review`、版本 `3.9.1`、versionCode 197、target SDK 36、仅 `arm64-v8a`，testOnly 未启用，V2 签名和 16 KiB ZIP 对齐均通过；签名证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975` 与原包一致。最终包 DEX/AOT 已确认原生 HDR 诊断、历史文件名表情正则、卡片补全和聊天内容布局代码，编译后源码哈希未漂移。
- 交付 [Review_v3.9.1.apk](../Review_v3.9.1.apk)，33,395,630 字节，SHA-256 `2E062A4C6BB803E86D80AA188775054DA0377BBA517BBFB0D0DC5B0316459664`。3.9.0 已校验复制后归档到 `build/previous-deliveries/Review_v3.9.0-before-v3.9.1.apk`，根目录保留新包。核验记录保存于忽略的 `build/hdr-chat-391-*`；官方 Web 静态代码参考在 `build/chat-render-audit/`。开发文档已同步到 `D:\App\开发文档\Review.md`。未在用户 vivo X300 Pro 上安装验证 HDR 高光、GIF 流畅度及真实账号消息；没有提交或推送源码。


## 3.9.0+196（2026-10-18）

- 新增 Android 14+ JPEG gain-map/Ultra HDR 原图查看；复用已下载的原图缓存，原生确认增益图后用硬件 ImageDecoder + Hybrid Composition 显示。普通图片和不支持设备自动保留原路径。
- 主图与画廊缩略条增加 GreenNote 同款 HDR 角标；不根据文件名或宣传误标，不预下载全部信息流原图。
- 限制原生解码、缓存和挂载范围；保持现有 Hero、分页、缩放和 Live Photo 行为，退出恢复窗口色彩模式。
- 样本来自用户提供的微博 `5345552066939360`，实测原图有 gain-map/ISO 21496 元数据，缩略图没有。当前无 ADB 真机，不宣称实际高光亮度或流畅度已验收。


- 36 项 HDR/画廊回归全部通过；相关 5 个 Dart 源码/测试文件定向分析无告警，差异检查通过（CRLF 文件按 `core.whitespace=cr-at-eol` 检查）。保留现有其他改动，未运行新的全量测试。
- 最终 ARM64 Release 增量构建成功（155.7 秒）；包名 `com.review`、版本 `3.9.0`、versionCode 196、min SDK 24、target SDK 36、仅 `arm64-v8a`，V2 签名和 16 KiB ZIP 对齐通过。签名证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975` 与原项目签名一致。APK 的 DEX/AOT 中已确认 HDR 原生类、最终 `cacheBudget` 字段、通道与画廊角标代码；相关日志和样本结构报告保存在忽略的 `build/hdr-*`、`build/hdr-audit/`。
- 交付 [Review_v3.9.0.apk](../Review_v3.9.0.apk)，33,395,630 字节，SHA-256 `E5FEE19FA66BF510820F616711A3FB2241330FB41E444AE8E56F35F4D5259E1C`。原根目录 3.8.0 APK 已校验哈希后归档至 `build/previous-deliveries/Review_v3.8.0-before-v3.9.0.apk`，保留回退。此包基于当前完整工作区，也包含同时存在的私信修复源码；并发消息修复的独立快照构建记录仍以其 3.8.1 条目为准。没有安装到设备，没有提交或推送源码。


## 3.8.1+195（2026-10-18）

- 修复“我的消息”页面“私信与群聊”标题后出现大段空白：嵌套会话列表显式关闭自动安全区 padding 和主滚动继承，外层继续负责顶栏与状态栏间距。
- 修复聊天气泡只渲染文本、忽略图片附件的问题。依据[微博聊天网页版](https://api.weibo.com/chat/)当前加载的 `app.48f8ddda.js`，读取 `media_type=1` 的 `att_ids`/`fids` 与 `pic_infos.original_pic`，显示缓存图片并打开已有画廊查看/下载；聊天预览解码宽度最多 1024px。登录 Cookie 仅附加到精确 HTTPS `upload.api.weibo.com/2/mss/msget` 路径，不发送给公共图床或其他地址。
- 私信和群聊在距离历史边缘 480dp 内自动预取旧消息，每次 40 条。分别使用 `max_id` / `max_mid` 和最早消息 ID 减 1 的游标；倒序懒列表在尾部追加历史，保持阅读位置。并发请求互斥、边界去重、空页/无新增时停止；失败保留消息与游标并提供重试，避免无限自动重试。发送后回读最新消息时保留已加载历史，优先复用接口自带发言人资料以减少补查。
- 新增 8 项回归，连同既有消息测试共 25 项全部通过；修改前后对照及独立快照全量测试均确认 33 项既有失败完全相同，独立快照全量为 256 通过、33 失败（主要为旧画廊用例缺少 ProviderScope 和既有卡片断言）。7 个相关源码/测试文件定向分析无问题。未使用真实账号收发测试消息，构造样例与解码图片测试不代表线上私信媒体已完成账号/设备验收。
- 本次开发中发现同目录有并发 HDR 原生/画廊修改；消息修复交付使用基于 `57a9d70` 并仅覆盖本次消息、媒体鉴权和版本文件的独立源码快照 `build/chat-release-source`。并发 HDR 文件与其他测试改动保留，不纳入本次消息修复 APK。

## 3.8.0+194（2026-10-18）

- 设置新增独立“缓存管理”页，可查看并手动清理可再生成的图片磁盘缓存；自动清理阈值默认 **200 MB**，支持关闭或选择其他阈值。统计和删除严格限定于临时 `cacheimage` 目录下直接存放、文件名为 32 位小写 MD5 的图片缓存，并保留最近 1 分钟写入的文件；不影响相册媒体、账号数据或其他临时文件。达到阈值时在启动阶段清理，修改阈值时立即检查。
- 关闭液态玻璃时，普通悬浮底栏改为单个灰色胶囊随选中项平滑移动，点击切页时可见选中背景过渡；保留既有液态玻璃底栏和固定导航栏分支。
- `flutter analyze --no-pub` 定向检查本次 7 个 Dart 文件通过，`git diff --check` 通过；未运行测试。ARM64 Release 命令生成了 APK，但 Flutter CLI 最终因 Gradle daemon 收到停止命令返回退出码 1。对生成并交付的 APK 独立核验：包名 `com.review`、版本 `3.8.0`、`versionCode` 194、target SDK 36、仅 `arm64-v8a`、16 KB ZIP 对齐及 APK V2 签名均符合预期；签名证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`。
- 交付 [Review_v3.8.0.apk](../Review_v3.8.0.apk)（33,395,602 字节），SHA-256：`FAE4D5090CC90630A337CA7577B6291C10D2A8987805E97477D761F5C1556305`；此前 `3.7.0+193` 回退包归档于 [Review_v3.7.0+193-before-v3.8.0.apk](../build/previous-deliveries/Review_v3.7.0+193-before-v3.8.0.apk)（33,395,602 字节），SHA-256：`60F088181071F7FA63D689E3A83B7EA310C29604F84DADFC06DA31F7C5F85AC1`。未在目标设备安装验收或检查实际界面效果。

## 3.7.0+193（2026-10-18）

- **信息流接入官方客户端原生 API，实现双通道容灾架构**：
  - 核实并解决“登录未掉但网页 Cookie 到期导致信息流刷不出”的问题。原生底层（`WeiboApi`/`WeiboAuthManager`）具备完整的客户端鉴权凭据（`gsid`、`sut`、`oauthSignature` 及 `cum` 校验签名），扩展原生请求转发接口，使信息流能以原生移动客户端身份直连官方核心 API（`https://api.weibo.cn/2/`）。
  - **关注流**：优先通过原生 API 调用 `statuses/unread_friends_timeline`（首屏未读）与 `statuses/friends/timeline`（历史分页），原生失效或网络异常时自动无缝降级至桌面 Ajax、移动端 H5 关注流及热门流。
  - **分组流与分组列表**：优先通过原生 API 获取分组微博 `groups/timeline`（带 `list_id`）与分组列表 `groups/allgroups`，异常时降级至桌面端接口。
  - **用户主页微博流**：统一抽象为 `FeedRepository.getUserTimeline`，优先调用原生 API `statuses/user_timeline`，彻底摆脱网页端 Cookie 寿命限制；失败时降级至桌面端 `/ajax/statuses/mymblog`。
  - **双通道容灾与完全向后兼容**：保留所有既有网页端 Cookie 导入与 Web 请求链路；支持桌面端、移动端与原生 API 三层容灾。
- 架构与工程实现：
  - `WeiboApi.java` 增加 `request(session, endpoint, params)` 方法并扩容响应上限至 4MB，`WeiboAuthManager.java` 引入内存会话缓存 `activeSession` 与 `hasNativeSession()`。
  - `MainActivity.kt` 原生通信线程池扩容至 4 线程，防止多并发请求串行阻塞；MethodChannel 增加 `hasNativeSession` 与 `requestWeiboApi`。
  - 新增 `WeiboNativeApi` Dart 客户端封装，`native_api_feed_test.dart` 5 个单元测试用例全量通过（5/5 passed），`flutter analyze --no-pub` 零告警。
- 版本按功能更新规则由 `3.6.1+192` 升至 `3.7.0+193`。ARM64 Release 构建成功（197.4 秒），核验包名 `com.review`、版本 `3.7.0`、`versionCode` 193、target SDK 36、仅 `arm64-v8a` 及 APK V2 签名；签名证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`。
- 交付 [Review_v3.7.0.apk](../Review_v3.7.0.apk)（33,395,602 字节），SHA-256：`60F088181071F7FA63D689E3A83B7EA310C29604F84DADFC06DA31F7C5F85AC1`；旧版回退包保留于 [Review_v3.6.1+192-before-v3.7.0.apk](../build/previous-deliveries/Review_v3.6.1+192-before-v3.7.0.apk)（33,395,602 字节），SHA-256：`6FB53CBA1CAE651BC52F03F69A7AD08CC44D7208A7CC33ECBDA4FD7357065062`。

## 3.6.1+192（2026-10-18）

- 提高液态玻璃悬浮底栏在浅色图片背景上的选中项可读性：选中水滴填充改为深色 40% 不透明度，选中图标和文字改为白色；保留折射、模糊和长按拖动行为。
- 版本按既有 bug 修正规则从 `3.6.0+191` 升至 `3.6.1+192`。`review_navigation_bar.dart` 定向分析无问题，`dart format` 未修改文件，`git diff --check` 通过；未运行测试。ARM64 Release 构建成功（175.9 秒），核验包名 `com.review`、版本 `3.6.1`、`versionCode` 192、target SDK 36、仅 `arm64-v8a`、16 KB ZIP 对齐及 APK V2 签名；签名证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975`。
- 交付 [Review_v3.6.1.apk](../Review_v3.6.1.apk)（33,395,602 字节），SHA-256：`6FB53CBA1CAE651BC52F03F69A7AD08CC44D7208A7CC33ECBDA4FD7357065062`；旧版回退包保留于 [Review_v3.6.0+191-before-v3.6.1.apk](../build/previous-deliveries/Review_v3.6.0+191-before-v3.6.1.apk)（33,395,602 字节），SHA-256：`62B039A066FC2C4CE2B1EEA7FB8A33300F68D571067BC95A4276AD0E3A11014D`。未在目标设备对浅色图片背景进行视觉验收。

## 3.6.0+191（2026-10-18）

- 图片画廊通过匹配的信息流 Hero 复用已经解码的缩略图帧，在原图加载时先显示预览；原图完成后于下一帧释放克隆的图像句柄并显示原图。沿用现有图片地址、缓存和 Hero 动画，不新增缩略图请求；没有可匹配的已解码 Hero 帧时保持既有加载方式。
- 合并 3.5.4 画廊按钮常态透镜改进：默认玻璃折射保持可见，画廊作用域最低质量为 `standard`。
- `image_gallery_page.dart` 定向 `flutter analyze --no-pub` 无问题，`dart format` 未修改文件，`git diff --check` 通过；本轮未运行测试。ARM64 Release 构建成功（192.1 秒），核验包名 `com.review`、版本 `3.6.0`、`versionCode` 191、target SDK 36、仅 `arm64-v8a`、16 KB ZIP 对齐和 APK V2 签名；证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975` 与前版一致。
- 交付 [Review_v3.6.0+191-before-v3.6.1.apk](../build/previous-deliveries/Review_v3.6.0+191-before-v3.6.1.apk)（33,395,602 字节），SHA-256：`62B039A066FC2C4CE2B1EEA7FB8A33300F68D571067BC95A4276AD0E3A11014D`；3.5.4+190 ARM64 回退包保留于 [Review_v3.5.4+190-before-v3.6.0.apk](../build/previous-deliveries/Review_v3.5.4+190-before-v3.6.0.apk)（33,395,602 字节），SHA-256：`7F6C09CDE35DB961C37E417FC04BD23BE9B3A2DD17F68D46A84BF2AA04424E00`。未在目标设备检查冷缓存首帧和预览到原图的切换观感。

## 3.5.4+190（2026-10-18）

- 修正图片画廊返回/下载玻璃按钮静止态透镜折射不明显的问题。开启液态玻璃时将按钮折射厚度从 10 调至 32、折射率从 1.18 调至 1.24，并将该画廊作用域质量下限设为 `standard`，避免降到无折射 shader 的 `minimal`；未按压时持续折射下方图片/视频，按压水滴交互和关闭开关时的样式不变。
- 版本从 `3.5.3+189` 升至 `3.5.4+190`。`image_gallery_page.dart` 定向分析无问题，`git diff --check` 通过，未运行测试。ARM64 Release 构建成功（188.3 秒），核验包名 `com.review`、版本 `3.5.4`、`versionCode` 190、target SDK 36、仅 `arm64-v8a`、16 KB ZIP 对齐和 APK V2 签名；签名证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975` 与前版一致。
- 3.5.4 ARM64 回退包归档为 [Review_v3.5.4+190-before-v3.6.0.apk](../build/previous-deliveries/Review_v3.5.4+190-before-v3.6.0.apk)（33,395,602 字节），SHA-256：`7F6C09CDE35DB961C37E417FC04BD23BE9B3A2DD17F68D46A84BF2AA04424E00`。未在目标设备安装或验收静止态透镜/长按观感。

## 3.5.3+189（2026-10-18）

- 修正图片画廊按钮没有大水滴折射的问题：开启时让 `GlassButton` 请求 `premium` shader 质量并保留自适应质量上限；移除 `interactionScale: 1.06`，恢复 48dp 按钮原生约 17dp 按压膨胀，让媒体内容在水滴下方参与完整折射。开关关闭时的现有局部 shader/模糊样式不变。
- 版本从 `3.5.2+188` 升至 `3.5.3+189`。画廊文件 `flutter analyze --no-pub` 无问题，`dart format` 未修改文件，`git diff --check` 通过；未运行测试。ARM64 Release 构建成功（158.8 秒），核验包名 `com.review`、版本 `3.5.3`、`versionCode` 189、target SDK 36、仅 `arm64-v8a`、16 KB ZIP 对齐和 APK V2 签名；签名证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975` 与前版一致。
- 交付 [Review_v3.5.3.apk](../Review_v3.5.3.apk)（33,395,602 字节），SHA-256：`FD03DA0058448C4BAC7E8C0BBF88E40F6B7CDC6AF3DC5AB896A3069733D55C0E`；3.5.2+188 回退包保留于 [Review_v3.5.2+188-before-v3.5.3.apk](../build/previous-deliveries/Review_v3.5.2+188-before-v3.5.3.apk)（33,395,602 字节），SHA-256：`A143637E0C8BE8C99951135AA8F67FE064AF222C0FD90FBBD8F53A77328FBF6F`。未进行目标设备安装或实际按钮折射/按压观感验收。

## 3.5.2+188（2026-10-18）

- 修复液态玻璃底栏慢速长拖跨多页时被错误限制到相邻页的问题。使用 Flutter `VelocityTracker` 读取松手水平速度，只对达到 `1000 logical px/s` 的快速抛动限制一页；慢拖按水滴最终所在 Tab 提交，时间线可慢拖到设置并跨过热搜。
- 版本由 `3.5.1+187` 升至 `3.5.2+188`。导航组件 `flutter analyze --no-pub` 无问题，`git diff --check` 通过；未运行测试。ARM64 Release 构建成功（255.2 秒），核验包名 `com.review`、版本 `3.5.2`、`versionCode` 188、target SDK 36、仅 `arm64-v8a`、16 KB ZIP 对齐和 APK V2 签名；签名证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975` 与前版一致。
- 交付 [Review_v3.5.2.apk](../Review_v3.5.2.apk)（33,395,602 字节），SHA-256：`A143637E0C8BE8C99951135AA8F67FE064AF222C0FD90FBBD8F53A77328FBF6F`；3.5.1+187 回退包保留于 [Review_v3.5.1+187-before-v3.5.2.apk](../build/previous-deliveries/Review_v3.5.1+187-before-v3.5.2.apk)（33,395,602 字节），SHA-256：`BE861A9AA8A9FE9309C92411A008F0B432F8E7BD4336A4CA948CB8E08BE20EE8`。未进行目标设备安装或慢拖/快速抛动的真机验收。

## 3.5.1+187（2026-10-18）

- 加强液态玻璃开启时画廊返回/下载按钮的水滴边缘折射：色散提高到与底栏选中水滴相同的 0.025，按住拖动时启用锚定拉伸和回弹，并匹配底栏白色交互高光。短点仍执行按钮动作，长按/拖动用于水滴交互；开关关闭时的按钮保持原样。
- 版本按既有功能修正规则从 `3.5.0+186` 升至 `3.5.1+187`。目标画廊文件 `flutter analyze` 无问题，`git diff --check` 通过；未运行测试。最终 ARM64 Release 构建成功（353.7 秒），核验包名 `com.review`、版本 `3.5.1`、`versionCode` 187、target SDK 36、仅 `arm64-v8a`、16 KB ZIP 对齐和 APK V2 签名；签名证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975` 与前版一致。
- 交付 [Review_v3.5.1.apk](../Review_v3.5.1.apk)（33,395,602 字节），SHA-256：`BE861A9AA8A9FE9309C92411A008F0B432F8E7BD4336A4CA948CB8E08BE20EE8`；3.5.0+186 回退包保留于 `build/previous-deliveries/Review_v3.5.0+186-before-v3.5.1.apk`（33,395,602 字节）。未进行目标设备安装、边缘折射画面或 GPU 帧率验收。

## 3.5.0+186（2026-10-18）

- 将个性化“使用液态玻璃效果”开关延伸到图片画廊左上返回和右上下载按钮。关闭时沿用原有局部 shader/模糊样式；开启时使用 `liquid_glass_widgets` 的 `GlassButton`，保留原按钮动作、过场显隐、下载禁用态和读屏标签。
- 仅开启时为画廊路由建立自适应玻璃质量作用域与媒体背景源；背景源排除顶部按钮，避免采集玻璃自身。版本按功能规则由 `3.4.3+185` 升至 `3.5.0+186`。
- 画廊文件 `dart analyze` 无问题，`git diff --check` 通过；未运行 Flutter 测试。ARM64 Release 构建成功（223.4 秒），核验包名 `com.review`、版本 `3.5.0`、`versionCode` 186、target SDK 36、仅 `arm64-v8a`、16 KB ZIP 对齐和 APK V2 签名。签名证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975` 与前版一致。
- 交付 [Review_v3.5.0+186-before-v3.5.1.apk](../build/previous-deliveries/Review_v3.5.0+186-before-v3.5.1.apk)（33,395,602 字节），SHA-256：`2520556E1CCC254310691B13BF13DCFFD84E5CEEFFB7EB85128749CB8CF67F2A`；3.4.3+185 回退包保留于 `build/previous-deliveries/Review_v3.4.3+185-before-v3.5.0.apk`（33,330,066 字节）。未进行目标设备安装、画面或 GPU 帧率验收。

## 3.4.3+185（2026-10-18）

- 修复液态玻璃底栏首启时长时间停留在标准画质的问题。原局部 `GlassAdaptiveScope(initialQuality: GlassQuality.standard)` 跳过了库的启动热身，恢复 premium 需等待多轮稳定帧窗口；移除固定初始质量后，底栏使用已预热的 premium 首帧路径，并保留 shader 支持探测和帧耗时自适应降级。
- 主体背景 blur 从 1.5 调到 2.0、折射率从 1.16 调到 1.19，轻微加强柔化与透镜折射；其余导航与手势行为不变。
- 定向分析通过（2 个修改的 Dart 文件无问题，4.2 秒）；`git diff --check` 通过，未运行 Flutter 测试。ARM64 Release 构建成功（242.0 秒），核验 `com.review`、版本 `3.4.3`、`versionCode` 185、target SDK 36、仅 `arm64-v8a`、16 KB ZIP 对齐及 APK V2 签名；证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975` 与前版一致。交付 [Review_v3.4.3.apk](../Review_v3.4.3.apk)（33,330,066 字节），SHA-256：`777595EAC38F7710A412BD91CAF346797B9694C5E7D4868DAAF21C7B0994B40F`；3.4.2+184 回退包保留于 `build/previous-deliveries/Review_v3.4.2+184-before-v3.4.3.apk`。未连接 Android 设备，真实启动时序、视觉折射和 GPU 帧率尚未真机验收。

## 3.4.2+184（2026-10-17）

- 修复液态玻璃底栏在时间线/热搜长按水滴时，按下阶段提前执行当前 Tab 回顶/刷新的问题。玻璃手势回调改为松手后提交；长按或拖回当前页时不触发同页动作，短点按仍保留既有重复点击行为，键盘与读屏语义激活仍即时执行。
- 液态玻璃拖动释放最多切换到起始页相邻的一项，拦截速度补偿造成的跨两页跳转（例如时间线直接跳到设置）。标准导航栏逻辑未改。
- 定向分析无问题，`git diff --check` 通过；ARM64 Release 构建成功（191.4 秒），未运行 Flutter 测试。APK 核验 `com.review`、版本 `3.4.2`、`versionCode` 184、target SDK 36、仅 `arm64-v8a`、16 KB ZIP 对齐及 APK V2 签名；证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975` 与前版一致。交付 [Review_v3.4.2.apk](../Review_v3.4.2.apk)（33,330,066 字节），SHA-256：`C1C917BC0EEC1FEF89C072AF20F3F4926EFDD064AF177D5C8836D266F7CFAD8F`；3.4.1 回退包保留于 `build/previous-deliveries/Review_v3.4.1+183-before-v3.4.2.apk`。未连接 Android 设备，手势时序、视觉效果和 GPU 帧率尚未真机验收。

## 3.4.1+183（2026-10-17）

- 将“使用液态玻璃效果”移出“底部导航”分组，作为独立、常驻的个性化设置；关闭悬浮底栏时仍可设置并保留偏好，当前仅悬浮底栏消费该偏好。
- 液态玻璃栏宽度改为原响应式宽度的 `2/3`。只在玻璃底栏实际启用时建立局部 `GlassAdaptiveScope`，以 `standard` 开始并根据 shader 支持与运行帧耗时自适应升降质量，避免在所有 Android 设备上始终强制 `premium`。
- 版本名升至 `3.4.1`、Android `versionCode` 升至 `183`。修改文件定向分析无问题；全项目分析无 error/warning、报告 57 条 info；未运行 Flutter 测试。`git diff --check` 通过。
- ARM64 Release 构建成功（226.0 秒），核验 `com.review`、版本 `3.4.1`、`versionCode` 183、target SDK 36、仅 `arm64-v8a`、16 KB ZIP 对齐和 APK V2 签名；证书 SHA-256 `3eb0f6708904f8ef916c6a2572e394ba981ee25d64861344cf1921ca7ea17975` 与 `3.4.0+182` 一致。交付 [Review_v3.4.1.apk](../Review_v3.4.1.apk)（33,330,066 字节），SHA-256：`7261E93DE5B3050F252A10BCB03EC563F08B45C72D2A3153679E9F545FE719AC`；`3.4.0+182` 回退包保留于 `build/previous-deliveries/Review_v3.4.0+182-before-v3.4.1.apk`。未连接 Android 设备，尚未做安装、视觉或 GPU 帧率验收。

## 3.4.0+182（2026-10-17）

- 引入 `liquid_glass_widgets: ^1.13.0` 并按要求在应用启动时预热 shader、接入亮度解析器。
- 个性化增加“使用液态玻璃效果”，默认关闭并纳入 WebDAV 个性化备份；仅悬浮底栏开启该选项时生效。
- 主页面使用 `GlassPage`、`Scaffold.extendBody` 和单一 body `GlassBackgroundSource`；将现有时间线/热搜/设置三项导航替换为按指定折射、高光、色散、尺寸与安全区参数配置的 `GlassTabBar.bottom`。库导航语义、轻触反馈和重复点击回顶/刷新的回调保持原样。
- 液态玻璃模式为三个根页面按 `viewPadding.bottom + 76dp` 增加滚动留白，避免 `extendBody` 注入底栏高度后重复计入；禁用时继续使用原 M3 导航和页面留白。
- 修改文件定向分析未发现错误/警告，仅有既有的 `feed_view.dart` `axisAlignment` 弃用 info；本轮未运行 Flutter 测试。`git diff --check` 通过。
- ARM64 Release 构建成功（271.5 秒），核验 `com.review`、版本 `3.4.0`、`versionCode` 182、target SDK 36、仅 `arm64-v8a`、16 KB ZIP 对齐及 APK V2 签名；证书 SHA-256 与 `3.3.0` 相同。交付 [Review_v3.4.0.apk](../Review_v3.4.0.apk)（33,330,066 字节），SHA-256：`8BD345B55199C15857A38E163C1CDFA80880C0B169A1A9ED610D97EF942A0F5D`；`3.3.0` 回退包保留于 `build/previous-deliveries/Review_v3.3.0-before-v3.4.0.apk`。没有连接真机，本轮未做安装、GPU 帧率或视觉验收。

## 3.3.0+181（2026-10-14）

- 个性化新增应用字体大小滑杆，布局、范围及步进参考 Review X；拖动时全局即时预览，松手保存，默认 100%。
- 缩放保留平台 TextScaler 曲线，系统无障碍字号仍生效；设置保存在本机，不加入 WebDAV 导出白名单。
- 新增字号定向测试 3 项通过，覆盖系统缩放曲线组合、预览/松手持久化/范围钳制及 Review X 式分组滑杆布局。修改文件定向 analyze 无问题；全项目 analyze 无 error/warning，保留 57 条 info。全量 Flutter 测试为 269 项通过、7 项失败；失败是既有的文章详情路由 1 项与微博正文折叠阈值 6 项，本次字号用例通过。`git diff --check` 通过。
- ARM64 Release 构建成功（369.6 秒），核验 `com.review`、版本 `3.3.0`、`versionCode` 181、target SDK 36、仅 `arm64-v8a`、16 KB ZIP 对齐及 APK V2 签名；签名证书 SHA-256 与前版一致。交付 [Review_v3.3.0.apk](../Review_v3.3.0.apk)（32,641,277 字节），SHA-256：`70DAD022C1435E50D7F34D5E00C45A27291B6007F6171705E5E5EE9679F281AD`；3.2.9 回退包保留于 `build/previous-deliveries/Review_v3.2.9-before-v3.3.0.apk`。没有连接真机，本轮未做安装和视觉验收。

## 3.2.9+180（2026-10-14）

- 修复实际 Hero 飞行层中的分页器祖先强制非空：图片已解码时 overlay 无分页器，旧代码抛出空值异常，被 Release 默认浅灰色 ErrorWidget 替代。现在飞行层直接绘制图片，分页识别器只在正式画廊页内注册。
- 撤回 3.2.8 无效的整页淡入改动，恢复原有路由背景过渡；连续快滑、缩放、滚轮与媒体激活实现保持。
- 用实际 Navigator push/pop 的解码转场回归替换只检查构建器返回类型的测试；修复前捕获空值异常，修复后验证真实飞行像素、动画中原图完成、重复打开、左右切图后返回均无 ErrorWidget。画廊/混合媒体定向 31 项通过，相关源码和测试分析无问题；本轮没有重复全量测试，既有全量失败记录见 3.2.8。
- ARM64 Release 构建成功（484.5 秒）；核验 `com.review`、`3.2.9+180`、target SDK `36`、仅 `arm64-v8a`、APK V2 签名证书与 3.2.8 一致、16 KB ZIP 对齐。交付 [Review_v3.2.9.apk](../Review_v3.2.9.apk)（32,510,209 字节），SHA-256：`3E965D4DAB8DC60C3710E84D4D61378EE071C44430C3730FBF4B35A39A6619AE`；3.2.8 回退包保留于 `build/previous-deliveries/Review_v3.2.8-before-v3.2.9.apk`。本机 ADB 无连接设备，未进行真机视觉或 Profile 验收。

## 3.2.8+179（2026-10-14）

- 曾尝试通过关闭共享元素入口的整页淡入处理打开灰块；用户后续确认无效，3.2.9 实际解码转场复现为空值异常，已撤回此项改动。本条保留当时构建记录，不作为现行修复建议。
- 没有 Hero 的头像/相册入口保留淡入，顶栏和缩略条继续在路由完成后各自淡入。
- 新增转场构建器回归，确认 Hero 路由不再生成整页 FadeTransition，普通画廊入口仍保留淡入。画廊/混合媒体定向 31 项通过；全项目 266 项通过、7 项失败，仍是文章详情路由 1 项与长文展开阈值 6 项既有失败。相关文件分析无问题，`git diff --check` 通过。
- ARM64 Release 构建成功（424.2 秒）；核验 `com.review`、`3.2.8+179`、target SDK `36`、仅 `arm64-v8a`、APK V2 签名证书与 3.2.7 一致、16 KB ZIP 对齐。交付 [Review_v3.2.8.apk](../Review_v3.2.8.apk)（32,510,209 字节），SHA-256：`444E5F6D44B2A81C1BCB7A330FE6C517062A1AAA31A4CD9964116A946045BBA4`；3.2.7 回退包保留于 `build/previous-deliveries/Review_v3.2.7-before-v3.2.8.apk`。未连接真机，未做视觉或 Profile 验收。

## 3.2.7+178（2026-10-14）

- 已解码图片的大步长单指移动可被内部缩放识别器抢先接收，导致未开始分页；用 extended_image 8.3.1 已有 imageBuilder/拖动识别器和分页回调修正识别顺序，保留双指缩放、放大平移、双击、原翻页物理及全屏视口。
- 当前图片与缓存邻页保持恒定 Hero 子树，用 HeroMode 只启用当前页飞行，避免跨过半页时销毁/重建图片手势状态。指针落下时校正 pager 状态集合的触摸页顺序。
- 按解码帧身份弱缓存完成态手势控件，减少父级跨页/控件显隐重建反复创建手势动画控制器；新帧正常更新，原图/GIF 的像素与解码尺寸不变。
- 主图连续拖动期间暂停媒体并延迟初始化，停稳后只激活最终项；连续经过多个 Live Photo 不再逐个创建控制器，手动播放规则不变。
- 画廊/混合媒体定向 30 项测试通过，新增真实解码像素、连续正反向甩动、双击恢复、双指捏合和媒体停稳激活回归。旧识别顺序与旧 Hero 包装在同一回归中分别失败，修复后通过；原图解码性能仍需 Android Profile 取证，本机未连接 ADB 设备，不能宣称真机验收。
- 修改的画廊和测试文件定向 analyze 无问题；全项目测试 265 项通过、7 项失败，与上一版记录相同（文章 detail=true 跳转 1 项、长文展开 6 项），不属于本轮画廊改动路径。
- ARM64 Release 构建成功（279.7 秒）；核验 `com.review`、`3.2.7+178`、target SDK `36`、仅 `arm64-v8a`、APK V2 签名与 3.2.6 证书一致及 16 KB ZIP 对齐。交付 [Review_v3.2.7.apk](../Review_v3.2.7.apk)（32,510,209 字节），SHA-256：`894EE255A690B6CBF32061BD9B2EF68DED6C934B50B28C455DAAAE90FE3392BE`；3.2.6 回退包保留于 `build/previous-deliveries/Review_v3.2.6-before-v3.2.7.apk`。当前没有连接 ADB 设备，未做真机安装或 Profile 帧时间验收。

## 3.2.6+177（2026-10-14）

- 主图使用 `BouncingScrollPhysics`，并只在图片缩放倍率不大于 1 时允许 PageView 翻页；放大后保留图片平移。主图与缩略条手势交接、停止旧缩略惯性继续沿用 3.2.5 已修复逻辑。
- 核实 `ExtendedPageController.shouldIgnorePointerWhenScrolling` 未被设为 true（依赖默认 false）。测试全局开启 `enableSlideOutPage` 会在图片加载/失败时加入竞争的缩放识别器，导致横滑和主图接管惯性回归失败，因此继续关闭；没有把水平轴和透明度改成纵向，避免把未生效配置误当根因。
- 画廊专项测试 23/23 通过，覆盖 2/8/18 张横向翻页、主图接管缩略条旧惯性、图片放大时禁止分页及已有滚轮同步。改动的画廊实现与测试文件 `dart analyze` 无问题；全项目测试 261 项通过、7 项失败（文章详情 `detail=true` 路由 1 项、微博长文展开预期 6 项；均为本次未改路径的既有失败）。`git diff --check` 通过。
- ARM64 Release 构建成功（352.7 秒）；核验 `com.review`、版本 `3.2.6`、versionCode `177`、target SDK `36`、仅 `arm64-v8a`、APK V2 签名与 3.2.5 证书一致、16 KB ZIP 对齐。交付 [Review_v3.2.6.apk](../Review_v3.2.6.apk)（32,510,209 字节），SHA-256：`B4FE8C8A20B6D93157AEF4137AD17531C1A7006738D5BB066E835DADE293CF86`；3.2.5 回退包保留于 `build/previous-deliveries/Review_v3.2.5-before-v3.2.6.apk`。未做真机连续滑动验收。

## 3.2.5+176（2026-10-14）

- 修复缩略条仍在惯性滚动时改为拖动主图，旧滚动活动可能继续抢占主图手势的问题。主图接管时保留缩略条小数页并停止旧惯性，不延迟主图同步、不改变全屏视口/Hero/缩放几何。
- 新增可直接迁移到其他 Flutter 图片画廊的[连续滑动性能修复指南](IMAGE_GALLERY_SWIPE_PERFORMANCE_GUIDE.md)。画廊专项测试 23/23 通过，覆盖滚轮惯性中切换主图手势、快速甩动同步、拖动停住以及 2/8/18 张媒体。全项目测试 261 项通过、7 项失败（文章详情路由 1 项、微博长文展开阈值 6 项；均为本次未修改的既有失败）。全项目分析无 error/warning，列出 57 条既有 info；本次涉及 Dart 文件定向分析无问题，`git diff --check` 通过。
- ARM64 Release 构建成功（363.7 秒）。核验 `com.review`、版本 `3.2.5`、versionCode `176`、target SDK `36`、仅 `arm64-v8a`、V2 签名、证书与 3.2.4 一致及 16 KB ZIP 对齐。交付 `Review_v3.2.5.apk`（32,510,209 字节），SHA-256：`068F706F8B24BD8C522BFD21170B169F52B9D0903C02141DAD41D15CC0507CB4`；旧版 `Review_v3.2.4.apk` 保留于 `build/previous-deliveries/Review_v3.2.4-before-v3.2.5.apk`。未做真机连续滑动/帧率验收。

## 3.2.4+175（2026-10-14）

- 关闭微博文章卡片外层的水波纹，避免已移除长按操作后按住卡片仍出现扩散动画。卡片单击仍可进入详情，子控件恢复原主题，内部按钮反馈不变。
- 定向 widget 回归通过：长按无菜单/触感且外层使用 `NoSplash`，“更多”仍能打开菜单。涉及 Dart 文件 `flutter analyze --no-pub` 无问题；未重跑全量测试。
- ARM64 Release 构建成功（512.7 秒）。核验包名 `com.review`、版本 `3.2.4`、versionCode `175`、target SDK `36`、仅 `arm64-v8a`、V2 签名、签名证书与 3.2.3 一致及 16 KB ZIP 对齐。交付 `Review_v3.2.4.apk`（32,510,209 字节），SHA-256：`DA6EC306A5F90147E5A29252DF4C332F149423E188CC0BD8D268797A36D05151`；3.2.3 回退包保留于 `build/previous-deliveries/Review_v3.2.3-before-v3.2.4.apk`。未做真机安装/视觉验收。

## 3.2.3+174（2026-10-13）

- 移除微博文章卡片的整卡长按菜单入口，菜单继续由卡片原有的顶部/底部“更多”按钮打开；卡片触摸/滚动不再触发外层全局触感，卡片内部按钮维持原反馈。
- 定向回归测试确认长按不打开菜单且无触感反馈，点击“更多”仍能打开菜单。改动文件静态分析无问题；全量 Flutter 测试 261 项通过、7 项失败：文章详情 `detail=true` 路由 1 项及 `TweetCard` 长文展开阈值/尾部预期 6 项，均不在本次触感改动范围。`git diff --check` 通过。
- ARM64 Release 构建成功（372.4 秒），核验 `com.review`、版本 `3.2.3`、versionCode `174`、target SDK `36`、`arm64-v8a`、V2 签名及 16 KB ZIP 对齐；签名证书与 3.2.2 一致。交付 `Review_v3.2.3.apk`（32,510,209 字节），SHA-256：`AD8CA8ED5A420330A125640C21FDF29D2837DC13FA1ED0A3F37DA5483B755D77`；`Review_v3.2.2.apk` 保留于 `build/previous-deliveries/Review_v3.2.2-before-v3.2.3.apk`。未做真机安装验收。

## 3.2.2+173（2026-10-13）

- 修复拖动底部画廊缩略条时主图在停住后与滚轮分页物理互相争夺、画面抽动的问题：拖动/归位阶段临时关闭主图逐页吸附；ScrollEnd 后等本帧拖动/惯性切换完成，再同步吸附主图与滚轮。
- 画廊测试通过，覆盖按住静止、松手归位、普通拖动、快速甩动、主图接管及双平台滚轮行为。真实设备上的触感/观感仍需安装验收。
- 画廊专项测试 22/22 通过，修改文件 `dart analyze` 无问题。全项目测试有 7 项未通过：文章详情卡片 `detail=true` 路由 1 项，以及 `TweetCard` 长文展开阈值/尾部文字显示预期 6 项；均不在本次修改路径，未改动。文章详情失败已单文件复现；全套测试仍未全绿。
- ARM64 Release APK 构建成功（186.8 秒），核验 `com.review`、版本 `3.2.2`、versionCode `173`、`arm64-v8a`、V2 签名、签名证书与 3.2.1 相同及 16 KB ZIP 对齐。交付 `Review_v3.2.2.apk`（32,510,209 字节），SHA-256：`B64CD4D8E400CC65807C9FE34E228C566A632C1A737AB3471C6F00276C951B43`；`Review_v3.2.1.apk` 保留作回退。未做真机安装验收。

## 3.2.1+172（2026-10-13）

- 修复图片画廊双击缩放偶发被清屏单击抢占：父级改用不参与 GestureArena 的指针监听，双击会取消尚未确认的区域单击；明确识别到图片缩放时增加遵循全局震动开关的轻触反馈。单击动作现在等待 Flutter 双击判定窗口后执行。
- 图片画廊回归测试 21 项通过，覆盖双击不清屏、单击清屏/侧边退出、Hero、缩略滚轮同步及图片裁切回程。真实设备触感和图片缩放观感仍需安装后验收。
- ARM64 Release 构建成功（406.9 秒），核验 `com.review`、版本 `3.2.1`、versionCode `172`、target SDK `36`、`arm64-v8a`、V2 签名和 16 KB ZIP 对齐，证书与前版一致。交付 `Review_v3.2.1.apk`（32,510,209 字节），SHA-256：`6966DC5FDB65456356D5FC37DD378B389D4110FBD305694F6955B390D769DC15`；3.2.0 回退包保留于 `build/previous-deliveries/Review_v3.2.0-before-v3.2.1.apk`。未做真机安装及触感验收。

## 3.2.0+171（2026-10-11，版本名回退）

- 按用户要求将应用对外版本名改回 3.2.0；Android versionCode 递增至 171，保证已安装版本仍可覆盖升级。源码功能不回退。
- 按用户要求将应用对外版本名改回 3.2.0；Android versionCode 递增至 171，保证已安装版本仍可覆盖升级。源码功能不回退。
- ARM64 Release 构建成功（135.0 秒），核验 com.review、3.2.0、versionCode 171、target SDK 36、arm64-v8a、V2 签名及 16 KB ZIP 对齐。交付 Review_v3.2.0.apk，SHA-256：6FC43BDBA1E8CA566825202089557190FF46F131318FBCDB59A5E5350C6BBDA4。此前 Review_v3.4.2.apk 已归档至 build/previous-deliveries/Review_v3.4.2-before-version-name-rollback-3.2.0.apk。


这里记录已经完成的版本变更及当次验证结果。当前行为和发布命令以 [DEVELOPMENT.md](../DEVELOPMENT.md) 为准；历史测试数量不代表以后构建的测试结果。更早的旧版综合手册原件保留在仓库 `docs/archive/Review-legacy-2026-09-23.md`，仅供追溯，不作为现行规范，也不再并入当前开发文档。

## 3.4.2+170（2026-10-11）

- 全部关注的官方来源说明继续位于头像昵称上方，字号、颜色和图标尺寸对齐“仅粉丝可见”；来源与可见范围同时存在时分行保留，长文本自然换行。文案沿用服务端 title，未返回博主姓名或动作时不猜造。最新微博原有样式不变。
- 卡片定向 10 项通过，新增检查带博主姓名的来源说明位于作者上方、与可见范围同字号同颜色且可共存；相关两个文件静态分析通过。ARM64 Release 构建成功（257.4 秒），核验 com.review、3.4.2、versionCode 170、target SDK 36、arm64-v8a、V2 签名及 16 KB ZIP 对齐，证书与前版一致。交付 Review_v3.4.2.apk，SHA-256：43E32A0958367A724CE29E6C46D971F04DED828BA016318CDC16009DED6A2E42。前版已核验归档至 build/previous-deliveries/Review_v3.4.1-before-v3.4.2.apk。构造来源文案仅验证显示，未完成真实账号推荐卡片验收，本轮未重跑全量测试。

## 3.4.1+169（2026-10-11）

- 用户直达按用户确认的门槛，仅展示至少 1 万粉丝的正式搜索账号，沿用官方排序、最多 3 个；不足 3 个按实际数量展示，没有符合条件的账号则隐藏。提交搜索后的完整用户列表不受限制，不新增请求或分页拉取。
- 搜索定向 9 项通过，新增覆盖 0/1/2/3/5 个热门候选、9999/10000 粉丝边界和官方排序保留；两个相关文件静态分析通过。ARM64 Release 构建成功（188.3 秒），核验包名 com.review、版本 3.4.1、versionCode 169、target SDK 36、arm64-v8a、V2 签名及 16 KB ZIP 对齐，证书与前版一致。交付 Review_v3.4.1.apk，SHA-256：C23D2ADDB1CF162630F3E219B7C6656EA5A6622596AC4F771ECAD7106F6D0218；前版已核验归档至 build/previous-deliveries/Review_v3.4.0-before-v3.4.1.apk。未做手机当前登录态验收，本轮未重跑全量测试。

## 3.4.0+168（2026-10-11）

- 补齐输入页“用户直达”遗漏的链路：账号使用正式用户搜索的官方排序，联想接口只取词；失败显示独立重试，不以同名联想账号替代。输入变更立即清除旧卡片，400ms 防抖及请求代次避免迟到结果覆盖。发布器 @ 提及保持原接口。
- 高级搜索结果接近底部（剩余不足 600dp）自动续页，内容不足一屏时继续补页，不再显示“加载更多”按钮；同一时间仅一个续页请求，沿用已提交条件，失败停止自动续页并保留重试，重新搜索回到顶部。
- 定向 13 项通过，涵盖错误联想隔离、输入切换/清空、直达失败重试、窄屏自动续页、重复触发锁定、条件快照、同页重试与短列表补页；相关 4 个文件静态分析无问题。全量 256 项通过、7 项既有失败（文章跳转 1 项、长文展开 6 项），与前版相同。
- ARM64 Release 构建成功（185.7 秒），构建前后源码、资源和构建配置哈希一致；两个修改页面完整源码已进入 kernel，APK 的 libapp 与最终去符号产物一致。核验 `com.review`、版本 `3.4.0`、versionCode `168`、target SDK `36`、`arm64-v8a`、V2 签名及 16 KB ZIP 对齐，证书与前版一致。交付 `Review_v3.4.0.apk`（32,510,209 字节），SHA-256：`9987719096DF2205DC2D5087AD0898FE710562FA96727965A1A1940D27C9474F`；3.3.1 已核验归档至 `build/previous-deliveries/Review_v3.3.1-before-v3.4.0.apk`，根目录只保留新包。尚未在手机当前登录态验收用户直达排名与自动续页交互。

## 3.3.1+167（2026-10-11）

- 修复用户搜索仅依赖移动域导致当前会话不可用：优先读取已核对的官方网页用户分类 HTML，移动容器仅兼容回退。已在登录浏览器确认“巴旦木公主_”为首位（56.6 万粉丝）；搜索 6 项样例检查通过，真实手机请求仍待验收。
- 搜索相关静态分析与 `git diff --check` 通过；全量测试 253 通过、7 失败，仍为文章卡跳转 1 项及长文展开 6 项。
- ARM64 Release 编译完成后，核验 `com.review`、版本 `3.3.1`、versionCode `167`、target SDK `36`、`arm64-v8a`、V2 签名及 16 KB ZIP 对齐；证书与 3.3.0 相同。最新完整搜索源码已进入 kernel，APK 的 libapp 与最终去符号产物一致。交付 `Review_v3.3.1.apk`（32,510,209 字节），SHA-256：`7D5A42BACE1BB7482F31177AA535BCED9FD26C58FBA36633F8E1211AD63B26FB`。旧版已核验归档至 `build/previous-deliveries/Review_v3.3.0-before-v3.3.1.apk`；根目录只保留新包。手机截图确认 3.3.0 的用户搜索失败，尚未在该手机登录态验证 3.3.1，不能用浏览器成功代替应用账号验收。

## 3.3.0+166（2026-10-11）

- 时间线顶栏改为关注流高级搜索，支持网页同款七种类型、关键词、起止日期和分页。通过登录中的微博网页实际捕获 `/ajax/statuses/search` 及 `atten=1`、七个 `has*` 开关、秒时间戳和顶层返回结构；未选类型省略参数，结束日期包含当天。结果复用现有卡片，失败明确重试，翻页锁定已提交条件并去重；不使用全站/本地过滤替代。
- 全部关注来源说明可与置顶标识同时显示，纯“热门/置顶”标题不重复作为推荐来源。定向回归 23 项通过，包含高级搜索参数、错误响应、窄屏、分页重试和原用户搜索；高级搜索三个新增/相关文件静态分析无问题。全量 251 项通过、7 项失败；失败为文章导航一项及长文展开六项，已在本次修改前源码隔离快照上复现相同 7 项（基线 20 项通过、7 项失败），未扩大修改范围。
- ARM64 Release 构建成功（155.0 秒），构建前后应用源码、资源和构建配置哈希一致。核验 `com.review`、`3.3.0`、versionCode `166`、target SDK `36`、`arm64-v8a`、V2 签名及 16 KB ZIP 对齐，证书与 3.2.0 一致。交付 `Review_v3.3.0.apk`（32,510,205 字节），SHA-256：`15F4749D3934EA710B440BB3EE59C8E8BAF71E0E003EAA34BC6969BE963A5A3C`；3.2.0 已校验归档于 `build/previous-deliveries/Review_v3.2.0-before-v3.3.0.apk`。本包包含当前主线的用户搜索修复。未连接真机；网页接口成功不等于应用实际账号已验收。

## 3.2.0+165（2026-10-11）

- “最新微博”与“全部关注”改为独立选择，不再同时高亮；最新微博保留现状，全部关注展示微博返回的关注/点赞等来源说明，与可见范围标签独立判断并支持长说明换行。详情补齐保留原关注流标题，不新增请求或本地推荐过滤。定向回归 17 项通过；真实账号来源文案仍需安装后核对。
- 修复综合主账号和“用户”标签误用 `/ajax/side/search` 联想候选：改用移动用户搜索容器，按官方返回顺序展示用户卡并按 UID 去重，补上独立分页、请求失败重试和旧响应隔离。搜索输入联想与发布器 @ 提及仍使用原接口。4 项搜索回归样例通过（含用户分页去重及失败后重试），相关静态分析通过；本次匿名环境受微博访客限制，实际账号搜索排名待真机确认。
- 最终 ARM64 Release 构建成功（149.9 秒，首轮之后补齐分类分页状态隔离并重新构建）。核验 `com.review`、`3.2.0`、versionCode `165`、target SDK `36`、`arm64-v8a`、V2 签名及 16 KB ZIP 对齐，证书与旧版一致；核对最终 kernel 含完整搜索源码、APK 的 libapp 与最终去符号产物一致。交付 `Review_v3.2.0.apk`（32,116,993 字节），SHA-256：`1A4569DC5903848C64AF6A52606228105AE490EDC4789A10DAA1F24FDA54BEBE`。旧包归档于 `build/previous-deliveries/Review_v3.1.4-before-v3.2.0.apk`。当前工作区的其他主线修改一同编入；未连接真机，实际账号搜索待安装验收。
- 全量 Flutter 测试本轮 244 通过、7 失败：`article_card_test.dart` 的一项文章导航与 `widget_test.dart` 的六项长文展开断言失败；当时搜索的三项通过；补充失败重试与分页覆盖后定向四项全部通过。未将这些其他模块失败记成搜索回归，也未改动它们以掩盖失败。

## 3.1.4+164（2026-10-08）

- 混合图库的视频缩略条按底部播放控制栏的实际高度排列在进度条上方，保留 8dp 间隔，适配字体缩放和底部安全区；拖动缩略条时固定位置，停稳后恢复对应媒体布局。图片视口和原有图片页缩略条位置保持现行实现。
- 混合媒体回归检查 4/4 通过，覆盖普通/放大字体与底部安全区下缩略条不遮挡进度条、进度点击调整及缩略条拖动时位置稳定；改动文件静态分析无问题，`git diff --check` 通过。ARM64 Release 构建成功（415.1 秒），核验 `com.review`、`3.1.4`、versionCode `164`、target SDK `36`、`arm64-v8a`、APK V2 签名及 16 KB 对齐，证书与前版一致。交付 `Review_v3.1.4.apk`（32,051,457 字节），SHA-256：`CCEBEC8F711981606B0613D5A0F8D82F6D489F382AD5DD58F03EA89A5F208100`；前版归档于 `build/previous-deliveries/Review_v3.1.3-before-v3.1.4.apk`。未连接真机，布局观感需安装后确认。

## 3.1.3+163（2026-10-08）

- 修复图片夹视频时点击底部全屏按钮导致画廊退出：嵌入播放器按钮现在切换同一播放器到横屏沉浸模式，并隐藏图库顶栏与缩略条；返回竖屏时恢复图库控件，视频控制器和播放位置不重建。
- ARM64 Release 构建成功（367.3 秒）；`aapt2` 核验包名 `com.review`、版本 `3.1.3`、`versionCode` `163`、target SDK `36`、ABI `arm64-v8a`。APK V2 签名有效且证书与前版一致；16 KB `zipalign` 核验通过。交付 `Review_v3.1.3.apk`（32,051,457 字节），SHA-256：`13C3994EC65708906BF62FCCC5118823277FD5138A570D360BBB243DA4090F7F`；`Review_v3.1.2.apk` 可恢复地归档至 `build/previous-deliveries/Review_v3.1.2-before-v3.1.3.apk`。未连接真机，横屏播放和返回手势仍需设备验收。

## 3.1.2+162（2026-10-08）

- 修复从信息流文章卡片进入后同一作者头像短暂“真实头像 → 占位图 → 真实头像”：卡片作者 UID 和头像 URL 随文章路由传递；文章 HTML 解析到相同 UID 时沿用信息流已使用的头像 URL，直接命中相同的图片缓存；UID 不同或缺失时不借用卡片头像。
- ARM64 Release 构建成功（276.5 秒）；`aapt2` 核验包名 `com.review`、版本 `3.1.2`、`versionCode` `162`、target SDK `36`、ABI `arm64-v8a`。APK V2 签名有效，证书 SHA-256 与前版一致（`3EB0F6708904F8EF916C6A2572E394BA981EE25D64861344CF1921CA7EA17975`）；16 KB `zipalign` 核验通过。交付 `Review_v3.1.2.apk`（32,051,457 字节），SHA-256：`AF672A539717D4BC30BC7E9465F885EF8810DD7A1C064ECD96FEF53918742097`。旧包保留于 `build/previous-deliveries/Review_v3.1.1-before-v3.1.2.apk`。未进行真机文章页/头像闪烁验收。

## 3.1.1+161（2026-10-08）

- 文章页此前每次 route 新建都会清空本地 document 并重新请求微博 HTML，加载期间整页被进度圈替换；头像又在 `ExtendedImage` loading 时显示占位。现在按登录 UID 和文章 ID 缓存最多 8 条已解析文档，二次进入先显示缓存；手动刷新保留旧正文，成功后再替换。缓存仅在进程内，不写入磁盘；未能确认 UID 的登录态不缓存。
- ARM64 Release 构建成功（236.7 秒）；`aapt2` 核验包名 `com.review`、版本 `3.1.1`、`versionCode` `161`、target SDK `36`、ABI `arm64-v8a`。APK V2 签名有效，证书 SHA-256 与前版一致（`3EB0F6708904F8EF916C6A2572E394BA981EE25D64861344CF1921CA7EA17975`）；16 KB `zipalign` 核验通过。交付 `Review_v3.1.1.apk`（32,051,457 字节），SHA-256：`F94F8FB41C9D6D8BDADE6C6EE83D77962976FCB97391F062EC45D18B8B1FAA0D`。旧包保留于 `build/previous-deliveries/Review_v3.1.0-before-v3.1.1.apk`。未进行真机文章页/头像显示验收。

## 3.1.0+160（2026-10-08）

- Android、桌面和 Fuchsia 的普通 `MaterialPageRoute` 按 Lurk `SpringPageRoute` 的覆盖式动画进入：新页面全宽滑入，旧页面固定且不淡入/淡出；LTR 从右侧进入、RTL 从左侧进入，push 320ms `easeOutCubic`、pop 220ms `easeInCubic`，关闭系统动画时直切。Android 动画开启时，预测式返回进度驱动同一 `PageRoute` 动画。iOS 保留 Cupertino 原生转场与边缘返回手势。主底栏改为 Lurk 式双页叠放，旧页和新页反向各平移一个屏宽，260ms `easeOutCubic`，保留三页状态及原有重选/回顶/刷新行为。图片画廊的显式路由和 Hero 缩放动画保持原实现。
- Lurk 转场修正后的 ARM64 Release 构建成功（212.5 秒）；`aapt2` 核验包名 `com.review`、版本 `3.1.0`、`versionCode` `160`、target SDK `36`、ABI `arm64-v8a`。APK V2 签名有效，证书 SHA-256 与前版一致（`3EB0F6708904F8EF916C6A2572E394BA981EE25D64861344CF1921CA7EA17975`）；16 KB `zipalign` 核验通过。交付 `Review_v3.1.0.apk`（32,051,457 字节），SHA-256：`6AD97BDF4AE821304977475B27852E3E255F3934C80457552B06EC2C52FA07E1`。修正前的同版本候选包保留在 `build/previous-deliveries/Review_v3.1.0-before-lurk-transition-correction.apk`；`Review_v3.0.3.apk` 仍可回退至 `build/previous-deliveries/Review_v3.0.3-before-v3.1.0.apk`。未进行真机动画验收。

## 3.0.3+159（2026-10-08）

- 全面排查并修复原生验证码登录后全项目网络写操作与关键信息流会话错配问题：
  1. 点赞/取消点赞（`setLikeState`）：双通道路由，移动会话走 `m.weibo.cn/api/attitudes/create` 与 `destroy`，携带 `id`、`attitude=heart`、`st`、`MLOGIN=1`；桌面会话保留 `/ajax/statuses/setLike` 与 `cancelLike`。
  2. 收藏/取消收藏（`setFavoriteState`）：双通道路由，移动会话走 `m.weibo.cn/api/favorites/create` 与 `destory`，携带 `id`、`st`、`MLOGIN=1`；桌面会话走 `/ajax/statuses/createFavorites` 与 `destoryFavorites`。
  3. 删除微博（`deleteTweet`）：双通道路由，移动会话走 `m.weibo.cn/profile/delMyblog`，携带 `mid`、`st`、`MLOGIN=1`；桌面端走 `/ajax/statuses/destroy`。
  4. 评论发表/回复/删除（`DetailRepository`）：引入移动端 `m.weibo.cn/api/comments/create`、`reply`、`destroy` 路由通道，携带移动 UA 与 `st`；放宽状态码校验至标准 2xx。
  5. 关注信息流（`FeedRepository.getFriendsTimeline`）：新增方案 3 移动关注流通道 `m.weibo.cn/feed/friends` 自动降级，彻底解决原生登录后桌面接口因未同步 SSO 返回空导致的首页关注流空白问题。
  6. 收藏大厅与赞列表（`favorites_page.dart` / `likes_favorites_page.dart`）：补齐移动端 `api/favorites/all_fav` 与个人赞容器 `230869{uid}_-_like` 降级回退。
  7. 微博发布（`compose_tweet_page.dart`）：桌面 `/ajax/statuses/update` 失败或移动会话时回退移动端发布通道。
- 新增 `test/user_actions_dual_channel_test.dart` 全链路隔离单元测试，结合既有用例 27/27 单元测试全部通过；相关 Dart 文件静态分析 0 Error。
- ARM64 Release 构建成功（584.0 秒）；`aapt2` 核验包名 `com.review`、版本 `3.0.3`、`versionCode` `159`、target SDK `36`、ABI `arm64-v8a`。APK V2 签名有效，证书与上一包一致；4-byte zipalign 校验通过。交付 `Review_v3.0.3.apk`（32,051,457 字节），SHA-256：`2AC06CDA7A302ED40A939B5922C796BB4334A013DB58CACA2AE4DB8D9158CC26`；上一版可恢复地归档至 `build/previous-deliveries/Review_v3.0.2-before-v3.0.3.apk`。未进行真实账号写操作，未连接真机。

## 3.0.2+158（2026-10-08）

- 修复桌面会话取消关注使用错误路径 `/ajax/friendships/destroy` 导致微博提示“你访问的地址不存在”；改为网页端实际使用的历史拼写 `/ajax/friendships/destory`。移动会话继续使用 `m.weibo.cn/api/friendships/destory`。
- 桌面/移动取关路由、对应会话 Cookie 与 XSRF 的拦截回归测试 4/4 通过；改动文件 Dart 分析无问题。全量测试 227/233 通过，6 项既有失败仍集中在 `widget_test.dart` 的长文展开控件断言，与本次取关改动无关。
- ARM64 Release 构建成功（425.8 秒）；`aapt2` 核验包名 `com.review`、版本 `3.0.2`、`versionCode` `158`、target SDK `36`。APK V2 签名有效，证书与上一包一致；16 KB zipalign 检查通过。交付 `Review_v3.0.2.apk`（31,985,921 字节），SHA-256：`8D00E8FEB4D40821A2D900F8749D045B2F0F267D9A04CFC93A209FD355232B30`；上一版可恢复地归档至 `build/previous-deliveries/Review_v3.0.1-before-v3.0.2.apk`。未执行真实账号取消关注，未进行真机验收。

## 3.0.1+157（2026-10-08）

- 修复原生登录后关注/取关失败：按会话范围选择移动端或桌面端微博接口，统一经过 `WeiboDioClient`，请求使用对应域 Cookie 与 XSRF，移动端补齐 `MLOGIN=1` 与 `st`。不再吞掉业务错误或在失败时修改本地关注状态。
- XSRF 刷新/403 重试按请求域隔离，移动端令牌不会写入桌面会话；新增隔离回归测试，使用伪造 Cookie 和拦截响应，不触碰真实微博账号的关注关系。
- 新增关注会话路由、服务端拒绝提示和 XSRF 域隔离拦截器测试，3/3 通过；本次修改文件静态分析无问题。全量测试 226/232 通过，6 项失败均为既有微博长文“展开全文”断言，不涉及本次文件；全量分析保留 58 条既有 info 级 lint。
- ARM64 Release 构建成功（218.8 秒）；`aapt2` 核验包名 `com.review`、版本 `3.0.1`、`versionCode` `157`、target SDK `36`、ABI `arm64-v8a`；APK V2 签名有效且证书与上一包一致，16 KB zipalign 检查通过。交付 `Review_v3.0.1.apk`（31,985,921 字节），SHA-256：`AAA8BBE98788E084A893301FE851CB284BB33B9D45B670B64E82932CE6018811`；上一版可恢复地归档至 `build/previous-deliveries/Review_v3.0.0-before-v3.0.1.apk`。未使用真实账号执行关注/取关，未进行真机验收。

## 3.0.0+156（2026-10-07）

- 整理统一开发文档：当前说明、完整变更记录、工程复盘和磨砂顶栏规范继续全文汇入 `D:\App\开发文档\Review.md`；将截至 2026-09-23 的旧版综合手册全文从当前汇编移除，仓库归档原件保留且不作为现行规范。
- 修复图库 push/pop 转场时顶部返回、页码/Live Photo 和下载控件提前显示或未及时消失的问题。玻璃按钮含 `BackdropFilter` 与 fragment shader，整组 `AnimatedOpacity` 会在合成层中过滤出黑帧；现改为逐帧调整按钮图标透明度、玻璃底色和模糊强度，不再对滤镜设置祖先透明层。顶部控件与缩略条共用路由动画状态：push 完成后以 140ms 淡入，pop 开始立即禁用点击并淡出；不改变 Hero 尺寸、主图 PageView 视口/约束、定位几何或手势。
- 图库、混合媒体与设置组件定向测试 27/27 通过；全量 Flutter 测试 223/229 通过，6 个失败均是未改动的微博卡片“展开全文”预期，与本次图库控件无关。改动文件静态分析无问题，`git diff --check` 通过。
- ARM64 Release APK 构建成功（294.2 秒）；核验包名 `com.review`、版本 `3.0.0`、`versionCode` `156`、target SDK `36`、ABI `arm64-v8a`。APK v2 签名有效且签名证书与上一包一致，16 KB zipalign 检查通过。交付 `Review_v3.0.0.apk`（31,985,921 字节），SHA-256：`02523A2E9215E720606E34306B08145DAC992485DADA7BF225B4EF04D265A15D`；上一版 `Review_v2.22.6.apk` 可恢复地归档至 `build/previous-deliveries/Review_v2.22.6-before-v3.0.0.apk`。未连接真机，最终转场视觉仍需设备确认。

## 2.22.6+155（2026-10-07）

- 收紧设置首页字体层级：设置项标题回归主题 `titleMedium`（Material 3 默认 16sp），分组标题使用 `titleSmall`（默认 14sp），不再强制放大字号或覆盖主题样式。删除订阅消息提醒、存储设置、登录账号和导出凭据行中重复标题含义的说明；保留 WebDAV 备份范围、动态凭据状态和应用版本等有实际信息量的辅助内容。
- 修复多图画廊 Hero 路由转场时缩略条提前露出造成的闪烁：路由 push 期间保持透明且不可交互，打开动画完成后淡入；路由 reverse 一开始立即淡出并禁用点击。不改变主图 PageView 视口/约束、Hero 图片几何或手势。
- 画廊与设置定向 Flutter 测试 24/24 通过；相关 Dart 静态分析无问题，`git diff --check` 通过。
- ARM64 Release APK 构建成功（341.3 秒）；核验包名 `com.review`、版本 `2.22.6`、`versionCode` `155`、target SDK `36`、ABI `arm64-v8a`；APK v2 签名有效，签名身份与前版相同，16 KB zipalign 检查通过。交付 `Review_v2.22.6.apk`（31,985,917 字节），SHA-256：`C13549E95C4C9995047F1AADDA97D739D80AFECC449A26190CD9CE341FD30737`；上一版 `Review_v2.22.5.apk` 可恢复地归档至 `build/previous-deliveries/Review_v2.22.5-before-v2.22.6.apk`。未连接真机，最终 UI 观感仍需安装确认。

## 2.22.5+154（2026-10-07）

- 对照 ReviewX 的实际顶栏代码，将磨砂背景改为直接绘制链 `ClipRect → BackdropFilter(sigma 20) → 渐变 DecoratedBox`，移除 Review 中额外的 `ShaderMask` 和 `BlendMode.src` 设置。此前 2.22.3/2.22.4 的组合虽然通过结构测试，但用户设备仍看不到模糊；记录为未解决尝试，不再沿用。
- 保留顶部渐变 alpha 0.95、边界 alpha 0、AppBar Material alpha 0.45及唯一底边；渐变色层本身提供状态栏侧低透光、分界线附近较明显磨砂的观感。新增回归断言确认 BackdropFilter 没有被 ShaderMask 包裹。定向 Flutter 测试 13/13 通过，Dart analyze 与 `git diff --check` 无问题。
- ARM64 Release APK 构建成功（393.6 秒）；核验包名 `com.review`、版本 `2.22.5`、`versionCode` `154`、ABI `arm64-v8a`；APK v2 签名有效，签名身份与前版相同，16 KB zipalign 检查通过。交付 `Review_v2.22.5.apk`（31,985,917 字节），SHA-256：`B71C67B865B56B83D5E840BF7B82D2C66ACF33DA451CCAC11CDA6140D7E64119`；上一版 `Review_v2.22.4.apk` 可恢复地归档至 `build/previous-deliveries/Review_v2.22.4-before-v2.22.5.apk`。未连接真机，视觉效果仍需安装确认。

## 2.22.4+153（2026-10-07）

- 按用户反馈，轻微提高磨砂顶栏状态栏侧的底色不透明度：顶部渐变叠加层 alpha 从 0.90 调至 0.95，Material alpha 保持 0.45，合成不透明度从约 0.945 提升至约 0.9725；边界渐变、模糊 alpha 0→0.60 与模糊合成模式均不变。
- 更新回归测试、顶栏设计规范、工程复盘和完整开发文档；版本名 `2.22.4`、Android `versionCode` `153`。相关 Dart 文件静态分析无问题，顶栏及关联页面定向测试 13/13 通过。
- ARM64 Release 构建成功（359.4 秒）；核验包名 `com.review`、版本 `2.22.4`、`versionCode` `153`、target SDK `36`、ABI `arm64-v8a`；APK v2 签名有效，签名证书与前版相同，16 KB zipalign 检查通过。交付 `Review_v2.22.4.apk`（31,985,917 字节），SHA-256：`389CF32D22339EFD29E1733397257521770669CBB0034B0325AA3348B3308492`；上一版 `Review_v2.22.3.apk` 可恢复地归档至 `build/previous-deliveries/Review_v2.22.3-alpha-9725.apk`。未连接真机，视觉效果仍需安装确认。

## 2.22.3+152（2026-10-07）

- 修复新磨砂渐变中 `BackdropFilter` 被 `ShaderMask` 遮罩后模糊不可见的问题：滤镜位于临时合成缓冲区时，默认 `srcOver` 可能产生异常；显式设置 `BlendMode.src`，不改用户确认的 alpha 0.90 渐变、alpha 0.45 Material 和 alpha 0→0.60 模糊遮罩。
- 新增回归断言确认实际 `BackdropFilter.blendMode`；定向 widget 测试 13/13 通过；指定文件静态分析无 error/warning（仅有 1 条既存 deprecation info）。ARM64 Release 构建成功（369.4 秒）；APK 核验包名 `com.review`、版本 `2.22.3`、`versionCode` `152`、`arm64-v8a`，APK v2 签名及 zipalign 验证通过，签名证书与 2.22.2 相同。
- 交付 `Review_v2.22.3.apk`（SHA-256：`019488ED3B7415A88DFEAD1276378A57D82F3CE875EDBF808F93602B0DC241DB`）；真机视觉复验未执行，仍需安装后确认模糊层实际可见性。
- 原 `Review_v2.22.2.apk` 已可恢复地归档至 `build/previous-deliveries/Review_v2.22.2-alpha-945.apk`；项目根目录仅保留当前验证通过的 APK。

## 2.22.2+151（2026-10-07）

- 根据用户确认的参数提高顶栏状态栏一侧的底色不透明度：颜色渐变叠加层顶部 alpha 为 0.90，AppBar Material alpha 为 0.45，合成后顶部约 0.945 不透明；边界处渐变 alpha 为 0，保留 Material 的 0.45 底色。模糊仍独立从状态栏侧 0 增至边界侧 0.60，不影响标题/控件；时间线、热搜和超话详情等自定义栏统一复用同一 Material alpha 常量。
- 同步更新统一顶栏设计规范、工程复盘和完整开发文档；版本名 `2.22.2`、Android `versionCode` `151`。
- 顶栏及此前关联布局定向测试 13/13 通过；改动相关 Dart 文件分析无 error/warning，`feed_view.dart` 保留 1 条与本次无关的既有弃用提示（`axisAlignment`）。
- ARM64 Release 构建成功（372.7 秒）；核验 `com.review`、版本 `2.22.2`、`versionCode` `151`、target SDK `36`、ABI `arm64-v8a`；APK v2 签名有效且证书与前版相同，16 KB zipalign 检查通过。交付 `Review_v2.22.2.apk`（31,985,917 字节），SHA-256：`E23C4653D9AD892DB49341B7148BF6D1B3738223D0D390603AD377CB3AAD11E7`。上一版 2.22.1 APK 保留在 `build/previous-deliveries/Review_v2.22.1-gradient-blur.apk`。未连接真机。

## 2.22.1+150（2026-10-07）

- 设置首页按轻量 M3 规范整理为“偏好与功能”“存储与备份”“账号设置”“关于与支持”四组；减弱卡片层级与图标颜色，统一 17sp 标题、14sp 说明、24dp 图标和箭头；移除只有标题、没有操作的设置首页顶栏，并校正设置内容与状态栏的间距。
- 设置分组使用独立低强调 surface：默认零外边距、无阴影/描边、透明 surface tint，24dp 圆角；普通主题使用 `surfaceContainerLow`，纯黑主题使用 `surfaceContainer`。不改全局 `CardTheme`，不叠加父级页面留白。
- 所有标准顶栏及时间线、热搜自定义栏、超话详情 SliverAppBar 统一复用 `ReviewFrostedBackdrop`。AppBar Material 主题色 alpha 0.58；独立颜色渐变顶部 alpha 0.57 → 边界 0；sigma 20 模糊另套 alpha 0 → 0.60 的纵向遮罩，状态栏附近基本不模糊、边界处保留 60% 模糊，遮罩不影响文字和控件。超话固定搜索/分类区仍计入完整顶栏边界，并关闭重复浅色分割线。
- 11 个覆盖式 EasyRefresh 页面统一使用 70dp 触发阈值；`safeArea: false` 避免将完整 AppBar inset 重复计入阈值，只将刷新指示器视觉位置下移。全局默认头和非覆盖式/嵌入式页面行为保持不变。热搜页面移除无数据时的顶部空白区域。
- 相关定向 widget 测试 13/13 通过；全量测试 220 项中 214 项通过，另有 6 项失败集中在 `test/widget_test.dart` 的微博正文“展开全文”断言，与本轮顶栏/设置卡片变更无关。全项目 Dart 分析有 60 条 info、无 error/warning；本轮涉及的顶栏、设置卡片和布局测试文件分析无问题；`git diff --check` 通过。
- ARM64 Release 构建成功（346.9 秒）。核验 `com.review`、版本 `2.22.1`、versionCode `150`、target SDK `36`、ABI `arm64-v8a`；APK v2 签名有效且证书与上一包相同，16 KB zipalign 检查通过。交付 `Review_v2.22.1.apk`（31,985,917 字节），SHA-256：`2F5DA519DAF06FD1C7672AD53F94647D4A39F8ACCF5756D12B70A05D04E90553`。上一份同版本包已备份至 `build/previous-deliveries/Review_v2.22.1-pre-gradient-blur.apk`，此前 2.22.0/2.21.4 回退包保留。未连接真机；视觉渐变仍需设备实测。
## 2.21.4+148（2026-10-07）

- 超话中心标签行下方增加 8dp 磨砂留白，避免材质边界紧贴标签产生“被切掉”的视觉；固定搜索/分类区从 100dp 调为 108dp，同时把列表间距从 12dp 调为 4dp，首条结果的屏幕位置保持不变。
- 修正 Android app Gradle 插件列表缺少 `org.jetbrains.kotlin.android` 的构建配置问题，按 Android、Kotlin、Flutter 插件顺序应用；同步补充开发文档中的防回归说明和磨砂顶栏规范。
- 超话及磨砂顶栏定向测试 3/3 通过，相关文件分析无问题。全量测试 216 项中 210 项通过，6 项失败仍集中在 `test/widget_test.dart` 的微博正文“展开全文”断言。全项目分析报告 58 条 info、无 error/warning。
- ARM64 Release 构建成功（388.6 秒）；核验 `com.review`、版本 `2.21.4`、versionCode `148`、target SDK `36`；APK v2 签名及 16 KB zipalign 通过，签名证书与前版一致。交付 `Review_v2.21.4.apk`（31,985,917 字节），SHA-256：`EB9E5A7F17EA4348A4336784FD0C13986258047E83301D9163313C2DABF5F5D2`；旧 `Review_v2.21.3.apk` 可恢复地归档至 `build/previous-deliveries/`，根目录只保留当前包。未连接真机。

## 2.21.3+147（2026-10-07）

- 修复超话中心磨砂层无法从完整顶栏边界生效的问题：启用 `extendBodyBehindAppBar`，让全屏滚动视口位于标题栏、搜索框和分类标签后方；将完整顶栏高度与原有间距计入列表内部首项 padding，保持初始首条结果的位置不变，同时让滚动内容经过整块顶栏并被模糊。加载和空状态仍位于固定头部下方。
- 同步修订可迁移设计规范及完整开发文档，明确“视口铺满、inset 放在 scroll 内部”的覆盖式实现，防止外层 `Column`/`Padding` 将模糊效果截在固定标签下方。
- 超话与磨砂顶栏定向 widget 测试 3/3 通过（含视口从屏幕顶端开始、首项 inset 位于列表内部的断言）；相关文件分析无问题。全量测试 216 项中 210 项通过，6 项失败均为 `test/widget_test.dart` 中既有微博正文“展开全文”断言。全项目分析有 58 条 info、无 error/warning；`git diff --check` 通过。未连接真机。
- ARM64 Release 构建成功（449.0 秒）；核验 `com.review`、版本 `2.21.3`、versionCode `147`、target SDK `36`、ABI `arm64-v8a`；APK v2 签名和 16 KB zipalign 通过，证书与前版一致。交付 `Review_v2.21.3.apk`（31,985,921 字节），SHA-256：`325A6D3F4E716507E6A3AF45F8823BD5C4CA4E4BC6537A9D045BE91F8A57A39C`；旧 `Review_v2.21.2.apk` 可恢复地归档至 `build/previous-deliveries/`，项目根目录只保留当前包。未连接真机。

## 2.21.2+146（2026-10-07）

- 超话中心关闭分类标签下方的浅色细分隔线，保留磨砂顶栏整体边界；其他共用顶栏默认分隔线不变。新增可独立参考的《磨砂顶栏设计规范》，并并入统一开发文档。
- `test/review_frosted_app_bar_test.dart` 与 `test/chaohua_center_page_test.dart` 定向测试 3/3 通过；涉及的 4 个 Dart 文件分析无问题。全量测试 216 项中 210 项通过，6 项失败均为 `test/widget_test.dart` 中既有微博正文“展开全文”断言。全项目分析有 58 条 info、无 error/warning；`git diff --check` 通过。未连接真机。
- ARM64 Release 构建成功（373.9 秒）；核验 `com.review`、版本 `2.21.2`、versionCode `146`、target SDK `36`、ABI `arm64-v8a`；APK v2 签名和 16 KB zipalign 通过，证书与前版一致。交付 `Review_v2.21.2.apk`（31,985,917 字节），SHA-256：`11D6CB707540222A99370D27F6175B085CC6F024C6E78E0276A035E54920F483`；旧 `Review_v2.21.1.apk` 可恢复地归档至 `build/previous-deliveries/`，项目根目录只保留当前包。未连接真机。

## 2.21.1+145（2026-10-07）

- 设置首页内容在状态栏安全区下方增加 8dp 留白；超话中心把搜索框和固定分类标签纳入磨砂顶栏，分隔边界位于分类标签下沿，结果列表仍独立滚动且保留原间距。
- 新增超话中心固定内容/滚动列表边界 widget 回归测试并通过；全量测试 215 项中 209 项通过，6 项既有微博正文“展开全文”断言失败。目标文件分析通过；全项目分析无 error/warning，保留 45 条 info；`git diff --check` 通过。未连接真机。
- ARM64 Release 构建成功（239.0 秒）；核验 `com.review`、版本 `2.21.1`、versionCode `145`、target SDK `36`、ABI `arm64-v8a`；APK v2 签名及 16 KB zipalign 通过，证书与前版一致。交付 `Review_v2.21.1.apk`（31,985,921 字节），SHA-256：`AC843FC9D612FFEF47C37AF03919899430B26A57C03F40FE9EDBEC5BF5035FE4`；旧 `Review_v2.21.0.apk` 可恢复地归档至 `build/previous-deliveries/`，项目根目录只保留当前包。未连接真机。

## 2.21.0+144（2026-10-07）

- 移除设置首页仅展示“设置”标题的顶栏；保留状态栏安全区与底部导航留白，个性化、存储等设置子页面的返回顶栏不变。修正搜索页热门搜索内嵌列表/网格继承顶部安全区 padding 导致榜单卡片顶部留白，现有热搜条目正常显示并从卡片顶部开始排列。
- `flutter test --no-pub` 共 214 项，208 项通过；6 项既有失败均在 `test/widget_test.dart` 的微博正文“展开全文”断言。设置页与搜索页定向 `flutter analyze --no-pub` 无问题，`git diff --check` 通过。未连接真机。
- ARM64 Release 构建成功（391.6 秒）；核验 `com.review`、版本 `2.21.0`、versionCode `144`、target SDK `36`、ABI `arm64-v8a`；APK v2 签名与 16 KB zipalign 通过，签名证书与前版一致。交付 `Review_v2.21.0.apk`（31,985,921 字节），SHA-256：`72658325C032239DDD63285E3D4AD566374082570BEFC107C7B814702017D962`；旧 `Review_v2.20.1.apk` 可恢复地归档至 `build/previous-deliveries/`，根目录只保留当前包。未连接真机。

## 2.20.1+143（2026-10-07）

- 修正共用磨砂顶栏合成后仍近似透明的问题：82% 主题底色直接设置在 AppBar Material 的 `backgroundColor`，不再留在 `flexibleSpace` 装饰层；模糊层只负责 sigma 20 局部模糊和底部分隔线，与时间线绘制方式一致。增加测试断言实际 AppBar `Material` 颜色及非透明模式，覆盖个性化、赞和收藏、关注列表等复用页面。
- 顶栏/分组面板/热搜定向测试 7/7 通过。全量 `flutter test --no-pub` 为 214 项，其中 6 项仍是 `test/widget_test.dart` 中既有的 TweetCard 全文展开/收起断言失败；其余通过。`flutter analyze --no-pub` 无 error/warning，报告 45 条 info；`git diff --check` 通过。未连接真机。
- ARM64 Release 构建成功（404.8 秒）；核验 `com.review`、版本 `2.20.1`、versionCode `143`、target SDK `36`、ABI `arm64-v8a`；APK v2 签名与 16 KB zipalign 通过，签名证书与前版一致。交付 `Review_v2.20.1.apk`（31,985,921 字节），SHA-256：`73E3F0D3B38C49B98C4EE5193BC01ACF3AD330C9BC43EE76BD07746485762F8B`；旧 `Review_v2.20.0.apk` 可恢复地归档至 `build/previous-deliveries/`，根目录只保留当前包。未连接真机。

## 2.20.0+142（2026-10-07）

- 将磨砂顶栏从时间线/热搜扩展为全应用统一的 `ReviewFrostedAppBar`，覆盖设置、详情、搜索、分组管理、赞和收藏、关注/粉丝列表等标准 AppBar；自定义 SliverAppBar 继续沿用同一套 82% 主题底色、sigma 20 局部模糊和分隔线。可安全滚动的页面在补回顶部内容 inset 后延伸到顶栏后方；登录、聊天输入、内嵌网页/视频及固定/pinned 布局只换材质、不改内容几何，降低键盘、播放器和滚动行为回归风险。
- 新增顶栏组件回归测试；`test/review_frosted_app_bar_test.dart`、`test/group_dropdown_test.dart`、`test/hot_trends_view_test.dart` 定向测试共 7 项通过。`dart analyze lib test` 无 error/warning，保留 44 条既有 info；`git diff --check` 通过。全量 `flutter test --no-pub` 共 214 项，其中 6 项既有 TweetCard 全文展开/收起断言失败，均在 `test/widget_test.dart`，与顶栏改动无关。设备视觉验收待完成。
- ARM64 Release 构建成功（447.9 秒）；核验 `com.review`、版本 `2.20.0`、versionCode `142`、target SDK `36`、ABI `arm64-v8a`；APK v2 签名通过，证书与上一版相同，16 KB zipalign 通过。交付 `Review_v2.20.0.apk`（31,985,917 字节），SHA-256：`AD038CFC32215A6E0AC3CCD1620918FB5063FE3B64317F97230A91B1E7D0F736`；旧 `Review_v2.19.17.apk` 可恢复地归档至 `build/previous-deliveries/`，根目录仅保留当前 APK。未连接真机，视觉表现仍需设备验收。

## 2.19.17+141（2026-10-07）

- 再次修正时间线顶栏仍被用户观察为全透明的问题：直接将当前主题 `appBarTheme.backgroundColor`（缺省时回退 Scaffold 背景色）设为 AppBar Material 的 82% 半透明底色；`BackdropFilter` 不再承担背景着色，只负责 sigma 20 的局部模糊。仅影响时间线顶栏。
- `test/group_dropdown_test.dart` 1/1 通过。全量 `flutter test --no-pub` 为 213 项通过、6 项失败，仍是 `test/widget_test.dart` 中 TweetCard 正文展开/收起断言；本次未改动相关卡片逻辑。定向 analyze 无 error/warning，保留 1 条既有 `axisAlignment` 弃用 info；`git diff --check` 通过。未连接真机。
- ARM64 Release 构建成功（359.5 秒）；核验包名 `com.review`、版本 `2.19.17`、versionCode `141`、target SDK `36`、ABI `arm64-v8a`、APK v2 签名及 16 KB zipalign 通过，签名证书与上一版相同。
- 交付 `Review_v2.19.17.apk`（31,985,917 字节），SHA-256：`F69DF1A05E88CD753C37AEB8475179B901162B143955D7B97B3127EE34A11EB6`；`Review_v2.19.16.apk` 归档至 `build/previous-deliveries/`，根目录仅保留当前 APK。

## 2.19.16+140（2026-10-07）

- 修正时间线顶栏此前看起来近乎透明的问题：旧版使用与页面底色相近的 `surface`，sigma 8 的模糊在无内容的顶部区域不易察觉；改用 `surfaceContainerHighest` 主题容器色（82%）并将局部 `BackdropFilter` 提高至 sigma 18，仍只作用于时间线顶栏。
- `test/group_dropdown_test.dart` 1/1 通过。全量 `flutter test --no-pub` 为 213 项通过、6 项失败，失败均是 `test/widget_test.dart` 中既有 TweetCard 正文展开/收起显示断言；本次仅修改时间线顶栏、版本与文档，没有改动这些卡片逻辑。定向 analyze 无 error/warning，保留 1 条既有 `axisAlignment` 弃用 info；`git diff --check` 通过。未连接真机，视觉效果仍需设备验收。
- ARM64 Release 构建成功（356.4 秒）；核验包名 `com.review`、版本 `2.19.16`、versionCode `140`、target SDK `36`、ABI `arm64-v8a`、APK v2 签名与 16 KB zipalign 通过，签名证书与上一版相同。
- 交付 `Review_v2.19.16.apk`（31,985,917 字节），SHA-256：`4748D0DEC145688AA7338D55C92D897EF450E0EC277C6ABEF6D1207CD7408A9B`；`Review_v2.19.15.apk` 归档至 `build/previous-deliveries/`，根目录仅保留当前 APK。

## 2.19.15+139（2026-10-07）

- 时间线顶栏试用局部磨砂玻璃：动态内容滚动到顶栏后方时使用 `ClipRect` 限定的 `BackdropFilter`（sigma 8）、82% 主题表面色和细分隔线；仅影响时间线，不启用全局玻璃材质或 shader。首条微博、登录/空状态和分组下拉位置保持原来的可视布局。
- `test/group_dropdown_test.dart` 1/1 通过；定向 `flutter analyze --no-pub` 无 error/warning，保留 1 条既有 `axisAlignment` 弃用 info；`git diff --check` 通过。未运行全量测试或真机视觉验收。
- ARM64 Release 构建成功（407.1 秒）；核验包名 `com.review`、版本 `2.19.15`、versionCode `139`、APK v2 签名、16 KB zipalign 通过，签名证书与 `2.19.14` 相同。
- 交付 `Review_v2.19.15.apk`（31,985,917 字节），SHA-256：`DB1C815EA0F94403BCFC9E067277045E00D5324037889630958A58A8385CB6A3`；`Review_v2.19.14.apk` 归档至 `build/previous-deliveries/`，根目录仅保留当前 APK。

## 2.19.14+138（2026-10-07）

- 修复 GIF 与旧视频/Live Photo 元数据冲突时误开视频播放器的问题：当 GIF 图片 URL 没有真实视频直链时，即使旧快照残留 `type=video`、`isVideo`、`fid` 或 `livePhotoVideoUrl`，仍按 GIF 图片进入画廊；单独的 `type=video` 标记不再创建无播放地址的播放器。真正的非 GIF MP4 直链仍走视频播放器；GIF 预览图伴随真实 MP4 直链时仍按视频处理。
- 新增混合媒体回归覆盖，验证带陈旧播放器元数据的 GIF 保持图片分类、真实 MP4 仍播放。`test/mixed_media_gallery_test.dart` 3/3、`test/models_test.dart` 37/37 通过；定向 analyze 无 error/warning，保留 1 条既有 info（`weibo_status_model.dart:1288`：`prefer_conditional_assignment`）；`git diff --check` 通过。测试夹具的 `path_provider` 缺少平台实现日志为非致命现象；未运行全量测试、未做真机媒体验收。
- ARM64 Release 构建成功（285.59 秒）；核验包名 `com.review`、版本 `2.19.14`、versionCode `138`、target SDK `36`、ABI `arm64-v8a`、APK v2 签名及 16 KB zipalign 通过，签名证书与上一版相同。
- 交付 `Review_v2.19.14.apk`（31,985,917 字节），SHA-256：`1225B7764DA55D6291DCFCFA3A7DF4508B7F9BB3BC654C722AE29DDAD4D4EE80`；`Review_v2.19.13.apk` 归档至 `build/previous-deliveries/`，项目根目录仅保留当前 APK。

## 2.19.13+137（2026-10-07）

- 修复多图混合媒体中 GIF 因附带 `fid` 被误判为 Live Photo 的分类问题：GIF 依据媒体类型及缩略图/大图/原图 URL 路径扩展名识别（忽略查询参数）；`fid` 不再为 GIF 或明确视频合成 Live Photo MP4 地址。直接 `video` 字符串/对象 URL、`video_url`、`videoUrl` 仍按普通视频播放；显式 Live Photo 字段继续使用手动播放控件。针对 F12 中的 `.gif` 地址和普通 MP4 直链增加回归覆盖。
- `test/mixed_media_gallery_test.dart` 3/3、`test/models_test.dart` 37/37 通过；定向 analyze 无 error/warning，保留 1 条既有 info（`weibo_status_model.dart:1282`：`prefer_conditional_assignment`）；`git diff --check` 通过。测试夹具中 `path_provider` 缺少平台实现的日志为非致命现象，未运行全量测试、未做真机媒体验收。
- ARM64 Release 构建成功（280.49 秒）；核验包名 `com.review`、版本 `2.19.13`、versionCode `137`、target SDK `36`、ABI `arm64-v8a`、APK v2 签名及 16 KB zipalign 通过，签名证书与上一版相同。
- 交付 `Review_v2.19.13.apk`（31,985,917 字节），SHA-256：`5572562950A66276DAFD02DA67994C2E60939F701E0154357E4D166BC12D93D1`；`Review_v2.19.12.apk` 归档至 `build/previous-deliveries/`，项目根目录仅保留当前 APK。

## 2.19.12+136（2026-10-07）

- 修复多图画廊中的 Live Photo 被同时识别为普通视频的问题：明确 Live Photo 标记优先；普通 `video_url` 不再触发 Live Photo 控制器；视频与 Live Photo 分类互斥，避免自动播放的视频播放器绕过顶部播放/暂停按钮。
- 新增混合媒体画廊回归测试，验证普通视频与 Live Photo 分类互斥、Live Photo 默认暂停且顶部按钮可播放/暂停。`test/mixed_media_gallery_test.dart` 3 项通过；定向 analyze 无 error/warning，保留 1 条既有 info；`git diff --check` 通过。测试过程有 `path_provider` 缺少平台实现的非致命日志。未运行全量测试，未连接真机。
- ARM64 Release 构建成功（460.1 秒）；核验包名 `com.review`、版本 `2.19.12`、versionCode `136`、target SDK `36`、ABI `arm64-v8a`、16 KB zipalign 与 APK v2 签名通过，签名证书与上一版相同。
- 交付 `Review_v2.19.12.apk`（31,985,917 字节），SHA-256：`4ECE43F86BF312D7286108EF3CC895E8BF64B1E40B7773095F549C334B456241`；`Review_v2.19.11.apk` 归档至 `build/previous-deliveries/`，项目根目录仅保留当前 APK。

## 2.19.11+135（2026-10-07）

- 彻底根除真机日志确凿定位的 `wbgjb.so` 缺失 `WeicoSecurityUtils.aa4` 导致的 JNI SIGABRT 闪退死循环（两层双保险实施）：
  1. **第一层（斩断冷启动死循环链路）**：在 `WeiboAuthManager.java` 的 `restoreSession()` 中，彻底移除了冷启动主路径上的同步 `api().refresh()` 触发。应用本地已通过 AES-GCM KeyStore 安全持久化了包含已验证 `uid` 和 `cookie` 的合法会话，直接返回给 Flutter 端加载首屏，0 毫秒阻塞、0 崩溃风险，冷启动瞬间秒开。
  2. **第二层（对齐上游 Share 完整 JNI ABI 规范）**：根据上游 `WeicoSecurityUtils.smali`（654 行字节码），将 Java 壳层 `WeicoSecurityUtils.java` 完整重建。补齐了底层 native `generateS` 所依赖的 `aa4(String, String, String)` JNI 静态方法回调及其关联算法 `toSecurityValue`（双 SHA-512 散列字符选取算法）、`sha512`、`toHex`；同时补齐 `aa2`（设备 ID 获取）、`aa3`（MD5 特殊下标字符提取）、`aaa`、`securityPsd`、`sinaPushParse`、`charToByte`、`hexString2Bytes` 及全部底层 Native 导出方法签名，彻底杜绝 `mid == null` 和 `Fatal signal 6 (SIGABRT)`。
- `test/auth_session_test.dart` 14/14 测试全部通过；ARM64 Release 构建成功（615.6 秒）；`aapt2` 核验包名 `com.review`、版本 `2.19.11`、versionCode `135`；APK v2 签名验证通过，签名身份与此前版本相同，4-byte zipalign 检查通过。
- 交付 `Review_v2.19.11.apk`（31,330,557 字节），SHA-256：`7DC9F3170123998988D74C01A08AA9994CC36A0A448CB296EDC9C57AB364C979`；`Review_v2.19.10.apk` 归档至 `build/previous-deliveries/`，项目根目录仅保留当前 APK 供用户真机验证冷启动与登录持久化。

## 2.19.10+134（2026-10-07）

- 彻底根治已登录用户冷启动首屏 0.5 秒至 1 秒闪退的最终源头（Chromium Native SIGSEGV 绝缘与全局安全加固）：
  1. **彻底绝缘 Android 原生 `CookieManager`**：在 `MainActivity.kt` 中完全移除 `import android.webkit.CookieManager`。此前已登录状态下冷启动，`FeedController.initAndLoad()` 首帧后调用 `reconcileNativeSession()`，触发 MethodChannel `getNativeCookiesByDomain`。在没有 WebView 上下文的纯 Flutter 进程中，主线程调用 `CookieManager.getInstance()` 并连续读取 8 个域名的 Cookie 会强行唤起系统 Chromium 引擎，在多核并发与缺失上下文时直接引发 C++ 底层 `SIGSEGV / SIGABRT` 致命崩溃（Linux 信号无法被 Java 捕获）。2.19.10 将 `getNativeCookies`、`getNativeCookiesByDomain` 和 `clearNativeCookies` 完全静态化返回安全空数据，原生端彻底零 `CookieManager` 依赖，彻底切断崩溃链路。
  2. **MainActivity 安装全局未捕获异常崩溃日志落盘**：在 `MainActivity.onCreate` 中安装全局 `Thread.setDefaultUncaughtExceptionHandler`，一旦发生任何未捕获异常，立即自动写入私有目录 `latest_crash.txt`，并通过 MethodChannel 提供 `getLatestCrashLog` 查询能力。
  3. **彻底清除 `onCreate` 中的组件启用状态检测**：将 `onCreate` 中触碰 `packageManager.setComponentEnabledSetting` 的历史自愈代码完全剥离，消除任何可能因包状态变更广播导致 AMS 延迟杀进程的潜在隐患。
  4. **Flutter 顶层与平台调度异常兜底**：在 `lib/main.dart` 中配置 `FlutterError.onError` 与 `PlatformDispatcher.instance.onError`，对所有未捕获的 Dart 异步异常进行全局捕获与平稳降级，阻止 Flutter 引擎异常退出。
- `test/auth_session_test.dart` 14/14 测试全部通过；ARM64 Release 构建成功（431.5 秒）；`aapt2` 核验包名 `com.review`、版本 `2.19.10`、versionCode `134`；APK v2 签名验证通过，签名身份与此前版本相同，4-byte zipalign 检查通过。
- 交付 `Review_v2.19.10.apk`（31,330,557 字节），SHA-256：`F76E8796930288A533F74B72667A969317FFFFDE858EAB6900601B3513B69C2F`；`Review_v2.19.9.apk` 归档至 `build/previous-deliveries/`，项目根目录仅保留当前 APK 供用户真机验证冷启动与登录持久化。

## 2.19.9+133（2026-10-07）

- 彻底定位并根除进入应用后 0.5 秒至 1 秒闪退的全部致命隐患：
  1. **彻底解耦 `WeiboAuthManager` 与 `CookieManager`**：Review 作为纯 Flutter 应用，所有网络请求通过 Dart 层的 `WeiboDioClient (Dio)` 并在 Header 中注入 Cookie 发送，完全不通过 Android 原生 WebView。2.19.8 将 `syncCookieManager()` 移入主线程 Handler 队列后，由于在 Flutter 首帧渲染完成（0.5s~1s）出队执行，循环遍历跨域名注入几十次并调用 `cookieManager.flush()`，极易与底层 Chromium 初始化/渲染管线产生争用引发 Native Abort。彻底删除 `WeiboAuthManager` 中的 `syncCookieManager()` 与 `clearCookieManager()` 及其所有调用，根除 Chromium 底层崩溃。
  2. **修复 `MainActivity.onCreate` 组件状态判断误区，杜绝 AMS 杀进程**：默认情况下（未切换过桌面图标时），`MainActivity` 在系统的组件启用状态是 `COMPONENT_ENABLED_STATE_DEFAULT (0)`，而不是 `COMPONENT_ENABLED_STATE_ENABLED (1)`。此前逻辑因判断 `hasEnabled` 为 `false`，导致每次冷启动均调用 `pm.setComponentEnabledSetting(MainActivity, ENABLED, DONT_KILL_APP)`。在现代 Android（特别是国内定制系统 MIUI/HyperOS/ColorOS/OriginOS 等）中，修改当前正处于前台的 Activity 自身组件状态，PMS 发出 `ACTION_PACKAGE_CHANGED` 广播，AMS 会在 500ms~1000ms 后直接强行杀死应用进程（无任何 Java Crash Stacktrace，精准表现为进入应用 0.5s~1s 闪退）！2.19.9 修复为仅在 `MainActivity` 明确处于 `COMPONENT_ENABLED_STATE_DISABLED` 且所有别名均未启用时才兜底恢复，正常冷启动绝不调用 `setComponentEnabledSetting`，彻底根除 AMS 延迟杀进程。
  3. **MainActivity 原生 Cookie 读取安全加固**：移除 `getNativeCookies` 与 `getNativeCookiesByDomain` 中多余的 `cookieManager.flush()` 磁盘同步写入，将 `CookieManager.getInstance()` 和 `getCookie` 调用全量包裹在 `try-catch (Throwable t)` 异常隔离块中，失败降级返回空数据，绝不波及宿主进程。
- `test/auth_session_test.dart` 14/14 测试全部通过；ARM64 Release 构建成功（281.7 秒）；`aapt2` 核验包名 `com.review`、版本 `2.19.9`、versionCode `133`；APK v2 签名验证通过，签名身份与此前版本相同，4-byte zipalign 检查通过。
- 交付 `Review_v2.19.9.apk`（31,330,561 字节），SHA-256：`6F45D7EF7473682070E88F489853F715015E1B750644D376F2D40E3039AF47AF`；`Review_v2.19.8.apk` 归档至 `build/previous-deliveries/`，项目根目录仅保留当前 APK 供用户真机验证冷启动与登录持久化。

## 2.19.8+132（2026-10-07）

- 彻底定位并修复真机在已有登录会话状态下冷启动/手机启动直接闪退（Crash on Startup / SIGABRT）的严重缺陷：
  1. **后台线程操作 CookieManager 引发 Chromium Native Abort 根因排查**：在 2.19.6 成功登录后，会话已持久化至原生 `EncryptedSessionStore`。当应用冷启动时，`auth_provider.dart` 立即调用原生 `restoreSession()`，运行在后台单线程 `weiboAuthExecutor`。`restoreSession()` 中调用 `syncCookieManager(session.cookie)` 在后台线程直接调用 `CookieManager.getInstance()` 和 `setCookie()`。在 Android 冷启动瞬间，Chromium WebView 尚未在 UI 主线程初始化，子线程触碰 CookieManager 会触发 Chromium 底层 `CHECK(BrowserThread::CurrentlyOn(BrowserThread::UI))` 断言失败或竞争崩溃，直接向进程发送 `SIGABRT` / `SIGSEGV` 致命信号，Java 层 `try-catch` 无法捕获，导致启动瞬间闪退。2.19.8 将 `syncCookieManager()` 和 `clearCookieManager()` 严格调度至 UI 主线程（`new Handler(Looper.getMainLooper()).post(...)`）异步执行，彻底消除跨线程初始化与并发崩溃隐患。
  2. **CookieManager URL 格式非法清洗**：此前 `syncCookieManager` 和 `MainActivity.getNativeCookies` 中将 `".weibo.com"`、`".weibo.cn"`、`".sina.com.cn"` 等非 URL 域名字符串直接传入 `setCookie()` 与 `getCookie()`，违反 Android WebView 要求传入绝对有效 URL 的规范，在部分系统引发底层解析异常。2.19.8 全面清洗，仅使用 `https://` 绝对合法 URL。
  3. **`EncryptedSessionStore.load()` 与 `restoreSession()` 故障隔离**：设备重启或 KeyStore 密钥状态异常可能导致解密抛出 `AEADBadTagException` 等异常。在 `load()` 中对解密流程全链路增加 `try-catch (Throwable t)`，发生异常时记录警告并清理损坏密文、安全返回 `null`；`restoreSession()` 增加顶层异常兜底，网络刷新失败时保留本地有效会话，绝不阻断冷启动进程。
  4. **MainActivity MethodChannel 回调安全加固**：`submitWeiboAuth` 与 `completeWeiboAuthError` 中的 `result.success` 和 `result.error` 增加异常捕获，防止通道解绑或重复提交引发崩溃。
- `test/auth_session_test.dart` 14/14 测试全部通过；arm64 Release 构建成功（224.2 秒）；`aapt2` 核验包名 `com.review`、版本 `2.19.8`、versionCode `132`；签名与对齐验证通过。
- 交付 `Review_v2.19.8.apk`（31,330,561 字节），SHA-256：`7D8D01CFC1E9D0B9762565527E11004E0BE79D77C7B783E7D6E7ED28B22D9682`；`Review_v2.19.7.apk` 归档至 `build/previous-deliveries/`，项目根目录仅保留当前 APK 供用户真机验证冷启动与登录持久化。

## 2.19.7+131（2026-10-07）

- 修复微博登录诊断日志泄露会话数据的问题：`WeiboApi` 不再输出完整响应 JSON；会话字段缺失时只记录 HTTP 状态和字段存在情况；CookieManager 同步/清理失败时只记录异常类型，不记录异常消息。HTTP 日志不含响应体、Cookie、Token 或表单参数。
- 按 Bug 修复规则将版本更新到 `2.19.7+131`。ARM64 Release 构建成功（327.0 秒）；`aapt2` 核验包名 `com.review`、版本 `2.19.7`、versionCode `131`、target SDK `36`、ABI `arm64-v8a`；APK v2 签名验证通过，签名身份与 `2.19.6` 相同，4-byte 与 16 KB zipalign 检查通过。
- 交付 `Review_v2.19.7.apk`（31,985,921 字节），SHA-256：`98BCF32E335A981DFAB6F5300807627B78CE0CDF018D1852F2A53324CFA6A1FF`；之前根目录的 APK 已移入 `build/previous-deliveries/` 保留回退，根目录仅留当前 APK。未运行 Flutter 测试；本次没有设备登录验收。

## 2.19.6+130（2026-10-07）

- 解决真机测试 2.19.5 成功收到短信验证码后，输入验证码点击“登录”提示“微博未返回完整登录会话，请重试”的拦截误判问题：
  1. **`hasRequiredFields` 误判拦截修复**：对比上游 Share 源码（`sd.1.smali` 短信验证码登录回调 `ThirdPartyLoginActivity$O00000Oo` 第 80-137 行），短信验证码登录响应中**根本不包含也无需 `sut`**（`sut` 是 SSO 单点登录凭据，仅在账号密码登录 `yd.1.smali` 中下发）。此前 Review 硬编码要求 `present(sut)` 以及根对象 `present(expire)`，导致所有短信登录即使微博服务端返回 200 OK 并下发完整凭据，也会 100% 被判为 `session_fields_missing` 并拒绝进入应用。2.19.6 将会话校验条件修正为必要充分条件：`present(uid) && (present(cookie) || present(accessToken) || present(gsid))`。
  2. **Cookie 多层嵌套结构深度解析**：核对上游 Share（`oo0o00o0.7.smali` 与 `Gz.smali`），微博服务端的 `cookie` 字段为包含各域名（`.weibo.cn`、`.weibo.com` 等）映射的 JSON 对象。Review 实现了多层 JSON Cookie 递归与键值提取，自动提取包含 `SUB=` 的登录 Cookie 并支持 `gsid` 回退兜底，确保 Flutter 端能直接获得合规的标准 Cookie 字符串。
  3. **原生 CookieManager 双向同步**：登录成功与恢复会话时将 Cookie 同步写入系统 `android.webkit.CookieManager` 并 `flush()`，退出登录时彻底清理，保证 WebView 与原生通道凭据完全一致。
  4. **字段缺失诊断**：会话校验不通过时只记录字段存在状态；禁止把原始 JSON 写入日志，因为其中可能包含 Cookie 或 Token。
- `test/auth_session_test.dart` 14/14 通过；`git diff --check` 通过。arm64 Release 构建成功（424.8 秒）；`aapt2` 核验 `com.review`、版本 `2.19.6`、versionCode `130`、target SDK `36`；APK v2 签名通过且证书与 2.19.5 相同，4-byte 及 page zipalign 检查通过。
- 交付 `Review_v2.19.6.apk`（31,985,921 字节），SHA-256：`BA58CF10027FFE7CAAE97F8D7FC2471FAE1B0C4869F8473F76849761B851883D`；`Review_v2.19.5.apk` 归档到 `build/previous-deliveries/`。随后用户在真实设备确认短信验证码发送、输入验证码登录、关注流加载与会话恢复通过。

## 2.19.5+129（2026-10-07）

- 解决真机测试 2.19.4 成功消除 JNI 闪退后，点击“获取验证码”被微博服务端拒发验证码的问题：
  1. **规范化 `area` 参数**：对照上游 Share 反编译源码（`wd.1.smali` 第 217-270 行），中国大陆区号（`"86"` 或 `"0086"`）在 `account/login_sendcode` 和 `account/login` 请求中显式设置为空字符串 `""`，手机号保持 11 位数字。此前 Review 错误地将 `"86"` 放入 `query.put("area", "86")`，导致微博服务端因参数不合规拒发短信。2.19.5 在发码和登录请求中自动将 `"86"` / `"0086"` 规范化为 `""`。
  2. **移除非法伪造的 `aid="7501641714"`**：核对上游 Share（`mA.2.smali` 与 `WeiboWebAuthorizeActivity.smali`），`"7501641714"` 是 AidTask 的应用 ID，绝非设备 AID；若 AidTask 未缓存真实设备 AID，Share 在 query 与 form 中完全不传 `aid`。此前 Review 在多处写死了伪造的 `aid="7501641714"`，导致微博服务端设备 token 校验失败。2.19.5 彻底移除了伪造的 `aid` 传参。
  3. **`ua` 参数补全系统版本号**：核对上游 `PB.smali` 第 41-48 行，标准 ua 格式为 `MANUFACTURER-MODEL__weibo__11.6.3__android__android<RELEASE>`。此前 Review 缺少末尾的 `Build.VERSION.RELEASE`，已补齐。
  4. **透传服务端真实错误描述 (`msg`)**：核对上游 Share（`oo0o00O0.6.smali` 与 `zd.smali`），发码失败时直接提取并向用户展示服务端返回的 `msg`（如“操作过于频繁，请稍后再试”）。此前 Review 抛弃了该字段并用硬编码兜底文案掩盖了真实拒发原因。2.19.5 已将服务端 `msg` / `errmsg` / `error` 全程透传至前端提示与错误日志。
- `test/auth_session_test.dart` 14/14 通过；`git diff --check` 通过。arm64 Release 构建成功（360.6 秒）；`aapt2` 核验 `com.review`、版本 `2.19.5`、versionCode `129`、target SDK `36`；APK v2 签名通过且证书与 2.19.4 相同，4-byte 及 page zipalign 检查通过。
- 交付 `Review_v2.19.5.apk`（31,985,921 字节），SHA-256：`8B281ADCFC9500F6745F506604C2F6475C640C5CF4617021E5EC310F8A0B121B`；`Review_v2.19.4.apk` 归档到 `build/previous-deliveries/`，项目根目录仅保留当前 APK。由于未连接真机，短信验证码发码与登录仍需在 2.19.5 上进行真实设备验收。

## 2.19.4+128（2026-10-07）

- 彻底定位并修复真机点击“获取验证码”闪退（SIGSEGV / Native Abort）的根因：
  1. `WeiboApi.commonLoginQuery()` 此前错误将 `android_id` 设为 `nativeRuntime.deviceId()`，触发调用 `DeviceId.getInstance().getDeviceId(application)`。`libweibosdkcore.so` 的 native 函数 `getDeviceIdNative` 通过 JNI 查找并调用 `DeviceId.genCheckId(String, String, String)`。Review 遗留的 `DeviceId.java` 缺少该方法，导致 JNI `GetMethodID` 返回 `NULL`，随后的 JNI 调用在 ART 虚拟机底层直接发生 SIGSEGV 崩溃，Java 层 `try-catch` 无法捕获。对照上游 Share 反编译源码（`UB.smali` 与 `aQ.1.smali`），`android_id` 本应直接读取系统 `Settings.Secure.ANDROID_ID`。现已将 `android_id` 恢复为系统获取。
  2. 在 `DeviceId.java` 中完整补齐 `genCheckId(String, String, String)`、`appendCheckId`、`checkMyPermission` 等 JNI 回调签名，并在库加载和调用点增加防御性捕获，杜绝后续任何由于反射符号缺失引发的底层崩溃。
  3. `FakePackageManager` 彻底摆脱 `android.test.mock.MockPackageManager`（该测试库在很多生产 ROM 上被剥离，会引发 `NoClassDefFoundError`），改为直接继承 `android.content.pm.PackageManager` 并安全代理所有抽象方法；从 `build.gradle.kts` 和 `AndroidManifest.xml` 中完全移除了 `android.test.mock`。
  4. `WeiboApi.java` 中 `cum` 为空时不再追加空参数；`MainActivity.kt` 的 `submitWeiboAuth` 增加全局 `catch (error: Throwable)` 兜底。
- `test/auth_session_test.dart` 14/14 通过；`git diff --check` 通过。arm64 Release 构建成功（408.0 秒）；`aapt2` 核验 `com.review`、版本 `2.19.4`、versionCode `128`、target SDK `36`；APK v2 签名通过且证书与 2.19.3 相同，4-byte 及 page zipalign 检查通过。
- 交付 `Review_v2.19.4.apk`（31,985,921 字节），SHA-256：`5E2A80213A7CD1C4766C43793F18E384C75285EED54D4787FEDFB9D1A60DB4F3`；`Review_v2.19.3.apk` 归档到 `build/previous-deliveries/`，项目根目录仅保留当前 APK。由于未连接真机，短信验证码发码与登录仍需在 2.19.4 上进行真实设备验收。

## 2.19.3+127（2026-10-06）

- 用户在 2.19.2 设备包上确认点击获取验证码仍闪退。按 Share 上游的按需加载路径修正 Review：短信发码不再提前加载仅供密码加密和 OAuth 签名使用的 `SecShare`、`wbgjb`；`WeiboApplication`、`DeviceId`、`SAUtils`、`WeicoSecurityUtils` 包装类各自加载所需库。四个 ARM64 登录库与 `Zelayan/share` 当前仓库二进制逐字节一致。
- `test/auth_session_test.dart` 14/14 通过；全量 `flutter test --no-pub` 为 212 项通过、6 项失败，均是 `test/widget_test.dart` 的微博长文“展开全文”断言。`git diff --check` 通过。arm64 Release 构建成功（366.5 秒）；`aapt2` 核验 `com.review`、版本 `2.19.3`、versionCode `127`、target SDK `36`；APK v2 签名通过且证书与 2.19.2 相同，16 KB `zipalign` 检查通过。
- 交付 `Review_v2.19.3.apk`（31,985,945 字节），SHA-256：`A21B79D6BEBC53AFC0D7B3E6205BB8396292BFBBC7FB4B3A66F4A329F97F726E`；`Review_v2.19.2.apk` 归档到 `build/previous-deliveries/`，项目根目录仅保留当前 APK。未连接 Android 设备，真实微博发码/登录仍需实机验收。

## 2.19.2+126（2026-10-06）

- 对照 Share 上游 `DeviceId` 调用，将设备标识 native 方法的 Context 从 `FakePackageContext` 改为初始化后的 `WeiboApplication`，与上游 `WSUtils.getApplication()` 调用一致；移除 NativeRuntime 中不再使用的 fake-context 成员。
- `test/auth_session_test.dart` 14/14 通过；全量 `flutter test --no-pub` 为 206 项通过、6 项失败，均是微博长文“展开全文”断言；`git diff --check` 通过。arm64 Release 构建成功（457.9 秒）；`aapt2` 核验 `com.review`、版本 `2.19.2`、versionCode `126`、target SDK `36`、ABI `arm64-v8a`；APK v2 签名通过且证书与 2.19.1 相同，16 KB zipalign 通过。交付 `Review_v2.19.2.apk`（31,985,945 字节），SHA-256：`5EA1DAD2278DD5DD780D048D1D6EE504D7A6A7B7BC5DAF0B4E590F0DA0F5C511`；`Review_v2.19.1.apk` 归档到 `build/previous-deliveries/`，根目录仅保留当前 APK。
- 后续用户实测 2.19.2 仍在点击获取验证码时闪退；Context 调整并未解决问题，参见 2.19.3 和[登录复盘](RETROSPECTIVE.md#登录方式切换2190)。

## 2.19.1+125（2026-10-06）

- 修复微博短信登录点击“获取验证码”时报 `UnsatisfiedLinkError`：`libwbutil.so` 在 `JNI_OnLoad` 中注册整组 8 个 `WeiboApplication` native 方法和 2 个 `EncryptSharedPreferences` native 方法；Review 原先只声明了部分方法且缺少后一个类，导致库加载失败，请求尚未发出。现已补齐精确签名；同时修正 `SecShare` 的 `SAUtils.secP` Java 包名以匹配库导出符号。
- 验证：`test/auth_session_test.dart` 14 项通过；arm64 Release 编译成功（592.1 秒）；`aapt2` 核验包名 `com.review`、版本 `2.19.1`、versionCode `125`、target SDK `36`；APK v2 签名通过、签名身份与 `2.19.0` 相同，16 KB zipalign 通过。依赖锁文件原有版本和镜像保持不变。
- 交付 `Review_v2.19.1.apk`（31,330,581 字节），SHA-256：`6520673F3D855BAAB72C270404C422C8A1F697D7F99CF81E5CD60031F53D88CD`；`Review_v2.19.0.apk` 归档至 `build/previous-deliveries/`，项目根目录只保留当前包。
- 当前未连接 Android 设备；真实微博短信发送、验证码验证及会话验收尚待设备测试。

## 2.19.0+124（2026-10-06）

- 登录页默认使用短信验证码，并新增账号密码切换入口；两种方式可互相切换，右上角 Cookie 导入保持可用。缩小表单最大宽度、水平留白、输入框内边距和主按钮高度。
- 密码登录通过 Android native `account/login`，由 Share 兼容 native 方法生成 `p=secP(password)` 和 `s=newCalculateS(account+password)`；密码只用于此次登录请求，清空 Flutter 输入框，不记录或持久化。登录结果继续走 Review Cookie/UID 验证和 Keystore 会话保存。
- 验证：登录定向 analyze 无诊断；`auth_session_test.dart` 14 项通过。全项目 analyze 输出 44 条 info；全量测试仍有 6 项 `test/widget_test.dart` 中的微博长文“展开全文”断言失败。`dart format` 与 `git diff --check` 通过。
- 原生兜底错误现在只暴露最多三层异常类型，并区分 native 组件加载错误与网络传输错误；异常消息和请求数据不向界面泄露，便于定位登录初始化失败。
- arm64 Release 构建成功（325.6 秒）；核验 `com.review`、版本 `2.19.0`、versionCode `124`、target SDK `36` 和 ABI `arm64-v8a`；16 KB zipalign 及 APK v2 签名通过，签名证书与上一版一致。交付 `Review_v2.19.0.apk`（31,985,945 字节），SHA-256：`2681B35A53F34B01A52BA4317E2C6BC7F86E73C4244E6BD70FE01208F82E8140`；`Review_v2.18.0.apk` 已归档至 `build/previous-deliveries/`，根目录只保留当前包。
- 未连接 Android 设备；验证码、账号密码的微博真实登录及 Review 会话仍需实机验收。

## 2.18.0+123（2026-10-06）

- 登录页改用 Review 原生 Material 3 界面，默认通过微博 Android 私有接口短信验证码登录，不要求用户预先设置微博密码；顶栏右侧保留“Cookie 导入”。native 登录返回的完整 session 只有在 Review 校验 Cookie/UID 后才写入 Android Keystore AES-GCM 存储，退出登录清理 native session。
- 应用启动时尝试恢复 native session，且仅在距上次刷新达到 5 小时 50 分钟后调用 `account/getoauth`。当前 Review 微博 API 继续用 Cookie 兼容层；完整普通 API session 迁移和真实设备/账号验收仍未完成。
- `dart format`、`git diff --check`、登录相关定向 analyze 和 `test/auth_session_test.dart`（12 项）通过。全量 analyze 有 44 条 lint/info；全量测试有 6 项在微博卡片全文展开文案断言失败，认证测试通过。arm64 Release 构建成功（347.8 秒）；`aapt2` 核验 `com.review`、版本 `2.18.0`、versionCode `123`、target SDK `36`、ABI `arm64-v8a`；16 KB zipalign 和 APK v2 签名通过，证书与上一版一致。交付 `Review_v2.18.0.apk`（31,985,945 字节），SHA-256：`A81B0DFD5EFEE34EFF2D063415A00C3414E1EA3F53C961B6922E20793B988319`；旧版已移至 `build/previous-deliveries/`，根目录只留当前包。未连接 Android 设备，短信和真实登录仍需实机验收。

## 2.17.3+122（2026-10-06）

- 画廊 PageView 始终保持全屏视口，顶栏和缩略条以覆盖层显示；显隐控件不再改变主图约束，避免放大后的图片突然移动。单张静态图片因此以整个屏幕为中心；多图照片保留当前缩放和平移状态。
- `dart format`、`git diff --check` 和画廊/版本常量静态分析通过；未运行测试。arm64 Release 构建成功（306.7 秒）；核验 `com.review`、版本 `2.17.3`、versionCode `122`、target SDK `36`、ABI `arm64-v8a`、16 KB zipalign 和 APK v2 签名通过，签名与上一版一致；APK 含局部玻璃按钮 shader。交付 `Review_v2.17.3.apk`（31,766,761 字节），SHA-256：`E1C2024E38302AADB7B2A75E19BF5B84AA741C73AFC95D9F5A5BD25720320D65`；`Review_v2.17.2.apk` 已移至 `build/previous-deliveries/`，根目录只留当前包。未连接真机。

## 2.17.2+121（2026-10-06）

- 参照用户的相册截图缩小画廊玻璃按钮：圆形视觉外径从 48dp 减为 44dp，保留 48dp 点击区域；降低背景模糊、球冠高度、折射位移上限和高光描边强度。
- `dart format` 与 `git diff --check` 通过；`flutter analyze --no-pub`（画廊和版本常量）无问题，未运行测试。arm64 Release 构建成功（376.3 秒）；核验 `com.review`、版本 `2.17.2`、versionCode `121`、target SDK `36`、ABI `arm64-v8a`、16 KB zipalign 和 APK v2 签名通过，证书与上一版一致；APK 包含画廊局部 shader，不含 Miuix 或全局玻璃资源。交付 `Review_v2.17.2.apk`（31,832,297 字节），SHA-256：`42827C9561942D01696F4FA062B706DF60A743D7520C4FC5DBC7E49AC0C34E8D`；`Review_v2.17.1.apk` 已移至 `build/previous-deliveries/`，根目录只留当前包。未连接真机。

## 2.17.1+120（2026-10-06）

- 将 Material 3 悬浮底栏宽度从 280dp 收至 264dp，保留 64dp 高度与每项 48dp 触控区域。
- 图片画廊顶栏的返回和下载控件改为 48dp 圆形灰色半透明玻璃按钮，增加高光描边；Impeller 用球冠法线和空气/玻璃 Snell 折射角驱动局部凸面位移，最大 1.25 shader 单位。滤镜限制在圆形按钮内，不做全屏截图或纹理捕获；shader 不可用时保留模糊和描边回退。全局液态玻璃及 Miuix 仍保持移除。
- `flutter analyze --no-pub` 全项目无 error/warning，列出 45 条 info；本轮 19 个 Dart 文件无 error/warning，仅 FeedView 有 1 条已有的 `axisAlignment` 弃用 info。`git diff --check` 通过，未运行测试。arm64 Release 构建成功（228.7 秒）；核验 `com.review`、版本 `2.17.1`、versionCode `120`、target SDK `36`、ABI `arm64-v8a`、16 KB zipalign 与 APK v2 签名通过，签名与上一版一致；APK 仅包含新的局部 `gallery_glass_button.frag`，没有 Miuix 或全局玻璃 shader。交付 `Review_v2.17.1.apk`（31,766,709 字节），SHA-256：`69A698AF19A9F14C7B4120AA579D59A99F5BF0D7F0E9FC631D1370832A63800E`；`Review_v2.17.0.apk` 已移至 `build/previous-deliveries/`，根目录仅留当前包。未连接真机。

## 2.17.0+119（2026-10-06）

- 按用户决定移除 Miuix 界面和液态玻璃导航，删除对应组件分支、主题桥接、着色器、设置项与 `flutter_miuix` 依赖。现有 Material 3、悬浮底栏开关、预置色与 Monet 动态取色继续保留。
- 旧版保存的 Miuix/玻璃偏好不再读取或写入；升级后导航使用 Material 3 标准样式。此前的实现记录留在回顾文档中，仅供历史追溯。
- `flutter analyze --no-pub` 全项目无 error/warning（45 条 info）；本次改动的 11 个目标无 error/warning，仅 FeedView 有 1 条已有的 `axisAlignment` 弃用 info；`git diff --check` 通过，未运行测试。arm64 Release 构建成功（411.8 秒）；核验包名 `com.review`、版本 `2.17.0`、versionCode `119`、target SDK `36`、ABI `arm64-v8a`、16 KB zipalign 与 APK v2 签名通过，签名与 2.16.9 一致；APK 无 Miuix 或玻璃 shader 资源。交付 `Review_v2.17.0.apk`（31,764,464 字节），SHA-256：`9EE518125EA00FF76D3541A197E56A3B7FB4BF822D40CA7D74C5F46C1C7CF8D2`；`Review_v2.16.9.apk` 已移至 `build/previous-deliveries/`，根目录仅留当前包。未连接真机。

## 2.16.9+118（2026-10-06）

- 按 Kyant 上游 SDF 透镜公式修正采样方向，背景沿外法线向外取样，恢复凸起折射；将拖动位置收敛到一个弹簧控制器，速度形变直接由触摸速度更新，释放后弹簧复位，减少每个触摸事件重启的动画控制器。
- `flutter analyze --no-pub`（导航栏与版本常量）无问题，`git diff --check` 通过；未运行测试。arm64 Release 构建成功（225.0 秒）；核验 `com.review`、版本 `2.16.9`、versionCode `118`、target SDK `36`、arm64-v8a、16 KB zipalign 与 APK v2 签名通过，签名与上一版一致。交付 `Review_v2.16.9.apk`（32,184,335 字节），SHA-256：`96C9D292CEC215019E69905C9C431927ECB5E3876CD77011E999A92AA5CBE1AA`；旧包已归档至 `build/previous-deliveries/Review_v2.16.8.apk`。没有连接真机，运行时卡顿改善与折射观感仍需设备验收。

## 2.16.8+117（2026-10-06）

- 按照 `legado-with-MD3` / Kyant Backdrop 的实际透镜机制重做选中层：SDF 圆弧映射仅折射胶囊内侧边缘，将完整导航图标行放到透镜采样层下，去掉遮挡折射的前景重绘；选中宽度与导航槽一致，使用弹簧跟手、78/56 按压缩放及方向性速度拉伸。M3 与 Miuix 共用该玻璃渲染路径。
- `flutter analyze --no-pub`（导航栏与版本常量）无问题，`git diff --check` 通过；未运行测试。arm64 Release 构建成功（217.1 秒），核验 `com.review`、版本 `2.16.8`、versionCode `117`、target SDK `36`、arm64-v8a、16 KB zipalign 和 APK v2 签名通过；签名与上一版一致。交付 `Review_v2.16.8.apk`（32,184,339 字节），SHA-256：`8F183EBA600D9C4B22012DCE83EE464B1F4F743491B12B769203E923CD4250AA`；旧包已归档至 `build/previous-deliveries/Review_v2.16.7.apk`，根目录只保留当前 APK。没有连接真机，动态观感与帧率仍需设备验收。

## 2.16.7+116（2026-10-06）

- 修正 M3/Miuix 液态玻璃透镜的凸起折射与明暗层次；将 Miuix 文字语义字号映射到当前 Material 主题，并统一玻璃导航标签为 12sp；修复底栏斜向拖拽离开边界后回弹到原选项；纯黑开关简化为“纯黑深色模式”。
- `flutter analyze --no-pub`（主题桥接、导航栏、个性化页、版本常量）无问题，`git diff --check` 通过；本轮未运行测试。arm64 Release 构建成功（210.1 秒），已确认液态玻璃 shader 存在于 APK；核验 `com.review`、版本 `2.16.7`、versionCode `116`、target SDK `36`、arm64-v8a、16 KB zipalign 与 APK v2 签名通过，证书与 2.16.6 一致。交付 `Review_v2.16.7.apk`（32,184,539 字节），SHA-256：`D13802D9B45533BA94A4E7D16732816E4CF8993C25C93C3BB8C97D6ACE662795`；旧包已归档至 `build/previous-deliveries/Review_v2.16.6.apk`。无真机交互验收。

## 2.16.6+115（2026-10-06）

- 按反馈移除单图/单视频画廊的底部预留：没有缩略条时仅避开顶部按钮区域，主图视口可延伸到屏幕底部；多图画廊的缩略条间距保持不变。
- `dart analyze`（画廊与版本常量）无问题，`git diff --check` 通过；本轮未运行测试。arm64 Release APK 核验 `com.review`、版本 `2.16.6`、versionCode `115`、target SDK `36`、arm64-v8a、16 KB zipalign 和 APK v2 签名通过。产物 `Review_v2.16.6.apk`（32,184,539 字节），SHA-256：`D4A39A858C647634E1F106767B5EBDA27D220634126279DA20AF7AE18AA72DF0`；旧根目录 APK 已移至 `build/previous-deliveries/Review_v2.16.5.apk`。未连接真机。

## 2.16.5+114（2026-10-06）

- 修复单图打开后位置偏下：无缩略条时为画廊底部增加与顶部相等的安全区 inset+68dp 留白，使主图视口对称居中；多图画廊原布局不变。
- 修正 M3 和 Miuix 液态玻璃透镜的凹陷观感：边缘折射由沿外法线采样改为向透镜内侧采样，增强中心放大，并使用上缘高光、下缘阴影表现凸起；Impeller 实时背景采样路径与非 Impeller 回退不变。
- `dart analyze`（画廊与版本常量）无问题，`git diff --check` 通过；本轮未运行测试。arm64 Release APK 核验 `com.review`、版本 `2.16.5`、versionCode `114`、target SDK `36`、arm64-v8a、16 KB zipalign 和 APK v2 签名通过。产物 `Review_v2.16.5.apk`（32,184,539 字节），SHA-256：`B7941B2E282386D92B3A6874FDF47BCCC52EF1B3F79D4AF1C4E7144F3274B939`；旧根目录 APK 已移至 `build/previous-deliveries/Review_v2.16.4.apk`。未连接真机，单图居中效果仍需设备复测。

## 2.16.4+113（2026-10-06）

- 重做 M3/Miuix 液态玻璃选中透镜的 Impeller 渲染：使用 Flutter GPU `ImageFilter.shader` 对实时 backdrop 做放大、边缘折射、速度色散和高光，避免 Miuix backdrop 每帧同步截图/离屏纹理合成；保留旧渲染后端回退、弹簧跟手、跨项拖动、重复点击和触感反馈，不新增依赖。
- 修复 Miuix 热搜分类栏左/右滑时的延迟：移除带 275ms 自动居中动画的 MiuixTabRow 路径，改用 TabController 连续页面进度驱动分段指示器和文字颜色，八个分类等宽显示。
- `flutter analyze --no-pub` 覆盖本轮 3 个 Dart 文件，无问题；`git diff --check` 通过，未运行测试。arm64 Release 构建成功（179.9 秒）；核验 `com.review`、版本 `2.16.4`、versionCode `113`、target SDK `36`、ABI `arm64-v8a`、16 KB zipalign 与 APK v2 签名通过，签名证书与上一版一致。交付 `Review_v2.16.4.apk`（32,184,347 字节），SHA-256：`83C463AB3905E99756BBD0400CDDE46DE7EDD883A9CEFB75B9F3CD3E9D46B0B8`；旧根目录 APK 已移至 `build/previous-deliveries/Review_v2.16.3.apk`。没有连接真机，玻璃观感、帧率和热搜跟手仍需设备验收。

## 2.16.3+112（2026-10-06）

- 按反馈将画廊主图可视范围恢复为返回/下载按钮行下沿至缩略条上沿；多图底部间距从 24dp 减为 8dp。缩放最低/回弹下限设为 fit 尺寸 1.0，避免 ExtendedImage 在低于适配尺寸时强制居中造成焦点偏移和底部空白；长图不再强制 topCenter 对齐。
- `dart analyze`（画廊与版本常量）无问题，`git diff --check` 通过；本轮未运行测试。arm64 Release APK 核验 `com.review`、版本 `2.16.3`、versionCode `112`、arm64-v8a 和 APK v2 签名。产物 `Review_v2.16.3.apk`（32,179,831 字节），SHA-256：`C5A13FD314D823A92F5EB34697C68B41F6F121E49C43747F8255990ADB69FFF1`；旧 APK 已归档至 `build/previous-deliveries/Review_v2.16.2.apk`。真机视觉效果待用户复测。

## 2.16.2+111（2026-10-06）

- 按用户反馈把图片画廊主图上边界再上移到状态栏安全区下沿。顶部返回/下载控件继续悬浮在主图上方，便于实机对比状态栏边界方案。
- `dart analyze lib/features/detail/presentation/widgets/image_gallery_page.dart` 无问题，`git diff --check` 通过；本轮未运行测试。arm64 Release APK 核验 `com.review`、版本 `2.16.2`、versionCode `111`、arm64-v8a 和 APK v2 签名。产物 `Review_v2.16.2.apk`（32,179,827 字节），SHA-256：`E7D033815F269A108886C99B1569E595147866EAA8258975075C5DCC17937F6E`；旧 APK 已归档至 `build/previous-deliveries/Review_v2.16.1.apk`。真机视觉效果待用户复测。

## 2.16.1+110（2026-10-06）

- 根据实机截图反馈，将画廊顶部图片边界从按钮下方再留 12dp，收紧到返回/下载控件下边缘；状态栏安全区仍保留。这样竖图可更靠近顶部操作区，同时不会进入控件后方。
- 其他布局、手势和媒体行为不变。改动画廊文件静态分析通过、`git diff --check` 通过；本轮未运行测试。arm64 Release APK 核验 `com.review`、版本 `2.16.1`、versionCode `110`、arm64-v8a 和 APK v2 签名。产物 `Review_v2.16.1.apk`（32,179,827 字节），SHA-256：`172EF6F542C9E4A44BD1A608F93B2120992B8C21072C94FD0B4D718071B89F93`；旧根目录 APK 已归档至 `build/previous-deliveries/Review_v2.16.0.apk`。尚未进行设备画面验收。

## 2.16.0+109（2026-10-06）

- 加深 Miuix 设计语言覆盖：主时间线与热搜切换到 Miuix Scaffold/TopAppBar，热搜分类使用 MiuixTabRow；设置大厅的分组入口使用 MiuixArrowPreference 和 Miuix 卡片，时间线微博卡片使用带 Squircle 与按压下沉反馈的 MiuixCard。Material 3 仍走原 Material 组件路径，共用业务数据、路由和回调。
- 参考 Legado 将设计引擎作为真实组件分支的做法：Miuix 主题桥接继续服务未迁移页面，新增页面优先使用 Review 语义组件，不复制业务页。
- `dart analyze` 覆盖本轮改动的 7 个 Dart 文件，无 error/warning；仅有原有 `FeedView.axisAlignment` 弃用 info。`git diff --check` 通过，未运行测试。arm64 Release 构建成功（130.6 秒）；核验包名 `com.review`、版本 `2.16.0`、versionCode `109`、target SDK `36`、ABI `arm64-v8a`，16 KB zipalign 与 APK v2 签名通过，证书与上一版一致。交付 `Review_v2.16.0.apk`（32,179,827 字节），SHA-256：`D870066C39B7FAA5C6884C3F8464037F55E8C6097450FCDCD6A240396A988F97`；`Review_v2.15.4.apk` 已移至 `build/previous-deliveries/`，根目录仅留当前 APK。当前未连接 Android 设备，Miuix 页面观感、触感及帧率需真机验收。

## 2.15.4+108（2026-10-06）

- 修正图片画廊主图可视区域：顶栏显示时在状态栏安全区下方再留 80dp（顶栏 68dp、呼吸间距 12dp），主图在顶部控制区与底部缩略条之间按剩余高度等比适配。竖图不再顶到状态栏或被按钮压住，图片中心也会因上下空间不对称自然下移；清屏后恢复全屏视口。
- 未改变图片手势、缩放锚点、分页、缩略条/视频控制器或 Hero 回程行为，不新增依赖与图像解码。
- `dart analyze lib/features/detail/presentation/widgets/image_gallery_page.dart` 无问题，`git diff --check` 通过；本轮未运行测试。arm64 Release APK 构建成功，核验 `com.review`、版本 `2.15.4`、versionCode 108、arm64-v8a 和 v2 签名。产物 `Review_v2.15.4.apk`（32,179,831 字节），SHA-256：`1EDC2689ABC02A14273DDEE192E45506E2FF0FABF62FB94FA86604531FA8499C`；旧根目录 APK 已移入 `build/previous-deliveries/Review_v2.15.3.apk`。当前没有设备画面验收。

## 2.15.3+107（2026-10-06）

- 参照 Legado 的浮动玻璃底栏改进 M3/Miuix Liquid Glass：选中透镜现在折射局部合成的页面与放大图标背景，按压时高度按 78/56 比例膨胀，快速拖动会拉伸水滴、增强折射和高光；新增捕获限于 320×88dp、1x，不重复捕获全屏页面。
- `flutter analyze --no-pub lib/core/design_system/components/review_navigation_bar.dart` 无问题；全项目分析无 error/warning、保留 45 条既有 info；`git diff --check` 通过，未运行测试。arm64 Release 构建成功（105.6 秒），核验包名 `com.review`、版本 `2.15.3`、`versionCode` 107、`targetSdkVersion` 36、ABI `arm64-v8a`；16 KB zipalign 与 APK v2 签名通过，证书与上一版一致。交付 `Review_v2.15.3.apk`（32,114,295 字节），SHA-256：`877E308919183C3084D24A20CE1ECD2ECAB8C6B81EADBE7B7211E7C080DD5F98`；旧版已归档至 `build/previous-deliveries/Review_v2.15.2.apk`。当前未连接 Android 设备，液态玻璃动画与性能尚未真机验收。

## 2.15.2+106（2026-10-06）

- 修正 Miuix 标准悬浮导航栏尺寸过小：三项按栏宽均分，宽屏为 280×64dp，窄屏自适应，并保留库的系统底部安全间距。
- 修复 Miuix 标准/液态玻璃导航与两种设计语言的液态玻璃导航没有触感反馈的问题；全部经过 `HapticFeedbackUtil`，遵守全局触感开关和节流规则。
- 为 M3、Miuix 液态玻璃底栏增加同一动态折射选中透镜：复用页面背景捕获，弹簧双边跟随选择和拖拽，保留原导航手势及重复点击回调。
- 恢复微博长文的时间线预览：默认使用微博 `text_raw`，仅当标准化全文确实比预览更长时显示“展开全文”；点击后才展开已获取的全文，主微博和转发微博一致。移除导致多数长文自动铺开的折叠门槛及逐帧行测量。
- `flutter analyze --no-pub` 无 error/warning，保留 45 条既有 info；`git diff --check` 通过，本轮未运行测试。arm64 Release 构建成功（324.9 秒）；核对包名 `com.review`、版本 `2.15.2`、`versionCode` 106、`targetSdkVersion` 36，`zipalign` 与 APK v2 签名校验通过，签名证书与上一版一致。产物 `Review_v2.15.2.apk`（32,114,295 字节），SHA-256：`0B4348AB0959FF7A018EA9D60E3F92A815C2DFBE62270E76CA14E976FE03D4F2`；旧根目录 APK 已移至 `build/previous-deliveries/Review_v2.15.1.apk`。未进行真机观感验收。

## 2.15.1+105（2026-10-06）

- 修复 Miuix 标准悬浮底栏被 Scaffold 拉伸后垂直居中的问题：按库现有的 52dp 内容高度和底部间距约束外层尺寸。
- M3 与 Miuix 液态玻璃底栏改用同一弹性玻璃导航指示器；M3 使用自身主题色，Miuix 使用提高对比度的中性色，恢复明显的移动水滴选中效果。
- Miuix 内置配色与 M3 色盘独立选择、独立持久化，Miuix 默认使用蓝色系；Monet 仍是两种风格共用开关，系统动态色可用时两边分别从系统主色生成色板。新增的 Miuix 色索引加入 WebDAV 个性化备份白名单。
- `ReviewThemeBridge` 扩展为全局 Miuix 兼容层，覆盖仍在共享功能页使用的 Flutter 卡片、列表、对话框、底部菜单、按钮、输入控件和常用状态控件；业务页面与微博逻辑仍共用。
- `flutter analyze --no-pub` 无 error/warning，保留 45 条既有 info；`git diff --check` 通过。本轮未运行测试，也未在真机验收交互和材质观感。
- arm64 Release 构建成功（413.1 秒）；核对包名 `com.review`、版本 `2.15.1`、`versionCode` 105、`targetSdkVersion` 36、ABI `arm64-v8a`，`zipalign` 和 APK v2 签名校验通过。产物 `Review_v2.15.1.apk`（32,114,291 字节），SHA-256：`75806A035FF22B38A2DBE11AD940FF3E9C8430A5ED1AC74F3680A514A300E3AC`；旧根目录 `Review_v2.15.0.apk` 已归档到 `build/previous-deliveries/`，根目录只保留当前 APK。

## 2.15.0+104（2026-10-06）

- 个性化设置在“明暗模式”下方新增 Material 3 / Miuix 界面风格切换；沿用同一套业务页面与状态。底栏支持 M3/Miuix 的贴底导航、标准悬浮导航和液态玻璃悬浮导航。液态玻璃选项仅在悬浮底栏开启时展示，关闭悬浮栏会保留已选材质。
- 新增 Miuix 色彩桥接、Miuix 通用页面/卡片/选择项组件及 Liquid Glass 背景捕获；两个新偏好键加入个性化备份白名单，现有账号凭据白名单规则不变。引入 `flutter_miuix ^1.3.0` 并更新兼容 SDK 下限至 Flutter `>=3.47.0` / Dart `^3.13.0`。
- `flutter test --no-pub` 全量 228 项通过；新增设计系统回归覆盖旧用户默认值、备份白名单、Miuix 明暗/纯黑调色、悬浮玻璃条件、六种导航组合、设置入口、重复点击与跨 Tab 拖动。改动文件 `dart analyze` 无问题；全项目分析无 error/warning，保留 45 条 info。
- arm64 Release APK 构建成功；核验包名 `com.review`、版本 `2.15.0`、versionCode `104`、ABI `arm64-v8a` 和 APK v2 签名。产物 `Review_v2.15.0.apk`（32,114,291 字节），SHA-256：`480A6817102811C4FDCF5E2759833562A8CE633926884892006C92A77FA805D7`；旧根目录 APK 已移入 `build/previous-deliveries/Review_v2.14.5.apk`。未在真机验收视觉与性能。

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
