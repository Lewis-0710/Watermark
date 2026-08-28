import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// Windows/macOS/Linux 平台的桌面初始配置：设置窗口标题和最小尺寸
Future<void> configureDesktopWindow() async {
  try {
    await windowManager.ensureInitialized();
    const WindowOptions windowOptions = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(880, 600),
      center: true,
      title: '水印杀手',
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  } catch (e) {
    debugPrint('configure desktop window skipped: $e');
  }
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));
}
