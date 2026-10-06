# Review 变更记录

这里记录已经完成的版本变更及当次验证结果。当前行为和发布命令以 [DEVELOPMENT.md](../DEVELOPMENT.md) 为准；历史测试数量不代表以后构建的测试结果。更早、更细的实施记录保存在[旧手册归档](archive/Review-legacy-2026-09-23.md)。

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
