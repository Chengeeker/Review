# Review 核心工程约束与交付铁律

## 1. 安装包编译与交付
- **单包交付铁律**：严禁一次编译或保留多个 APK 安装包。每次打包必须清理或覆盖旧包，项目根目录下严格仅保留单个以 `Review_v{version}.apk` 命名的安装包（如 `Review_v1.4.apk`）。
- **打包命令**：
  ```powershell
  & "D:\flutter_sdk\bin\flutter.bat" build apk --release --target-platform android-arm64 --android-skip-build-dependency-validation
  Copy-Item -Path "build\app\outputs\flutter-apk\app-release.apk" -Destination "Review_v{version}.apk" -Force
  ```

## 2. Git 提交规范
- **Commit Message**：除非用户另有明确指令，Git commit 信息统一严格为 `"update"`。

## 3. 搜索与时间线流规范
- **搜索流原生 1:1 对齐**：放弃应用自定义筛选与打分改序逻辑，综合大搜直连 `https://s.weibo.com/weibo`，完全沿用微博官方原生流序与置顶/热门判定。
- **UI 纯净动线**：严禁在综合栏中自行添加未经验证的聚合卡片（如“话题关联官方账号”）。
- **权威开发文档路径**：开发文档统一维护在 `D:\App\开发文档\Review.md`。
