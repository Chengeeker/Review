<div align="center">

# 🌟 Review

**一款基于 Flutter 打造的现代化、极简的第三方动态资讯与信息流客户端**

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Material You](https://img.shields.io/badge/Material%20Design-3.0-7B1FA2?logo=material-design&logoColor=white)](https://m3.material.io/)
[![Platform](https://img.shields.io/badge/Platform-Android%20(arm64--v8a)-3DDC84?logo=android&logoColor=white)](https://github.com/Chengeeker/Review)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

*专为追求极致流畅体验、纯粹阅读质感与细腻交互的 Android 用户打造。*

---

</div>

## 🌟 核心特性与设计亮点

### 🚫 1. 纯净极简，告别一切干扰
- **纯粹关注流**：直连原生关注流与自定义分组接口，按时间线真实呈现动态内容，告别混乱推荐算法以及信息流商业推广。
- **60% 进度双通道静默预加载**：当浏览进度达到 60% 或视口距底部小于 1500dp（且渲染至倒数第 8 条）时，后台自动静默拉取下一批内容，消除滑动到底部的白屏与等待停顿。

### 👆 2. 细腻手势与触感反馈
- **单击时间线位置记忆**：深入阅读动态时，单击底栏“时间线”平滑回到顶部；在顶部再次单击，精准平滑返回刚刚阅读的那篇文章原位置。
- **双击时间线回顶刷新**：连续双击底栏“时间线”，直接平滑回到顶部并触发时间线刷新。
- **双击顶栏交互**：第一次双击顶栏空白处/标题平滑回到顶部，第二次双击直接触发界面刷新。
- **物理级实时跟手震动**：点一下震一下，连点两下连震两下，震动反馈与手指敲击 1:1 同步，40ms 极低防抖阈值保障快速连击响应。

### 🎨 3. Material Design 3 动态设计与个性化定制
- **精巧悬浮胶囊底栏**：完美遵循 MD3 规范设计的紧凑型悬浮胶囊底栏与原生全宽底栏自适应切换。
- **系统壁纸动态取色**：完美适配 Android 12+ 动态取色（Monet Palette），界面色彩随系统壁纸实时律动。
- **多款精选主题色**：内置莫兰迪多色预设、深色/浅色自适应切换以及专为 OLED/AMOLED 屏幕优化的纯黑模式。
- **排版与卡片自由度**：支持卡片圆角/扁平磁贴风格切换、字体大小/行高缩放、IP属地显示开关、智能相对时间等数十项视觉微调。

### 📸 4. Live Photo 原生实况播放与保存
- **实况数据深度解析**：支持 `type: livephoto` 自动提取底层短视频流与封面，提供专属同心圆 `LIVE` 胶囊标识。
- **全屏画廊无缝循环播放**：画廊支持点击与长按切换实况视频重叠循环播放，支持一键保存高清静态大图、Live 视频动图或全部导出至系统相册。

### 🛡️ 5. 安全防护与防御性网络机制
- **数据导出严格白名单安全防护**：`StorageService.exportAllData` 采用显式白名单，备份时**绝不导出 Cookie、Access Token 与 WebDAV 密码**，杜绝文件外泄安全隐患。
- **Dio 401/432 防死循环重试**：网络拦截器加入 `is_retried` 保护，鉴权失效时**严格限制最多只重试 1 次**，彻底消除递归死循环风险。
- **免密访客引擎 (`VisitorTokenEngine`)**：模拟标准 Web 浏览器环境指纹，未登录状态下秒级生成有效访问凭据，畅享全网热门动态与实时榜单。
- **WebDAV 私有云同步**：支持标准 WebDAV 协议的配置与历史备份恢复，数据完全归属于用户自身。

---

## 🏗️ 架构与项目结构

详细架构说明与开发者指南请参阅 [DEVELOPMENT.md](DEVELOPMENT.md)。

```
lib/
├── core/                         # 全局核心基础库
│   ├── auth/                     # 认证与登录状态管理 (AuthProvider)
│   ├── constants/                # 全局常量与原生 API 端点 (ApiConstants)
│   ├── network/                  # 网络请求与访客引擎 (DioClient, VisitorTokenEngine)
│   ├── services/                 # WebDAV 备份与存储服务 (WebDavService, StorageService)
│   ├── theme/                    # 主题、排版与样式管理 (ThemeProvider, CardDisplayProvider)
│   ├── utils/                    # 文本解析、时间格式化、触感震动与弹性路由工具
│   └── widgets/                  # 全局通用组件 (AppAvatar)
├── features/                     # 功能模块 (Feature-First 架构)
│   ├── auth/                     # 登录界面与凭据验证
│   ├── compose/                  # 发布文章与表情键盘
│   ├── detail/                   # 文章详情、双层评论与全屏画廊
│   ├── drawer_features/          # 侧边栏功能 (浏览历史、收藏、关注话题等)
│   ├── feed/                     # 时间线信息流、分组切换与静默预加载 (FeedController)
│   ├── home/                     # 主框架 (MainScaffold, NavigationBar, AppDrawer)
│   ├── profile/                  # 用户个人主页、动态、相册与视频瀑布流
│   ├── search/                   # 实时热搜榜单与关键词搜索
│   └── settings/                 # 应用设置、存储管理与 WebDAV 备份
└── main.dart                     # 应用程序入口
```

---

## 🚀 编译与构建指南

### 1. 环境要求
- **操作系统**: Android（目标架构：`arm64-v8a`）
- **Flutter SDK**: `>= 3.24.0`
- **Dart SDK**: `>= 3.5.0`
- **JDK**: `17`
- **Android Gradle Plugin (AGP)**: `8.x`

### 2. 获取代码与安装依赖
```bash
flutter pub get
```

### 3. 运行单元测试套件
```bash
flutter test
```

### 4. 编译 Release 正式版 APK (`arm64-v8a` 架构)
```bash
flutter build apk --release --target-platform android-arm64 --android-skip-build-dependency-validation
```

编译成功后，生成的 Android `arm64-v8a` 架构安装包按“应用名+版本名”自动命名保存于项目根目录下（如 `Review_v1.4.apk`）。

---

## 🔒 隐私与免责声明

1. **隐私安全**：本应用为开源第三方客户端，所有登录凭据与配置数据均仅保存在用户本地设备沙盒或用户指定的私有 WebDAV 云端，绝不收集或上传任何个人隐私数据。
2. **免责声明**：本项目仅供编程学习与个人技术交流使用，所有平台内容与多媒体资源版权均归原平台所有。请勿用于商业用途。
