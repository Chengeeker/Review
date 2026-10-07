# Review 工程复盘

这里保留能帮助避免回归的根因和检查办法。当前功能、接口边界与发布流程以 [DEVELOPMENT.md](../DEVELOPMENT.md) 为准。旧版综合手册截至 2026-09-23，原件仍在仓库 `docs/archive/Review-legacy-2026-09-23.md`，仅供追溯；其中的操作建议可能过时或互相矛盾，不能当作现行规范。

> **历史归档：** Miuix 与悬浮底栏液态玻璃已在 `2.17.0` 按用户决定移除。以下条目不要求恢复它们。`2.17.1` 按新的明确需求，只在图片画廊的两个圆形操作按钮上增加局部玻璃折射；这不恢复全局材质选项或 Miuix。

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

- **更正（2.16.9：透镜方向与拖动帧负载）**：2.16.8 shader 用 `position - normal * ...` 向胶囊内部取样，和 Kyant `RoundedRectRefractionShader` 的 `coord + d * grad` 相反；SDF 外法线方向才形成凸透镜，向内采样会变成凹透镜。2.16.5 的旧记录也把这个方向写反了。拖动时原实现每个指针事件都重启左右边缘两个位置弹簧和速度弹簧；现改为单一位置弹簧，速度样本直接驱动形变，释放时再弹簧复位。设备尚未连接，因此卡顿改善和最终观感仍需真机验收。

- **现象与根因（2.16.8：液态玻璃像毛玻璃底板上的选中块）**：Flutter 实时路径把整个胶囊中心统一放大，而 Legado/Kyant 的 `lens` 按 SDF 法线和 `circleMap` 只重折射胶囊内侧的一圈；Review 还只以 30% 透明度把图标行放入滤镜输入，又在透镜上方重画完整图标，因此图标没有进入折射结果。选中胶囊还比实际槽位宽 10dp，较实的渐变和边框进一步压住了折射。上游 `FloatingBottomBar` 用 `rememberCombinedBackdrop(backdrop, tabsBackdrop)` 合并页面与完整图标层，以 `lens(10dp × press, 14dp × press, depthEffect = true)`、`DampedDragAnimation`、78/56 按压缩放和带方向的速度拉伸共同产生水滴移动。当前 Review 用 Flutter `ImageFilter.shader` 移植相同的边缘折射轮廓与分层关系，图标行置于透镜下、选中层不再被重画遮盖，槽宽与每个导航项对齐。Legado 声明 `io.github.kyant0:backdrop:2.0.1`、`io.github.kyant0:capsule:2.1.3` 和应用级 Haze `1.7.3`；其中实际透镜在 Backdrop，Haze 不是该选中透镜的实现。源码：[FloatingBottomBar](https://github.com/HapeLee/legado-with-MD3/blob/main/app/src/main/java/io/legado/app/ui/widget/components/FloatingBottomBar.kt)、[DampedDragAnimation](https://github.com/HapeLee/legado-with-MD3/blob/main/app/src/main/java/io/legado/app/ui/animation/DampedDragAnimation.kt)、[Kyant SDF lens shader](https://github.com/Kyant0/AndroidLiquidGlass/blob/kmp/backdrop/src/commonMain/kotlin/com/kyant/backdrop/internal/Shaders.kt)、[Legado dependencies](https://github.com/HapeLee/legado-with-MD3/blob/main/gradle/libs.versions.toml)。Flutter/Compose 的采样与坐标系统不同，源码适配完成和 APK 构建不能代替目标设备上的动态观感验收。
- **覆盖检查（2.16.0）**：之前主题桥接虽然能改 Material 全局色彩/形状，但 Miuix 原生组件主要集中在底栏和个性化页，导致整体验感像只换色。上游 Legado 的 ThemeComponents 使用 Miuix 自己的 ThemeController/Theme/Typography，并把设计引擎保存在主题状态中；Review 因此在共享页面增加真实 Miuix Scaffold、TopAppBar、TabRow、ArrowPreference 与 Card 路径，保留 Material 3 分支和同一业务逻辑。后续继续沿用户可见频率迁移，不能把全局 recolor 当成完整适配。参考：[Legado ThemeComponents](https://github.com/HapeLee/legado-with-MD3/blob/main/app/src/main/java/io/legado/app/ui/theme/ThemeComponents.kt)、[Legado theme state](https://github.com/HapeLee/legado-with-MD3/blob/main/app/src/main/java/io/legado/app/ui/theme/LegadoTheme.kt)。
- 第三方 Miuix glass navigation 在点击当前已选中的 Tab 时不再次调用选择回调；Review 的首页把重复点击用于回顶/刷新。替换导航组件时必须在共享适配层补回已选项点击，并回归快速重复点击和跨 Tab 拖动，不能只验证切页。
- Miuix 卡片不提供 Material 祖先，卡片中复用的 `ChoiceChip`、`ListTile` 等 Material 子控件可能因缺少 `Material` 报错。共享卡片封装应在 Miuix 卡片内部提供透明 Material 层，并以真实包含旧 Material 子控件的页面回归。
- Miuix 自带开关可能无条件触发震动，绕过 Review 可关闭的全局触感偏好。设置控件应从 Review 的用户操作回调统一触发反馈；玻璃背景捕获只在悬浮底栏玻璃模式挂载，按 1x 捕获页面背景并排除导航栏自身，避免多余纹理工作或反馈循环。
- 界面风格开关在“设置 → 个性化 → 明暗模式”下方；风格与悬浮栏材质分开保存。悬浮栏关闭时隐藏材质选项但保留选值，旧用户默认仍为 Material 3 + 标准材质。回归应覆盖六种风格/导航组合、备份白名单、明暗与纯黑色板桥接及关闭/重开后材质记忆。
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

- **现象**：照旧手册改动关注流或取消关注接口后，出现陌生内容或请求失败。**根因**：旧手册把“绝不请求未读流”和桌面端 `destory` 当作通用规则；当前源码首屏有受限的未读流回退，桌面取消关注拼作 `destroy`，移动端才拼作 `destory`。**回归点**：按 `FeedRepository` 与当前会话判断回退范围，核对目标域名及实际接口拼写，不跨域套用旧规则。
- **现象**：“我的收藏”接口成功，页面却为空。**根因**：`/ajax/favorites/all_fav` 的 `data` 可能直接是列表，按固定 `data.list` 结构强转会失败。**回归点**：先做运行时类型判断，再按实际响应结构解包；不要用空 `catch` 掩盖解析错误。
- **现象**：子页面已点赞的微博再次点击仍发送点赞请求。**根因**：复用卡片只查询首页控制器，子页面持有的是自己的列表状态。**回归点**：操作以卡片当前有效状态为准，失败时回滚，并向外部列表同步结果。
- **现象**：列表翻页断流或楼中楼只显示首段预览。**根因**：混用上刷与下翻参数，或丢弃服务端游标。**回归点**：按各接口的 `max_id`、`is_mix` 等实际返回值续页；不要把首屏数组当成全部数据。

- **现象**：普通微博列表有两张真实配图，详情却多出“抽奖详情”的小图。**根因**：将 `url_type=39` 通用网页链接及网页缩略图都视为自动动态图片，详情补全后把抽奖导航图混进配图。**修复与回归点**：按单条链接的标题、对象类型或微博抽奖域名在共享模型里排除抽奖缩略图，同时取消该链接的自动卡片补全资格；不能按整篇正文出现“抽奖”或按图片尺寸过滤真实配图。覆盖 `url_struct` 链接内图片、`url_objects` 图片、移动端 `page_info` 和历史快照往返；生日/夺金分层卡片、祝福与普通正文链接必须继续保留。已有旧快照中已经存下的误配图不做无依据删除，重新获取官方状态后使用新规则。

## Android 与交互

- **现象**：微博文章封面被转换为普通配图后，点击只能打开画廊，无法进入已适配的文章阅读页。**根因**：图片模型没有保留链接语义，自动卡片和原生文章共用图片点击分支。**修复与回归点**：为文章封面保存原生文章目标，点击复用既有路由；只认可微博官方文章 URL 或明确的 article 对象 ID，不将通用网页、视频、抽奖或生日/荣誉卡片误判成文章。覆盖桌面/移动 URL、各接口封面结构、旧快照补回目标、序列化往返，以及列表/详情点击进入原生阅读页；加载列表时不能提前请求文章内容。

- **现象**：热搜页底栏双击或顶栏双击可能只回顶、不刷新，或误刷新其他分类。**根因**：各热搜分类分别持有懒加载列表状态，页面层不能直接操作当前分类列表。**回归点**：动作从当前 `TabController.index` 定位该分类状态；回顶使用该列表自己的 `ScrollController`，刷新只调用同一分类现有接口；页面切换时取消底栏单击判定计时器，离开页面/销毁时释放计时器和控制器。
- **现象**：自动奖牌/会员卡片在时间线中被压成窄长图，详情画廊却正常。**根因**：用透明前景图的尺寸计算合成卡片容器比例，再用 `BoxFit.cover` 裁切前景与背景。**回归点**：有独立背景层时以背景画布成对宽高作为比例来源；没有可用尺寸时采用横向卡片默认比例；自动卡片图层使用等比完整显示，普通微博图片布局保持原样。
- **现象**：应用重启后部分图片重新下载、临时缓存持续增长。**根因**：`Image.network` 只保留进程内缓存，而 `extended_image` 的磁盘缓存默认没有容量上限；完整 URL 不同也会产生不同缓存文件。**回归点**：新增图片入口复用统一的磁盘缓存，并确认 `ExtendedNetworkImageProvider` 显式开启 `cache`；缓存维护只扫描临时 `cacheimage` 目录内 MD5 命名文件，不能触碰相册媒体和账号资料。真机需区分加载占位与实际网络下载，并测量冷启动流量及缓存大小。
- **现象**：本机 JDK 17 构建时报 `Selector`/loopback 错误。**根因**：默认用户临时目录的本地通信管道异常。**回归点**：按 [Release APK 步骤](../DEVELOPMENT.md#102-release-apk)在当前构建进程中使用已存在的项目临时目录，构建完成后核对 APK 元数据和签名。
- **现象**：仅为构建改版本时 `pubspec.lock` 被重写。**根因**：Release 命令默认再次执行 Pub 解析，可能切换 hosted 源或升级约束内的包。**回归点**：依赖已解析时使用 `--no-pub` 构建；依赖更新单独执行 `flutter pub get`，确认锁文件差异有意后再打包。
- **现象**：模态弹窗出现慢、背景水波纹拖尾。**历史误区**：旧手册 8.6 节建议人为等待 80ms 并使用 `InkRipple`，8.10 节随后撤销了这套做法。**当前代码**：`HapticSplashFactory` 默认委托 `InkSplash.splashFactory`；修改弹窗交互时以当前源码和真机效果为准，不恢复旧延迟。
- **现象**：点击微博正文中的 `@用户` 打开主页时没有触感。**根因**：提及文字由 `TextSpan` 的 `TapGestureRecognizer` 单独处理导航，不经过 Material 水波纹的全局按下反馈。**修复与回归点**：在提及点击回调中调用 `HapticFeedbackUtil.light()`，复用触感开关、冷却与同手势去重；针对正文提及点击验证主页回调和单次轻触，话题、链接及普通文本不改变。

## 文档维护

修复完成后，将当前行为写入 `DEVELOPMENT.md`，版本和当次验证写入 `CHANGELOG.md`，可复用的根因及回归点写在本文件；顶栏规范变更还要维护 `FROSTED_TOP_BAR_DESIGN_SPEC.md`。运行同步脚本，将这些当前文档的完整正文汇入 `D:\App\开发文档\Review.md`，不能只保留索引链接。旧版综合手册原件留在仓库归档目录、不再拼进现行主文档；签名口令、Cookie、Token 等凭据不进入任何开发文档。
