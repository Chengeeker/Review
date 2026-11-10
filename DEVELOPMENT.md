# 构建与验证

仓库根目录是 Review 的 Gradle 工程，应用模块位于 `app/`。使用 JDK 21、Android SDK 37.2 和 Build Tools 37.0.0。将 SDK 目录写入本机 `local.properties` 或设置 `ANDROID_HOME`。

## 源码检查

Windows 在仓库根目录运行以下命令。其他系统使用 `./gradlew`。

```powershell
.\gradlew.bat :app:testDebugUnitTest :app:lintRelease
```

测试涵盖内容解析、请求与状态处理，以及 Compose 页面交互。实际屏幕亮度、触感和服务会话另行验证。

## 签名安装包

正式安装包使用原签名证书。将本机签名配置保存为根目录的 `key.properties`，也可以用 `REVIEW_KEY_PROPERTIES` 指定配置文件。配置包含 `storeFile`、`storePassword`、`keyAlias` 和 `keyPassword`。相对密钥路径以签名配置文件所在目录为准。

Windows 安装 Python 3 并设置 `ANDROID_HOME` 后运行 `.\build.ps1`。脚本构建 ARM64 Release APK，运行测试和 Lint，核对应用标识、版本、签名、原生库架构、16 KiB 对齐和 ZIP 完整性，再复制为 `Review_v<版本>.apk`。

签名配置、私钥、构建输出和内部开发记录均保存在本机。
