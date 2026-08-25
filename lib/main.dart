import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'screens/home_page.dart';
import 'utils/desktop_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 桌面端（Windows/macOS/Linux）初始化窗口尺寸
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    await configureDesktopWindow();
  }
  runApp(const WatermarkRemoverApp());
}

class WatermarkRemoverApp extends StatelessWidget {
  const WatermarkRemoverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '水印清除大师',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.dark(
          primary: Colors.blueAccent,
          secondary: Colors.purpleAccent,
          surface: Colors.grey[900]!,
        ),
      ),
      home: const HomePage(),
    );
  }
}
