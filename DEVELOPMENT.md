# Review 开发指南

Review 是使用 Flutter 构建的 Android 动态阅读与信息流应用。本文档面向公开仓库，仅记录通用工程结构、构建步骤和验证边界。

## 公开内容约束

- README、文档、提交信息及其他公开说明使用真实、中性的功能描述，不标注上游社交平台名称、客户端归属或信息源关系。
- 保留运行必需的源码标识、接口地址、文件名和 JNI 包名，不为文案调整破坏功能。
- 完整技术记录直接维护在本地统一文档内，不再拆分主题源目录或运行拼接脚本；公开文档独立维护，不能直接用内部资料覆盖。
- 上传前检查公开材料正文、链接、文件名和截图文字；遵循根目录 `AGENTS.md`。

## 当前版本

当前源码为 `3.14.13+251`，应用 ID 为 `com.review`，Android 仅交付 `arm64-v8a` 正式安装包。版本以 `pubspec.yaml`、应用版本常量、Android 构建配置和最终 APK 元数据共同核验。

## 工程结构

- `lib/core/`：认证、网络、持久化、主题、通用组件与工具。
- `lib/features/`：信息流、详情、搜索、发布、个人资料、消息和设置。
- `android/app/`：Android 主工程、平台通道与原生能力。
- `test/`：模型、网络、状态、布局、手势与备份回归。
- `packages/liquid_glass_widgets/`：当前使用的局部玻璃材质组件。

## 开发环境

以 `pubspec.yaml` 与锁文件为准：Flutter >= 3.47.0、Dart >= 3.13.0，Android 构建使用 JDK 17。依赖版本由 `pubspec.lock` 固定；升级依赖需单独审查锁文件变化。

```powershell
flutter pub get
flutter test --no-pub
```

## 10.2 Release APK

继续使用现有包名和正式签名，保留回退包；不另建测试包名或测试签名。签名从被 Git 忽略的 `android/key.properties` 与本地密钥读取，不提交凭据、密钥或安装包。

```powershell
flutter build apk --release --target-platform android-arm64 --no-tree-shake-icons --android-skip-build-dependency-validation --no-pub
```

`android/gradle.properties` 保持 `disable-abi-filtering=true`，并由 app 显式限制 `arm64-v8a`，避免插件重新启用其他架构。

JDK 若出现临时目录 loopback 管道错误，先配置 JDK 17 的 `JAVA_HOME`，再使用项目内临时目录：

```powershell
$taskJavaHome = $env:JAVA_HOME
if (-not $taskJavaHome) { throw '请先配置 JDK 17 的 JAVA_HOME' }
$taskTempDir = Join-Path (Get-Location) 'build\.jvm-temp'
New-Item -ItemType Directory -Path $taskTempDir -Force | Out-Null
$env:JAVA_HOME = $taskJavaHome
$env:TEMP = $taskTempDir
$env:TMP = $taskTempDir
$env:JAVA_TOOL_OPTIONS = "-Djdk.net.unixdomain.tmpdir=$taskTempDir"
$env:Path = "$taskJavaHome\bin;$env:Path"
```

若已确认阻塞于远程依赖且本地缓存齐全，可使用离线构建，不改变锁文件：

```powershell
android/gradlew.bat -p android --offline assembleRelease '-Ptarget-platform=android-arm64' '-Ptarget=lib/main.dart' '-Ptree-shake-icons=false' '-Pdart-obfuscation=false'
```

Flutter 原始产物通常位于 `build/app/outputs/flutter-apk/app-release.apk`；直接使用 Gradle 构建时位于 `build/app/outputs/apk/release/app-release.apk`。核验包名、版本、唯一 ABI、正式签名和 ZIP 对齐后，将交付包命名为 `Review_v<版本名>.apk`，计算 SHA-256。项目根目录只保留当前交付包，回退包保存在 `build/previous-deliveries/`，不能为清理缓存删除该目录。

项目目录清理仅删除确认可重建的编译、测试和插件产物，以及已核对内容相同的重复二进制。保留源码、未提交修改、依赖锁文件、包配置、签名、当前安装包、回退包与复盘资料；不递归清空整个 `build/`，不跟随目录链接。清理后首次编译或测试会重建缓存，耗时可能增加。仅整理目录不修改应用版本，也不为清理重新打包。

## 数据与备份

- 默认安全备份保存设置、浏览历史与屏蔽列表等普通数据，排除登录凭据和 WebDAV 密码。
- 用户选择全量备份时会包含敏感凭据与 Android 原生会话的可迁移字段；JSON 文件含明文凭据，用户需保护云盘与历史文件。
- 恢复前校验格式、字段类型与账号一致性；原生会话重新加密保存，避免混入旧账号状态。
- 切回安全备份不会删除此前的全量历史副本。图片、视频缓存及远程内容不属于设置备份。

## 验证与交付边界

执行与改动相关的回归、必要静态分析和 `git diff --check`。公开记录须区分自动化测试、构建与静态包检查，以及真实设备、账号、视觉、播放和云盘验收；不能以构建通过代替实际使用验收。

- [变更记录](docs/CHANGELOG.md)
- [工程复盘](docs/RETROSPECTIVE.md)
- [磨砂顶栏规范](docs/FROSTED_TOP_BAR_DESIGN_SPEC.md)
- [UI 复用规范](docs/REVIEW_UI_REUSE_SPEC.md)
- [画廊滑动指南](docs/IMAGE_GALLERY_SWIPE_PERFORMANCE_GUIDE.md)
