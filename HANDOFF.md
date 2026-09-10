# 水印杀手工程交接文档

> 本文档面向新开发者、维护者和 AI 编程工具。目标是让接手者在不了解历史上下文的情况下，能够完成环境搭建、功能定位、问题排查、测试和发布。
>
> 文档更新时间：2026-09-10
>
> 本次交接前基线：`develop` 分支，基于 commit `03521e1`（`docs: 完善项目 README 说明文档与系统架构`）
>
> 应用版本：`1.0.1+4`
>
> 仓库：`Lewis-0710/Watermark`

## 1. 接手前先看什么

建议按以下顺序阅读：

1. 本文档：了解当前实现、限制和风险。
2. [README.md](README.md)：了解产品定位、功能宣传和基础命令。
3. [pubspec.yaml](pubspec.yaml)：确认 SDK 约束和依赖。
4. [lib/screens/home_page.dart](lib/screens/home_page.dart)：了解输入分流和首页 UI。
5. [lib/screens/douyin_webview_page.dart](lib/screens/douyin_webview_page.dart)：了解在线链接的快速解析、WebView 兜底和下载。
6. [lib/utils/url_resolver.dart](lib/utils/url_resolver.dart)：了解平台解析器。
7. [lib/screens/process_page.dart](lib/screens/process_page.dart) 与 [lib/utils/inpainting.dart](lib/utils/inpainting.dart)：了解本地媒体处理流程和图像修复算法。
8. `test/`：了解已有测试，以及哪些测试依赖真实网络。

## 2. 项目概览

「水印杀手（Watermark Remover）」是一个 Flutter 跨平台应用，当前包含两条主要能力链：

- 在线媒体解析：从抖音、TikTok、B 站、YouTube 分享链接中提取媒体并下载到临时目录。
- 本地图片去水印：用户导入图片，用涂鸦标记水印区域，在设备本地运行 Dart 图像修复算法，再保存结果。

目标平台目录已经包含：

- iOS
- Android
- macOS
- Windows
- Web（目前已验证可以构建；功能行为仍以具体平台能力为准）

项目没有自建后端、数据库或环境变量配置。媒体解析直接请求第三方平台页面/API，因而对网络环境、平台反爬策略和页面结构变化敏感。

许可证为 Apache License 2.0，详见 [LICENSE](LICENSE)。使用下载和处理能力时必须遵守第三方平台条款、版权和当地法律法规。

## 3. 当前可验证状态

### 3.1 本地环境

本文档编写时使用的环境：

- Flutter：`3.44.0`，stable channel
- Dart：`3.12.0`
- macOS Apple Silicon
- 项目声明的最低约束：Flutter `>= 3.10.0`，Dart `>= 3.0.0 < 4.0.0`

项目当前分支是 `develop`，并跟踪 `origin/develop`。`main` 分支也存在，但日常开发和本次交接均基于 `develop`。

### 3.2 已执行验证

以下结果是本文档编写时的真实结果，不代表所有网络环境都能复现：

| 命令 | 结果 | 备注 |
| --- | --- | --- |
| `flutter test` | 通过 | 共 4 个测试；包含真实 TikTok 和 YouTube 下载请求 |
| `flutter build web` | 通过 | Web 编译成功；构建过程仍提示依赖升级和 Apple 工具链警告 |
| `flutter analyze` | 返回非 0 | 没有编译错误，但有 23 条 `info` 级诊断，主要是弃用 API、测试 lint 和测试依赖声明问题 |
| `flutter pub get` | 通过 | 当前约束下有 46 个可升级但不兼容现有约束的依赖版本 |

`pubspec.lock` 被当前 `.gitignore` 的 `*.lock` 规则忽略，仓库没有锁定 Dart/Flutter 依赖解析结果。不同机器执行 `flutter pub get` 可能获得不同的兼容版本，升级依赖前应先评估并补充可复现策略。

## 4. 系统架构和主流程

```text
首页 HomePage
  ├─ 粘贴文本/链接
  │    └─ DouyinWebViewPage
  │         ├─ UrlResolver 直接解析成功 ────────┐
  │         └─ iOS/Android WebView 嗅探兜底 ────┤
  │                                             ▼
  └─ 选择本地图片/视频 ───────────────────── ProcessPage
                                                ├─ 图片：涂鸦 → 生成 mask → inpainting → JPEG
                                                └─ 视频：预览/保存原文件，当前不执行去水印
```

### 4.1 首页输入分流

入口是 `HomePage._onStart()`：

- 输入为空且未选本地文件：弹出提示，不继续。
- 输入文本中只要匹配到 `http://` 或 `https://`，就进入 `DouyinWebViewPage`。因此页面名称虽然带有「Douyin」，实际上承担所有在线链接的统一入口。
- 没有 URL 时，进入 `ProcessPage`，把本地路径列表交给处理页。
- 首页可以累计选择多个本地文件；当前没有显式清空列表的入口，重新选择会继续追加。

### 4.2 在线解析链路

`DouyinWebViewPage` 先调用 `UrlResolver.resolve()`，直接解析成功后把临时文件路径传给 `ProcessPage`。直接解析失败时：

- iOS/Android：加载隐藏的 `WebView`，注入 `fetch` 和 `XMLHttpRequest` 拦截脚本，再从 DOM、页面结构化数据和 HTML 中找媒体地址。
- Windows/macOS/Linux：没有内置移动 WebView；直接解析失败后显示失败提示，不会自动打开浏览器完成兜底。
- Web：可以走直接解析，但 WebView 兜底条件不成立，不应假设有移动端同等能力。

WebView 嗅探器的关键参数：

- 单次提取超时：45 秒。
- 失败最多重试：3 次，每次间隔约 2 秒。
- 有视频时只取第一个视频；没有视频时下载识别到的图片列表。
- 下载文件写入系统临时目录，然后替换当前页面进入 `ProcessPage`。

### 4.3 `UrlResolver` 支持范围

`lib/utils/url_resolver.dart` 使用域名判断平台，再选择对应解析策略：

| 平台 | 当前策略 | 输出 | 主要限制 |
| --- | --- | --- | --- |
| 抖音 | 跟随短链重定向、提取视频 ID、解析 SSR/Next/React 数据，最后用 HTML 正则兜底 | 视频或图集 | 页面结构变化、私密内容和反爬会导致失败；移动端可再走 WebView |
| TikTok | `HttpClient` 跟随重定向，解析页面 JSON/脚本，保留 Cookie 后下载 | 视频或图集 | 强依赖页面结构和 Cookie；代码当前关闭了该请求的证书校验，见风险章节 |
| B 站 | 调用 `view` 和 `playurl` API，优先 `durl`，否则取 DASH 第一条视频流 | 视频 | 当前没有音视频合并逻辑；登录、分区限制和清晰度策略可能影响结果 |
| YouTube | `youtube_explode_dart` 获取 manifest，优先选最高码率 MP4 muxed 流 | 视频 | 没有 muxed 流时可能选到仅视频流，不能保证包含音频；受平台策略和库版本影响 |
| 未知域名 | 直接抛出不支持异常 | 无 | 不会自动调用第三方通用解析服务 |

`UrlResolver.extractUrl()` 支持从夹杂中文标点、说明文字和反引号的文本中提取第一个 HTTP(S) URL。

### 4.4 本地媒体处理链路

`ProcessPage` 负责媒体加载、预览、手势、涂鸦、处理和保存：

1. 本地图片使用 `image` 包解码，同时创建 Flutter `ui.Image` 用于预览。
2. 本地视频使用 `video_player` 循环播放。
3. 用户用单指涂鸦标记区域；双指用于缩放/平移。
4. `MaskPainter` 将 UI 坐标转换到原图坐标，生成白色 mask。
5. `runInpainting()` 处理图片，结果编码为质量 `95` 的 JPEG。
6. 桌面端保存到系统 Downloads 目录；移动端通过 `gal` 保存到系统相册。

视频目前只能预览和保存原文件。`_startProcess()` 对视频直接返回，没有视频逐帧去水印实现；README 路线图中的「视频动态局部消除」仍未完成。

## 5. 图像修复算法说明

实现位于 [lib/utils/inpainting.dart](lib/utils/inpainting.dart)，当前不是云端调用，而是纯 Dart 本地计算：

1. 扫描 mask，计算涂鸦区域包围盒。
2. 包围盒向四周扩展 20 像素，只在局部区域计算。
3. 对亮度做 7×7 形态学开运算，使用顶帽结果识别孤立文字/Logo。
4. 对较大的目标 mask 做形态学闭合，并做 9×9 膨胀以覆盖抗锯齿和阴影。
5. 使用垂直方向已知背景像素做初始插值。
6. 对目标区域执行 400 次 Perona–Malik 各向异性扩散。
7. 只把目标像素写回原图，未标记区域保持原始像素。

需要注意：算法运行在 Dart isolate 的主执行上下文中，虽然循环中会让出微任务，但大图或大面积涂鸦仍可能造成明显卡顿。修改算法时应优先增加可重复的合成图片测试，并关注内存和耗时。

## 6. 目录和文件职责

| 路径 | 职责 |
| --- | --- |
| `lib/main.dart` | 应用入口、Material 主题、桌面窗口初始化 |
| `lib/screens/home_page.dart` | 星空/太阳系首页、URL 文本输入、本地文件选择、入口分流 |
| `lib/screens/douyin_webview_page.dart` | 在线链接直接解析、移动端 WebView 兜底、媒体下载进度 |
| `lib/screens/process_page.dart` | 图片/视频预览、缩放平移、涂鸦 mask、处理和保存 |
| `lib/utils/url_resolver.dart` | 抖音/TikTok/B 站/YouTube 平台检测、解析、下载 |
| `lib/utils/douyin_webview_extractor.dart` | WebView JavaScript 注入、DOM/结构化数据解析、媒体 URL 提取 |
| `lib/utils/inpainting.dart` | 局部图像修复算法 |
| `lib/utils/desktop_config.dart` | 桌面窗口初始尺寸、最小尺寸、标题栏和显示状态 |
| `test/widget_test.dart` | 首页最小渲染测试 |
| `test/url_resolver_test.dart` | URL 提取测试和真实网络下载测试 |
| `pubspec.yaml` | Flutter/Dart 约束、依赖和应用版本 |
| `android/` | Android manifest、Gradle、权限、图标和混淆配置 |
| `ios/` | iOS Xcode 工程、权限、导出配置 |
| `macos/` | macOS Xcode 工程、沙盒 entitlement 和窗口宿主 |
| `windows/` | Windows Runner、CMake 和应用图标 |
| `web/` | Web 入口 HTML |

## 7. 开发环境和常用命令

### 7.1 环境要求

- Flutter SDK `>= 3.10.0`。
- Dart SDK `>= 3.0.0 < 4.0.0`。
- iOS/macOS：Xcode、签名证书和 CocoaPods/当前 Flutter Apple 工具链。
- Android：Android Studio、Android SDK 和 Java 17 工具链（Android Gradle 配置使用 Java 17）。
- Windows：Visual Studio 2022 的 C++ 桌面开发组件。
- 在线解析和网络测试需要可访问抖音、TikTok、B 站、YouTube 及其 CDN。

### 7.2 初始化和运行

```bash
flutter pub get
flutter devices

# 桌面端
flutter run -d macos
flutter run -d windows

# 移动端
flutter run -d ios
flutter run -d android

# Web
flutter run -d chrome
```

桌面端窗口默认尺寸为 `1280×800`，最小尺寸为 `880×600`，配置见 `lib/utils/desktop_config.dart`。

### 7.3 测试和检查

```bash
# 全量测试（包含真实网络请求）
flutter test

# 单独运行 UI 测试
flutter test test/widget_test.dart

# 单独运行网络解析测试
flutter test test/url_resolver_test.dart

# 静态分析
flutter analyze

# Web 构建验证
flutter build web
```

网络测试使用固定的 TikTok 和 YouTube 分享链接，不是离线单元测试：链接失效、平台限流、地区限制或网络代理都会导致失败。不要把它们当作稳定的 CI 健康检查；后续最好拆分为 mock 测试和显式 opt-in 的集成测试。

## 8. 构建和发布

### 8.1 常用构建命令

```bash
# iOS
flutter build ipa --export-options-plist=ios/ExportOptions/AppStoreExport.plist

# macOS
flutter build macos --release

# Android
flutter build apk --release
flutter build appbundle --release

# Windows
flutter build windows --release
```

### 8.2 发布前必须确认的配置

- `pubspec.yaml` 的 `version: 1.0.1+4` 同时影响 Flutter 构建版本名和版本号；发布新版本前要明确递增规则。
- Android application ID 当前为 `com.example.watermark_remover`，只配置了 `arm64-v8a` ABI。
- Android `release` 构建当前仍写死使用 debug signing config，不能直接用于正式发布；接手后必须改为正式 keystore，并通过未跟踪的 `key.properties` 或 CI secret 注入。
- iOS bundle ID 当前为 `com.lewis.watermarkRemover`，部署目标为 iOS 14.0；导出 plist 含固定 Apple Team ID，发布前确认账号、证书、profiles 和 bundle ID 仍归当前团队所有。
- macOS bundle ID 当前为 `com.lewis.watermarkRemover`，部署目标为 macOS 11.0；Release entitlement 允许网络访问、用户选择文件读写和 Downloads 目录读写。
- iOS/macOS 配置中启用了较宽松的网络访问策略。若准备上架或面向不受信网络，需重新评估 ATS 和证书策略。
- Android 使用了阿里云 Maven 镜像以及 `google()`、`mavenCentral()`；构建失败时先确认镜像可用性。
- 当前 Flutter 输出提示 iOS 项目存在 CocoaPods 与 Swift Package Manager 集成迁移警告；升级 Flutter 或插件前应先处理 Apple 工具链迁移，不要直接删除 `Pods` 或改工程文件。

## 9. 平台行为和权限

### Android

`android/app/src/main/AndroidManifest.xml` 声明了：

- `INTERNET`：在线解析和下载。
- Android 12 及以下的外部存储读取权限。
- Android 13+ 的图片/视频媒体读取权限。
- Android 9 及以下的写入权限。

正式验证时要覆盖至少一台 Android 13+ 和一台较旧版本设备，确认 `gal`、`file_picker` 的系统权限弹窗和拒绝后的错误提示。

### iOS

`ios/Runner/Info.plist` 配置了相册读写、相机、麦克风用途说明，并允许任意网络加载。WebView 嗅探只在 iOS/Android 代码路径中显示，且使用不受限制的 JavaScript 模式。

### macOS

沙盒 entitlement 已允许网络客户端、用户选择文件读写和 Downloads 目录读写。首次访问文件或下载目录时，需要在真实 macOS 沙盒应用中验证权限，而不能只依赖 `flutter run` 的开发环境。

### Windows

窗口由 `window_manager` 配置；当前没有独立的网络解析或 WebView 兜底实现。桌面保存路径使用系统 Downloads 目录。

## 10. 已知问题、风险和限制

以下事项接手后应优先评估：

### 高优先级

1. **TikTok 请求关闭证书校验。** `url_resolver.dart` 中的 `HttpClient.badCertificateCallback` 无条件返回 `true`。这会降低 HTTPS 安全性，正式发布前应移除并设计正确的证书/网络失败处理。
2. **Android Release 使用 debug 签名。** 当前配置不具备正式发布安全性，必须在发布前替换。
3. **解析器依赖第三方页面结构。** 抖音/TikTok 的 JSON 字段、HTML、CDN URL 和反爬规则变化都会直接影响功能；目前没有服务端适配层或远程开关。
4. **YouTube 可能下载无音频流。** 当 manifest 没有 muxed 流时，代码会选择视频流，未做音视频合并。
5. **网络策略过宽。** iOS/macOS 允许任意网络加载，且 WebView 开启 unrestricted JavaScript，应结合真实需求收紧。

### 中优先级

1. **视频去水印未实现。** 视频可以下载、预览和保存，但处理按钮对视频不执行算法。
2. **纯 Dart 修复算法可能卡顿。** 大图、大 mask 和固定 400 次迭代会消耗较多 CPU/内存；目前没有 isolate、取消任务或尺寸上限。
3. **WebView 兜底仅限移动端。** 桌面直链失败后不会自动唤起浏览器；Web 端也没有移动 WebView 兜底。
4. **真实网络测试不稳定。** 测试依赖固定公开链接和外部平台，可能因内容删除、限流、代理或地区而失败。
5. **依赖没有锁定。** `pubspec.lock` 被忽略，`flutter pub get` 会随时间解析到不同的兼容版本。
6. **静态分析存在历史问题。** 当前 Flutter 3.44.0 下有 23 条 `info`，包括 `withOpacity`、`allowMultiple`、Matrix API 弃用，以及测试包未在 `pubspec.yaml` 显式声明等问题。

### 文档与实现偏差

- README 的平台 badge 包含 Web，但 Web 的在线解析和保存能力需要单独验证，不能按移动端能力推断。
- README 提到「多级撤销/重做」，当前实现只看到了撤销，没有重做栈。
- `pubspec.yaml` 中的 `provider`、`shared_preferences`、`image_picker`、`intl`、`permission_handler`、`screenshot` 当前没有被 `lib/` 或 `test/` 直接 import；删除前要确认是否存在平台工程或未来功能依赖。

## 11. 常见排障路径

### 链接解析失败

1. 先确认输入文本中确实包含 `http://` 或 `https://`，且域名属于当前支持范围。
2. 在 `DouyinWebViewPage._start()` 查看是 `UrlResolver` 直接解析失败，还是移动端 WebView 提取失败。
3. 按平台检查：
   - 抖音：短链重定向、视频 ID、SSR 字段和视频 CDN 地址。
   - TikTok：页面 JSON、Cookie、`playAddr`/`downloadAddr` 和证书错误。
   - B 站：`view`/`playurl` API 响应、`cid`/`aid` 和 Referer。
   - YouTube：`youtube_explode_dart` 是否还能取得 manifest。
4. 不要直接把第三方页面 HTML 或 Cookie 写入日志、Issue 或交接文档。

### WebView 提取失败

1. 确认是在 iOS/Android 真机或模拟器上运行；桌面端没有兜底 WebView。
2. 查看 `DouyinWebViewExtractor.timeout`、重试次数和 `_started` 状态。
3. 检查目标页面是否把媒体放在新的 JSON 字段、iframe、M3U8 或 DRM 播放链路中。
4. 修改 `interceptorScript` 或 `_parsePage()` 后，至少用一个视频和一个图集回归。

### 图片处理异常或卡顿

1. 先确认 `ProcessPage` 是否正确加载了原图和 `dartImage`。
2. 检查 `_MaskPainter` 的 UI 坐标到原图坐标换算，尤其是图片比例与缩放状态。
3. 在 `runInpainting()` 检查 mask 是否有白色像素、局部包围盒是否越界。
4. 记录原图尺寸、mask 面积、处理耗时和内存，不要只看最终颜色结果。
5. 处理结果统一是 JPEG；如果需要保留透明通道或原始格式，应先重新设计导出协议。

### 保存失败

- 桌面端：检查 Downloads 目录是否可获取、是否有沙盒权限和写权限。
- 移动端：检查相册权限、`gal` 插件版本和系统媒体库限制。
- 视频：当前只允许保存原视频；不存在视频处理后的 `processedBytes`。

## 12. 面向 AI 工具的工作协议

AI 工具接手本仓库时，建议遵守以下规则：

1. 先阅读本文件、README、`pubspec.yaml` 和相关平台配置，再修改代码。
2. 修改解析器前先写离线 fixture/mock 测试；不要把新的真实平台请求直接塞进默认单元测试。
3. 修改图像算法前先确认 mask 坐标、像素格式和输出格式，再增加合成图片回归测试。
4. 任何平台权限、bundle ID、签名、entitlement 或 Gradle 配置变更，都要在对应平台实际构建一次。
5. 不要把 Cookie、Access Token、keystore、证书私钥、Apple 私密配置或完整用户媒体写入仓库、日志和文档。
6. 不要把 GitHub Token 写入 remote URL；使用凭据管理器或 CI secret。当前本机历史远端配置曾包含访问令牌，接手时应先轮换该令牌并清理本地 remote 配置。
7. 不要为了让测试通过而放宽 TLS 校验、关闭权限检查或硬编码用户凭据。
8. 保留用户已有未提交修改；提交前检查 `git status` 和 `git diff`，只提交本次任务相关文件。
9. 代码变更至少执行 `flutter analyze`、相关测试和对应平台构建/运行验证，并在交接记录中区分「通过」「未执行」「因外部条件失败」。
10. 修改第三方解析字段时，在代码注释或提交信息中说明数据来源、失败兜底和隐私风险。

## 13. 后续建议优先级

### P0：发布前必须处理

- 替换 Android Release debug 签名。
- 移除 TikTok 的无条件证书校验绕过。
- 轮换曾出现在本机 Git remote 配置中的访问令牌，并使用安全凭据管理。
- 明确 iOS/macOS bundle ID、Team ID、签名证书和 App Store Connect 归属。

### P1：稳定性和可维护性

- 将平台解析器抽象成可独立测试的策略，并为每个平台建立脱敏 HTML/JSON fixture。
- 把真实网络测试改成显式集成测试，默认测试只使用 mock。
- 为 inpainting 增加基准图、耗时、内存和大图边界测试；必要时迁移到 isolate。
- 决定是否提交 `pubspec.lock`，或建立明确的依赖版本冻结/升级流程。
- 清理弃用 API、未使用依赖和 `flutter analyze` 诊断。

### P2：功能完善

- 视频逐帧去水印与音视频导出。
- 任务队列、取消、历史记录和失败重试。
- 桌面端 WebView/浏览器兜底方案。
- 更清晰的权限拒绝提示、错误分类和诊断日志。
- 对 README、路线图和真实实现做定期同步。

## 14. 新接手者验收清单

- [ ] 已确认使用的分支、远程仓库和 Git 凭据安全。
- [ ] 已执行 `flutter pub get`，并记录实际 Flutter/Dart 版本。
- [ ] 已执行 `flutter test`，知道其中包含真实网络测试。
- [ ] 已执行 `flutter analyze`，确认现有诊断不会被误认为运行时错误。
- [ ] 已在至少一个桌面端运行本地图片处理和保存。
- [ ] 已在至少一个移动端验证相册权限、WebView 兜底和媒体保存。
- [ ] 已验证一个在线视频和一个图集链接；失败时记录平台、地区和时间。
- [ ] 已确认 Android 签名、iOS/macOS Team ID、Bundle ID 和发布配置。
- [ ] 已确认没有将 Token、Cookie、私钥或用户媒体提交到 Git。
- [ ] 已把后续变更同步到本文件和 README。
