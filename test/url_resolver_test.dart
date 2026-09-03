import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:watermark_remover/utils/url_resolver.dart';

class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getTemporaryPath() async {
    return Directory.systemTemp.createTempSync('wm_test_').path;
  }
}

class MyRealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = MyRealHttpOverrides();

  setUpAll(() {
    PathProviderPlatform.instance = MockPathProviderPlatform();
  });

  group('UrlResolver 基础解析与提取测试', () {
    test('正确提取混合文本中的 URL', () {
      const tiktokText = '看看这个视频 https://vt.tiktok.com/ZSVEwsUTb/ 真的很棒！';
      final url = UrlResolver.extractUrl(tiktokText);
      expect(url, 'https://vt.tiktok.com/ZSVEwsUTb/');

      const ytText = '分享链接：https://youtu.be/LwTopTPyiEw?si=W9g8FJXKuipq96oU';
      final ytUrl = UrlResolver.extractUrl(ytText);
      expect(ytUrl, 'https://youtu.be/LwTopTPyiEw?si=W9g8FJXKuipq96oU');
    });
  });

  group('UrlResolver 真实网络解析与下载测试', () {
    test('TikTok 短链解析与下载成功', () async {
      const testUrl = 'https://vt.tiktok.com/ZSVEwsUTb/';
      final progressUpdates = <double>[];
      final statusUpdates = <String>[];

      final results = await UrlResolver.resolve(
        testUrl,
        onProgress: (p, s) {
          progressUpdates.add(p);
          statusUpdates.add(s);
        },
      );

      expect(results, isNotEmpty);
      expect(results.first.isVideo, isTrue);
      final file = File(results.first.localPath);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(10000));
      print('TikTok 测试成功，下载文件大小: ${file.lengthSync()} 字节');
      print('进度回调次数: ${progressUpdates.length}, 最新状态: ${statusUpdates.last}');
    }, timeout: const Timeout(Duration(seconds: 40)));

    test('YouTube 视频解析与下载成功', () async {
      const testUrl = 'https://youtu.be/LwTopTPyiEw?si=W9g8FJXKuipq96oU';
      final progressUpdates = <double>[];
      final statusUpdates = <String>[];

      final results = await UrlResolver.resolve(
        testUrl,
        onProgress: (p, s) {
          progressUpdates.add(p);
          statusUpdates.add(s);
        },
      );

      expect(results, isNotEmpty);
      expect(results.first.isVideo, isTrue);
      final file = File(results.first.localPath);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), greaterThan(100000));
      print('YouTube 测试成功，下载文件大小: ${file.lengthSync()} 字节');
      print('进度回调次数: ${progressUpdates.length}, 最新状态: ${statusUpdates.last}');
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}
