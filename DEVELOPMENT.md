# 📘 Review 开发与技术架构文档

本文档旨在为 **Review** 项目的开发者提供完整的技术架构、核心业务流程、网络通道设计、状态管理范式以及手势与动效规范说明。

---

## 目录

1. [技术栈与选型](#1-技术栈与选型)
2. [项目目录结构](#2-项目目录结构)
3. [状态管理架构 (Riverpod 2.x)](#3-状态管理架构-riverpod-2x)
4. [时间线与原生网络通道设计](#4-时间线与原生网络通道设计)
   - 4.1 游标分片分页机制 (Cursor Sharding)
   - 4.2 双通道静默预加载引擎 (Dual-Channel Preloading)
   - 4.3 关系流与原生接口矩阵
5. [交互手势、悬浮底栏与物理触感引擎](#5-交互手势悬浮底栏与物理触感引擎)
   - 5.1 MD3 Expressive 悬浮胶囊底栏与纯净切换动效
   - 5.2 时间线底栏交互 (单击原位穿梭 / 双击回顶刷新)
   - 5.3 顶栏交互 (双击回顶 / 二次刷新)
   - 5.4 物理级 1:1 跟手震动 (HapticSplashFactory)
6. [多媒体与 Live Photo 引擎](#6-多媒体与-live-photo-引擎)
7. [安全性与防御性网络机制](#7-安全性与防御性网络机制)
8. [测试与构建规范](#8-测试与构建规范)

---

## 1. 技术栈与选型

- **核心框架**: Flutter 3.x / Dart 3.x (目标平台：Android `arm64-v8a`)
- **状态管理**: `flutter_riverpod: ^2.5.1` (StateNotifier, Provider)
- **网络通信**: `dio: ^5.7.0` (原生拦截器、Cookie 管理、CSRF 动态注入)
- **UI & 动效规范**: Material Design 3 Expressive (Material You / Monet 动态取色) + 物理弹簧阻尼转场
- **滚动与刷新**: `easy_refresh: ^3.4.0` + `CustomScrollView` + `SliverList`
- **本地存储**: `shared_preferences: ^2.3.2` (显式白名单导出防护)
- **私有云同步**: `webdav_client: ^1.2.3`

---

## 2. 项目目录结构

项目采用 **Feature-First (按功能特性划分)** 架构，保持高内聚低耦合：

```
lib/
├── core/                                 # 全局核心基础库
│   ├── auth/                             # 认证提供者 (auth_provider.dart)
│   ├── constants/                        # 原生 API 常量 (api_constants.dart)
│   ├── network/                          # 网络引擎 (weibo_dio_client.dart, visitor_token_engine.dart)
│   ├── services/                         # 存储与 WebDAV (storage_service.dart, webdav_service.dart)
│   ├── theme/                            # 主题与排版 (theme_provider.dart, card_display_provider.dart)
│   ├── utils/                            # 工具库 (haptic_feedback_util.dart, weibo_text_parser.dart, spring_page_route.dart)
│   └── widgets/                          # 通用原子组件 (app_avatar.dart)
├── features/                             # 业务功能模块
│   ├── auth/                             # 登录模块 (Webview 抓包与 Cookie 凭据解析)
│   ├── compose/                          # 发布微博 (文本、图片上传、表情键盘)
│   ├── detail/                           # 微博正文详情 (双层树状评论结构、转发列表)
│   ├── drawer_features/                  # 侧边栏子模块 (浏览历史、收藏夹、关注话题、我的好友)
│   ├── feed/                             # 核心时间线 (feed_controller.dart, feed_view.dart, tweet_card.dart)
│   ├── home/                             # 主框架 (main_scaffold.dart, app_drawer.dart)
│   ├── profile/                          # 个人主页 (用户主页、相册瀑布流、视频网格)
│   ├── search/                           # 发现与搜索 (热搜榜单、实时联想搜索)
│   └── settings/                         # 综合设置 (外观个性化、存储与备份、关于)
└── main.dart                             # 应用程序主入口
```

---

## 3. 状态管理架构 (Riverpod 2.x)

```
                     ┌───────────────────────────┐
                     │     ThemeStateNotifier    │
                     │  (主题色系、悬浮底栏样式)  │
                     └─────────────┬─────────────┘
                                   │
                                   ▼
┌─────────────────────────┐  ┌─────────────┐  ┌─────────────────────────┐
│     FeedStateNotifier   │◄─┤ MainScaffold├─►│    AuthStateNotifier    │
│ (时间线流、游标、分组)  │  └─────────────┘  │ (UID、Cookie、登录状态) │
└────────────┬────────────┘                   └─────────────────────────┘
             │
             ▼
┌─────────────────────────┐
│    TimelineScrollNotifier│ (单击原位穿梭 / 双击回顶刷新 / 顶栏双击调度)
└─────────────────────────┘
```

---

## 4. 时间线与原生网络通道设计

### 4.1 游标分片分页机制 (Cursor Sharding)

针对微博原生后端的流式数据结构，时间线采用 `max_id` 分片游标机制实现无限滚动：

- **端点**: `/ajax/feed/friendstimeline` (全部关注)
- **分页参数规则**:
  - 首页刷新：`list_id: '10001'`, `refresh: 0`, `page: 1`，从响应中提取最新全局游标 `max_id`；
  - 向下加载更多：`list_id: '10001'`, `refresh: 4`, `max_id: state.maxId`, `page: state.page + 1`；
  - **关键原则**：向下加载更多时**严禁携带 `since_id`**，确保服务端沿 `max_id` 游标向历史数据深度遍历，彻底解决加载 10~20 条即截断空白的问题。

### 4.2 双通道静默预加载引擎 (Dual-Channel Preloading)

为实现极致丝滑的“无限瀑布流”体验，应用内置双通道前置预取：

1. **视口滚动进度检测 (60% 深度阈值 / 剩余 1500dp)**：
   在 `CustomScrollView` 外层通过 `NotificationListener<ScrollNotification>` 监听滑移进度，当滑移超过 60% 深度或距底部不足 1500dp 时自动在后台拉取下一页。
2. **列表构建索引双保险 (倒数第 8 条)**：
   在 `SliverChildBuilderDelegate` 中，当 `index >= feedState.statuses.length - 8` 时，利用 `WidgetsBinding.instance.addPostFrameCallback` 在下一帧静默预拉取下一页。

### 4.3 关系流与原生接口矩阵

- **关注用户**: `POST /ajax/friendships/create` (携带 `uid`, `st`, `Referer: https://weibo.com/u/{uid}`)
- **取消关注**: `POST /ajax/friendships/destory` (注意微博原生历史拼写为 `destory`，返回 `{"ok": 1}`)
- **博主主页时间线**: `GET /ajax/statuses/mymblog?uid={uid}&page={page}&feature=0`

---

## 5. 交互手势、悬浮底栏与物理触感引擎

### 5.1 MD3 Expressive 悬浮胶囊底栏与纯净切换动效

- **全列圆角胶囊容器**：选中项采用 `borderRadius: BorderRadius.circular(28)` 的大圆角容器，**将当前项的图标与文字标签完整包裹在内**；
- **纯净即时切换动效**：
  - 点击切换 Tab 时，**原选中位置的胶囊容器立即销毁不残留**，彻底杜绝跨位置插值导致的反色闪烁与残影；
  - **新选中位置的胶囊容器平滑淡入**（`160ms`，`Curves.easeOutCubic`），动效干净利落、纯净自然；
  - 彻底清除 `InkWell` 在切换时的额外深色 splash 叠加干扰，保证背景色彩纯净一致。

### 5.2 时间线底栏交互 (MainScaffold)

- **单击时间线**：
  - 当前浏览深度 > 50dp 时：记录当前浏览文章的绝对位置 `_lastSavedOffset = offset`，平滑缓动回到顶部（`0.0`）；
  - 当前处于顶部（offset <= 50dp）且存在历史记录时：再次单击直接平滑返回 `_lastSavedOffset` 原位置；
- **双击时间线**：
  - 连续两次快速点击（<= 300ms）：直接飞跃回顶部，并异步触发 `refreshFeed()` 全量刷新。

### 5.3 顶栏交互 (FeedView AppBar)

- **第一次双击顶栏**：深入浏览时双击顶栏空白/标题区域，平滑回到顶部；
- **第二次双击顶栏**：当前已在顶部时，再次双击直接触发时间线刷新。

### 5.4 物理级 1:1 跟手震动 (HapticSplashFactory)

- **设计原则**：点一下严格震一下，连点两下严格连震两下，震动触发与手指触控屏幕瞬间 1:1 实时同步；
- **单通道物理触控驱动**：由全局 `HapticSplashFactory` 在手指按下的瞬时单通道触发，移除所有业务回调中的冗余二次调用；
- **微秒级防抖响应**：防抖冷却阈值设为 `40ms`（仅过滤硬件电气抖动），确保快速双击时每一次敲击都能得到干脆清脆的物理触感反馈。

---

## 6. 多媒体与 Live Photo 引擎

- **实况图识别与解析**：`WeiboPicModel.fromJson` 自动识别 `type: "livephoto"`，解析 `video` 字段中的底层视频流及 `fid`；
- **全屏手势画廊 (`ImageGalleryPage`)**：
  - 支持多点触控缩放、双击放大与下拉弹性拖拽返回（`PhysicsSpringGalleryRoute`）；
  - 实况图提供长按循环重叠播放短视频流，松手自动还原高清静态帧；
  - 支持一键导出高清原图、Live 短视频或合并保存到 Android 系统相册。

---

## 7. 安全性与防御性网络机制

1. **配置与数据备份显式白名单 (`StorageService.exportAllData`)**：
   - 采用严格键名白名单机制，**Cookie、Token、WebDAV 密码等敏感认证字段严禁进入导出 JSON**，彻底杜绝备份文件外泄导致的账户安全风险。
2. **Dio 401/432 防死循环重试拦截**：
   - 在 `WeiboDioClient` 中设置 `is_retried` 标记位，鉴权失效时严格限制最多重试 1 次，杜绝递归无限请求耗尽设备资源。
3. **免密访客引擎 (`VisitorTokenEngine`)**：
   - 模拟标准 Chrome 浏览器指纹，在未登录状态下自动获取临时访客 Sub Token，保证热门动态与榜单正常浏览。

---

## 8. 测试与构建规范

### 8.1 单元测试套件

运行完整测试套件：
```bash
flutter test
```
包含 22 项覆盖全面的单元测试：
- `test/models_test.dart`: 模型序列化、Live Photo 提取、双层评论解析、白名单安全防护测试；
- `test/text_parser_test.dart`: 微博富文本、@超链接、#话题、原生表情符号正则解析测试；
- `test/time_formatter_test.dart`: 相对时间（刚刚、X分钟前、昨天、具体日期）格式化测试；
- `test/widget_test.dart`: `TweetCard` 渲染、长文展开与操作栏交互测试。

### 8.2 正式版打包

```powershell
# 编译 Android arm64-v8a Release APK
& "D:\flutter_sdk\bin\flutter.bat" build apk --target-platform android-arm64 --release --no-tree-shake-icons --android-skip-build-dependency-validation
Copy-Item -Path "D:\App\Review\build\app\outputs\flutter-apk\app-release.apk" -Destination "D:\App\Review\Review_arm64-v8a.apk" -Force
```
打包交付物：`D:\App\Review\Review_arm64-v8a.apk`。
