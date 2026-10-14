# Flutter 多图画廊连续滑动性能修复指南

适用于“全屏主图 + 底部缩略图滚轮”且两者各自使用滚动控制器的 Flutter 画廊。目标是避免旧惯性抢手势、让横向切图流畅，并在缩放时正确把拖动留给图片平移。

## 根因

两个 `PageController` 各自维护独立的 `ScrollActivity`。滚轮手势期间，缩略条滚动监听会逐帧把小数页位置用 `mainPosition.jumpTo(...)` 镜像到主图；如果用户在缩略条惯性尚未结束时改为拖主图，只把“缩略条正在驱动主图”的布尔标志关闭是不够的：缩略条的 ballistic activity 仍在运行，可能继续写入位置、抢占主图刚开始的拖动，造成手势无响应、跳动或卡住。

## 最小修复

在主图的 `NotificationListener<ScrollNotification>` 里，仅对真实用户拖动的 `ScrollStartNotification` 转移控制权：先使旧同步 epoch 失效并关闭滚轮到主图的镜像，再以滚轮当前像素位置 `jumpTo(position.pixels)` 停止尚未结束的滚轮活动。这个调用保持当前小数页，不把缩略条突然吸附到整数页。主图之后成为唯一滚动所有者；跨页后，原有 `onPageChanged` 负责同步缩略条。

```dart
bool onMainGalleryScroll(ScrollNotification notification) {
  if (notification.depth != 0 ||
      notification is! ScrollStartNotification ||
      notification.dragDetails == null) {
    return false;
  }

  syncEpoch++;
  thumbnailUserScrolling = false;
  thumbnailSettling = false;

  if (thumbnailController.hasClients &&
      thumbnailController.position.isScrollingNotifier.value) {
    final position = thumbnailController.position;
    position.jumpTo(position.pixels);
  }
  return false;
}
```

把字段名替换成目标项目的命名。`jumpTo(currentPixels)` 是为了调用 `ScrollPosition` 的活动切换机制来停止惯性；不要仅仅跳转到当前整数页，否则手指刚开始拖动时画面会先跳一下。

## 主图翻页与缩放手势

`ExtendedImageGesturePageView` 自己注册横向拖动识别器；不要再让主图的横向拖动同时承担页面退出。对当前使用的 `extended_image 8.3.1`，建议主图分页这样配置：

```dart
ExtendedImageGesturePageView.builder(
  controller: pageController,
  physics: const BouncingScrollPhysics(),
  canScrollPage: (details) => (details?.totalScale ?? 1.0) <= 1.0,
  // itemCount / itemBuilder ...
)
```

这样 1 倍适配状态由 PageView 横向切图，图片放大后 pager 不再分页，拖动留给图片平移。控制器的 `shouldIgnorePointerWhenScrolling` 默认是 `false`；先查是否被显式改成 `true`，不要把一个未启用的选项当成根因。

本项目的 `ExtendedImageSlidePage.slideAxis` 虽然仍为水平，但单图 `enableSlideOutPage` 明确关闭，因此该轴在当前图片手势中并不参与竞争。试开 `enableSlideOutPage: true` 后，依赖在图片加载中/失败占位阶段增加的 `ExtendedImageSlidePageHandler` 会用 `ScaleGestureRecognizer` 接收拖动；专项回归随即出现横向分页失败、主图不能接管旧滚轮惯性。故不能照搬“把轴改为垂直并全局打开滑出”这一步。若目标应用要支持下滑退出，应额外按图片加载中、失败占位、正常解码、已放大四种状态验证；必要时等图片手势可用后才启用退出，但不要因此重建当前分页/缩放子树。

当前经过回归的配置：

```dart
ExtendedImageGesturePageView.builder(
  physics: const BouncingScrollPhysics(),
  canScrollPage: (details) => (details?.totalScale ?? 1.0) <= 1.0,
  // controller / children ...
)

ExtendedImage.network(
  imageUrl,
  mode: ExtendedImageMode.gesture,
  enableSlideOutPage: false,
)
```

背景透明度必须跟随实际启用的退出轴：启用纵向退出时用 `offset.dy` 与页面高度计算；退出关闭时不要把透明度回调误认为横向翻页的根因。

## 不要做的事

- 不要把主图同步推迟到下一帧或 post-frame：快速滑动时主图会明显落后于缩略条。
- 不要在主图已经接管后，继续由滚轮监听器对主图 `jumpTo`。
- 不要把每次经过的页排成 `animateToPage` 队列；高速度时主图会落后并逐张追赶。
- 不要为解决手势冲突改变全屏 PageView 视口、Hero tag/几何或图片缩放配置；这会引入返回动画和缩放位置回归。
- 不要在滚轮处于惯性时销毁/重建滚轮或其控制器；这会中断正在进行的手势。

## 回归验收

用真实滚动手势覆盖以下序列，而不只断言最后的下标：

1. 拖动并快速甩动缩略条，在惯性未结束时立刻拖动主图。
2. 主图接手后，确认缩略条旧滚动活动停止，且当前画面没有先跳到整数页。
3. 持续拖动主图，确认主图能跨页；松手后主图和滚轮最终页一致。
4. 反方向重复，并覆盖列表首尾、2 张图及较多图片、Android/iOS 的滚动行为。
5. 缩略条拖动后按住不动至少数百毫秒：主图与滚轮都应静止，不得互相吸附或抽动。
6. 主图 1 倍时左右拖动可翻页，放大时分页回调为 false；分别覆盖加载、失败和已解码图片，确认没有退出手势识别器拦截横滑。

自动化 widget test 能验证滚动所有权和位置同步，但不能代替真机上的帧时间、触觉马达节奏、真实图片解码和网络加载验收。
