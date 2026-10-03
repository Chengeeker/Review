# Review 旧版综合手册归档（截至 2026-09-23）

> 本文件保留旧手册的历史描述，目录和 4.30–4.32 等编号存在重复，若干修复建议已被后续章节推翻。请从 D:\App\开发文档\Review.md 进入当前文档；本归档不能作为现行规范。原文件中的签名敏感材料已移除。

---

# Review 核心架构与全功能开发/配置自愈权威手册

> **文档定位**：本手册为 Review（Material 3 现代化极简动态资讯与信息流客户端）的权威技术说明书、接口规范与全功能复原指南。用于全面记录核心业务逻辑、网络请求签名规则、各频道数据路由、UI交互规范、高级特性实现机制，以及在后续迭代中发生任何异常时的**绝对自检与自愈指引**。

---

## 目录
1. [项目概览与关键环境参数](#1-项目概览与关键环境参数)
2. [核心防错铁律与接口抓包原则（必读）](#2-核心防错铁律与接口抓包原则必读)
3. [频道与核心接口路由技术规范](#3-频道与核心接口路由技术规范)
   - [3.1 “关注”频道（纯关注博主时间线）](#31-关注频道纯关注博主时间线)
   - [3.2 “特别关注”与用户自定义分组](#32-特别关注与用户自定义分组)
   - [3.3 分组列表全量拉取与系统冗余过滤 (`allGroups`)](#33-分组列表全量拉取与系统冗余过滤-allgroups)
   - [3.4 全网热门与公共分类频道](#34-全网热门与公共分类频道)
   - [3.5 微博详情与嵌套评论流](#35-微博详情与嵌套评论流)
   - [3.6 微博发布、编辑替换与删除机制](#36-微博发布编辑替换与删除机制)
   - [3.7 账号鉴权与多通道 UID 自动提取](#37-账号鉴权与多通道-uid-自动提取)
   - [3.8 实时热搜与内容搜索](#38-实时热搜与内容搜索)
   - [3.9 关注与取消关注原生纯净接口矩阵](#39-关注与取消关注原生纯净接口矩阵)
4. [核心功能特性与 UI 交互实现细节](#4-核心功能特性与-ui-交互实现细节)
   - [4.1 微博卡片时间格式化与全自由个性化显示体系](#41-微博卡片时间格式化与全自由个性化显示体系)
   - [4.2 语言与本地化体系 (默认纯中文)](#42-语言与本地化体系-默认纯中文)
   - [4.3 全局交互与触感震动反馈体系](#43-全局交互与触感震动反馈体系)
   - [4.4 导航布局风格与悬浮胶囊底栏 (MD3 Expressive)](#44-导航布局风格与悬浮胶囊底栏-md3-expressive)
   - [4.5 顶部时间线下拉分组面板与分组管理系统](#45-顶部时间线下拉分组面板与分组管理系统)
   - [4.6 发微博与真·编辑替换机制](#46-发微博与真编辑替换机制)
   - [4.7 微博卡片与详情页全套操作管理](#47-微博卡片与详情页全套操作管理)
   - [4.8 微博样式个性化系统 (`WeiboStyleSettingsPage`)](#48-微博样式个性化系统-weibostylesettingspage)
   - [4.9 微博正文表情图形化 Emoji 渲染引擎 (全量收录)](#49-微博正文表情图形化-emoji-渲染引擎-全量收录)
   - [4.10 微博详情页与发表评论 / 楼中楼回复全流程](#410-微博详情页与发表评论--楼中楼回复全流程)
   - [4.11 微博相片九宫格经典纯净淡入淡出 (Fade Transition) 过渡系统](#411-微博相片九宫格经典纯净淡入淡出-fade-transition-过渡系统)
   - [4.12 纯净独立微博热搜大厅 (`HotTrendsView`)](#412-纯净独立微博热搜大厅-hottrendsview)
   - [4.13 独立搜索落地页与实时联想/用户直达系统 (`SearchView`)](#413-独立搜索落地页与实时联想用户直达系统-searchview)
   - [4.14 微博全景搜索结果页与 12 大分类顶栏 (`SearchResultsPage`)](#414-微博全景搜索结果页与-12-大分类顶栏-searchresultspage)
   - [4.15 纯粹系统设置大厅 (`SettingsView` - 主底栏第 3 个 Tab)](#415-纯粹系统设置大厅-settingsview---主底栏第-3-个-tab)
   - [4.16 顶栏侧边栏入口与个人大厅 (`AppDrawer` - 精简纯净版)](#416-顶栏侧边栏入口与个人大厅-appdrawer---精简纯净版)
   - [4.17 图片与视频相册直存与多级目录存储规则](#417-图片与视频相册直存与多级目录存储规则)
   - [4.18 导出账号凭据与 Cookie 复制系统](#418-导出账号凭据与-cookie-复制系统)
   - [4.19 WebDAV 云端全量备份与跨设备恢复机制](#419-webdav-云端全量备份与跨设备恢复机制)
   - [4.20 物理弹簧阻尼转场与全局触感系统](#420-物理弹簧阻尼转场与全局触感系统)
   - [4.21 微博 Live 实况图原生解析与动态播放系统](#421-微博-live-实况图原生解析与动态播放系统)
   - [4.22 发微博编辑页结构精细化重构](#422-发微博编辑页结构精细化重构)
   - [4.23 个人主页多维分栏体系与 2 列瀑布流视频卡片 (`UserProfilePage`)](#423-个人主页多维分栏体系与-2-列瀑布流视频卡片-userprofilepage)
   - [4.24 超长截图/长图全屏触控与平滑双击缓动缩放 (`ImageGalleryPage`)](#424-超长截图长图全屏触控与平滑双击缓动缩放-imagegallerypage)
   - [4.25 评论区原生图片渲染与全场景智能链接识别体系](#425-评论区原生图片渲染与全场景智能链接识别体系)
   - [4.26 发微博多图图床上传与定位参数体系 (`ComposeTweetPage`)](#426-发微博多图图床上传与定位参数体系-composetweetpage)
   - [4.27 游标分片分页与双通道 60% 静默预加载引擎](#427-游标分片分页与双通道-60-静默预加载引擎)
   - [4.28 时间线底栏交互与双向原位穿梭机制](#428-时间线底栏交互与双向原位穿梭机制)
   - [4.29 物理级 1:1 实时跟手触感震动系统](#429-物理级-11-实时跟手触感震动系统)
   - [4.30 屏幕帧率与分辨率独立控制系统 (`ScreenRefreshRatePage`)](#430-屏幕帧率与分辨率独立控制系统-screenrefreshratepage)
   - [4.31 深度链接原生拦截与直达系统 (`LinkRoutingService`)](#431-深度链接原生拦截与直达系统-linkroutingservice)
   - [4.32 全功能内置浏览器与杜绝 404 机制 (`InAppBrowserPage`)](#432-全功能内置浏览器与杜绝-404-机制-inappbrowserpage)
   - [4.33 文章正文与多级评论长按划词自由复制系统](#433-文章正文与多级评论长按划词自由复制系统)
   - [4.34 视频播放器全能加速与清晰度无缝切换系统 (`WeiboVideoPlayerPage`)](#434-视频播放器全能加速与清晰度无缝切换系统-weibovideoplayerpage)
   - [4.35 微博卡片长按唤起操作面板与快捷取关博主机制](#435-微博卡片长按唤起操作面板与快捷取关博主机制)
   - [4.36 自定义应用字体粗细弹窗系统 (5 档精细调节)](#436-自定义应用字体粗细弹窗系统-5-档精细调节)
   - [4.37 官方预设应用图标切换与全场景资源同步系统 (`CustomAppIconPage`)](#437-官方预设应用图标切换与系统状态双向自同步系统-customappiconpage)
   - [4.38 搜索多维结果流与官方 1:1 原生大搜体系 (`SearchResultsPage` & `s.weibo.com` 原生直连)](#438-搜索多维结果流与官方-11-原生大搜体系-searchresultspage--sweibocom-原生直连)
   - [4.39 微博博文编辑记录查看系统 (`EditHistoryBottomSheet` 与 `/ajax/statuses/editHistory` 原生直连)](#439-微博博文编辑记录查看系统-edithistorybottomsheet-与-ajaxstatusesedithistory-原生直连)
   - [4.40 Material 3 Expressive (M3e) 全局视觉体系与触觉动效升级](#440-material-3-expressive-m3e-全局视觉体系与触觉动效升级)
   - [4.45 图片画廊横向分页与斜向手势隔离修复 (`ImageGalleryPage`)](#445-图片画廊横向分页与斜向手势隔离修复-imagegallerypage)
   - [4.46 发出的评论直达、置顶与官方游标分页修复 (`LikesCommentsPage` / `StatusDetailPage`)](#446-发出的评论直达置顶与官方游标分页修复-likescommentspage--statusdetailpage)
   - [4.47 微博直播动态官方状态识别与播放器自愈修复](#447-微博直播动态官方状态识别与播放器自愈修复)
   - [4.48 登录 Cookie 域隔离与时间线空态自愈修复](#448-登录-cookie-域隔离与时间线空态自愈修复)
   - [4.49 高评论量微博评论官方续页参数修复](#449-高评论量微博评论官方续页参数修复)
   - [4.50 深度文章 HTTPS 链接与个人主页头像预览修复](#450-深度文章-https-链接与个人主页头像预览修复)
   - [4.51 微博深度文章原生渲染、返回键与外部浏览器修复](#451-微博深度文章原生渲染返回键与外部浏览器修复)
   - [4.52 深度文章 HTML 请求隔离与登录态兜底修复](#452-深度文章-html-请求隔离与登录态兜底修复)
   - [4.53 深度文章短链接解析与多会话响应选择修复](#453-深度文章短链接解析与多会话响应选择修复)
   - [4.54 自定义图标深色适配资源更新](#454-自定义图标深色适配资源更新)
   - [4.55 自定义图标第二版素材微调](#455-自定义图标第二版素材微调)
   - [4.56 升级后 Cookie 分域迁移与时间线会话修复](#456-升级后-cookie-分域迁移与时间线会话修复)
   - [4.57 凭据检测多候选验证与官方响应兼容修复](#457-凭据检测多候选验证与官方响应兼容修复)
   - [4.58 网页端登录闭环、自动同步凭据与多级校验自愈](#458-网页端登录闭环自动同步凭据与多级校验自愈)
   - [4.59 登录检测超时取消与手动重试可靠性修复](#459-登录检测超时取消与手动重试可靠性修复)
5. [网络层与安全鉴权体系](#5-网络层与安全鉴权体系)
6. [Android 原生工程与签名打包规范](#6-android-原生工程与签名打包规范)
7. [故障排查与自愈自检清单 (CheckList)](#7-故障排查与自愈自检清单-checklist)

---

## 1. 项目概览与关键环境参数

- **项目名称**：`Review`（**重要规则：Review 不要翻译成中文**）
- **开发框架**：Flutter 3.x / Dart 3.x (Material 3 + Riverpod 状态管理)
- **应用包名 (Application ID)**：`com.review`
- **应用版本基线 (Version)**：当前版本为 `2.9.0`（`pubspec.yaml`：`2.9.0+76`；当前 Android `versionCode`：`76`；应用内版本显示由 `ApiConstants` 集中维护）。
- **版本号规则**：采用三段式 `MAJOR.MINOR.PATCH`。功能更新提升 `MINOR` 并将 `PATCH` 归零（例如 `1.7.0 -> 1.8.0`）；Bug 修复提升 `PATCH`（例如 `1.7.0 -> 1.7.1`）；从 `1.7.1` 推送功能更新时直接变为 `1.8.0`，不使用 `1.7.2`。每次发布时 `versionCode` 正常加 1。
- **版本显示同步铁律**：每次版本号变动都必须同步检查并更新 `pubspec.yaml`、`android/app/build.gradle.kts` 中的 `versionName` / `versionCode`、`lib/core/constants/api_constants.dart` 中的 `appVersion` / `appVersionCode`，以及设置页“关于 Review”的版本显示；上述信息必须一致后才能构建发布包。APK 文件按 `Review_v{完整版本名}.apk` 命名（如 `Review_v2.8.8.apk`）。
- **签名材料**：原手册在此处包含本地敏感凭据，归档时已移除。签名方式以当前开发文档为准。
- **本地源码仓库**：`D:\App\Review`
- **GitHub 远程仓库**：`https://github.com/Chengeeker/Review`
- **唯一输出产物路径**：`D:\App\Review\Review_v2.9.0.apk`（**重要规则：所有编译生成的正式安装包必须直接放置在项目根目录 `D:\App\Review\`，严禁仅保留在 `build/app/outputs/flutter-apk/` 深层目录让用户寻找；且项目根目录下严格只保留当前最新版本唯一单个正式安装包**）
- **Git 提交铁律**：**Git commit 提交信息统一严格为 `"update"`**。

---

## 2. 核心防错铁律与接口抓包原则（必读）

在后续迭代与维护中，**必须无条件遵守以下铁律**，严禁引入未经验证的猜测逻辑：

> [!IMPORTANT]
> **接口抓包原则**：**必要时，对微博后端所有候选接口进行逐一穷举和实测抓包，务必要找到微博原生后端中真正纯净的接口，并完成功能的精准直连。**
>
> **端侧真机测试铁律**：**测试的时候不要只测试网页能不能正常显示，因为我最终用的是应用而不是网页。有时候网页读出来的效果跟应用实际用的效果是有差距的，一切以应用端为准。最好加入视觉识别来精准定位我说的问题。**
>
> **单包交付与根目录输出铁律**：**编译生成的正式 APK 必须直接放置在项目根目录 `D:\App\Review\`（如 `Review_v2.8.8.apk`），严禁留在 `build/app/outputs/flutter-apk/` 等深层路径让用户寻找。每次编译交付时，仅在项目根目录保留应用名加版本号的单个正式安装包。**
>
> **Git 提交铁律**：**Git commit 提交信息统一严格为 `"update"`。**
>
> **专属架构编译铁律**：**严禁直接编译未限定架构的多架构胖包。必须且只能使用 `flutter build apk --release --target-platform android-arm64` 编译专属 `arm64-v8a` 纯 64 位安装包，包体严格控制在 ~30MB 左右。**
>
> **搜索流原生 1:1 对齐铁律**：**放弃应用自己的筛选、评分加权与改序逻辑，完全沿用微博官方原生内容与排序。它的顺序是怎么样，你就怎么样，只负责做好 UI 适配。严禁自定义冗余的长列表卡片（如“话题关联官方账号”）。**

### 🚫 严禁事项
1. **严禁在“关注”频道调用 `/ajax/feed/unreadfriendstimeline`**：
   - 微博后端的 `unreadfriendstimeline` 是商业化“未读智能推荐流”，微博会强行在其中插入大量未关注博主（`following: false`）、好友点赞、公域热门等内容；
   - 只要调用该接口，“关注”频道就会沦为公共推荐流。
2. **严禁向下加载更多时携带 `since_id`**：
   - 微博原生分页向下加载历史内容时，**只能携带 `max_id` 分片游标，严禁携带 `since_id`**。携带 `since_id` 会导致后端锁定时间窗口，造成刷 10~20 条后出现空白断流的严重 Bug。
3. **严禁缺少专属请求头**：
   - 桌面端 Ajax 接口（`/ajax/feed/*`、`/ajax/statuses/*`）**必须附带 `Referer`、`X-Requested-With: XMLHttpRequest` 以及从 Cookie 自动提取的 `X-XSRF-TOKEN`**，否则会被微博 WAF 直接拦截并返回 `403 Forbidden`。
4. **严禁在分组接口中混淆 GID 路由**：
   - 实体分组（特别关注、vivo、游戏等）走 `groupstimeline`；
   - 主关注流走 `friendstimeline`。
5. **严禁遗漏 `localizationsDelegates` 全局代理**：
   - 必须配置 `GlobalMaterialLocalizations.delegate`、`GlobalWidgetsLocalizations.delegate` 与 `GlobalCupertinoLocalizations.delegate`，确保中文环境下所有 Material 组件均稳定渲染，彻底杜绝崩溃为灰色色块。
6. **严禁一次输出多个 APK 安装包**：
   - 必须严格保留单个应用名加版本号的安装包（`Review_v{version}.apk`）。
7. **严禁编译多架构全量胖包 (Fat APK)**：
   - 必须使用 `flutter build apk --release --target-platform android-arm64` 编译纯 `arm64-v8a` 安装包。
8. **严禁使用除 `update` 以外的 Git commit message**。

---

## 3. 频道与核心接口路由技术规范

### 3.1 “关注”频道（纯关注博主时间线）
- **功能目标**：仅拉取当前登录用户已关注博主的最新微博，纯时间倒序，绝对零公域推荐、零广告。
- **请求方法**：`GET`
- **请求 URL**：`https://weibo.com/ajax/feed/friendstimeline`（⚠️ **注意：不带 `unread` 前缀**）
- **请求头规范 (Headers)**：
  ```http
  Referer: https://weibo.com/
  X-Requested-With: XMLHttpRequest
  X-XSRF-TOKEN: <从 Cookie 中提取的 XSRF-TOKEN>
  User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ...
  ```
- **请求参数 (Query Parameters)**：
  - `list_id`: 固定传入 `'10001'`
  - `refresh`: 首次刷新传入 `0`；向下加载更多页传入 `4`
  - `page`: 分页页码（从 1 开始依次递增）
  - `count`: 单页条数（固定传入 `25`）
  - `max_id`: 滚动分页下一页分片游标（从上一页返回体的 `max_id` 获取）
  - `since_id`: **仅在首页下拉刷新时可选传入最新微博 ID，向下加载更多时绝对不能传递此参数**
- **返回结构与断言**：
  - `response.data['statuses']` 为微博列表；
  - 数据集内所有博主对象的 `user.following` 均为 `true`；
  - 下一页游标：`response.data['max_id']`。

---

### 3.2 “特别关注”与用户自定义分组
- **功能目标**：拉取用户分组（如“特别关注” `4152890832681124`、自定义“vivo” `4837511216240175`、游戏、电影等）内博主的微博。
- **请求方法**：`GET`
- **请求 URL**：`https://weibo.com/ajax/feed/groupstimeline`
- **请求头规范 (Headers)**：
  ```http
  Referer: https://weibo.com/mygroups?gid=<目标GID>
  X-Requested-With: XMLHttpRequest
  X-XSRF-TOKEN: <从 Cookie 中提取的 XSRF-TOKEN>
  ```
- **请求参数 (Query Parameters)**：
  - `list_id`: 目标分组的数值 GID（例如特别关注为 `4152890832681124`）
  - `count`: `25`
  - `max_id`: 分页下一页游标
  - `since_id`: 刷新游标

---

### 3.3 分组列表全量拉取与系统冗余过滤 (`allGroups`)
- **功能目标**：拉取当前登录用户云端创建的所有分组，并过滤掉系统公共冗余项。
- **请求方法**：`GET`
- **请求 URL**：`https://weibo.com/ajax/feed/allGroups`
- **请求头规范 (Headers)**：
  ```http
  Referer: https://weibo.com/
  X-Requested-With: XMLHttpRequest
  X-XSRF-TOKEN: <从 Cookie 中提取的 XSRF-TOKEN>
  ```
- **系统冗余过滤规则**：
  - 遍历 `response.data['groups']` 中的 `item['group']`；
  - 过滤排除以 `10001`（全部关注）、`11000`（最新微博）、`10002`（原创）、`10003`（视频）、`10004`（群微博）、`10008`（互相关注）、`10009`（好友圈）以及 `102803`（热门公共分类）开头的项；
  - 剩下的即为用户真正的云端个人分组（如 `游戏`、`电影`、`vivo`、`名人明星`、`同学`、`同事` 等）。

---

### 3.4 全网热门与公共分类频道
- **功能目标**：浏览全网公开热门内容及同城、搞笑、数码等公共分类。
- **请求方法**：`GET`
- **请求 URL**：`https://m.weibo.cn/api/container/getIndex`
- **请求参数**：
  - `containerid`: 分类 ID（全网热门为 `102803`，其他为 `102803_ctg1_-_ctg1_xxx`）
  - `extparam`: `discover|new_feed`
  - `since_id`: 下一页游标

---

### 3.5 微博详情与嵌套评论/转发/点赞互动矩阵
- **单条微博正文及富文本**：
  - `GET https://weibo.com/ajax/statuses/show?id=<微博MID>`
- **一级评论流（支持按热度与按时间排序）**：
  - 首页：`GET https://weibo.com/ajax/statuses/buildComments?id=<微博MID>&uid=<作者UID>&is_reload=1&is_show_bulletin=2&is_mix=0&count=15&flow=<0:按热度|1:按时间>&max_id_type=0&fetch_level=0&type=1&locale=zh-CN`
  - 后续页：保持 `max_id` 游标，并使用网页端续页参数 `is_reload=0`、`is_mix=1`；若游标为空、为 `0` 或与上一页重复，则停止分页。
  - 解析层兼容官方返回的 `data: [...]` 与 `data: {data/comments/list: [...], max_id: ...}` 两种分页封装，避免把有效评论误判为空。
- **二级嵌套楼中楼回复**：
  - `GET https://weibo.com/ajax/statuses/getSecondComment?flow=0&id=<一级评论CID>&max_id=<游标>&count=20`
- **转发列表（转发名单与转发微博）**：
  - `GET https://weibo.com/ajax/statuses/repostTimeline?id=<微博MID>&page=<页码>&count=20`
- **点赞列表（赞的名单与点赞用户）**：
  - **首选移动端轻量稳定通道**：`GET https://m.weibo.cn/api/attitudes/show?id=<微博MID>&page=<页码>&count=20`
  - **备选桌面端直连通道**：`GET https://weibo.com/ajax/statuses/likeShow?id=<微博MID>&page=<页码>&count=20`
- **直播动态官方状态与播放流解析**：
  - 直播微博正文通常只提供 `https://weibo.com/l/wblive/p/show/<live_id>` 房间页地址；该地址是 HTML 页面，不能直接交给 `video_player` 当作媒体流。
  - 通过官方房间元数据接口 `GET https://weibo.com/l/!/2/wblive/room/show_pc_live.json?live_id=<live_id>` 获取当前状态、封面、标题和签名播放地址；请求必须沿用微博网页端 Referer 与登录态。
  - `status=1` 表示直播中，只接受官方返回的 `live_origin_hls_url` / `live_origin_flv_url` 等当前直播流字段；`status=0` 显示“直播尚未开始”。
  - `status=3` 是官方回放状态，`status=5` 等其他已结束状态不再把 `replay_origin_url` 当作当前直播流播放，Review 统一显示“直播已结束”，避免把回放误判成直播或把房间页误判为失效视频。

---

### 3.6 微博发布、编辑替换与删除机制
- **发新微博**：
  - `POST https://weibo.com/ajax/statuses/update`
  - 请求体：`{'content': '正文内容'}`
  - 请求头：`Referer: https://weibo.com/`, `X-XSRF-TOKEN`
- **修改微博 (VIP 原生接口)**：
  - `POST https://weibo.com/ajax/statuses/modify`
  - 请求体：`{'id': '微博MID', 'content': '新正文内容'}`
- **删除微博**：
  - `POST https://weibo.com/ajax/statuses/destroy`
  - 请求体：`{'id': '微博MID'}`
  - 请求头：`Referer: https://weibo.com/`, `X-XSRF-TOKEN`
- **真·编辑替换机制 (True-Edit Replacement)**：
  - 用户点击“编辑微博”进入编辑界面（携带原微博 `editMid` 与正文）；
  - 点击“保存修改”时，先尝试原生 modify；若为普通用户则发布新内容并**自动调用 `/ajax/statuses/destroy` 销毁旧微博**，同时在本地时间线中**秒级即时移除旧微博卡片并刷新**，杜绝重复冗余。

---

### 3.7 账号鉴权与多通道 UID 自动提取
由于 `/ajax/profile/info` 接口必须强制传入 `uid` 参数（否则报错 `缺少必要参数`），系统实现了多通道精准自动提取：
1. **通道一**：`GET /ajax/profile/detail` -> 从返回体 `data.verified_url` 中正则提取 `uid=(\d+)`；
2. **通道二**：`GET /ajax/feed/allGroups` -> 从系统分组 `gid: 11000(\d+)` 或 `10001(\d+)` 中提取用户的真实 `UID`；
3. **拉取个人档案**：使用提取到的 `UID` 立即调用 `GET /ajax/profile/info?uid=$UID`，完整获取头像（`avatar_large`）、昵称（`screen_name`）、关注数与粉丝数，存入 `StorageService`。

---

### 3.8 实时热搜与综合内容搜索 (唯一纯净官方直连)
- **官方原生热搜大榜**：
  - 首选接口：`GET https://weibo.com/ajax/statuses/hot_band`（全量 50+ 官方大榜热搜词）；
  - 备用接口：`GET https://weibo.com/ajax/side/hotSearch`（提取 `data.realtime[]` 获取热搜词、热度数值及标签 `hot`, `new`, `boil`）。
- **关键词综合大搜 (微博原生网页端核心引擎)**：
  - **请求方法**：`GET`
  - **请求 URL**：`https://s.weibo.com/weibo`
  - **核心参数**：`q={关键词或#话题#}`, `page={页码}`
  - **专属请求头**：`Referer: https://s.weibo.com/`, `Accept: text/html,application/xhtml+xml...`
  - **核心技术优势与架构突破**：
    1. **彻底放弃碎屑时间流**：此前使用的移动端/Ajax 接口（`/ajax/statuses/search`）仅为时间线流（Timeline Feed），充斥 0 互动的散碎发帖，并不具备官方综合排序能力；
    2. **100% 承袭微博网页端推荐排序**：`s.weibo.com` 直接返回官方算法深度加权后的卡片流，包含置顶博文（`card-top` 置顶）与官方蓝 V、赛事机构及大 V 名嘴的热门发帖（`card-top` 热门）；
    3. **高保真并行注水 (Parallel Hydration)**：解析出各卡片 `mid` 后，并发通过 `GET /ajax/statuses/show?id={mid}` 拉取完整富媒体模型，全链路响应时间仅需 ~1.5 秒；
    4. **官方元数据并发探测 (`topicHeads`)**：第一页并发调用 `/ajax/statuses/search` 获取 `topicHeads`，解析词条导语、封面大图、阅读量、讨论量与主持人认证。

---

### 3.9 关注与取消关注原生纯净接口矩阵
- **关注博主**：
  - **请求方法**：`POST`
  - **请求 URL**：`https://weibo.com/ajax/friendships/create`
  - **请求体 (FormData)**：`uid={目标UID}`
  - **专属请求头**：`Referer: https://weibo.com/u/{目标UID}`, `X-XSRF-TOKEN: {st}`
- **取消关注**：
  - **请求方法**：`POST`
  - **请求 URL**：`https://weibo.com/ajax/friendships/destory`（⚠️ **注意：微博原生历史接口拼写即为 `destory`，非 `destroy`**）
  - **请求体 (FormData)**：`uid={目标UID}`
  - **专属请求头**：`Referer: https://weibo.com/u/{目标UID}`, `X-XSRF-TOKEN: {st}`
  - **返回断言**：响应体包含 `{"ok": 1}` 即断定为取消关注成功。

---

### 3.10 微博原生超话生态与关注列表接口矩阵
- **关注的超话列表 (唯一纯净官方直连)**：
  - **请求方法**：`GET`
  - **请求 URL**：`https://weibo.com/ajax/profile/topicContent`
  - **核心参数**：`tabid=231093_-_chaohua`, `page={页码}`
  - **专属请求头**：`Referer: https://weibo.com/u/page/follow/{uid}/231093_-_chaohua`, `X-Requested-With: XMLHttpRequest`
  - **数据提取**：`data.list[]` 包含 `title`、`topic_name`、`pic`、`oid`（去除 `1022:` 即为原生 `containerid` 如 `100808...`）、`content1`（简介）、`content2`（粉丝数）、`status_count`（帖子数）、`following`。
- **超话动态频道分栏顶栏自动探测与信息流 (`ChaohuaDetailPage`)**：
  - **请求方法**：`GET`
  - **请求 URL**：`https://weibo.com/ajax_proxy/chaohua/page`
  - **核心参数**：`containerid={flowId}`, `page={页码}`
  - **专属请求头**：`Referer: https://weibo.com/p/{超话ID}`, `X-Requested-With: XMLHttpRequest`
  - **频道顶栏自适应发现**：从响应中提取 `channelInfo.channels[]`，包含热门（`_-_recommend`）、最新（`_-_feed`）、精华（`_-_soul`）及各超话特有子频道（如数码超话特有的“同城”、“开黑组队”、“开箱测评”、“OS”等），动态生成吸顶 Tab 栏。
  - **动态信息流提取**：遍历 `items[]` 中 `category == 'feed'` 的 `data` 对象，直接无缝转化为 `WeiboStatusModel` 渲染，支持各频道独立缓存与翻页。
- **超话签到 (Checkin)**：
  - **请求方法**：`POST`
  - **请求 URL**：`https://weibo.com/ajax_proxy/chaohua/page/checkin`
  - **请求体 (FormData)**：`scene_id=pc_checkin&page_id={超话ID}&timezone=Asia/Shanghai&lang=zh-CN&plat=Win32`
  - **返回断言**：响应包含 `code: 100000` 或 `10000`，带签到名次与经验值加成。
- **超话关注/取关**：
  - 关注：`POST https://weibo.com/ajax_proxy/chaohua/page/follow` (FormData: `page_id={超话ID}`)
  - 取关：`POST https://weibo.com/ajax_proxy/chaohua/page/unfollow` (FormData: `page_id={超话ID}`)

---

### 3.11 超话实体搜索原生接口与检索体系
- **超话实体检索 (唯一纯净官方直连)**：
  - **请求方法**：`GET`
  - **请求 URL**：`https://weibo.com/ajax/stopic/list`
  - **核心参数**：`keyword={关键词}`
  - **专属请求头**：`Referer: https://weibo.com`, `X-Requested-With: XMLHttpRequest`
  - **数据提取**：返回匹配的所有超话实体列表，包含 `title`（超话名）、`page_id`（超话 containerid）、`image`（封面图/头像）、`description`（粉丝数与详细简介），点击直接进入对应 `ChaohuaDetailPage`。

---

### 3.12 多视频微博解析与渲染机制 (Mix-Media Architecture)
- **多视频/图文混排原生解析**：
  - 微博新版后端在包含多条视频或图文混排时，将媒体存放于 `mix_media_info: { items: [...] }` 结构中；
  - 引擎深度遍历 `mix_media_info.items`，将 `type == 'video'` 的项目转化为携带 `isVideo: true`、`videoUrl`、`videoDuration`、`videoTitle` 的 `WeiboPicModel`；
  - `NineGridView` 自动识别视频项目，在卡片中央叠加磨砂播放按钮图标并在右下角渲染时长标签；
  - 点击视频条目直达 `WeiboVideoPlayerPage` 播放高清视频，图片条目直达 `ImageGalleryPage` 浏览大图。

---

### 3.13 官方全量表情库与超话智能直达体系
- **全量 340+ 官方表情库**：
  - 对齐 `https://weibo.com/ajax/statuses/config` 中的 `emoticon.ZH_CN` 完整表情字典；
  - `WeiboEmojis` 内置全量表情短语映射（如 `[努力]`、`[不愧是你]`、`[心]`、`[doge]`、`[吃瓜]`、`[打call]` 等）及高分辨率官方 CDN PNG 链接；
  - `WeiboTextParser` 通过 `WidgetSpan` 渲染官方高清表情图，并支持 Unicode 兜底。
- **超话智能直达**：
  - 解析 `#xxx[超话]#`、`#xxx超话#` 或在 `url_struct` 中 `page_id` / `ori_url` 包含 `100808` 的超话链接；
  - 点击直接唤起 `ChaohuaDetailPage` 进入超话大厅，普通话题则跳转普通关键词搜索。

---

### 3.14 超话中心与「我的关注」聚合体系
- **我的关注 (`MyFollowsPage`)**：
  - 侧边栏原“关注的人”与“关注的超话”整合为统一入口；
  - 页面顶部双 Tab 栏无缝切换「关注的人」与「关注的超话」，支持独立下拉刷新与分页。
- **超话中心 (`ChaohuaCenterPage`)**：
  - 侧边栏新增超话中心入口；
  - 集成官方分类体系（游戏、电竞、动漫、体育、明星、红人、影视综、AI、读书、生活、学习等），支持即时输入检索与分类超话快速直达。

---

### 3.15 第三方存储访问与 Android App Links 配置
- **三方文件管理器与私有存储支持**：
  - 配置 `android:requestLegacyExternalStorage="true"` 与 `android:preserveLegacyExternalStorage="true"`；
  - 配置 `android:allowBackup="true"` 与 `android:fullBackupContent="true"`；
  - 配置 `FileProvider` 支持 `root-path`、`files-path`、`cache-path`、`external-path` 与 `external-files-path`，允许 MT 管理器等第三方工具全面读取导出与备份数据。
- **微博 App Links 支持**：
  - 在 `AndroidManifest.xml` 中为 `m.weibo.cn`、`weibo.com`、`card.weibo.cn`、`media.weibo.cn`、`card.weibo.com` 配置 `autoVerify="true"` 的 `VIEW` 过滤器，支持系统设置中“打开支持的链接”勾选默认跳转。

---

### 3.16 互动通知体系与消息中心架构
- **「我的消息」综合中心 (`MyMessagesPage`)**：
  - 整合 `@我的`、`收到的赞`、`发出的评论`、`收到的评论` 与原生私信群聊列表；
  - **清除未读信息**：消息页 AppBar 右侧只显示扫把图标。点击先将联系人及互动提醒的当前未读计数保存为本地基线，再并发请求服务端清理端点（`POST /webim/2/direct_messages/set_all_read.json`、`GET /webim/2/direct_messages/clear_unread.json`、`GET /ajax/message/clearUnread`）；后续展示按“当前服务端未读数 - 清除基线”计算，且不低于 0，避免重新进入消息页时旧计数复现。HTTP 2xx 本身不等同于业务成功；无法识别服务端确认时保留本地清零并提示服务器未确认；
  - **群聊免打扰**：未读气泡显示在各自群头像右上角；免打扰群按已保存的会话群 ID 匹配，使用灰底灰字，普通群保持红色。该开关当前是 Review 本地提醒设置，不宣称同步微博服务器状态；
  - **移除网页版入口**：完全剔除顶部 WebView 入口，实现 100% 纯原生通讯体验。
- **互动通知独立页面**：
  - **收到的赞 (`ReceivedLikesPage`)**：顶栏纯净展示「收到的赞」，直连 `/ajax/message/attitudes`，无多余顶栏 Tab；
  - **发出的评论 (`SentCommentsPage`)**：顶栏纯净展示「发出的评论」，直连 `/ajax/message/myCmt`；
  - **收到的评论 (`ReceivedCommentsPage`)**：顶栏纯净展示「收到的评论」，直连 `/ajax/message/cmt`。

---

### 3.17 微博点赞与收藏原生接口矩阵
- **微博点赞 (Like)**：
  - **请求方法**：`POST`
  - **请求 URL**：`https://weibo.com/ajax/statuses/setLike`
  - **请求体 (JSON)**：`{"id": "微博MID"}`
  - **专属请求头**：`Referer: https://weibo.com/`, `X-XSRF-TOKEN`
  - **返回断言**：响应包含 `ok: 1` 或返回 status 对象。
- **取消微博点赞 (Cancel Like)**：
  - **请求方法**：`POST`
  - **请求 URL**：`https://weibo.com/ajax/statuses/cancelLike`
  - **请求体 (JSON)**：`{"id": "微博MID"}`
  - **返回断言**：响应包含 `ok: 1` 或 `result: true`。
- **微博收藏 (Create Favorite)**：
  - **请求方法**：`POST`
  - **请求 URL**：`https://weibo.com/ajax/statuses/createFavorites`
  - **请求体 (JSON)**：`{"id": "微博MID"}`
- **取消微博收藏 (Destroy Favorite)**：
  - **请求方法**：`POST`
  - **请求 URL**：`https://weibo.com/ajax/statuses/destoryFavorites`（⚠️ 注意拼写为 `destoryFavorites`）
  - **请求体 (JSON)**：`{"id": "微博MID"}`

---

### 3.18 原生群聊生态体系与预热缓存机制
- **全局静态用户预热缓存 (`ChatConversationPage.globalUserCache`)**：
  - 为彻底消除点击群聊进入时前 1 秒由于头像未拉取导致的默认占位符闪烁，建立全局内存级用户缓存；
  - 在「我的消息」列表、群信息页、群成员列表中加载到的用户信息即时同步写入全局缓存；
  - 进入群聊会话时首帧同步渲染群友真实头像与昵称，体验极致平滑。
- **完整未截断群公告获取 (`GroupInfoPage`)**：
  - 基础 `query.json` 接口返回的群公告常被服务端强制截断；
  - 系统并发请求官方专用完整公告接口：`GET https://api.weibo.com/webim/groupchat/query_user_bulletin.json?id={gid}&source=209678993`，提取 100% 完整公告长文本在卡片与弹窗中渲染。
- **群成员全量解析与检索 (`GroupMembersPage`)**：
  - 支持单次拉取 500 名群成员，深度异步并行解析头像与昵称，群主与管理员自动置顶，支持本地即时模糊搜索。

---

### 3.19 Android SAF DocumentsProvider 原生存储挂载适配
- **MT 管理器与系统 SAF 文件选择器支持**：
  - 实现 `ReviewDocumentsProvider : DocumentsProvider`；
  - 在 `queryRoots` 中注入 `Root.COLUMN_ICON`（`R.mipmap.ic_launcher`）与 `Root.COLUMN_SUMMARY`（`ctx.packageName` 即 `com.review`）；
  - 在 `AndroidManifest.xml` 中为 Provider 声明 `android:icon` 与 `android:label="Review"`；
  - MT 管理器在「添加本地存储」中精准展示 Review 应用图标，副标题展示应用包名而非可用空间，根目录支持读写应用完整数据目录。

---

## 4. 核心功能特性与 UI 交互实现细节

### 4.1 微博卡片时间格式化与全自由个性化显示体系
- **RFC 822 原生时间解析**：
  - 微博后端返回的原始时间格式通常为 RFC 822（如 `"Fri Aug 28 01:15:56 +0800 2026"`）；
  - 引擎 `WeiboTimeFormatter` 自动解析并转化为易读中文时间；
- **显示模式自由切换**：
  1. **智能相对时间（默认开启）**：自动转换为“刚刚”、“3分钟前”、“2小时前”、“昨天 15:30”、“8月28日 01:15”等极其清爽的显示；
  2. **绝对具体时间**：转换为“2026年8月28日 01:15”等严谨时间；
- **细项自由开关（位于“设置 - 主题与外观个性化”）**：
  - `显示星期几`、`显示具体年份`、`显示时区标识 (+0800)`、`显示具体秒数`、`显示发布设备 / 来自...`、`显示发布位置 / IP 属地`。

---

### 4.2 语言与本地化体系 (默认纯中文)
- 应用默认统一采用标准简体中文（`Locale('zh', 'CN')`）；
- 完整接入 `flutter_localizations` 与 `GlobalMaterialLocalizations.delegate`、`GlobalWidgetsLocalizations.delegate`、`GlobalCupertinoLocalizations.delegate`。

---

### 4.3 全局交互与触感震动反馈体系
- 选项名称：`震动反馈`，默认开启；
- 基于 `HapticSplashFactory` 与 `HapticFeedbackUtil` 全局拦截，设置 **40ms 极低硬件防抖阈值**，确保极速敲击时每次点击精准触发。

---

### 4.4 导航布局风格与悬浮胶囊底栏 (MD3 Expressive)
- **外观形态**：居中实体圆角悬浮导航胶囊（`width: 280`, `height: 64`, `borderRadius: BorderRadius.circular(32)`），支持安全区智能抬升，并可在设置中自由切换为标准全宽导航栏；
- **全列圆角胶囊选中指示器**：选中项采用 `borderRadius: BorderRadius.circular(28)` 的大圆角容器，**完整包裹当前项的图标与文字标签**；
- **纯净即时切换动效**：
  - 点击切换时，**原选中位置的胶囊容器立即销毁不残留**，彻底杜绝跨位置插值导致的反色闪烁与残影；
  - **新选中位置的胶囊容器平滑淡入**（`160ms`，`Curves.easeOutCubic`），动效干净利落、纯净自然；
  - 移除 `InkWell` 的二次深色 splash 叠加干扰，保证背景色彩纯净一致。

---

### 4.5 顶部时间线下拉分组面板与分组管理系统
- 标题（如 `最新微博 ▾`）平滑展开/收起 4 列网格分组面板，右上角提供“编辑”直达分组管理；
- 分组管理支持“个人分组”、“默认分组”、“热门分组”自由定制，保存后即时同步刷新。

---

### 4.6 发微博与真·编辑替换机制
- 接入 `image_picker` 唤起系统相册（上限 9 张），带实时预览与单个移除；
- 内置 `WeiboEmojiKeyboard` 微博表情键盘。

---

### 4.7 微博卡片与详情页全套操作管理
- 卡片底栏右侧与详情页右上角 `···` 更多操作菜单：包含删除微博、编辑微博、复制正文、复制链接、收藏微博、不感兴趣。

---

### 4.8 微博样式个性化系统 (`WeiboStyleSettingsPage`)
- 8 档字号调节（13pt - 20pt）、7 档行高倍数调节（1.1倍 - 1.7倍）、5 种卡片背景布局、大图/小图模式切换、图片圆角切换等；
- **v1.5 精简优化**：彻底清理移除了历史遗留且无明显视觉效用的“扁平化风格 (标题栏无阴影)”开关及底层数据字段，全面回归 Material 3 原生自适应动态标高体系。

---

### 4.9 微博正文表情图形化 Emoji 渲染引擎 (全量收录)
- 全量收录 150+ 款微博官方表情，自动将正文中 `[流鼻血]` 渲染为 🤤、`[doge]` 渲染为 🐶、`[酸]` 渲染为 🍋 等。

---

### 4.10 微博详情页三栏互动体系（转发/评论/赞）、AI生成识别与排序切换
- **现代交互三栏 Tab 联动设计**：
  - 高度还原官方微博互动视觉：在正文卡片下方呈现“转发 X”、“评论 Y”、“赞 Z”三栏平滑切换 Tab，辅以 Material You 主色调平滑过渡的选中指示器与触感震动反馈。
  - **动态数量自适应同步**：实时响应微博正文数据与各频道拉取结果，智能展示各维度的互动总量。
- **评论排序自由切换（热度流 vs 时间流）**：
  - 评论 Tab 顶栏右侧提供便捷的“⇅ 按热度” / “⇅ 按时间”排序切换按钮。
  - 触发切换时，接口自动以对应 `flow` 参数（`flow=0` 按热度，`flow=1` 按时间）精准拉取首屏数据，并重置游标与加载状态。
- **评论区 IP 属地与智能 AI 生成识别**：
  - 评论卡片用户名下方展示清晰的副标题信息：`[发布时间]  [来自 属地]`（如 `10分钟前 来自 湖北`）。
  - **AI 机器人与生成式内容精准识别**：内置智能 AI 识别引擎，对于“千问”（如阿里千问官方机器人）、“文心”、“元宝”等 AI 账号，以及来源字段标记为“*AI生成”的评论，自动识别并统一归整规整为 `来自 AI生成`。
- **转发名单与点赞用户名单直达**：
  - **转发列表**：展示转发用户的昵称、认证标识、转发时间与完整转发正文，点击转发内容可直接下钻至该转发微博的正文详情页。
  - **赞的名单**：展示点赞用户的大尺寸高清头像、昵称、认证黄V/蓝V标识、个人简介及点赞心形图标。
  - **用户主页无缝直达**：在转发列表与点赞列表中，点击用户头像或整条卡片，均可秒级无缝跳转至该博主的个人主页（`UserProfilePage`）。
- **Tab 切换滚动位置保护与动态高度防回顶机制**：
  - **多通道异步静默预加载**：进入详情页时，后台自动并发预加载点赞与转发列表（`_fetchReposts()` 与 `_fetchAttitudes()`），用户切换 Tab 时瞬时呈现，彻底杜绝数据未到时的空白与突兀感。
  - **滚动视口防塌陷引擎**：通过 `ScrollController` 动态监听记录当前浏览视口偏移量 `_savedScrollOffset`；当切换至加载中、空列表或条目较少的分栏时，动态计算并撑开占位高度（`_calculateMinTabHeight`），并在下帧回调自动校准视口，根除 Flutter 因可滚动高度小于屏幕而强制回顶（`clamped to 0.0`）的严重体验 Bug。
- **发表评论与楼中楼回复全流程**：
  - 原生直连 `POST /ajax/comments/create` 与 `POST /ajax/comments/reply`，支持图片附件与表情键盘。
  - 从侧边栏「我的消息 → 发出的评论」点击评论时，页面会把该条评论记录作为 `initialComment` 传入详情页；在官方评论请求完成前先置顶显示目标评论，避免用户先看到评论区中部或空列表。
  - 官方评论树加载后按评论 ID（兼容 Base62 与数字 mid）去重；若目标已在首屏或后续页中，则将其所在的一级评论线程移动到列表顶部，并滚动定位到目标评论。楼中楼目标会沿 `reply_comment` 父链加载对应二级评论。
  - 目标评论记录缺少完整状态对象时仍可使用其状态 ID 打开详情；评论 ID 解析兼容 `id/idstr/cid/cidstr/comment_id` 等官方字段，`rootid=0` 不会被误当作有效父评论。

---

### 4.10.1 个人主页博主微博内容专属搜索系统 (`UserTimelineSearchPage` - v1.4 新特性)
- **精准入口布局**：位于个人主页右上角 `AppBar.actions`，在分享链接图标左侧设立 `[ 🔍 搜索微博 ]` 专属按钮。
- **沉浸式专属搜索流**：
  - 点击按钮通过物理弹性阻尼动画平滑推入专属搜索页，自动展示 `搜索 @[博主昵称] 的微博` 输入框与即时搜索/一键清空操作；
  - 接口直连官方原生 `/ajax/statuses/search?uid={uid}&q={keyword}&page={page}`，数据 100% 严格限定在该博主全部历史发博中，无任何外部干扰；
  - 搜索结果以标准 `TweetCard` 呈现，支持全量富文本、表情渲染、图片九宫格展开、视频播放与无缝点击进入详情页互动；
  - 整合 `EasyRefresh`，支持上拉分页连续加载更多历史博文，并配备友好空状态与检索引导。

---

### 4.11 微博相片九宫格经典纯净淡入淡出 (Fade Transition) 过渡系统
- 纯净透明暗色淡入淡出（展开 220ms，收回 200ms），彻底杜绝形变畸变与回弹过冲。

---

### 4.12 纯净独立微博热搜大厅 (`HotTrendsView`)
- 底栏第 2 个 Tab 专属呈现，内置系统级定位 `ACCESS_FINE_LOCATION` 反查所在城市，官方 9 大分类顶栏体系。

---

### 4.13 独立搜索落地页与实时联想/用户直达系统 (`SearchView`)
- 实时搜索联想匹配博主高清头像、认证标识与粉丝数，下方保留历史与 Top 9 + 更多热搜。

---

### 4.14 微博全景搜索结果页与 12 大分类顶栏 (`SearchResultsPage`)
- 12 大分类 TabBar（综合、实时、用户、图片、视频、关注、热门、评论、话题、超话、地点、商品）。

---

### 4.15 纯粹系统设置大厅 (`SettingsView` - 主底栏第 3 个 Tab)
- 涵盖主题外观、触感震动、缓存清理、凭据导出、关于 Review 及退出登录。

---

### 4.16 顶栏侧边栏入口与个人大厅 (`AppDrawer` - 精简纯净版)
- 点击左上角头像或左边缘向右滑动展开侧边栏，涵盖赞和评论、我的收藏、我的微博、我的分组、关注超话、关注的人与浏览记录。

---

### 4.17 图片与视频相册直存与多级目录存储规则
- Android Scoped Storage 深度整合，提供默认路径、个人昵称前缀、发博博主昵称前缀 3 种存储模式。

---

### 4.18 导出账号凭据与 Cookie 复制系统
- 支持一键复制完整 Cookie 字符串或核心 `SUB` 凭据。

---

### 4.19 WebDAV 云端全量备份与跨设备恢复机制
- 标准 WebDAV 协议（坚果云、Nextcloud 等），一键备份恢复个性化配置；备份文件仅包含经过 `StorageService.allowedExportKeys` 白名单筛选的设置项。
- **明确不备份/不恢复的内容**：微博 Cookie、SUB、Access Token、XSRF Token、WebDAV 密码及其他登录凭据。恢复设置时如设备本地仍有有效 Cookie，应用只会继续使用该本地登录态，不代表 Cookie 来自云端备份。

---

### 4.20 物理弹簧阻尼转场与全局触感系统
- 采用 Spring 物理阻尼曲线实现自然平滑的页面转场。

---

### 4.21 微博 Live 实况图原生解析与动态播放系统
- 解析 `type: livephoto`，画廊长按循环重叠播放实况视频，支持原图与短视频导出。

---

### 4.22 发微博编辑页结构精细化重构
- 右上角小尾巴入口、左下角定位设置、右下角字数统计与底栏发送操作。

---

### 4.23 个人主页多维分栏体系与 2 列瀑布流视频卡片 (`UserProfilePage`)
- 微博/相册/视频三联 Tab，视频瀑布流自适应网格卡片与内置原生播放器。

---

### 4.24 超长截图/长图全屏触控与平滑双击缓动缩放 (`ImageGalleryPage`)
- 识别长图宽高比（$h/w > 2.0$），长图顶端对齐，双击阶梯平滑缩放。

---

### 4.25 评论区原生图片渲染与全场景智能链接识别体系
- `isRealImageUrl` 严格校验图片附件，语义化呈现短链卡片。

---

### 4.26 发微博多图图床上传与定位参数体系 (`ComposeTweetPage`)
- 新浪图床直连 Base64 上传流，获取 PID 注入发博请求。

---

### 4.27 游标分片分页与双通道 60% 静默预加载引擎
- **分片游标机制**：向下滚动时严格使用上一页返回的 `max_id` 作为分片游标，禁止携带 `since_id`，支持万条内容连续翻阅；
- **双通道前置预取**：
  1. 视口滚动监听（`NotificationListener<ScrollNotification>`）：当用户浏览进度达到 **60% 深度** 或距底部 **小于 1500dp** 时，后台静默异步拉取下一页；
  2. 列表渲染双保险（`SliverChildBuilderDelegate`）：渲染至倒数第 8 条时通过 `addPostFrameCallback` 触发静默预加载；
- **无感体验**：滑动惯性到底部前新内容已就绪拼装，完全杜绝白屏与等待停顿。

---

### 4.28 时间线底栏交互与双向原位穿梭机制
- **单击时间线底栏**：
  - 深入浏览时单击：记录当前浏览文章位移 `_lastSavedOffset`，平滑回顶（`0.0`）；
  - 在顶部再次单击：精准平滑返回刚刚阅读的那篇文章原位置；
- **双击时间线底栏**：
  - 连续双击：直接回到顶部并触发时间线全量刷新；
- **双击顶栏**：
  - 第一次双击顶栏：深入浏览时平滑回到顶部；
  - 第二次双击顶栏：在顶部时直接触发时间线刷新。

---

### 4.29 物理级 1:1 实时跟手触感震动系统
- **绝对跟手**：由物理触控瞬时事件（按下瞬时）单通道驱动，点一下严格震一下，连点两下严格连震两下；
- **40ms 防抖响应**：硬件防抖阈值设为 40ms，消除所有冗余手动二次触发，确保极速连续双击时每一次敲击均能获得清脆干脆的物理微震。

---

### 4.30 赞和收藏双顶栏体系 (`LikesFavoritesPage`)
- **侧边栏入口**：位于 Drawer 第 1 项「赞和收藏」（原“赞和评论”与“我的收藏”合并）；
- **双顶栏架构**：
  1. `我的赞`：直连 `/ajax/statuses/likelist` 与 `/ajax/profile/likelist`，展示点赞过的微博流；
  2. `我的收藏`：直连 `/ajax/favorites/all_fav`，支持完整微博卡片渲染与多级分页；
- **移除冗余**：收到的赞、发出的评论、收到的评论统一收拢到「我的消息」中心。

---

### 4.31 我的消息中心与互动通知体系 (`MyMessagesPage` / `LikesCommentsPage`)
- **侧边栏入口**：置于侧边栏 Drawer 中「我的关注」下方、「超话中心」上方；
- **四大快捷通知入口**：
  - `@我的`：直达提及我的微博与评论（`MentionsPage`）；
  - `收到的赞`：直达 `LikesCommentsPage(initialTabIndex: 0)`（直连 `/ajax/message/attitudes`）；
  - `发出的评论`：直达 `LikesCommentsPage(initialTabIndex: 1)`（直连 `/ajax/message/myCmt`）；
  - `收到的评论`：直达 `LikesCommentsPage(initialTabIndex: 2)`（直连 `/ajax/message/cmt`）；
- **原生私信与群聊列表**：直连 `/webim/2/direct_messages/contacts.json`，展示联系人头像、群组/好友名称、最后发言、未读红点及 `[有人@我]` 特征标识；点击直接进入原生聊天页。
- **未读角标**：侧边栏“我的消息”后显示 `@我的`、收到的赞、收到的评论和非免打扰私信/群聊的合计；打开侧边栏时拉取，并在页面存活时每分钟刷新。计数使用持久化清除基线处理，接口失败时不以 0 覆盖上一次已知数。
- **清除未读**：只保留消息页右上角扫把图标；同时清理私信/群聊及微博消息提醒分区，清除基线本地持久化。

---

### 4.32 原生聊天对话与群生态体系 (`ChatConversationPage` / `GroupInfoPage` / `GroupMembersPage` / `GroupWeiboPage`)
- **原生聊天会话 (`ChatConversationPage`)**：
  - 群聊消息直连 `/webim/groupchat/query_messages.json`，单聊私信直连 `/webim/2/direct_messages/conversation.json`；
  - **群成员真实头像与昵称并发解析**：基于 `/webim/2/users/show.json` 并行拉取所有发言人真实微博头像与昵称；
  - 呈现左右双向气泡、时间居中分割线、撤回与系统提示气泡、微博表情与富文本链接解析；
  - 底部即时输入栏沿用网页端 WebIM 请求路径 `/webim/groupchat/send_message.json` / `/webim/2/direct_messages/new.json`；不能只凭 HTTP 2xx 宣称发送成功，需检查业务响应并回读会话确认，不再伪造本地发送气泡。上述 WebIM 路径是当前兼容实现，尚未以微博公开接口契约或测试账号发送验证；严禁使用用户账号对外发送测试消息；
- **原生群信息详情 (`GroupInfoPage`)**：
  - 1:1 像素级还原官方群信息布局：群头像、群名称、群简介、置顶聊天与消息免打扰 Switch、退出群聊等；
  - **群二维码弹窗**：内置离线高精度二维码生成 (`QrImageView`)，展示群号、群头像、一键复制群分享链接；
  - **群公告详情弹窗**：支持点击展开完整群公告，提供富文本渲染与一键复制功能；
  - **消息免打扰**：本地持久化群 ID；用于灰色未读角标、排除侧边栏聚合数和后台通知。
- **专属群成员列表 (`GroupMembersPage`)**：
  - 直连 `/webim/groupchat/query_members.json?count=500`；
  - 支持群成员实时搜索（昵称/UID）、金牌群主徽章、蓝牌管理员徽章与加群时间展示；
- **专属群微博专区 (`GroupWeiboPage`)**：
  - 直连 `/ajax/statuses/mymblog?uid={ownerUid}` 与群动态流，支持全量微博卡片、下拉刷新与分页加载。

---

## 5. 网络层与安全鉴权体系

### 5.1 全局 Dio 拦截器 (`WeiboDioClient`)
1. **自动提取 XSRF-TOKEN**：从 Cookie 中提取 `XSRF-TOKEN` 并在请求中动态注入 `X-XSRF-TOKEN`；
2. **401/432 防死循环重试**：设置 `is_retried` 限制最多重试 1 次。

### 5.2 登录凭据获取与生命周期保护
- Android 原生 CookieManager 扫描读取 HttpOnly 安全 Cookie，多通道 UID 识别；
- 退出登录调用原生通道彻底清理。

### 5.3 数据导出严格白名单安全防护体系 (`StorageService.allowedExportKeys`)
- 仅允许导出视觉配置与分组排序；
- **严禁导出 `keySubCookie`、`keyFullCookie`、`keyAccessToken`、`keyWebDavPassword` 等敏感认证凭据**。

---

## 6. Android 原生工程与签名打包规范

### 6.1 构建产物唯一性
根目录必须且仅保留唯一的发布包：
```text
  D:\App\Review\Review_v2.9.0.apk
```

### 6.2 权威一键编译命令
在 PowerShell 中执行以下命令即可完成构建并覆盖输出单一交付安装包：
```powershell
# 1. 设置环境变量
$env:JAVA_HOME = "D:\jdk17"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL = "https://storage.flutter-io.cn"
# 本机 JDK 17 使用默认用户临时目录时，Selector 本地通信管道会报 Invalid argument: connect。
# 仅为本次 PowerShell 构建进程指定项目内临时目录，不要修改用户/系统级 TEMP、TMP。
$buildJvmTemp = "D:\App\Review\build\.jvm-temp"
New-Item -ItemType Directory -Path $buildJvmTemp -Force | Out-Null
$env:TEMP = $buildJvmTemp
$env:TMP = $buildJvmTemp

# 2. 执行编译
& "D:\flutter_sdk\bin\flutter.bat" build apk --target-platform android-arm64 --release --no-tree-shake-icons --android-skip-build-dependency-validation

# 3. 产物提取与覆盖（文件名使用应用名 + 版本名）
Copy-Item -Path "D:\App\Review\build\app\outputs\flutter-apk\app-release.apk" -Destination "D:\App\Review\Review_v2.9.0.apk" -Force
```

---

## 7. 故障排查与自愈自检清单 (CheckList)

| 异常现象 | 可能原因 | 排查步骤与自愈修复方案 |
| :--- | :--- | :--- |
| **底栏切换时原选中位置的胶囊闪烁/残影** | `AnimatedContainer` 在有色与透明之间插值导致 RGB 偏黑变暗 | 检查 `_buildCapsuleItem`：未选中项直接隐藏不渲染背景，选中项通过 `TweenAnimationBuilder` 执行 160ms 顺滑淡入，并移除 `InkWell` 多余 splash。 |
| **单次点击产生两次震动（点一下震两下）** | 全局 `HapticSplashFactory` 与业务回调（`onTap` / `onDestinationSelected`）重复触发震动 | 统一由 `HapticSplashFactory` 在手指按下瞬时单通道触发，剔除业务回调中的手动二次 `HapticFeedbackUtil.selection()` / `light()`。 |
| **时间线下滑加载卡顿 / 刷 10-20 条后空白断流** | 向下分页误传了 `since_id` 导致窗口锁定，或缺少 `list_id: 10001` / `refresh: 4` | 检查 `FeedRepository.getFriendsTimeline`：向下翻页必须携带 `list_id: '10001'`, `refresh: 4`, `max_id: state.maxId`，严禁携带 `since_id`。 |
| **取消关注报错“请检查网络或稍后重试”** | 微博原生接口拼写为历史命名 `destory` | 检查取消关注接口 URL，必须为 `POST /ajax/friendships/destory`（非 destroy），返回 `{"ok": 1}` 视为成功。 |
| **双击震动不跟手 / 震动延迟 / 连震异常** | 冷却时间过长拦截了第 2 次点击，或人为合成了延迟双脉冲 | 检查 `HapticFeedbackUtil`，将防抖阈值设为 40ms，在触控事件触发时即时调用单次震动，实现 1:1 跟手。 |
| **短信验证码登录点击登录后黑屏** | WebView 拦截到外部 Scheme 跳转发生崩溃 | 在 `NavigationDelegate` 的 `onNavigationRequest` 中拦截所有非 `http/https` 请求返回 `NavigationDecision.prevent`。 |
| **退出登录后再次登录秒退回** | Android 底层原生 `CookieManager` 保留旧账号会话 | 在 `AuthNotifier.logout()` 中调用原生通道 `clearNativeCookies` 及 `WebViewCookieManager().clearCookies()`。 |
| **Gradle 启动时报 Unable to establish loopback connection / Invalid argument: connect** | 本机 JDK 17 在默认用户临时目录下创建 Selector 本地通信管道失败 | 仅对构建进程把 `TEMP`、`TMP` 指向已存在的项目内目录（如 `D:\App\Review\build\.jvm-temp`）；不要永久改用户/系统环境变量。此目录的 JDK `Selector.open()` 检查通过，Release 构建使用项目内临时目录成功。 |
| **底栏或分组编辑页面变成灰色不可操作色块** | 启用语言配置但未注入 `flutter_localizations` 代理 | 检查 `main.dart` 中的 `MaterialApp` 是否包含 `localizationsDelegates` 全局三联代理。 |
| **关注流刷出陌生博主或公共信息流** | 请求了带有智能推荐的未读流 | 检查 URL 必须为 `/ajax/feed/friendstimeline`，绝对不能带 `unread` 前缀。 |
| **接口返回 403 Forbidden** | 缺少防盗链或防跨站请求头 | 检查请求是否携带了 `Referer`、`X-Requested-With: XMLHttpRequest` 以及 `X-XSRF-TOKEN`。 |
| **本人发布的微博未显示“删除/编辑”选项** | UID 未成功从登录态提取 | 确认多通道提取逻辑（`/ajax/profile/detail` 及 `/ajax/feed/allGroups`）正常执行。 |
| **编辑微博后产生两条重复内容** | 未调用原微博销毁逻辑 | 确认是否在发布新内容后调用了 `deleteStatus(widget.editMid!)` 并从本地时间线即时移除。 |
| **微博正文中表情显示为 `[xxx]` 文本** | 文本解析器未挂载表情映射 | 检查 `WeiboTextParser` 正则是否包含表情分组，确认 `WeiboEmojis.getEmoji()` 命中。 |
| **打包安装后提示签名不匹配** | 签名未应用 `infinitycm.jks` | 检查 `build.gradle.kts` 中 `buildTypes.release.signingConfig` 是否绑定了 `signingConfigs.release`。 |
| **时间线分组下拉面板出现大片空白** | `Align` 默认 `heightFactor: null` 膨胀撑满屏幕 65% 最大高度 | 在 `GroupDropdownPanel` 中使用 `ConstrainedBox(maxHeight: 0.65 * screenHeight)` + `Column(mainAxisSize: MainAxisSize.min)`，严禁外层套用无约束 `Align`。 |
| **我的分组未在下拉面板中呈现** | 本地缓存与官方云端分组状态可能不同，或官方接口暂时失败 | 优先展示已成功读取的官方云端分组；网络失败时保留上次已验证缓存；严禁凭空生成“个人分组”或把本地假分组当作云端分组。 |
| **时间线点赞报错或无响应** | 微博网页端已升级为 `/ajax/statuses/setLike` 与 `/ajax/statuses/cancelLike` | 检查点赞接口 URL 与请求体，点赞使用 `POST /ajax/statuses/setLike`（body: `{"id": mid}`），取消点赞使用 `POST /ajax/statuses/cancelLike`（body: `{"id": mid}`），配合 `Referer: https://weibo.com/` 请求头。 |
| **点进群聊前一秒头像闪烁默认群友占位图** | 页面内用户缓存为空，依赖进入会话后异步拉取 | 建立静态全局内存缓存 `ChatConversationPage.globalUserCache`，在我的消息联系人、群成员列表与群详情加载时并发预热；进入会话时首帧同步渲染。 |
| **群公告在群设置页展示被截断** | `query.json` 接口返回的公告内容被服务端截取 | 并发调用 `GET /webim/groupchat/query_user_bulletin.json?id={gid}&source=209678993` 获取 100% 完整无截断的公告正文，覆盖群基本信息卡片与弹窗。 |
| **MT 管理器添加本地存储展示可用空间而非包名，且无应用图标** | `queryRoots` 未配置 `Root.COLUMN_SUMMARY` 与 `Root.COLUMN_ICON` | 在 `MatrixCursor` 中设置 `Root.COLUMN_SUMMARY` 为 `ctx.packageName`（`com.review`），`Root.COLUMN_ICON` 为 `R.mipmap.ic_launcher`；在 `AndroidManifest.xml` 的 `<provider>` 声明 `android:icon` 与 `android:label`。 |
| **MT 管理器添加本地存储展示冗余根或多余长文本** | `queryRoots` 暴露了外部私有存储或包含冗长标题 | `ReviewDocumentsProvider.queryRoots` 仅保留单个内部私有存储根（`context.filesDir.parentFile`），标题（`Root.COLUMN_TITLE`）严格为 `"Review"`。 |
| **热搜分类分栏词条过少（不足 10 条）或底部留白过大** | 分类匹配后过早截断且底部使用了过大的 Safe Area 边距 | 在 `getCategoryHotSearch` 中先置顶分类强相关词条，再无缝拼接全量热搜，确保每个分栏均具备 50+ 词条；底栏边距收紧至 `72.0`。 |
| **赞和收藏中“赞无法取消 / 再次点击依然是赞”** | `TweetCard` 依赖首页全局 `FeedController` 获取点赞状态，在非首页子列表中因找不到 ID 导致 `wasLiked` 误判为 `false`，错误调用了 `setLike` 且无本地重绘 | 见第 8 节复盘：在 `_TweetCardState` 建立自闭环状态控制（`_effectiveLiked`），根据真实当前状态精确下发 `toggleLike(mid, currentlyLiked: wasLiked)`，若已赞则调用 `cancelLike`，并通过乐观 UI 毫秒级即时重绘。 |
| **“我的收藏”页面为空 / 无法获取任何数据** | 微博官方 `/ajax/favorites/all_fav` 返回的 `data` 是 `List`，代码误用 `data['data']?['list']` 导致强类型转换异常被 catch 吞并 | 见第 8 节复盘：重构解包层，自适应判断 `rawData is List` 与 `rawData is Map`，严禁假设单一 JSON 结构；同时补齐 `favorited: true` 标记。 |

---

## 8. 核心开发复盘、高频踩坑反思与防御性编程准则 (Engineering Retrospective & Guidelines)

### 8.1 状态生命周期与跨组件状态同步脱节 (Decoupled State Management Bug)
- **踩坑现象**：在「赞和收藏」（我的赞/我的收藏）、博主个人主页、微博详情页中，点击点赞按钮无法取消赞，反而重复发送点赞请求；或者点赞后卡片没有即时视觉反馈。
- **犯错根因**：
  1. **错误假设全局单一数据源**：盲目假设所有微博卡片都是由首页 `feedControllerProvider.state.statuses` 渲染的。但在子页面中，列表是页面自身维护的局部 State；
  2. **状态判定失效导致反向调用**：`FeedController.toggleLikeLocally` 在自己的列表中找不到该微博 ID，导致局部变量 `wasLiked` 永远保持默认的 `false`。因此无论用户怎么点，系统都认为“当前没点赞”，进而向服务端发送 `POST /ajax/statuses/setLike`（点赞），而不是 `POST /ajax/statuses/cancelLike`（取消赞）；
  3. **缺乏本地重绘能力**：由于首页控制器并未持有子页面的数据，控制器通知更新时子页面不会收到任何通知，导致 UI 看起来完全没有响应。
- **防御性准则与避免再次犯错规范**：
  - **通用组件必须具备自闭环状态能力**：类似 `TweetCard` 这种可复用于任何页面（时间线、详情、个人主页、搜索、超话、收藏、历史）的基础卡片，必须在 `_TweetCardState` 中维护独立的 `_liked`、`_attitudesCount`、`_favorited` 状态，并在 `didUpdateWidget` 中做差量重置；
  - **基于组件真实状态下发指令**：点赞/取消赞操作必须以组件当前的真实值（`_effectiveLiked`）为准，已赞则调用 `cancelLike`，未赞则调用 `setLike`；
  - **乐观 UI + 失败自愈回滚**：点击瞬时立即更新本地 UI 并震动，异步请求失败时自动还原上一个状态并弹出错误提示；
  - **按需联动外部控制器**：通过 `feedControllerProvider.notifier.syncLikeLocally` 单向同步，但绝不反向强依赖控制器的存在。

### 8.2 JSON 数据结构假设与强类型转换崩溃 (TypeCast & API Schema Assumption Bug)
- **踩坑现象**：在「我的收藏」页面中，接口明明返回了 200 成功响应，但页面上始终显示“暂无收藏内容”，无法获取任何数据。
- **犯错根因**：
  1. **凭经验臆测统一结构**：大部分微博信息流接口（如好友动态、超话动态）返回的结构是 `{"data": {"list": [...]}}` 或 `{"data": {"statuses": [...]}}`；
  2. **强类型语言的索引异常**：但官方 `/ajax/favorites/all_fav` 返回的 `data` 字段直接就是 `List<dynamic>`（即 `{"ok": 1, "data": [{...}, {...}]}`）。在 Dart 中，如果对一个 `List` 执行 Map 索引取值（`data['data']?['list']`），会直接抛出 `NoSuchMethodError: Class 'List<dynamic>' has no instance method '[]'` 或类型断言异常；
  3. **静默异常吞并**：由于代码外层套用了 `try { ... } catch (_) {}`，该异常被静默忽略，导致 `extracted` 列表始终为空。
- **防御性准则与避免再次犯错规范**：
  - **严禁对后端 JSON 结构做单一形状假设**：编写列表解包代码时，必须采用自适应的多层类型守卫：
    ```dart
    final dynamic rawData = data['data'];
    final List rawList;
    if (rawData is List) {
      rawList = rawData;
    } else if (rawData is Map) {
      rawList = (rawData['list'] as List?) ?? (rawData['statuses'] as List?) ?? [];
    } else {
      rawList = (data['list'] as List?) ?? (data['statuses'] as List?) ?? [];
    }
    ```
  - **新接口必须编写真实探测脚本**：对接任何新接口或进行重构时，必须先在 `scratch/` 中运行纯 Dart 脚本拉取真实响应，打印 `json.keys` 与 `data.runtimeType`，确认其精确数据格式后再接入业务层。

### 8.3 历史接口拼写陷阱与必填参数约束 (Legacy API Naming & Param Traps)
- **踩坑现象**：取消关注返回 404/500、点赞列表返回 400 Bad Request。
- **犯错根因**：
  1. **历史拼写不一致**：微博早期系统存在拼写错误并沿用至今（如取消关注为 `/ajax/friendships/destory`，少了一个字母 `u`；取消收藏为 `/ajax/statuses/destoryFavorites`；而删除微博却是正确的 `/ajax/statuses/destroy`）；
  2. **必填参数依赖**：点赞列表 `/ajax/statuses/likelist` 必须显式携带 `uid` 参数，缺省时服务端直接返回 400 Bad Request；
  3. **服务端截断问题**：基础群查询 `/webim/groupchat/query.json` 会将长公告截断，只有独立端点 `/webim/groupchat/query_user_bulletin.json` 才能获取全量内容。
- **防御性准则与避免再次犯错规范**：
  - 所有请求端点统一维护在 [api_constants.dart](file:///D:/App/Review/lib/core/constants/api_constants.dart)，并在注释中高亮标注历史拼写特性与必选参数；
  - 请求时必须完整配置 `Referer: https://weibo.com/`、`X-Requested-With: XMLHttpRequest` 以及 `X-XSRF-TOKEN` 请求头。

### 8.4 UI 视觉闪烁与缓存预热机制 (Visual Flickering & Cache Pre-warming)
- **踩坑现象**：进入群聊的前 1 秒，所有发言人头像显示为默认占位符，1 秒后突兀跳变为真实头像。
- **犯错根因**：把数据加载完全寄托在目标页面的 `initState` 异步调用中，未考虑页面进入首帧的视觉连贯性。
- **防御性准则与避免再次犯错规范**：
  - 建立全局常驻内存缓存（如 `ChatConversationPage.globalUserCache`）；
  - 在前置页面（消息列表、群成员列表、群详情页）加载到用户信息时即时预热注入缓存；
  - 目标页面首帧直接优先读取全局缓存同步渲染，无缝消除闪烁感。

### 8.5 悬浮胶囊底栏与视口底部内边距重叠过大 (Bottom Navigation Bar Safe Padding Overflow)
- **踩坑现象**：在开启悬浮胶囊底栏的情况下，设置页等页面向下滑动时会露出大面积无用空白区域。
- **犯错根因**：
  1. **系统安全边距与硬编码边距重复叠加**：在 `SettingsView` 中错误将底部边距配置为 `MediaQuery.of(context).padding.bottom + 96.0`，并在列表末尾重复添加了 `SizedBox(height: 16)`；
  2. **视口预留估算严重超标**：悬浮胶囊底栏自身高度仅为 64dp，底部偏移 6-14dp，实际仅需 `72.0` 的内边距即可让底部的“关于/退出登录”卡片平滑滑出且不被胶囊遮挡；而 `+96.0` 与手势条（24-48dp）累加后导致预留空间高达近 140dp，造成视觉上的大片空白断层。
- **防御性准则与避免再次犯错规范**：
  - 悬浮胶囊底栏模式下，主页各 Tab（时间线 `FeedView`、热搜 `HotTrendsView`、设置 `SettingsView`）的底部内边距严格统一对齐为 `themeState.useFloatingNavBar ? 72.0 : 16.0`；
  - 列表自身已配置 `padding: EdgeInsets.fromLTRB(..., bottomNavPadding)` 时，严禁在 children 末尾再次放置额外的 `SizedBox` 占位，避免二次边距叠加。

### 8.6 模态弹窗打断水波纹与卡片直角水波纹闪烁 (Modal Trigger Ripple Glitch & Card Overflow)
- **踩坑现象**：点击设置页中的“关于应用”或“检测账号凭据有效性”时，按下时未见明显平滑动画，而在弹窗浮层出现的瞬间，背景的功能栏卡片会突然闪现一个尖锐直角的无圆角长方形高亮框。
- **犯错根因**：
  1. **弹窗同步阻塞水波纹生命周期**：在 `onTap` 瞬时同步触发 `showDialog` / `showModalBottomSheet`，立即将模态遮罩压入导航栈，导致原页面的触控手势被强制取消（`onTapCancel`），水波纹未能自然展开扩散就被迫直接跳跃至结束态，在弹窗暗色背景下呈现突兀的瞬态白闪；
  2. **Shader 着色器在路由中断时的直角渲染**：默认使用的 `InkSparkle.splashFactory` 在 Android 上强依赖 Impeller/Skia 着色器。在未指定 `borderRadius` 且失去焦点时，着色器按原始边界矩形计算，渲染出无圆角（直角 90°）的闪烁框；
  3. **Card 容器未配置裁切行为**：`Card` 默认 `clipBehavior: Clip.none`，内部 `ListTile` 的水波纹扩散超出圆角卡片边界，在边缘产生直角溢出。
- **防御性准则与避免再次犯错规范**：
  - **启用自然水波纹渲染器与全局圆角**：在 `HapticSplashFactory` 中采用平滑同心圆扩散的 `InkRipple.splashFactory`；并在 `app_theme.dart` 的 `listTileTheme` 中显式指定 `shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))`；
  - **Card 容器强制开启抗锯齿裁切**：全局 `cardTheme` 及每个 `Card` 显式设置 `clipBehavior: Clip.antiAlias`，彻底杜绝水波纹向卡片外部直角溢出；
  - **模态交互预留涟漪扩散时钟**：触发模态弹窗（`showDialog` / `showModalBottomSheet`）的交互前，异步注入 80ms 微延迟（`await Future.delayed(const Duration(milliseconds: 80))`），让手指下压抬起时的同心圆涟漪在视觉上自然展开完毕后再淡入弹窗遮罩，彻底消除后滞白闪与视觉割裂。

### 8.7 第三方组件英文硬编码与全局中文化本地化注入规范 (Third-party Localization & EasyRefresh)
- **踩坑现象**：在时间线、超话、消息等页面下拉刷新时，头部显示“pull to refresh”、“last updated at ...”等英文提示。
- **犯错根因**：第三方包（如 `easy_refresh`）默认采用英文国际化文案，若在各业务页面未逐一声明或未在应用入口全局配置 defaultBuilder，会导致英文提示遗漏泄露。
- **防御性准则与避免再次犯错规范**：
  - 在 `main.dart` 应用启动入口处，统一配置 `EasyRefresh.defaultHeaderBuilder` 与 `EasyRefresh.defaultFooterBuilder`；
  - 强制声明纯中文文案：“下拉刷新”、“释放立即刷新”、“正在刷新...”、“刷新成功”、“最后更新于 %T”、“上拉加载”、“加载完成”、“没有更多了”；
  - 杜绝在各个页面分散 hardcode 甚至漏配，确保全局所有下拉与上拉刷新 100% 保持中文化统一。

### 8.8 模态弹窗位移动画消除与原地轻量淡入规范 (Modal Dialog Motion Elimination)
- **踩坑现象**：删除微博或触发确认弹窗时，弹窗从屏幕上方往下掉落飘动。
- **犯错根因**：Flutter 原生 `showDialog` / `DialogRoute` 在 Android 平台默认叠加了下落或缩放曲线，产生上下漂移感。
- **防御性准则与避免再次犯错规范**：
  - **模态弹窗原地淡入 (`showAppDialog`)**：封装 `showAppDialog` 工具函数，采用 `showGeneralDialog` 配备轻量 `FadeTransition`（`transitionDuration: 60ms`），完全去除 Scale 与 Slide 偏移，弹窗直接在屏幕正中央平稳就地呈现，杜绝任何“动来动去”的视觉干扰。

### 8.9 悬浮胶囊上方全局独立 Overlay Toast HUD 与杜绝路由跟随飘移 (Overlay-based Static Toast HUD)
- **踩坑现象**：发博成功或操作提示时，提示依然从底部滑动飞入飞出，或在发博成功页面关闭（`Navigator.pop`）时被带着一起滑走，导致用户根本看不清字就消失了。
- **犯错根因**：
  1. `ScaffoldMessenger` / `SnackBar` 挂载在具体页面或局部 `Scaffold` 上，页面在执行 `Navigator.pop(true)` 返回时，其子树动画将强行携带 SnackBar 一起退出视口；
  2. `SnackBar` 自身内置垂直 translation 位移曲线，在不同页面高度下飘移不定。
- **防御性准则与避免再次犯错规范**：
  - **基于根节点 `rootNavigatorKey.overlay` 搭建专属 HUD**：
    - 在 `app_toast.dart` 中建立全局唯一 `OverlayEntry` 控制器，完全脱离当前页面的 `Scaffold` 生命周期；
    - 即使发博页面、登录页面瞬时 `pop`，Toast 也稳固悬浮在应用最顶层，不随任何路由位移或销毁；
  - **绝对固定于悬浮胶囊底栏正上方 (`bottom: 84dp`)**：
    - 垂直方向通过 `Positioned(left: 24, right: 24, bottom: 84)` 锁定在悬浮胶囊底栏正上方；
    - 纯 `FadeTransition`（100ms 淡现，2600ms 充裕静止阅读时间，100ms 淡隐），位置 100% 绝对静止，彻底消灭任何上下飘动。

### 8.10 模态交互点击延迟消除与背景水波纹拖尾隔离 (Immediate Modal Triggering & Background Ripple Isolation)
- **踩坑现象**：点击“设置-关于应用”时，点击动画响应过慢，在弹窗浮层已经弹出来后，背景底层的卡片按钮依然在持续缓慢扩散水波纹。
- **犯错根因**：
  1. 代码中存在人为加入的 `Future.delayed(80ms)` 阻塞了弹窗响应，造成明显的输入顿挫与延迟感；
  2. `InkRipple` 默认具有长达 500ms 的慢速扩散衰减生命周期，在模态浮层弹出后仍未结束扩散，隔着半透明遮罩能清晰看到背景在“持续蠕动”。
- **防御性准则与避免再次犯错规范**：
  - **彻底移除所有人工延迟**：所有按钮 `onTap` 点击事件直接同步响应，实现 0ms 零延迟呼出弹窗与路由跳转；
  - **启用敏捷水波纹与即时高亮反馈**：在 `HapticSplashFactory` 中采用 `InkSplash.splashFactory`，并为列表项配置 `splashColor` / `highlightColor`，轻触瞬间给与即时反馈，弹窗出现时背景即刻恢复平静，彻底杜绝浮层后方的视觉拖尾。

### 8.11 系统全局字体粗细调节 (Font Weight Adjustment) 适配与动态联动规范
- **踩坑现象**：在 Android 系统设置中调节“字体粗细”（如 HyperOS/ColorOS/OriginOS/HarmonyOS/OneUI 的字体粗细滑块或全局粗体开关）后，应用内的所有文本粗细均不发生改变，始终停留在固定粗细。
- **犯错根因**：
  1. **Flutter 原生限制**：Flutter 默认仅监听布尔值的 `boldText`，且 `TextStyle` 与 `ThemeData` 的原生实现不会自动根据 Android 12+ (API 31+) 的 `Configuration.fontWeightAdjustment`（-300 ~ +300 连续数值）去动态变换字重；
  2. **硬编码字重与静态 TextTheme**：全局组件与富文本解析器中大量使用固定的 `FontWeight.w600`、`FontWeight.bold`，未与系统级字重偏移量进行联动计算。
- **防御性准则与避免再次犯错规范**：
  - **Android 原生通道桥接 (`MainActivity.kt`)**：
    - 读取 `resources.configuration.fontWeightAdjustment`（及无障碍粗体开关），并通过 `MethodChannel` 提供 `getFontWeightAdjustment` 查询；
    - 监听 `onConfigurationChanged`，在用户在系统设置修改字重滑块后实时向 Flutter 发送 `onFontWeightAdjustmentChanged` 广播；
  - **全局动态字重矩阵与主题变换 (`AppTheme` & `ThemeNotifier`)**：
    - 封装 `AppTheme.adjustFontWeight(base, delta)`，基于 9 级字重索引（`w100` ~ `w900`）进行安全钳位换算；
    - 在 `AppTheme.lightTheme` 与 `darkTheme` 中全量重构 `TextTheme`，对 15 级 Typography（`displayLarge` 到 `labelSmall`）以及 AppBar/ListTile/TabBar/Dialog 等组件全局施加字重偏移；
    - 在 `MaterialApp.builder` 中注入全局 `DefaultTextStyle`，确保所有未显式指定字重的文本默认继承动态字重；
    - 扩展 `context.adjustWeight(base)`，富文本解析器（`WeiboTextParser`）与卡片头部组件全面采用动态字重，确保系统外调节字重时，应用内所有文字（正文、用户名、标题、副标题、标签、按钮等）100% 实时同步变粗或变细。

### 8.12 中文字体间距（Letter Spacing）规范与应用内独立字重调节机制
- **踩坑现象**：在跟随系统或改变字重后，整个界面的中文字间距显得异常疏离或松散（字与字之间空隙过大、排版松垮）。
- **犯错根因**：
  1. Flutter 原生 `Typography.material2021` 中针对西文 Roboto 默认预设了大于 0 的 `letterSpacing`（如 `bodyMedium: 0.25`, `bodyLarge: 0.5`, `bodySmall: 0.4` 等）。当字重增加时，带有正字间距的西文配置应用在全角中文字符上会造成汉字字间距异常放大；
  2. 缺乏应用内独立的字重定制开关，用户如果开启了系统大粗体但只想让 Review 应用保持轻盈精致时无法独立配置。
- **防御性准则与避免再次犯错规范**：
  - **中文字体间距归零规范**：在 `AppTheme._adjustTextThemeFontWeights`、`_buildAdjustedTextTheme` 及 `WeiboTextParser` 中，所有字阶与富文本统一显式声明 `letterSpacing: 0.0`，彻底消除汉字排版的怪异空隙；
  - **个性化独立字重调节**：在「个性化 -> 字体粗细」中增加「自定义应用字体粗细」开关。开启后通过 5 档滑块（细体 -100、标准 0、中等 +100、较粗 +200、粗体 +300）自由控制，且完全不受系统全局设置影响，并提供带富文本的实时卡片预览。

### 8.13 全平台应用图标及相关资源高清重构与规范
- **规范要求**：应用启动图标、各分辨率 Mipmap（mdpi、hdpi、xhdpi、xxhdpi、xxxhdpi）、Web 图标及「关于应用」弹窗 Logo 必须统一从高清源图自动生成；
- **实现方案**：
  - 使用双三次高保真插值（HighQualityBicubic）算法从高清源图生成 `assets/icons/app_logo.png` (512x512) 与 Android 各尺寸 `ic_launcher.png` (48x48 ~ 192x192)；
  - 确保「关于应用」对话框及系统桌面图标 100% 同步更新。

### 8.14 全局设置页面与列表卡片行间距、内边距与排版质感规范 (Settings Layout & Typography Spacing)
- **踩坑现象**：对比「存储设置」页面（舒适、通透、不拥挤），其他设置页面（如「个性化设置」、「微博样式设置」、「设置首页」等）的设置项与文本排版视觉上显得非常拥挤局促。
- **犯错根因**：
  1. **缺少结构化 Card 容器**：部分页面（如 `weibo_style_settings_page.dart`）直接在 ListView 中平铺大量 SwitchListTile/ListTile，没有按照功能区域划分进独立的圆角卡片，导致视觉层级模糊且密密麻麻；
  2. **ListTile 默认行高与间距局促**：Flutter MD3 的 `ListTile` 在没有配置 `contentPadding`、`minVerticalPadding` 以及标题/副标题显式行高时，上下文字与图标贴合过紧；
  3. **副标题与标题行高缺失**：副标题没有配置 `height: 1.4` 且字号未做微调，导致折行或多行说明文字挤作一团。
- **防御性准则与避免再次犯错规范**：
  - **统一全局 `ListTileThemeData` 呼吸感**：
    - 在 `AppTheme.lightTheme` 与 `darkTheme` 中全量配置：
      ```dart
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        minVerticalPadding: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        titleTextStyle: TextStyle(
          fontWeight: adjustFontWeight(FontWeight.w600, fontWeightAdjustment),
          color: scheme.onSurface,
          fontSize: 15,
          height: 1.35,
          letterSpacing: 0.0,
        ),
        subtitleTextStyle: TextStyle(
          fontWeight: adjustFontWeight(FontWeight.normal, fontWeightAdjustment),
          color: scheme.onSurfaceVariant,
          fontSize: 12.5,
          height: 1.4,
          letterSpacing: 0.0,
        ),
      ),
      ```
  - **统一功能分区卡片容器规范**：
    - 所有设置页面一律使用标准 MD3 容器卡片：
      ```dart
      Card(
        elevation: 0,
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.1),
            width: 0.8,
          ),
        ),
        child: ...
      )
      ```
    - 卡片与卡片之间保持 `const SizedBox(height: 14)` 呼吸间距；
    - 卡片内部不同选项之间使用 `const Divider(height: 1, indent: 56)` 或 `indent: 16, endIndent: 16` 优雅分隔，确保视觉清晰、疏密有致、质感出众。

### 4.30 屏幕帧率与分辨率独立控制系统 (`ScreenRefreshRatePage`)
- **功能定位**：在个性化设置中独立控制应用运行时的屏幕帧率（刷新率）与渲染分辨率模式，支持 9 档硬件级精细调节。
- **档位定义矩阵**：
  1. **自动 (0)**：跟随系统全局动态自适应调度；
  2. **原生分辨率 120Hz (1)**：锁定硬件最高原生分辨率（如 `1260x2800`），极致 120Hz 顺滑高刷；
  3. **原生分辨率 90Hz (2)**：最高原生分辨率，均衡 90Hz 流畅体验；
  4. **原生分辨率 72Hz (3)**：最高原生分辨率，细腻 72Hz 平衡显示；
  5. **原生分辨率 60Hz (4)**：最高原生分辨率，标准 60Hz 稳定省电；
  6. **1080P 120Hz (5)**：高效 1080P FHD 渲染，120Hz 极速高刷；
  7. **1080P 90Hz (6)**：高效 1080P FHD 渲染，90Hz 舒适流畅；
  8. **1080P 72Hz (7)**：高效 1080P FHD 渲染，72Hz 节能高刷；
  9. **1080P 60Hz (8)**：高效 1080P FHD 渲染，60Hz 极限长续航。
- **Android 原生实现**：
  - 通过 `MainActivity.kt` 中的 `setScreenRefreshRateMode` 与 `getSupportedDisplayModes` 原生通道；
  - 动态查询 `display.supportedModes` 探测硬件最大物理宽高与可用模式 ID，优先精准匹配物理 `preferredDisplayModeId`，并兜底设置 `window.attributes.preferredRefreshRate`。

### 4.31 深度链接原生拦截与直达系统 (`LinkRoutingService`)
- **功能定位**：全局拦截外部分享链接、文章短链接及应用内点击链接，直达原生页面。
- **Intent 拦截与广播打通**：
  - `MainActivity.kt` 缓存冷启动 `initialUrl`，并在 `onNewIntent` 中截获热启动链接，通过 `MethodChannel('com.sharelite/cookies')` 广播至 Flutter；
  - `main.dart` 启动时调用 `LinkRoutingService.initDeepLinkListener(rootNavigatorKey)` 挂载全局监听。
- **正则匹配矩阵**：
  - 文章：`https?://(?:m\.)?weibo\.cn/(?:status|detail)/([0-9a-zA-Z]+)`、`https?://(?:www\.)?weibo\.com/([0-9]+)/([0-9a-zA-Z]+)`
  - 用户主页：`https?://(?:m\.|www\.)?weibo\.(?:cn|com)/(?:u|profile)/([0-9]+)`
  - 超话社区：`https?://(?:m\.)?weibo\.cn/p/(100808[0-9a-zA-Z_]+)`
- **独立 ID 加载支持**：
  - `StatusDetailPage` 支持传入纯 `statusId`，并自动调用 `getStatusDetail` 异步拉取正文与评论，彻底避免外部打开时白屏或无反应。

### 4.32 全功能内置浏览器与杜绝 404 机制 (`InAppBrowserPage`)
- **功能定位**：接管所有普通网页与 `t.cn` 短链接访问，杜绝外部浏览器 404 与防盗链拦截。
- **核心机制**：
  - **Cookie 全量注入**：在加载网页前通过 `WebViewCookieManager` 将应用内所有登录凭据与 Cookie 注入对应域名；
  - **智能重定向拦截**：在 `onNavigationRequest` 中动态匹配重定向 URL，若目标为微博文章/用户主页/超话，立即拦截并平滑切回原生原生界面；
  - **全套操作栏**：顶部提供返回、前进、刷新、复制链接、系统浏览器打开等完整浏览器交互。

### 4.33 文章正文与多级评论长按划词自由复制系统
- **功能定位**：彻底解决只能整篇复制的问题，实现任意文字长按自由划词、拖动光标与自由复制。
- **实现机制**：
  - 仅在进入文章详情页（`isDetail == true`）时启用 `SelectionArea` 自由划词选区；
  - 在首页时间线列表（`isDetail == false`）中保持轻量文本渲染，确保用户点击卡片文字任何区域均可丝滑流畅点进文章详情；
  - 详情页内部配合 `Text.rich` 与 `TapGestureRecognizer`，实现“点击话题/用户名直达 + 长按拖动光标划词选区”双轨无冲突共存。

### 4.34 视频播放器全能加速与清晰度无缝切换系统 (`WeiboVideoPlayerPage`)
- **功能定位**：全功能视频沉浸式播放体验。
- **核心能力**：
  - **左右长按 2.0X 极速快进**：长按屏幕任意区域即刻触发震动反馈并以 2.0X 倍速快进，顶部展示浮动胶囊指示器，松手即恢复原速；
  - **倍速选择弹窗**：支持 `[0.5X, 0.75X, 1.0X, 1.25X, 1.5X, 2.0X, 3.0X]` 7 档精细调节；
  - **清晰度无缝切换**：从 `playback_list` 解析 1080P/720P/480P/流畅多分辨率视频源；切换时保留当前精确播放毫秒位置与播放状态，实现断点无缝续播。

### 4.35 微博卡片长按唤起操作面板与快捷取关博主机制
- **功能定位**：在信息流列表中提供快捷手势操作与博主管理。
- **核心能力**：
  - **长按卡片唤起菜单**：在未进入文章时，长按微博卡片任意非交互区域触发触感震动，并拉起“更多操作”底部面板；
  - **快捷取关博主**：在“屏蔽博主”上方新增「取关 @博主名称」快捷选项，调用 `FeedRepository.unfollowUser` 双通道直连接口，操作完成即刻给予震动与 Toast 反馈。

### 4.36 自定义应用字体粗细弹窗系统 (5 档精细调节)
- **功能定位**：重构个性化字体粗细交互与统一视觉风格。
- **核心能力**：
  - **5 档单选弹窗**：放弃冗余的滑动条与开关，点击直接弹出选项弹窗（偏细 -100、默认 0、中等 +100、偏粗 +200、加粗 +300），点击即刻生效并闭合；
  - **全量视觉一致性**：板块采用与其他所有个性化 Card 100% 相同的边框、圆角与背景色规范（`colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)`），浅色深色模式下均完美协调；
  - **内嵌效果预览**：底部实时呈现当前字重下的段落排版渲染效果。

### 4.37 官方预设应用图标切换与系统状态双向自同步系统 (`CustomAppIconPage`)
- **功能定位**：提供 3 款高品质官方预设应用图标，支持用户自由切换，通过底层 `activity-alias` 实现手机桌面图标物理切换，并建立 Flutter 与 Android 原生系统状态的双向自同步机制，彻底规避本地存储与系统真实激活组件脱节的问题。
- **核心能力**：
  - **3 套专属官方预设图标（内置高品质无损压缩）**：
    - **官方默认**：基于 `icon1.jpeg` 精细裁切，对应 `.MainActivity` 根入口；
    - **质感经典**：基于 `icon.png` 渲染，对应 `.MainActivityAlias1`；
    - **活力新潮**：基于 `icon3.png`（极简艺术素材）渲染，对应 `.MainActivityAlias2`；
  - **无损微缩压缩与统一格式**：
    - 统一处理为 256x256 高品质标准 PNG，单张平均仅 ~100KB，总增量严格控制在 ~300KB 内，彻底规避安装包体积膨胀；
    - Android 原生对应输出 `mdpi` 到 `xxxhdpi` 全规格 Mipmap 资源；
  - **系统级真实状态双向自同步（彻底解决“默认图标但显示活力新潮”的逻辑 Bug）**：
    - 在原生层实现 `getCurrentAppIcon` 方法，直接查询 Android 底层 `PackageManager.getComponentEnabledSetting` 获取当前系统上真正在运行的组件别名；
    - `CustomAppIconNotifier` 初始化以及用户进入 `CustomAppIconPage` 页面时，自动触发 `syncWithSystem()`，以系统底层真实状态为唯一事实标准自动校正 Flutter 状态与本地持久化缓存，杜绝任何因覆盖安装、系统重置或历史缓存导致的显示与系统状态不一致；
  - **平滑切换与安全进程退出（抽屉防死锁策略）**：
    - 切换时在后台线程中采用 `PackageManager.SYNCHRONOUS` 强刷盘标志，**先禁用其余旧别名、最后启用目标别名**，彻底杜绝系统广播合并期间 Launcher 抽屉优先抓取到排位靠前的旧别名（如质感经典）导致死锁卡顿的问题；
    - 进程退出延时由 600ms 提升至 1200ms，为 vivo 等深度定制系统的 Launcher 后台服务提供充分的 SQLite 图标缓存重建与广播处理窗口期；
  - **全场景应用内 Logo 同步联动**：
    - 「系统设置」->「关于 Review」弹窗等位置实时读取 `customAppIconProvider`，应用内展示与所选图标 100% 保持一致；
  - **资源受控保护**：预置图标不可删除，支持用户无限制自由平滑切换。

### 4.38 搜索多维结果流与官方 1:1 原生大搜体系 (`SearchResultsPage` & `s.weibo.com` 原生直连)
- **功能定位**：彻底解决此前搜索“散乱无互动、无置顶、缺少双方当事人/大V热门”的问题。全面放弃客户端自定义筛选与打分排序逻辑，直接接入微博原生网页端综合大搜引擎 `https://s.weibo.com/weibo`，实现与官方网页端 1:1 精准对齐与纯净渲染。
- **核心能力**：
  - **专属词条介绍卡片（严格位于搜索栏与分类顶栏中间）**：
    - 自动并发解析官方搜索接口中的 `topicHeads` 结构；
    - 呈现词条封面大图（大圆角，点击支持无缝调起沉浸式画廊全屏浏览）；
    - 呈现词条标准化标题（如 `#TTG对战AG#`）以及一键复制/分享话题链接；
    - 实时阅读量（如 `3.9亿`）与讨论量（如 `16.8万`）的中文数值格式化呈现；
    - 词条导语与简介说明（`summary`）；
    - 话题主持人身份标签（`claim_info`）与点击直达博主主页能力；
  - **官方原生徽章渲染体系 (1:1 对齐官方网页版)**：
    - **置顶徽章 (`📌 置顶`)**：对应官方 `card-top` 置顶，赋予绿色背景与图钉图标，强制排布在“综合”流首位；
    - **热门徽章 (`🔥 热门`)**：对应官方 `card-top` 热门，赋予橙红色渐变背景与火焰图标，精准标记官方当事蓝 V（如广州TTG、成都AG超玩会）及权威赛事解说大 V 发帖；
    - **纯净动线衔接**：热门博文之后无缝衔接后续最新动态与讨论流；
  - **彻底移除冗余的自定义卡片**：
    - 彻底删除了原先客户端自制的“话题关联官方账号”大列表，解决账号堆叠、头像异常与粉丝数显示为 0 的体验缺陷，让搜索结果动线与官方网页版 100% 保持纯净一致；
  - **“综合”与“实时”分流体验**：
    - **综合流**：完全沿用 `s.weibo.com` 原生排序（置顶 + 热门 + 最新深度加权）；
    - **实时流**：严格按发布时间倒序排布，满足用户探索最新用户碎碎念与实时现场的需求。

### 4.39 微博博文编辑记录查看系统 (`EditHistoryBottomSheet` 与 `/ajax/statuses/editHistory` 原生直连)
- **功能定位**：全面支持查看微博博文的历史修订版本（如包含 `edit_count > 0` 的微博），实现与官方网页端（点击“更多”->“查看编辑记录”）1:1 对齐的历史版本时间线与正文内容对照。
- **核心能力与实现细节**：
  - **原生纯净接口实测直连**：
    - 接口路径：`https://weibo.com/ajax/statuses/editHistory`
    - 核心参数：`mid={mid}&page={page}`（经实测严禁传 `id`，必须传字符串或长整数 `mid`，否则微博后端报 400 错误；带 `Referer: https://weibo.com/` 请求头以通过防盗链拦截）；
    - 返回结构：标准 `ok: 1, total: N, statuses: [...]`，包含完整的修订历史列表；
  - **状态模型与编辑标记扩展 (`WeiboStatusModel`)**：
    - 新增 `editCount`（字段 `edit_count`，默认为 0）与 `isEdited` 计算属性（`editCount > 0`）；
    - 在微博卡片头部（发布时间右侧）若检测到博文已编辑，高亮呈现可点击的 `已编辑` 胶囊微标签（Pill Badge），点击直接拉起编辑历史；
  - **更多操作面板入口 (`TweetCard`)**：
    - 在博文卡片“更多操作”底部菜单中，若博文已编辑，在最顶层优先呈现「查看编辑记录」项，并贴心显示「已编辑 N 次」副标题，点击即可无缝调起编辑历史；
  - **M3e 沉浸式修订历史弹窗 (`EditHistoryBottomSheet`)**：
    - 采用 Material 3 Expressive 28dp 超大圆角容器与 38dp 触觉拖动手柄；
    - 顶部呈现动态计数（如 `共 2 个修订版本`）与博主身份标识；
    - 版本卡片采用 Expressive 20dp 独立卡片，具备鲜明版本徽章标识：
      - 当前最新版本标红凸显：`🔥 最新版本 (当前)`；
      - 历史版本标示：`第 N 版`；
      - 最初发布版本标青凸显：`🌱 首次发布`；
    - 完整支持修订时间格式化、发布 IP 属地展示、富文本解析（话题/用户/表情/链接直达）及配图九宫格全功能点击大图预览；
    - 支持触底分页加载历史修订，优雅适配网络异常与空态重试。

### 4.40 Material 3 Expressive (M3e) 全局视觉体系与触觉动效升级
- **设计规范指引**：依据 Google 官方 Material 3 Expressive 设计规范 (`https://m3.material.io/blog/building-with-m3-expressive`)，全面提升应用的视觉层级感、形态张力、触觉反馈与动效生动度。
- **核心升级细节**：
  - **卡片容器圆角升级 (Expressive Radii)**：
    - 普通微博卡片、功能卡片圆角由传统的 16dp 提升至 **22dp**，赋予内容流更强烈的圆润现代感与呼吸感；
    - 卡片内部嵌套的转发微博卡片统一采用 **16dp** 柔和微圆角与极淡容器描边，形成清晰舒适的视觉嵌套包裹秩序；
    - 微博相片九宫格：单图模式采用 **16dp** 圆角，多图模式采用 **12dp** 连续平滑圆角；
  - **底部抽屉与对话框标准 (Expressive BottomSheet & Dialog)**：
    - 底部操作弹窗、编辑记录弹窗全面升级为 **28dp** 顶部大圆角，顶端居中配备 **38x4.5dp** 的 M3e 物理触觉拖动手柄（Tactile Drag Handle）；
    - 全局对话框升级为 **28dp** 标准 Expressive Dialog 圆角；
  - **底栏导航与浮动指示器 (Expressive Navigation Bar)**：
    - 导航栏指示器采用标准 `StadiumBorder()` 胶囊形态，高度设定为 68dp，背景色提升为 `colorScheme.surfaceContainer`，带来更为沉浸的层级过渡；
  - **浮动操作按钮 (Expressive FAB) 与搜索栏 (Search Bar)**：
    - FAB 按钮采用 20dp 柔和 Squircle 平滑圆角；
    - 搜索框统一采用全椭圆 `StadiumBorder()` 药丸胶囊轮廓；
### 4.41 微博评论与二级楼中楼回复全链路修复与防跨域 CSRF 令牌架构
- **核心痛点与排查**：
  - 针对 v1.5 版本中发送评论提示“发送失败，请你检查登录状态与网络后重试”的问题进行了抓包与微博后端原生接口深度调试，定位出三大根因并完成系统性解决：
    1. **移动端与桌面端 XSRF-TOKEN 域名冲突与 Cookie 污染**：原 `ensureXsrfToken` 优先请求 `m.weibo.cn/api/config` 获取 `st` 令牌，移动端响应返回了 `SUB=deleted` 并在 Cookie 中植入移动端专属令牌；后续向 `weibo.com/ajax/comments/create` 发起桌面端评论请求时，携带了移动端错配令牌，被微博安全网关拦截并返回 403 Forbidden（CSRF Error）；
    2. **回复接口参数字段偏差**：微博桌面端 `/ajax/comments/reply` 强制要求携带参数键名为 `id`（微博数字 mid）与 `cid`（被回复评论 ID）；此前代码传递了 `'mid': statusId` 导致微博后端报 400 Bad Request；
    3. **微博唯一标识类型限制 (Base62 mblogid vs 64位纯数字 mid)**：微博评论接口只接受 64 位纯数字字符串 ID，若传入 Base62 字母串（如 `RgxuHaukX`），微博后端拒绝解析并直接返回 400 错误。
- **核心升级与实现细节**：
  - **桌面原生 CSRF 令牌防护与智能自愈 (`WeiboDioClient`)**：
    - `ensureXsrfToken` 统一使用桌面端端点 `https://weibo.com/ajax/statuses/config` 及 `https://weibo.com/ajax/config/getconfig`，携带 PC 统一 UA 与 Referer，消除跨端 Cookie 互相注销与令牌污染；
    - 请求拦截器通过正则表达式 `RegExp(r'XSRF-TOKEN=[^;]+')` 动态检测并原地替换更新持久化 Cookie 中的最新令牌；
    - 响应中若检测到 403 跨站伪造拦截，自动触发 `forceRefresh` 重试机制，无感静默恢复请求。
  - **Base62 字母 ID 转换 64 位纯数字 mid 算法 (`WeiboStatusModel.mblogidToMid`)**：
    - 内置标准微博 Base62 编码转换算法（每 4 位字母切片逆向换算并补齐 7 位高位 0），实现字母 ID 与 64 位数字 ID 的无损互转；
    - 在 `DetailRepository.sendComment` 与 `DetailRepository.replyComment` 前置统一执行数字归一化，无论是从路由、分享短链还是缓存进入详情页，均可 100% 成功发起评论与回复。
  - **精准错误反馈机制 (`CommentActionResult`)**：
    - 重构底层结果为 `CommentActionResult(success, message)`，精细化捕获 `DioException` 并提取微博返回的错误提示（如微博被删除、内容含敏感词、频率限制、账号异常等）；
### 4.42 评论与楼中楼删除系统、触觉单震动优化与系统版本同步
- **功能背景与权限机制**：
  - 全面支持用户删除自身发表的评论（包括一级评论与二级楼中楼回复），同时支持博主在自己发布的微博正文下删除他人发布的任何评论；
  - 权限识别算法：
    - `isMyComment`：当前登录账号 UID 与评论作者 UID 一致（`comment.user.id == myUid`）；
    - `isMyStatus`：当前登录账号 UID 与当前微博博主 UID 一致（`status.user.id == myUid`）；
    - `canDelete = isMyComment || isMyStatus`，满足任一条件即在操作弹窗中呈现删除选项，避免非法操作。
- **原生接口与调用标准**：
  - 接口端点：`POST https://weibo.com/ajax/statuses/destroyComment`；
  - 核心载荷：`{'cid': numericCid}`（数字字符串评论 ID，自动经过 `mblogidToMid` 归一化校验）；
  - 携带请求头：`Referer: https://weibo.com/`、`X-Requested-With: XMLHttpRequest` 及与 Cookie 同步的 `X-XSRF-TOKEN`；
  - 响应校验：返回 `{ok: 1, data: {...}}` 代表成功注销。
- **交互与视觉标准 (`StatusDetailPage`)**：
  - 点击或长按任意一级评论或二级楼中楼，呼出 Material 3 Expressive 28dp 大圆角操作面板；
  - 列表项依次呈现：
    1. 「回复 @昵称」；
    2. 「复制评论内容」；
    3. 「删除评论」（位置严格排列于复制评论内容正下方，采用 `colorScheme.error` 醒目红标警示，若为博主删除他人评论，贴心附加“博主可删除他人评论”副文本提示）；
  - 点击删除触发二次确认对话框（`AlertDialog`），确认后静默调用 `destroyComment` 接口；
  - 成功后即时触发震动触感反馈、弹出轻提示，并立即在本地列表移除该评论及关联楼中楼，无需整页重载。
- **触觉震动反馈精简（解决长按双震动）**：
  - 针对长按评论条目会触发两次震动的问题，定位出原因在于 Flutter 的 `InkWell` 在长按时默认调用了 `Feedback.forLongPress(context)`，与应用内部呼出弹窗时的 `HapticFeedbackUtil.light()` 叠加触发；
  - 在评论与子评论的 `InkWell` 组件中统一配置 `enableFeedback: false`，彻底消除组件内置冗余震动，确保长按仅触发一次干脆轻巧的触觉反馈。
- **系统包名与版本信息硬核同步**：
  - 针对系统应用安装器识别版本落后（显示为 1.5）的问题，全面核查并修正 `android/app/build.gradle.kts` 中 `defaultConfig` 的硬编码配置；
  - 严格同步 `versionCode = 7` 与 `versionName = "1.6"`，确保 Android 系统包解析、应用内关于页面以及 `pubspec.yaml` 三方版本号绝对一致。

### 4.43 微博正文与评论 @提到用户 解析与直达检索链路修复
- **问题排查与根因剖析**：
  - 用户反馈在特定微博（如 `5878848794/RgqqGz4iz` 与 `6074356560/5339192420207768`）中点击 `@提到用户`（如 `@成都AG救赎_`、`@成都AG丶轩染`、`@成都AG小麦-`、`@BaocQqqq` 等）时，应用内无法搜到用户且个人主页信息为空，而网页版均能正常访问；
  - 经排查定位，原应用在通过 `screenName` 打开 `UserProfilePage` 时，仅依赖了搜索联想建议接口 `/ajax/side/search` 反查数字 UID。该接口仅收录极少数头部热门账号或联想词条，大量垂直领域博主（包含下划线、中划线等特殊命名的用户）在联想池中返回空列表，导致 UID 获取失败，时间线随之请求中断；
  - 经对微博原生网络请求逆向验证，微博官方网页端在访问 `/n/{screen_name}` 时，底层直接调用 `/ajax/profile/info?screen_name={screen_name}`（支持精准通过去除 `@` 前缀的昵称直达），可 100% 稳定获取用户完整详情（数字 UID、头像、认证标识、粉丝数等）。
- **核心修复与实现细节**：
  - **用户主页原生昵称直连与缓存升级 (`UserProfilePage`)**：
    - `initState` 规范化过滤：对传入的 `screenName` 自动剥离前缀 `@`，并支持优先命中 `_profileUserCache` 中的昵称缓存，实现零延迟即时呈现；
    - `_fetchUserProfileAndTimeline` 双重检索策略：
      1. 第一层（核心）：优先直接调用 `/ajax/profile/info?screen_name={cleanScreenName}`，直接获取官方完整用户对象与真实数字 UID，秒级点亮主页资料与统计数据；
      2. 第二层（降级容灾）：若直接昵称未命中，自动无缝降级至 `/ajax/side/search` 模糊联想池；
    - 下拉刷新自愈：在 `EasyRefresh.onRefresh` 中，若检测到 `_user.id.isEmpty`（如首次弱网未解析成功），下拉刷新会自动重新触发全量检索链路并加载博文。
  - **搜索仓库联想直达增强 (`SearchRepository.getSearchSuggestions`)**：
    - 在用户搜索联想若未在侧边栏接口匹配到有效用户时，自动回退并发尝试精准昵称查询，确保在全局搜索框搜索特定博主昵称（如带有 `@` 或特殊符号）时，博主专属名片卡片亦能稳健置顶展示。
  - **链接深层路由全网覆盖 (`LinkRoutingService`)**：
    - 在 `canHandleNatively` 与 `openUrl` 中新增对 `weibo.com/n/{screenName}` 与 `m.weibo.cn/n/{screenName}` 官方网页重定向协议的原生正则拦截，自动解码并无缝路由至 `UserProfilePage(screenName: screenName)`。

### 4.44 视频播放器横屏显示、全功能手势控制（亮度/音量/进度/倍速）及下载与分享系统 (`WeiboVideoPlayerPage`)
- **功能背景与用户诉求**：
  - 针对此前视频播放仅能全程竖屏导致横屏视频视野局促的问题，新增一键横屏旋转切换支持；
  - 界面顶栏右侧新增「下载」与「分享」按钮（精准剔除冗余的小窗、投屏与更多菜单项）；
  - 针对视频播放沉浸式交互，全面构建通用手势、横屏分界手势、竖屏分界手势及高质感 M3 HUD 浮层提示。
- **横竖屏自由旋转与沉浸式 UI 架构**：
  - **切换按钮布局**：在底栏控制行中，横竖屏切换图标按钮严格置于进度条下方最右侧（画质选择项右侧）；
  - **系统屏幕方向接管**：通过 `SystemChrome.setPreferredOrientations` 在 `landscapeLeft/landscapeRight` 与 `portraitUp` 之间无缝切换；
  - **系统栏沉浸式自适应**：横屏状态下自动激活 `SystemUiMode.immersiveSticky` 隐藏系统状态栏与导航栏，扩展至极致全屏视野；竖屏状态下自动切回 `edgeToEdge`；
  - **安全返回拦截 (`PopScope`)**：横屏播放状态下，无论用户点击顶部返回按钮、物理返回键还是触发侧滑返回手势，优先平滑回退至竖屏状态，二次返回时方退出播放器，杜绝直接退出页面的突兀体验；页面销毁（`dispose`）时确保 100% 恢复全局竖屏方向。
- **全维度视频触控手势控制矩阵 (1:1 响应用户规范)**：
  1. **通用手势**：
     - **左右长按倍速**：长按屏幕左侧（`x < 0.45`）或右侧（`x > 0.55`），触发清脆轻微触感震动，瞬时切换至 2.0X 倍速快进，顶部展示 `2.0X 快进中` 药丸胶囊 HUD，手指抬起时自动无感恢复原速；
     - **双击左右两侧快进/快退**：双击屏幕左侧 35% 区域向后快退 10 秒（`-10s`），双击屏幕右侧 35% 区域向前快进 10 秒（`+10s`），居中弹出动效指示徽章；
     - **双击中间播放/暂停**：双击屏幕中央 30% 区域（`0.35 <= x <= 0.65`），直接切换播放与暂停；
     - **单击屏幕**：平滑唤出或隐藏顶底控制栏，内置 4 秒无操作自动淡出计时器。
  2. **横屏状态下手势（以屏幕水平中线为分界）**：
     - **左侧垂直滑动**：调节屏幕亮度（范围 0.01 ~ 1.0），无级平滑线性调节，中央居中弹出当前亮度百分比 HUD 与太阳图标；
     - **右侧垂直滑动**：调节媒体音量（范围 0.0 ~ 1.0），中央居中弹出当前音量百分比 HUD 与喇叭图标；
     - **水平滑动**：全屏范围任意左右拖动即可调整视频播放进度，中央 HUD 显示目标跳转时间、总时长及快进快退秒数差值，松手瞬间精准 Seek。
  3. **竖屏状态下手势（以屏幕水平中线为分界）**：
     - **左侧垂直滑动**：调节屏幕亮度；
     - **右侧垂直滑动**：调节媒体音量；
     - **底部水平滑动**：以视频画面下半区域为感知热区，左右滑动精确调节播放进度。
- **Android 原生亮度与音量无权限静默调节通道 (`MainActivity.kt`)**：
  - 亮度通道：基于 `window.attributes.screenBrightness` 直接调控当前窗口亮度，无须向用户索取侵入性的系统设置修改权限（`WRITE_SETTINGS`），退出页面时系统自动恢复默认亮度；
- **视频原生下载与系统级分享体系**：
  - **视频下载**：顶栏下载按钮调用 `Dio.download` 流式落盘至缓存目录，并通过原生 `saveMediaToGallery(isVideo: true)` 将视频保存至系统相册 `Movies/Review` 目录，同步触发 Android 媒体扫描广播（`MediaScannerConnection`），相册立即可见；
  - **系统分享**：调用 Android 原生 `ACTION_SEND` 意图，支持唤起系统分享面板分享视频标题与直链，并在无对应应用时自动复制链接至剪贴板。
- **手势竞技场分层隔离与控制栏按钮 0ms 即时响应**：
  - **排查与根因**：全屏手势监听器若直接包裹整个播放器页面（含顶底控制栏），其包含的 `onDoubleTap`、`onLongPress` 与 `onPan` 手势识别器会在 Flutter `GestureArena` 竞技场中与子组件的 `IconButton` / `InkWell` 点击产生竞争，强制系统等待 300~500ms 双击与长按判断窗口，造成底栏画质/倍速/横屏按钮及顶栏下载/分享按钮点击明显迟滞；
  - **分层解耦架构**：将全屏手势监听器独立收拢为 `Positioned.fill` 手势专属层，严格置于视频画面上方、操作控制栏下方；顶栏与底栏独立位于最上层。点击控制栏各功能按钮直达子组件，0ms 瞬时触发，彻底消除延迟；
- **单次点击双重震动消除（单通道触觉规范）**：
  - **排查与根因**：应用全局主题在 `app_theme.dart` 中统一配置了 `splashFactory: const HapticSplashFactory()`，所有 `InkWell` 与 `IconButton` 在手指按下瞬间（`onPointerDown`）会自动触发一次轻柔触觉震动；若在业务按钮回调（`onTap` / `onPressed` 或 `_toggleOrientation`、`_showSpeedMenu`、`_showQualityMenu`、`_performDownloadVideo`、`_performShareVideo` 等方法）中再次手动调用 `HapticFeedbackUtil.light()`，则在手指抬起瞬时又会触发一次震动，表现为“点下去震一次、抬起来震一次，点一下震两下”；
  - **防御性消除**：全量清理顶栏（返回、下载、分享）及底栏（倍速、画质、横屏开关、播放暂停）所有按钮回调中的二次手动震动调用，统一由 `HapticSplashFactory` 负责物理级瞬时按下单次震动，严格做到“点一下震一下”。

### 4.45 图片画廊横向分页与斜向手势隔离修复 (`ImageGalleryPage`)
- **问题现象**：查看多图时，手指左右滑动若带有斜角，外层图片滑出手势可能抢占分页手势，导致图片斜向拖动、顿挫，甚至直接销毁画廊；关闭滑出手势后，部分拖动又可能只被图片手势消费而没有推动分页器。
- **根因**：`ExtendedImageGesturePageView` 的横向分页与 `ExtendedImageSlidePage`/`enableSlideOutPage` 的图片退出手势存在 Gesture Arena 竞争；同时分页器未显式配置滚动物理。
- **修复规范**：
  - `ExtendedImage` 在多图画廊中设置 `enableSlideOutPage: false`，单指拖动不再触发滑出销毁；
  - `ExtendedImageGesturePageView` 显式使用 `const ClampingScrollPhysics()`，让横向分页器稳定接管拖动；
  - 外层 `ExtendedImageSlidePage` 的轴向及背景渐隐计算限定为水平轴，避免出现斜向位移视觉效果；
  - 斜向但带有明显左右分量的滑动，统一按横向分页处理；退出画廊使用返回按钮或点击退出。
- **历史验证结果（2.5.3）**：该次 release APK 已验证为 `com.review`、`versionName 2.5.3`、`versionCode 39`；当时 Flutter 全部 112 项测试通过。

### 4.46 发出的评论直达、置顶与官方游标分页修复 (`LikesCommentsPage` / `StatusDetailPage`)
- **问题现象**：从「我的消息 → 发出的评论」打开一条评论时，详情页只打开原微博，目标评论要等评论区按顺序加载后才出现在中间位置；大评论量微博还可能因分页参数或返回结构变化而无法找到目标评论。
- **根因**：原跳转只传入微博状态，未把消息记录中的评论对象传给详情页；评论续页固定使用 `is_mix=0`，未完整遵循网页端的 `max_id` 续页参数；部分官方响应把评论列表和游标封装在嵌套 `data` 中，且 `rootid=0` 不能作为有效父评论处理。
- **实现规范**：
  - `LikesCommentsPage` 解析并传递 `initialComment`、评论 ID 和父评论 ID；详情页首帧先显示目标评论置顶预览，避免等待整页评论加载。
  - 官方评论树返回后按规范化评论 ID 去重；找到目标后把所属一级评论线程移动到顶部，并滚动到目标评论。楼中楼目标按 `reply_comment` 父链补拉二级评论，找到后使用真实官方评论替换预览。
  - `DetailRepository.getComments` 首页使用 `is_reload=1/is_mix=0`，续页使用 `is_reload=0/is_mix=1`，携带 `max_id_type=0`、`fetch_level=0`、`type=1` 与 `locale=zh-CN`，并拒绝重复游标，避免高评论量微博死循环或停在首屏。
  - 评论 ID 兼容 `id`、`idstr`、`cid`、`cidstr`、`comment_id` 等字段，并兼容 Base62 与数字 mid；无效的 `0`、`-1` 和空父 ID 不参与父链定位。
- **历史验证结果（2.5.3）**：新增评论分页、嵌套回复、跨 30 页定位、目标评论置顶预览和删除入口回归测试；当时 Flutter 全部 112 项测试通过。

### 4.47 微博直播动态官方状态识别与播放器自愈修复
- **问题背景**：部分直播动态的微博卡片包含的是直播房间网页地址，而不是可直接播放的媒体 URL。旧逻辑把房间页或过期地址交给原生播放器，表现为持续转圈、视频加载失败或链接已失效；直播结束后还可能错误播放回放。
- **数据模型与请求链路**：
  - `WeiboStatusModel` 从 `live`、`live_info`、`wblive`、`page_info`、`card_info` 和 `url_struct` 等官方字段提取 `liveId`，并保留 `liveStatus`；直播动态即使暂时没有直连流，也仍被识别为可进入播放器的媒体内容。
  - `FeedRepository` 与 `DetailRepository` 在直播 ID 存在且缺少可播放流时，调用官方房间元数据接口 `ApiConstants.liveRoom`，补齐封面、标题、状态及当前播放流。
  - 仅当官方 `status=1` 时采纳当前直播流；房间 HTML URL 永远不传给 `video_player`。`replay_origin_url` 不作为当前直播流的降级来源。
- **播放器状态表现**：
  - `status=1`：播放官方当前直播流；
  - `status=0`：显示“直播尚未开始”；
  - `status=3`（官方回放）及 `status=5` 等其他结束/非直播状态：统一显示“直播已结束”，不自动进入回放；
  - 官方状态查询失败时保留原有普通视频播放链路，不凭空伪造直播结束状态；只有确认是直播房间且取得官方状态后，才显示对应直播状态文案。
- **覆盖范围**：时间线卡片、微博详情、转发嵌套卡片和个人主页视频卡片均传递 `liveId` / `liveStatus`，统一使用同一套官方状态识别和播放规则。
- **历史验证结果（2.5.5）**：覆盖直播房间页解析、直接直播流 URL 规范化和 `status=3` 不提升回放流的回归测试；Flutter 全部 114 项测试通过。release APK 已核验为包名 `com.review`、`versionName 2.5.5`、`versionCode 41`，文件为 `D:\App\Review\Review_v2.5.5.apk`。

### 4.48 登录 Cookie 域隔离与时间线空态自愈修复
- **问题**：偶发出现 Cookie 检测有效，但时间线为空，退出账号重新登录后恢复。
- **根因**：移动端 `m.weibo.cn` 与桌面端 `weibo.com` 的 Cookie 在 WebView/SSO 恢复期间可能不同；旧原生桥接将不同域名 Cookie 无序合并，移动端接口成功也不能证明桌面关注流可用。
- **修复**：
  1. Android 原生 CookieManager 按桌面端/移动端域名分别读取并持久化；
  2. 桌面端网络请求优先使用 `weibo.com` Cookie，移动端请求优先使用 `weibo.cn` Cookie；
  3. 登录自动识别和“检测凭据有效性”以 `GET https://weibo.com/ajax/config/getconfig` 的桌面会话为权威，不再用移动端配置、未读流或公开个人资料单独判定有效；
  4. 应用启动及关注时间线出现空响应时，先执行一次会话同步并重新请求，且并发同步合并，避免退出重登才能恢复；
  5. XSRF-TOKEN 更新同步写回三类 Cookie，防止重启后使用旧令牌。
- **兼容性**：旧版本只有完整 Cookie 时自动作为桌面/移动端的初始回退，不影响已有登录态；未使用或保存用户提供的 Cookie。
- **后续更正**：本节修复了运行期间的分域读取和空响应重试，但当时没有为升级用户迁移已经落盘的旧混合 Cookie，也只校验单个桌面候选值。旧混合值若被写入桌面槽位，仍可能遮蔽后方有效的完整 Cookie；该迁移缺口由 4.56 修复。
- **验证结果（2.5.6）**：Flutter 全部 114 项测试通过；release APK 已核验包名 `com.review`、`versionName 2.5.6`、`versionCode 42`，文件为 `D:\App\Review\Review_v2.5.6.apk`。

### 4.49 高评论量微博评论官方续页参数修复
- **问题**：部分评论数量较多的微博在应用内只能显示少量评论，继续滚动后无法加载剩余内容；普通微博表现不明显。
- **核对结果**：对照同一微博的网页版网络请求，首屏请求使用 `is_reload=1`、`is_mix=0`、`count=10`；续页继续使用 `is_reload=1`、`is_mix=0`，携带官方返回的 `max_id`，并将 `count` 提高为 20。原应用续页错误使用 `is_reload=0`、`is_mix=1`，并附加网页版当前未使用的分页参数，容易在高评论量微博上无法正常推进游标。
- **修复**：
  1. 评论首屏与续页统一使用官方网页版的 `is_reload=1`、`is_mix=0` 参数；
  2. 首屏默认请求 10 条，续页默认请求 20 条，减少高评论量微博的请求次数；
  3. 移除当前网页版未使用的 `max_id_type` 与 `type` 参数，保留官方需要的 `id`、`uid`、`flow`、`fetch_level` 和 `locale`；
  4. 只使用响应中的官方 `max_id` 推进分页，并将空值、`null`、`-1` 统一识别为结束游标，避免错误续页或重复请求。
- **影响范围**：仅调整详情页评论的官方请求参数、分页数量和游标终止判断，不改变评论排序、评论展示、楼中楼补拉、评论删除及发表评论逻辑。
- **验证结果（2.5.7）**：评论分页定向测试通过；Flutter 全部 115 项测试通过。release APK 已核验包名 `com.review`、`versionName 2.5.7`、`versionCode 43`，文件为 `D:\App\Review\Review_v2.5.7.apk`，SHA-256 为 `86C5312A076C42B29709E91C6ADD3CEA74B92A40F063420917FBB09270604CE2`。

### 4.50 深度文章 HTTPS 链接与个人主页头像预览修复
- **问题**：部分微博的深度测评报告等文章卡片返回 `http://weibo.com/ttarticle/...` 链接。网页版会将它 301 到 HTTPS，但 Android WebView 在当前 `cleartext` 安全策略下会在重定向前拦截明文请求，表现为“网页无法加载”。个人主页顶部博主头像此前只有展示，没有打开大图的入口。
- **核对结果**：指定微博的网页正文中真实文章链接为 `http://weibo.com/ttarticle/p/show?id=2310475343796384104518`，服务器响应为 301，目标为同路径 HTTPS 地址；普通外部 HTTP 链接不应被改写。
- **修复**：
  1. `LinkRoutingService` 仅对 `weibo.com` / `weibo.cn` 及其子域的 HTTP 链接升级为 HTTPS，保留查询参数并继续交给官方文章页面加载；
  2. `InAppBrowserPage` 初始加载和后续微博导航都复用同一规范化逻辑，避免文章页面再次跳回明文 URL；
  3. 个人主页顶部头像使用现有 `ImageGalleryPage` 打开，优先使用 `avatar_hd`，缺失时回退 `avatar`，不改变头像图片本身的下载和缓存逻辑。
- **影响范围**：只调整官方微博文章链接的协议和个人主页顶部头像的查看入口，不改变普通外链、时间线微博内容、账号会话或头像展示。
- **验证结果（2.5.8）**：链接路由定向测试及 Flutter 全部 116 项测试通过；release APK 已核验包名 `com.review`、`versionName 2.5.8`、`versionCode 44`，文件为 `D:\App\Review\Review_v2.5.8.apk`，SHA-256 为 `4B73983F5776C0AF8EFF8608C9D09CD3D460ED693EF70475DC18475722B174BE`。

### 4.51 微博深度文章原生渲染、返回键与外部浏览器修复
- **问题与根因**：
  - `weibo.com/ttarticle/p/show?id=...` 之前被统一送入 `InAppBrowserPage`，实际显示的是网页容器，不是应用内原生文章内容；
  - 内置浏览器的 `PopScope` 会优先消费 WebView 历史记录，官方文章 HTTP→HTTPS 重定向后，左上角返回键表现为刷新或没有返回；
  - “在外部浏览器打开”没有检查 `url_launcher` 的返回结果，Android 11+ 也没有声明 HTTP/HTTPS 的外部 Intent 查询，因此失败时没有任何可见反馈。
- **官方内容核对**：官方文章页提供稳定的 `node-type="articleTitle"`、`node-type="contentBody"`、`.authorinfo` 与正文 `figure/img` 节点。应用使用这些官方 HTML 内容作为唯一数据源；没有在本地写入或拼接文章正文。
- **修复**：
  1. `LinkRoutingService` 识别官方 `ttarticle` URL，保留完整文章 ID（按字符串处理，避免长数字精度丢失），改为打开 `WeiboArticlePage`；普通微博详情、主页、超话和外部链接路由保持原样；
  2. 新增原生 Flutter 文章页：显示官方标题、作者头像、作者/时间/阅读信息、章节标题、段落和正文图片；图片继续复用现有原生画廊，文章刷新也从官方地址重新取数；
  3. 内置浏览器左上角明确执行路由返回，不再把 WebView 历史后退误当作页面返回；系统返回仍保留原有 WebView 历史处理；
  4. 原生文章页和内置浏览器均对外部浏览器调用检查成功/失败结果；Android Manifest 增加 HTTP/HTTPS VIEW Intent 查询，失败时显示“未找到可用的外部浏览器”。
- **影响范围**：仅改变官方长文 `ttarticle` 的展示路由和返回/外部打开行为；普通网页仍使用内置浏览器，微博登录凭据、微博卡片和其他页面不改变。
- **验证结果（2.5.9）**：路由与官方 HTML 解析定向测试通过；Flutter 全部 117 项测试通过。release APK 已核验包名 `com.review`、`versionName 2.5.9`、`versionCode 45`，文件为 `D:\App\Review\Review_v2.5.9.apk`，SHA-256 为 `F8DAA61B6CAA99DA6EFFBCF6AA749CD09A033FE8EF07105C0A1973C512257892`；构建完成后项目根目录仅保留当前 APK，旧的 `Review_v2.5.8.apk` 已删除。

### 4.52 深度文章 HTML 请求隔离与登录态兜底修复
- **问题与核对**：
  - 原生文章页使用通用 `WeiboDioClient.dio` 请求长文，而该客户端面向 JSON AJAX 接口，统一注入 `X-Requested-With`、CSRF 和访客重试逻辑；部分设备会因此拿到登录/空壳页面，解析不到 `contentBody`，最终显示“文章加载失败”。
  - 用同一文章 ID 对官方地址进行真实请求验证：官方 HTML 页面本身能返回 `node-type="articleTitle"` 和 `node-type="contentBody"`，问题不在文章资源失效。
- **修复**：
  1. `WeiboDioClient.getArticleHtml` 使用独立的 HTML `Dio` 请求，不继承 JSON/AJAX 拦截器；保留桌面 Cookie 用于受限文章；
  2. 如果桌面会话返回登录页或空壳，自动尝试完整 Cookie 和无 Cookie 的公开文章请求，避免陈旧会话阻断公开文章；
  3. 继续以官方 HTML 正文为唯一数据源，解析失败时不填充本地伪造内容。
- **影响范围**：只调整长文读取通道，不改变时间线、登录 Cookie 分域、JSON API、文章原生渲染和外链路由。
- **验证结果（2.5.10）**：官方文章请求冒烟验证通过，Flutter 全部 117 项测试通过；release APK 已核验包名 `com.review`、`versionName 2.5.10`、`versionCode 46`，文件为 `D:\App\Review\Review_v2.5.10.apk`，SHA-256 为 `E4F28437B05F9EAFBCBCB9E760211247B29D025AD99E644AA1E3473F7FD8A3E4`；构建完成后项目根目录仅保留当前 APK，旧的 `Review_v2.5.9.apk` 已删除。

### 4.53 深度文章短链接解析与多会话响应选择修复
- **问题与核对**：指定微博 `https://weibo.com/6048569942/Rinlk6N10` 的官方状态接口返回的正文链接为 `http://t.cn/AXOxP3Ga`，正文末尾还带有零宽字符；同一响应的 `url_struct` 才提供真实的 `long_url`：`http://weibo.com/ttarticle/p/show?id=2310475343796384104518`。原链接匹配使用严格字符串相等，零宽字符导致无法命中 `url_struct`，应用可能把短链接交给通用网页路由，随后文章页拿不到正文。
- **修复**：
  1. `WeiboTextParser` 在匹配 `short_url`、`ori_url`、`long_url` 前清理微博附加的零宽字符，并优先使用官方 `long_url`，确保深度文章直接进入原生文章页；普通短链接仍沿用原有通用路由。
  2. `WeiboDioClient.getArticleHtmlCandidates` 保留桌面 Cookie、完整 Cookie、无 Cookie 三组非空官方 HTML 响应；原生文章页逐份解析，只采用真正包含正文块的响应，避免陈旧登录态返回 200 空壳时提前失败。
  3. 未改变文章 ID 的字符串处理、官方 HTML 唯一数据源、普通外链路由和登录 Cookie 存储。
- **验证结果（2.5.11）**：使用官方状态接口核对了文章短链接与 `url_struct.long_url` 的对应关系；新增零宽字符短链接解析回归测试；Flutter 全部 118 项测试通过。release APK 已核验包名 `com.review`、`versionName 2.5.11`、`versionCode 47`、arm64 架构，文件为 `D:\App\Review\Review_v2.5.11.apk`，SHA-256 为 `6307FBC571508603CED050D039FDFB0A4470B9D84B139FC291C33E37FCC0FFA9`；构建完成后项目根目录仅保留当前 APK，旧的 `Review_v2.5.10.apk` 已删除。

### 4.54 自定义图标深色适配资源更新
- **变更范围**：保留“官方默认”图标及 `default` 入口不变，仅替换两个可选预设：`alias1`（质感经典）使用 `D:\Download\图片\icon.png`，`alias2`（活力新潮）使用 `D:\Download\图片\icon3.png`。
- **资源处理**：新源图保持正方形比例，生成 Flutter 预览资源 `assets/icons/app_icon_1.png` / `app_icon_2.png`，并同步生成 Android `mipmap-mdpi`、`hdpi`、`xhdpi`、`xxhdpi`、`xxxhdpi` 下的两个 activity-alias 图标；图标切换状态、别名 ID、默认图标和关于页面联动逻辑不变。
- **兼容性**：只更新图像资源，不改变 `CustomAppIconNotifier`、PackageManager 别名切换及进程退出刷新机制；覆盖安装后已选择的 `alias1` / `alias2` 会继续对应原选项，只显示新的图像。
- **验证结果（2.6.0）**：资源尺寸与 Android 各密度文件已核对，Flutter 全部 118 项测试通过；release APK 已核验包名 `com.review`、`versionName 2.6.0`、`versionCode 48`、arm64 架构，并确认 APK 中包含 `mipmap/ic_launcher_alias1` 与 `mipmap/ic_launcher_alias2`；文件为 `D:\App\Review\Review_v2.6.0.apk`，SHA-256 为 `36EC7F25EAE11548291CF53F300E53601A4F5439776E1AA0E1CFFCF1950B5AB7`；构建完成后项目根目录仅保留当前 APK，旧的 `Review_v2.5.11.apk` 已删除。

### 4.55 自定义图标第二版素材微调
- **变更范围**：沿用 4.54 的图标映射和预设逻辑，仅重新替换两张经过微调的素材：`alias1`（质感经典）使用 `D:\Download\图片\icon.png`，`alias2`（活力新潮）使用 `D:\Download\图片\icon3.png`；官方默认图标保持不变。
- **资源处理**：依据新源图重新生成 Flutter 预览资源 `assets/icons/app_icon_1.png` / `app_icon_2.png`，并同步刷新 Android `mipmap-mdpi`、`hdpi`、`xhdpi`、`xxhdpi`、`xxxhdpi` 下的两个 activity-alias 图标；不修改别名 ID、图标选择状态、默认图标或其他业务逻辑。
- **兼容性**：这是已有自定义图标功能的素材微调，覆盖安装后 `alias1` / `alias2` 仍保持原选择，只更新显示资源；不影响时间线、登录、微博内容和其他设置。
- **源文件校验**：`icon.png` SHA-256 为 `C58D5314D1A5120E792AD7F0A3A7FE05393E0B913C98B5E1A53A7A9A4BAB5604`；`icon3.png` SHA-256 为 `22749E5725E10E8E71300E0C0CC0E8A66F954E9C429CCC2552C1C519385BC815`。
- **验证结果（2.6.1）**：Flutter 全部 118 项测试通过；release APK 已核验包名 `com.review`、`versionName 2.6.1`、`versionCode 49`、arm64 架构，并确认 APK 中包含 `mipmap/ic_launcher_alias1` 与 `mipmap/ic_launcher_alias2`；文件为 `D:\App\Review\Review_v2.6.1.apk`，SHA-256 为 `9043280EEA52E04FE54CC76FF3E071BE64DC689C34CA306E0C380D7597BCCB52`；构建完成后项目根目录仅保留当前 APK，旧的 `Review_v2.6.0.apk` 已删除。

### 4.56 升级后 Cookie 分域迁移与时间线会话修复
- **问题复现条件**：部分用户从旧版本覆盖升级后，Cookie 本身仍有效，但时间线完全为空；“检测账号凭据有效性”只能得到“暂时无法验证”，退出后重新登录才恢复。
- **根因**：2.5.6 已实现运行期桌面端/移动端 Cookie 分域，但旧版完整 Cookie 在首次迁移时会被无条件同时写入两个分域槽位；旧完整值通常以移动端 Cookie 为主，可能污染桌面端槽位。网络层又优先读取桌面槽位，且会话同步过去只验证第一个候选值，因此后方仍有效的完整 Cookie 没有机会参与验证。
- **修复**：
  1. 新增 Cookie 分域结构版本。旧结构升级时只清除可重新生成的桌面/移动端派生副本，保留完整 Cookie、`SUB`、`SUBP` 等登录凭据，不执行退出登录；
  2. 会话同步依次核验原生桌面 Cookie、已存桌面 Cookie、完整 Cookie，并通过官方桌面配置接口与预期 UID 校验；前一个候选失效时继续尝试后续候选；
  3. 只有确实通过桌面端验证的 Cookie 才写入桌面槽位，移动端验证结果不再反向覆盖桌面会话；移动端验证同时要求官方返回明确的登录状态；
  4. 凭据检测前强制执行一次分域同步，不再用未经验证的合并值覆盖完整 Cookie；官方返回 `ok=-100` 或登录跳转地址时识别为明确失效；
  5. 检测状态拆分为“有效”“桌面会话待同步”“已过期”“暂时无法验证”。移动端仍有效而桌面端暂时不同步时保留全部凭据并提示自动修复结果，不误报过期、不清空账号。
- **兼容性**：升级迁移仅重建分域派生数据，不删除用户完整 Cookie；新登录会直接写入当前结构版本。网络波动或官方接口响应变化仍归类为“暂时无法验证”，不会触发自动退出。
- **验证结果（2.6.2）**：新增旧混合 Cookie 升级迁移、过期桌面候选回退到有效完整 Cookie、官方 `ok=-100` 判定等回归测试；Flutter 全部 121 项测试通过。release APK 已核验包名 `com.review`、`versionName 2.6.2`、`versionCode 50`、arm64 架构并通过签名验证；文件为 `D:\App\Review\Review_v2.6.2.apk`，SHA-256 为 `ECB308E2AE1200BDA74B5D1E473F3C0F64A74F183F2D719AE4FE531D597E69F1`；构建完成后项目根目录仅保留当前 APK，旧的 `Review_v2.6.1.apk` 已删除。

### 4.57 凭据检测多候选验证与官方响应兼容修复
- **问题**：2.6.2 已能迁移旧分域 Cookie，但部分有效账号点击“检测账号凭据有效性”时仍显示“暂时无法验证”。
- **根因**：会话同步虽然会验证原生桌面、已存桌面和完整 Cookie，但显式检测随后又只读取单个首选桌面副本，并再次依赖 `getconfig` 的固定响应结构；因此前一步已经验证成功、完整 Cookie 仍有效或微博返回 `idstr` 等结构变体时，后一步仍可能覆盖为“不明确”。
- **修复**：
  1. `reconcileNativeSession` 的返回值统一表示“是否已经核验到与当前账号匹配的桌面会话”，显式检测成功后直接复用该结论，不再重复降级为单接口判断；
  2. 桌面验证继续依次尝试原生桌面、已存桌面、完整 Cookie，任一候选验证成功即修复桌面槽位，避免陈旧副本遮蔽有效完整 Cookie；
  3. 兼容 `uid`、`id`、`idstr` 及用户对象内对应字段，也兼容登录标记位于响应根节点或 `data` 节点；
  4. 当 `getconfig` 返回结构不完整或请求异常时，使用官方 `/ajax/feed/allGroups` 作为独立回退，但必须从分组项中提取到与本地当前账号完全一致的 UID 才判定有效；微博未登录时返回的游客默认分组 UID 不匹配，因此不会被误判；
  5. 官方明确返回 `ok=-100` 或登录跳转时仍立即判定该候选失效，不用其他公开数据掩盖真实过期状态。
- **验证结果（2.6.3）**：新增桌面配置 `idstr` 结构、游客分组 UID 排除、显式检测修复陈旧桌面槽位等回归测试；Flutter 全部 124 项测试通过，认证修复文件定向静态分析零问题。release APK 已核验包名 `com.review`、`versionName 2.6.3`、`versionCode 51`、arm64 架构并通过签名验证；文件为 `D:\App\Review\Review_v2.6.3.apk`，SHA-256 为 `F35DB8C3434FD726FE3D7538E7C4F9B3A7F7196A95127BA8AEC6CC0725C982C6`；构建完成后项目根目录仅保留当前 APK，旧的 `Review_v2.6.2.apk` 已删除。

### 4.58 网页端登录闭环、自动同步凭据与多级校验自愈
- **问题背景与痛点**：
  1. 用户在内置 WebView 登录页面完成短信验证码或密码登录后，页面常常停留在新浪跨域票据置换（`login.sina.com.cn/sso/v2/crossdomain`）期间的白屏或移动端落地页，用户无法直观获知是否登录成功，且容易遗漏点击底部的“完成登录 / 同步凭据”按钮；
  2. 即使手动点击底部同步按钮，也会弹出 `已读取 Cookie，但微博接口未确认登录 / 移动:无; 桌面:SCF,SUB,SUBP,ALF; SSO:...`，同时偶现 `net::ERR_ABORTED` 网页无法打开错误，导致正常登录流程彻底受阻，只能依靠手动导出/导入 Cookie 兜底。
- **根因分析**：
  1. **落地重定向 404**：登录初始 URL `weiboWebLoginUrl` 设置的返回地址为 `url=https%3A%2F%2Fweibo.com`。由于移动 WebView User-Agent 会被微博桌面站 302 重定向至 `https://m.weibo.cn/?&jumpfrom=weibocom`，而该特殊地址在微博服务器上直接返回 HTTP 404；
  2. **跨域置换被意外中断**：在 `login.sina.com.cn/sso/v2/crossdomain` 置换票据时，部分第三方探针/打点资源加载失败触发了 `onWebResourceError` 中的强行重载，导致正在进行的票据交换被中断，产生 `net::ERR_ABORTED` 白屏；
  3. **多级验证死锁**：在 Cookie 验证函数 `canCommitVerifiedSession` 中，移动端配置请求缺少专用移动端 User-Agent 与 `Referer: https://m.weibo.cn/` 导致直接被拒；而桌面端三级（`/ajax/profile/detail`）和四级（`/ajax/feed/allGroups`）接口解析出正确 UID 后，遗漏了设置 `desktopSessionVerified = true`，导致即便抓取到了有效 Cookie 也被系统误判为未确认；
  4. **缺乏自动感知闭环**：登录凭据检测过去仅依赖用户手动点击底栏按钮触发，未建立与网页端登录按钮点击、表单提交及票据路由变更的双向联动机制。
- **修复与全自动闭环实现**：
  1. **智能意图感知与 JS 桥接**：在 WebView 中注入 `ReviewLoginBridge` 交互监听。当用户在网页中点击“登录”按钮或提交表单时，系统立即启动后台静默轮询，提前进入凭据捕获状态；
  2. **票据路由嗅探与全屏优雅遮罩**：扩展 `isLoginSuccessTransitionUrl` 判定逻辑。一旦检测到网页导航进入 `ticket=`、`crossdomain` 跨域票据置换或移动落地页阶段，立即唤起全屏原生 Material 3 居中遮罩（“正在完成登录并同步凭据... 已检测到登录操作，正在为您自动同步，无需手动操作”），彻底遮盖白屏与中间态脚本页面，消除用户的迷茫感；
  3. **高频自动同步与自动返回**：以 600ms 为周期主动轮询 Native CookieManager，一旦捕获到包含 `SUB` 的有效凭据立即调用多候选验证。验证成功后直接弹出“🎉 微博账号登录成功！已为您同步真实关注流”并自动 Pop 回退到主界面进入关注流，实现零手动干预的全程自动化；
  4. **修复底层验证路由与请求头**：
     - 修复 `weiboWebLoginUrl` 返回地址为 `https://m.weibo.cn/`，杜绝 404；
     - 移除 `onWebResourceError` 对跨域过程的强制打断；
     - Tier 1.5 增加 `/ajax/statuses/config` 桌面备选配置；
     - Tier 2 请求 `m.weibo.cn/api/config` 补全专用移动 UA 与 `Referer: https://m.weibo.cn/`；
     - Tier 3 与 Tier 4 解析出 UID 后正确置位 `desktopSessionVerified = true`，并弹性支持根级与 `data` 级的多形态响应。
- **APK 交付与根目录存放铁律执行**：
  - 严禁让用户在 `build/app/outputs/flutter-apk/` 等深层路径寻找安装包；
  - 每次编译生成的正式 Release 安装包必须统一放置在项目根目录 `D:\App\Review\` 下（如 `D:\App\Review\Review_v2.8.8.apk`），且根目录下严格只保留当前最新版本唯一单个安装包。
- **验证结果（2.8.8）**：
  - 单元测试与 Widget 测试：全工程全部 149 项自动化测试通过；
  - 静态代码分析：`flutter analyze` 零问题；
  - 端侧实测验证：登录流程全自动闭环，白屏完全被原生加载态替代，无缝完成凭据同步并直达关注流；
  - 产物核验：编译完成的安装包为 `D:\App\Review\Review_v2.8.8.apk`。

### 4.59 登录检测超时取消与手动重试可靠性修复
- **问题复核**：自动轮询期间，手动同步按钮此前会因 `_isChecking` 被禁用；定时轮询在验证请求尚未结束时还会排队额外检测。更重要的是，登录页对 `setAndVerifyCookie` 使用 `Future.timeout` 只会停止等待，不会取消 Dio 请求，慢响应可能在界面已认为超时后继续执行。
- **修复**：
  1. 为登录页的每个 Cookie 候选验证传入独立 `CancelToken` 和候选时限；认证函数把同一令牌传递给桌面、移动端及资料/分组回退请求，超时或登录页退出时取消真实请求，并在会话落盘前检查取消状态，防止迟到响应提交会话；
  2. 检测中的“完成登录 / 同步凭据”保持可点击。点击会排队一次手动重读 Cookie 的检测；纯自动轮询遇到正在运行的检测则跳过，不额外堆积任务；
  3. 登录页成功返回保持非阻塞，不以桌面 SSO 同步失败否定已由官方移动接口确认的登录；关注流请求调整为在桌面 Cookie 协调完成后再启动，并检查账号仍是刚登录的账号。提示语改为“登录成功，正在加载关注流”，不提前宣称时间线已同步完成。
- **兼容性边界**：保留 4.58 的 `m.weibo.cn` 回跳、第三方 Cookie、JS 登录桥接、600ms 自动轮询、多候选 Cookie 验证、桌面/移动端响应兼容及 Tier 1.5/3/4 回退策略；本修复只收紧检测并发、取消及关注流启动顺序。
- **Dio API 兼容修正**：Dio 5 的 `CancelToken` 是 `dio.get(..., cancelToken: token)` 请求参数，不属于 `Options`；已修正 6 个凭据验证请求点，保留原有真实请求取消与超时行为。
- **Release 验证结果（2.8.9）**：构建命令正常退出（exit code 0）；APK 包名 `com.review`、`versionName 2.8.9`、`versionCode 73`、arm64-v8a，APK Signature Scheme v2 验签通过，签名证书与 2.8.8 相同。文件为 `D:\App\Review\Review_v2.8.9.apk`（31,185,313 bytes），SHA-256 为 `51C5CF6E0B4B914398C1CB9C0B86DEB716FADF1D1DF2BF3C8BCFDEBE28E64372`；根目录仅保留当前 APK。未运行自动化测试、`flutter analyze` 或 Android 真机验证。

### 4.60 消息未读计数、免打扰与周期通知修复
- **未读清零基线**：旧实现只将当前联系人对象改为 0；重新请求 `contacts.json` 后服务端旧计数覆盖本地值。现在分别持久化消息中心分类基线和每个会话基线，显示 `max(0, 服务端计数 - 基线)`；检测到服务端计数已低于基线时重置该基线，使清零后的新消息从 1 开始累计。清除操作本地立即生效，远端接口只在可识别业务成功响应时提示同步成功。
- **群免打扰**：`GroupInfoPage` 将群 ID 保存在 SharedPreferences；消息列表中的免打扰群角标改为灰色，并从侧边栏消息总数和后台私信通知排除。此设置仅作用于 Review 本地提醒，不声称修改微博官方服务器设置。
- **侧边栏角标**：`MessageUnreadService` 汇总 `/ajax/remind/unread` 的提及、赞、评论计数及 `/webim/2/direct_messages/contacts.json` 的未读会话计数。读取失败时保留上次角标而不是误显示 0。`/ajax/remind/unread` 属网页兼容接口，非当前公开 API 契约，必须对字段缺失/结构变化采取失败保护。
- **后台订阅提醒**：设置页首次进入时请求 Android 通知权限；总开关和 @、点赞、回复、私信分类开关写入本地偏好。Android 使用 WorkManager 联网周期任务读取未读计数，周期下限 15 分钟且实际执行受系统省电/联网调度影响；首次运行、总开关重新开启、账号切换时只建立新计数基线，不推送历史未读；通知只显示类别和条数，不展示消息正文。Cookie 继续复用 Flutter 本地会话存储，不新增明文凭据副本。
- **发送消息的确认边界**：旧实现以 HTTP 2xx 直接保留本地合成消息，可能把业务失败呈现为已发送。现在先检查响应业务字段，再重新读取会话；服务器回读不到时不显示伪造气泡并提示先核实，防止用户盲目重复发送。`/webim/groupchat/send_message.json` 和 `/webim/2/direct_messages/new.json` 仍是未经公开契约/测试账号验证的兼容路径；本次没有使用用户账号发送消息。
- **验证范围**：`dart analyze` 全工程 0 warning/error，保留 51 条 info（包含代码风格、API 弃用、异步 BuildContext 安全提示及测试风格提示，未做大范围机械改写）。全量 Flutter 自动化测试 149 项通过；Android `:app:compileReleaseKotlin` 编译成功（仅有既存弃用 API 警告及 `ReviewDocumentsProvider` 条件警告）。
- **Release 验证结果（2.9.0）**：arm64 Release 构建成功（约 410 秒）；APK 包名 `com.review`、`versionName 2.9.0`、`versionCode 74`、ABI `arm64-v8a`。APK Signature Scheme v2 验签通过，签名证书 SHA-256 `3EB0F6708904F8EF916C6A2572E394BA981EE25D64861344CF1921CA7EA17975`，与上一版一致；文件 `D:\App\Review\Review_v2.9.0.apk`，大小 31,699,064 bytes，SHA-256 `2210D2142A5C42A629E0181D594FE05DB81AE04C9AFDB96F82EF00F6FC9BE3C1`。项目根目录只保留当前正式 APK。未做 Android 真机通知验收。

### 4.61 群聊免打扰角标位置与未读总数显示修正
- **问题**：将 `/webim/2/direct_messages/contacts.json` 的 `totalNumber` 展示为“私信与群聊”标题旁的气泡。它不是单个会话的未读数，也没有纳入清零基线，因此点击清除后仍然存在；同时容易让人误以为免打扰角标是一个总数。
- **修复**：移除“私信与群聊”标题旁的 `totalNumber` 气泡；每条会话只根据自己的 `unread_count`，在对应头像右上角显示气泡。免打扰直接按群信息页保存的群 ID 匹配并显示灰色；其他群及私聊的气泡保持红色。侧边栏“我的消息”聚合角标仍保留，免打扰群会话从该聚合数和后台私信通知中排除。
- **清零保证**：各会话原始未读数写入本地清零基线，界面仅显示 `max(0, 当前会话未读数 - 该会话基线)`；重新打开消息页不会复现清除前的气泡。
- **版本规则**：遵照本次明确要求，应用显示版本名仍为 `2.9.0`，仅将 `versionCode` 从 74 提升至 75 以支持覆盖安装。
- **验证结果**：新增界面回归测试检查标题不显示 `totalNumber`、免打扰群头像右上角为灰色、普通群保持红色，以及清除后重新进入仍无旧会话气泡；全量 Flutter 测试 150 项通过。`dart analyze` 全工程无 warning/error，仍有 51 条 info 级提示。
- **Release 验证结果（2.9.0，versionCode 75）**：arm64 Release 构建成功（约 381 秒）；APK 包名 `com.review`、`versionName 2.9.0`、`versionCode 75`、ABI `arm64-v8a`。APK Signature Scheme v2 验签通过，签名证书 SHA-256 `3EB0F6708904F8EF916C6A2572E394BA981EE25D64861344CF1921CA7EA17975`，与上一构建一致；文件 `D:\App\Review\Review_v2.9.0.apk`，大小 31,699,064 bytes，SHA-256 `35113E062E8ED80DA61CDA321E3F30179EFEB5B38D826BF1E528CC94A559B14C`。项目根目录仅保留这一正式 APK。未做 Android 真机通知验收。

### 4.62 打开消息即按范围标记本地已读
- **问题**：本地未读基线原来只在手动点扫把时更新；打开某个群聊/私信后，该会话自己的头像角标仍保留。打开 @、点赞或收到评论分类，也没有清理对应分类的本地未读计数。
- **修复**：进入会话时只将该会话当前服务端原始未读值存为本地基线，并立即隐藏该会话角标；其他会话保持未读。返回消息列表重新读取 contacts 时仍按每会话基线计算，因此旧角标不会复现，新到消息从零开始累计。进入 @、收到的赞、收到的评论页面时，分别读取微博提醒计数并只更新对应分类基线；“我的消息”总览和“发出的评论”不清理未浏览分类。后台通知水位与服务端原始计数对齐，避免已浏览的旧通知延迟再次提醒。
- **版本规则**：应用显示版本名保持 `2.9.0`；Android `versionCode` 和 pubspec build number 从 75 提升至 76。
- **回归验证**：验证打开一条群会话后仅其角标消失、其他会话角标仍在；验证打开点赞分类后只清除点赞基线、提及和评论计数保留，新赞正常重新计数。
- **构建验证**：全量 Flutter 测试 152 项通过；`dart analyze --no-fatal-warnings .` 无 warning/error，仍有 51 条 info。按本文件的 JDK 临时目录 workaround 完成 arm64 Release 构建（约 382 秒）；APK 包名 `com.review`、`versionName 2.9.0`、`versionCode 76`、ABI `arm64-v8a`，APK 签名校验通过，签名证书 SHA-256 `3EB0F6708904F8EF916C6A2572E394BA981EE25D64861344CF1921CA7EA17975`。APK `D:\App\Review\Review_v2.9.0.apk`，大小 31,699,060 bytes，SHA-256 `A52FEEA6CB760F9930E496BD114BCD8C55BE9EBF02D7A9EFEC09A680717F3F67`。未做真机通知验收。

---
*文档权威版本：2026-09-23 (v2.9.0)*
*维护团队：Review 开发组*
