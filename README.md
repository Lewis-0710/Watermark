# 水印杀手 (Watermark Remover)

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.10+-02569B?logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-3.0+-0175C2?logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/Platform-iOS%20|%20Android%20|%20macOS%20|%20Windows%20|%20Web-4E9A06" alt="Platform">
  <img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg" alt="License">
</p>

**水印杀手 (Watermark Remover)** 是一款基于 Flutter 构建的高颜值、高性能跨平台无水印媒体解析与智能图像去水印应用。

项目兼具**主流社交媒体全自动解析下载**与**本地媒体高保真无痕消除**两大核心能力。无论是抖音、TikTok、YouTube、B站的视频/图集快速提取，还是针对照片中的台标、Logo、水印杂质的涂鸦消除，均能提供丝滑高效的体验。

---

## ✨ 核心特性

### 1. 多平台媒体无水印解析与下载
- **主流平台覆盖**：全面支持**抖音 (Douyin)**、**TikTok**、**YouTube**、**哔哩哔哩 (Bilibili)** 以及各类通用网页分享链接。
- **自动提取文本链接**：支持直接粘贴包含文字、标点的混合分享文案，自动通过正则提取有效 URL。
- **图集与视频双解析**：
  - 视频：直接嗅探获取最高清晰度 MP4 无水印直链。
  - 图集：自动解析多张高清原图并提供批量下载与预览。
- **双引擎解析机制**：
  - **无头直链解析器**：桌面端及常规网络环境下秒级解析，直接提取纯净媒体流。
  - **WebView 智能嗅探引擎**：移动端内置浏览器环境，动态捕获网络请求，有效应对反爬与复杂重定向。

### 2. 高保真无痕图像修复算法 (Inpainting Engine)
内置自主研发的纯 Dart 图像修复管线，摆脱云端 API 依赖，兼顾隐私与处理速度：
- **局部保真定位**：仅对涂鸦标记的包围盒区域进行局部裁剪计算，涂鸦区域外 **100% 原始像素保留**。
- **真 2D 形态学顶帽变换 (Top-Hat)**：采用标准开运算（先腐蚀后膨胀），天然滤除阶跃边缘与大面积轮廓，仅精确响应孤立文字笔画与 Logo。
- **字腔形态学闭合 (Hole-Filling Closing)**：自动闭合文字内部腔隙（如“0”、“8”或汉字字腔），彻底杜绝文字残留与空心光圈。
- **9×9 阴影膨胀包络**：全覆盖字迹边缘半透明抗锯齿与微弱阴影扩散，防止边缘色污污染修复底色。
- **垂直先验插值 + 各向异性导度扩散 (Perona-Malik PDE)**：利用已知背景像素垂直插值作为初值，在异质边缘自动阻断横向渗色，确保边界清晰锐利，实现真正的“无痕去除”。

### 3. 极致视觉与全端自适应 UI
- **科幻宇宙动态背景**：纯 Canvas 硬件加速渲染的星空粒子与太阳系行星轨道公转动效，带来沉浸式视觉体验。
- **跨平台响应式布局**：
  - 手机端针对竖屏交互优化，紧凑易触达；
  - 桌面端（macOS / Windows）优化宽屏边距，支持键盘 `Enter` 快捷启动与窗口尺寸记忆。
- **手势交互画布**：支持双指缩放平移、单指涂鸦框选、自适应笔刷粗细以及多级撤销/重做。
- **系统相册一键保存**：集成 `gal` 库，处理后的高清图片与下载的视频可一键存入系统相册。

---

## 🛠 技术架构

```text
lib/
├── main.dart                          # 应用入口与全局主题配置
├── screens/
│   ├── home_page.dart                 # 宇宙动态首页、链接输入与本地文件导入
│   ├── process_page.dart              # 媒体处理画板、涂鸦手势、图片修复与结果保存
│   └── douyin_webview_page.dart       # 移动端 WebView 嗅探与降级解析页
└── utils/
    ├── inpainting.dart                # 高精度形态学与各向异性 PDE 图像修复算法
    ├── url_resolver.dart              # 抖音/TikTok/YouTube/B站网络流解析与下载器
    ├── douyin_webview_extractor.dart  # 网页环境多媒体嗅探脚本与提取逻辑
    └── desktop_config.dart            # 桌面端（macOS/Windows/Linux）窗口初始化与尺寸管理
```

---

## 🚀 快速上手

### 环境要求
- [Flutter SDK](https://flutter.dev/docs/get-started/install): `>= 3.10.0`
- [Dart SDK](https://dart.dev/get-dart): `>= 3.0.0 < 4.0.0`
- 操作系统平台工具链：
  - **iOS / macOS**：Xcode 14+ 及 CocoaPods / Swift Package Manager
  - **Android**：Android Studio 及 Android SDK (API 21+)
  - **Windows**：Visual Studio 2022（C++ 桌面开发套件）

### 安装与运行

1. **克隆仓库**
   ```bash
   git clone https://github.com/your-username/watermark_remover.git
   cd watermark_remover
   ```

2. **拉取项目依赖**
   ```bash
   flutter pub get
   ```

3. **运行开发环境**
   ```bash
   # 运行于 macOS 桌面端
   flutter run -d macos

   # 运行于 iOS 模拟器/真机
   flutter run -d ios

   # 运行于 Android 设备
   flutter run -d android

   # 运行于 Chrome 浏览器
   flutter run -d chrome
   ```

4. **运行单元与组件测试**
   ```bash
   flutter test
   ```

---

## 📦 打包与发布

### iOS / macOS
项目已内置 App Store 导出与上架配置，配置文件位于 `ios/ExportOptions/`：
```bash
# 构建 iOS 归档包 (IPA)
flutter build ipa --export-options-plist=ios/ExportOptions/AppStoreExport.plist

# 构建 macOS 应用程序
flutter build macos --release
```

### Android
```bash
# 构建 APK 文件
flutter build apk --release

# 构建 App Bundle
flutter build appbundle --release
```

### Windows
```bash
flutter build windows --release
```

---

## 🗺 路线图 (Roadmap)

- [x] 抖音、TikTok、YouTube、B 站直链解析与下载
- [x] 移动端智能 WebView 媒体流自动嗅探与捕获
- [x] 2D 形态学顶帽变换与各向异性 PDE 无痕图像修复
- [x] iOS、macOS、Android、Windows 多平台界面适配
- [x] 动态粒子宇宙与太阳系交互动效
- [ ] 视频动态局部消除与去水印算法
- [ ] 批处理任务队列与历史下载记录管理
- [ ] 接入轻量端侧 AI 大模型提升复杂纹理修复精度

---

## 📄 开源协议

本项目采用 [Apache License 2.0](LICENSE) 许可证。

---

## ⚠️ 免责声明

1. 本项目仅供编程技术交流、算法学习与个人研究使用。
2. 请在遵守相关平台服务条款与国家法律法规的前提下使用本工具。
3. 请尊重原创作者的知识产权与内容版权，未经授权不得将下载或处理后的内容用于任何商业盈利或侵犯他人合法权益的行为。
