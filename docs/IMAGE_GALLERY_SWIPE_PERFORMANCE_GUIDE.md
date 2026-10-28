# Flutter 多图画廊连续滑动性能修复指南

适用于“全屏主图 + 底部缩略图滚轮”且两者各自使用滚动控制器的 Flutter 画廊。目标是避免旧惯性抢手势、让横向切图流畅，并在缩放时正确把拖动留给图片平移。

## Hero 飞行层没有分页器：Release 灰色错误占位（2026-10-14）

完成态图片的 `imageBuilder` 不能假设自己始终位于分页器内部。Hero 的 push 飞行会在 Navigator overlay 中重新构建目标图片子树，那里没有 `ExtendedImageGesturePageViewState` 祖先。强制非空会抛出 `Null check operator used on a null value`；Flutter 的 Release 默认错误占位使用 `RenderErrorBox.backgroundColor = 0xF0C0C0C0`，视觉上是一大片浅灰色，不是普通的背景蒙版。

分页器查找必须允许 null；缺少祖先时直接返回 `image`，让飞行层绘制原图片。只有画廊页中的完成态图片安装额外分页识别器。不能通过吞掉 FlutterError 或把 ErrorWidget 改透明掩盖问题。3.2.8 关闭整页 FadeTransition 的尝试没有解决空值异常，已撤回；继续保留原路由淡入及独立控件显隐。

实际回归通过正式 `PhysicsSpringGalleryRoute` 推入 `ImageGalleryPage`，提供已解码原图，并在第二次打开时让原图于飞行途中完成。修复前第一段动画就捕获空值异常；修复后逐帧没有异常或 ErrorWidget，飞行层中心像素与固定蓝色原图一致，随后左右翻页和另一张图片的返回动画正常。两次回程分别覆盖普通 cover 图片的几何插值与网页卡片完整显示的子树回退。只断言构建器返回类型，或在主页直接挂载图库进行分页测试，不能验证 overlay 的祖先环境。

## 已解码图片快速拖动被缩放识别器接收（2026-10-14）

仅用加载占位图片验证分页会漏掉此问题：图片解码成功后，`ExtendedImageGesture` 才会安装内部的 `ScaleGestureRecognizer` 与双击识别器。`extended_image 8.3.1` 的横向拖动识别器位于图片外层；当单次移动同时越过缩放平移与分页拖动的识别距离时，内层缩放识别器先胜出。该版本 `GestureDetails.movePage()` 在 `totalScale <= 1` 时返回 false，内部缩放路径也就不再向分页转交拖动。结果是指针到达了图片，但没有分页 `ScrollStart`，实际 page position 不变。此现象不能用解码耗时或分页吸附解释。

本轮回归将真实解码的 120×240 像素通过 Flutter ImageCache 提供给正式画廊，在 800×600 测试视口连续发送 -40、-160、-160px 的单指移动。旧代码的 gesture arena 日志由 `ScaleGestureRecognizer` 胜出，page 保持 0；修复后由图片内层的分页拖动识别器胜出，page 为 0.4，并产生真实拖动 `ScrollStart`。这是可复现的自动化输入证据，不是 Android Profile 帧率验收。

### 用已有 API 修复识别顺序

依赖已公开 `ExtendedImageGesture.imageBuilder`、`ExtendedHorizontalDragGestureRecognizer` 和分页状态的 `onDragDown/onDragStart/onDragUpdate/onDragEnd/onDragCancel`。使用这些接口在图片绘制子树内注册分页识别器，使它先于图片缩放识别器收到同一移动事件；仍由原分页控制器管理拖动、速度与吸附，不另写翻页物理，不修改依赖缓存或复制整个包。

在图片的 `loadStateChanged` 中返回下列完成态构建；加载或失败时返回 null，保留依赖默认占位和外层分页识别器：

```dart
if (state.extendedImageLoadState != LoadState.completed) return null;
return ExtendedImageGesture(
  state,
  imageBuilder: (image, {imageGestureState}) {
    final gesture = imageGestureState!;
    final pager = gesture.context
        .findAncestorStateOfType<ExtendedImageGesturePageViewState>();
    // Hero flights paint this image outside the pager subtree.
    if (pager == null) return image;
    return Listener(
      onPointerDown: (_) {
        pager.extendedImageGestureStates.remove(gesture);
        pager.extendedImageGestureState = gesture;
      },
      child: RawGestureDetector(
        gestures: {
          ExtendedHorizontalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                  ExtendedHorizontalDragGestureRecognizer>(
            () => ExtendedHorizontalDragGestureRecognizer(
              canHorizontalOrVerticalDrag: () =>
                  (gesture.gestureDetails?.totalScale ?? 1) <= 1,
              shouldAccpetHorizontalOrVerticalDrag:
                  (trackers) => trackers.length == 1,
            ),
            (recognizer) => recognizer
              ..onDown = pager.onDragDown
              ..onStart = pager.onDragStart
              ..onUpdate = pager.onDragUpdate
              ..onEnd = pager.onDragEnd
              ..onCancel = pager.onDragCancel
              ..minFlingDistance = pager.widget.physics.minFlingDistance
              ..minFlingVelocity = pager.widget.physics.minFlingVelocity
              ..maxFlingVelocity = pager.widget.physics.maxFlingVelocity
              ..gestureSettings = MediaQuery.gestureSettingsOf(gesture.context),
          ),
        },
        child: image,
      ),
    );
  },
);
```

`GestureRecognizerFactoryWithHandlers` 来自 Flutter widgets/material，不是 gestures 库。外层 `ExtendedImageGesturePageView` 也设置 `shouldAccpetHorizontalOrVerticalDrag: (trackers) => trackers.length == 1`，避免双指同向移动被外层接成分页。两条分页识别路径都只接适配倍率下的单指横移，放大后的平移与双指捏合继续交给原图片识别器，双击仍使用原 `onDoubleTap` 回调。

指针落下时的 remove/add 不是删除图片：8.3.1 用 Set 保存已挂载图片手势状态，并通过最后一项获取当前状态，重复 add 不会把既有项移动到末尾。显式把触摸图片的状态移到末尾，可避免经过/缓存邻页的缩放状态被拿来检查本次分页门槛。

### Hero 必须保留图片子树

原先根据当前下标返回 `Hero(child: image)` 或直接返回 image，跨过半页时会销毁刚显示的 `ExtendedImageGestureState` 并重建；恢复旧包装方式的对照测试确认旧实例已 defunct。应该保持包装层级恒定，只通过 `HeroMode` 禁用邻页飞行：

```dart
return HeroMode(
  enabled: index == currentIndex,
  child: Hero(tag: tag, flightShuttleBuilder: flightBuilder, child: image),
);
```

继续按来源网格、图片身份、下标生成 tag，视频仍不参加图片 Hero。验证的是实际启用的 Hero 数量，不能用树中全部 Hero 控件数判断是否会出现多个飞行。

### 媒体初始化与真实性能验收

依赖的 `ExtendedImageGesture.didUpdateWidget` 会重新构造 `GestureAnimation`。完成态构建使用画廊内 `Expando<ExtendedImageGesture>`，以 `state.extendedImageInfo` 的对象身份为键复用同一解码帧的控件，减少分页/控件显隐造成的重复初始化；不按 URL 或下标永远缓存图片控件。新图片帧产生新 ImageInfo，仍会更新控件，因此不会冻结 GIF。Expando 的弱键不会把已释放页面的像素长期留在强引用 Map 中。回归同时检查跨页时相同帧控件实例不变、注入新解码帧后控件正常更新。

主图真实拖动开始时暂停已有 Live Photo，并将活跃媒体下标设为 -1；每个经过下标仍立即更新图片、计数和 Hero 选择，视频/Live Photo 初始化延至 `ScrollEnd` 后。结束回调必须检查同步 epoch、mounted、主图仍未滚动，防止旧结束通知激活新拖动途经的媒体；缩略条原有接管和结束归位逻辑继续保留。专项测试连续三次甩动时经过项没有创建视频控制器，停稳后只初始化最终 Live Photo，默认不播放，点击按钮才播放。

原图解码量、`onPageChanged` 重建耗时仍是待 Profile 验证的性能候选，不能写成已经确认的根因。本次不缩小原图解码尺寸、不预加载全部原图，不改变 PageScrollPhysics、PageView 视口、Hero 几何或双击倍率。正式 Android 设备需使用 Profile 模式记录 UI/raster 帧耗时，分别覆盖冷/热缓存、真实大图、网络加载/失败、Live Photo 与普通视频；本机 ADB 无连接设备时只能标记未验收。

## 缩略条旧惯性接管的根因

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
  shouldAccpetHorizontalOrVerticalDrag: (trackers) => trackers.length == 1,
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
7. 使用已解码像素执行动画未结束时继续甩动、反向甩动、双击 1→2.5→6→1 倍、双指同向平移和捏合，再回到 1 倍后翻页；记录 pointer、真实拖动 ScrollStart 和连续 page position，不能只调用 canScrollPage 断言门槛。
8. 在半页前记录已挂载的进入页手势实例，跨过半页后必须保持同一实例；返回时仅当前 Hero 参与飞行。连续甩动经过 Live Photo 时不初始化，停稳后仅初始化最终项。

自动化 widget test 能验证滚动所有权和位置同步，但不能代替真机上的帧时间、触觉马达节奏、真实图片解码和网络加载验收。


## 后续页原图加载占位（3.11.3）

每页原图处于 loading 且 previewUrl 与原图不同的时候，返回该页自己的 ExtendedImage 缓存预览，BoxFit.contain；初始 Hero 快照仍优先。完成态继续返回原有手势图片，失败态继续由依赖显示重试，不预取全部原图。此分支不能只限 initialIndex，否则滑到第二页仍会露出黑色背景。回归通过未完成原图流验证第二页预览已解码及原图完成后的切换。


## 3.12.1退场与打开时序

玻璃模式 reverse 时直接移除顶部控件和缩略栏，返回取消后等 completed 再恢复。不要更改主图 PageView 约束、Hero 身份、缩放状态；普通模式继续原140ms淡出。当前路由打开330ms、返回200ms，Hero 使用 Flutter 默认飞行曲线和几何插值；3.12.5至3.13.5的弹簧、非线性曲线及中断重开均为已撤回的历史实现，不可套用到当前行为。Hero 返回快照在最后绘制帧后释放。信息流缩略 `ExtendedImage` 以照片ID/图层稳定身份；有解码帧时 provider 刷新期间绘制旧帧，仅首次加载显示占位，避免 pop 结束时短暂露出黑/底色。HDR 缩略标记在初始化继承共享原图检测缓存并接续已有 `Future`，不能只等活跃项原生解码，也不要为了缩略标记预取所有原图。


### 3.12.6 打开飞行与真实曲线核验

两端 Hero 显式 linear/reverse linear 和 RectTween，避免默认 fastOutSlowIn 与路由弹簧叠加。打开和关闭使用相同冻结像素绘制及几何插值。路由弹簧刚度200，反向 flipped。旧3.12.5参数仅为历史记录。回归必须经过真实 Navigator push 并采样飞行矩形与像素。
