import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

/// 解析后的媒体信息
class ResolvedMedia {
  final String localPath;
  final bool isVideo;
  ResolvedMedia({required this.localPath, required this.isVideo});
}

/// 链接解析器：从抖音/B站分享链接提取无水印媒体并下载到本地
class UrlResolver {
  static Dio _createDio() => Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 60),
        headers: {
          'User-Agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
              'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
          'Referer': 'https://www.douyin.com/',
        },
      ));

  /// 从分享文本中提取 URL（支持被 backtick 包裹、带中文标点的情况）
  static String? extractUrl(String text) {
    final cleaned = text.replaceAll('`', '').trim();
    // 允许包含引号、中文标点、括号等
    final regex = RegExp(r'https?://[^\s，。、,)"\'\']+');
    final match = regex.firstMatch(cleaned);
    return match?.group(0);
  }

  /// 解析并下载媒体
  static Future<List<ResolvedMedia>> resolve(String inputUrl) async {
    final url = extractUrl(inputUrl) ?? inputUrl.trim();
    if (url.isEmpty) throw Exception('未检测到有效链接');

    final platform = _detectPlatform(url);
    switch (platform) {
      case 'douyin':
        return _resolveDouyin(url);
      case 'bilibili':
        return _resolveBilibili(url);
      case 'youtube':
        throw Exception('YouTube 暂不支持直接解析');
      default:
        throw Exception('不支持的平台，请粘贴抖音/B站链接');
    }
  }

  static String _detectPlatform(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('douyin.com') || lower.contains('iesdouyin.com')) {
      return 'douyin';
    }
    if (lower.contains('bilibili.com') || lower.contains('b23.tv')) {
      return 'bilibili';
    }
    if (lower.contains('youtube.com') || lower.contains('youtu.be')) {
      return 'youtube';
    }
    return 'unknown';
  }

  // ==================== 抖音 ====================

  static Future<List<ResolvedMedia>> _resolveDouyin(String shareUrl) async {
    // 提取短链 code
    final codeMatch = RegExp(r'douyin\.com/([A-Za-z0-9_\-]+)').firstMatch(shareUrl) ??
        RegExp(r'iesdouyin\.com/([A-Za-z0-9_\-/]+)').firstMatch(shareUrl);
    final shortCode = codeMatch?.group(1) ?? '';

    // 策略 1：尝试跟随重定向
    try {
      return await _resolveDouyinViaRedirect(shareUrl);
    } catch (e) {
      debugPrint('抖音重定向解析失败: $e');
    }

    // 策略 2：直接用短链 code 调 API
    try {
      if (shortCode.isNotEmpty) {
        return await _resolveDouyinViaApi(shortCode);
      }
    } catch (e) {
      debugPrint('抖音API直接解析失败: $e');
    }

    // 策略 3：尝试 iesdouyin 分享页
    try {
      if (shortCode.isNotEmpty) {
        return await _resolveDouyinSharePage(shortCode);
      }
    } catch (e) {
      debugPrint('抖音分享页解析失败: $e');
    }

    throw Exception('所有解析策略均失败，请检查网络或稍后重试');
  }

  /// 策略 1：跟随重定向
  static Future<List<ResolvedMedia>> _resolveDouyinViaRedirect(
      String shareUrl) async {
    final dio = _createDio();
    final resp = await dio.get(
      shareUrl,
      options: Options(
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    final realUrl = resp.realUri.toString();

    final idMatch = RegExp(r'/video/(\d+)').firstMatch(realUrl) ??
        RegExp(r'/share/video/(\d+)').firstMatch(realUrl) ??
        RegExp(r'aweme_id=(\d+)').firstMatch(realUrl);

    String? videoId = idMatch?.group(1);

    if (videoId == null) {
      final body = resp.data.toString();
      final bodyMatch = RegExp(r'"awemeId":"?(\d+)"?').firstMatch(body) ??
          RegExp(r'aweme_id[=:"]+(\d+)').firstMatch(body) ??
          RegExp(r'/video/(\d+)').firstMatch(body);
      videoId = bodyMatch?.group(1);
    }

    if (videoId == null) throw Exception('无法提取抖音视频ID（重定向方式）');
    return await _downloadDouyinByVideoId(videoId);
  }

  /// 策略 2：直接用 iesdouyin API
  static Future<List<ResolvedMedia>> _resolveDouyinViaApi(
      String shortCode) async {
    final dio = _createDio();

    // 直接用短链 code 调 API
    final apiUrl = 'https://www.iesdouyin.com/web/api/v2/aweme/iteminfo/'
        '?item_ids=$shortCode';
    final resp = await dio.get(apiUrl);

    final data = resp.data is Map ? resp.data as Map : <String, dynamic>{};
    final itemList = data['item_list'] as List?;

    if (itemList != null && itemList.isNotEmpty) {
      final item = itemList[0] as Map;
      final itemId = item['aweme_id']?.toString();
      if (itemId != null) return await _downloadDouyinByVideoId(itemId);
    }

    throw Exception('API 未返回有效数据');
  }

  /// 策略 3：访问分享页提取视频信息
  static Future<List<ResolvedMedia>> _resolveDouyinSharePage(
      String shortCode) async {
    final dio = _createDio();
    final pageUrl = 'https://www.iesdouyin.com/share/$shortCode/';
    final resp = await dio.get(pageUrl);
    final html = resp.data.toString();

    // 从 SSR 数据中提取视频 ID
    final idMatch = RegExp(r'"awemeId":"?(\d+)"?').firstMatch(html) ??
        RegExp(r'aweme_id[=:"]+(\d+)').firstMatch(html);

    String? videoId = idMatch?.group(1);

    if (videoId == null) {
      // 尝试直接从页面提取视频 URL
      final videoMatch = RegExp(r'"playAddr"[^[]*"urlList":\[?\s*"([^"]+)"')
              .firstMatch(html) ??
          RegExp(r'(https?://[^"]+douyin[^"]+\.mp4[^"]*)').firstMatch(html);

      if (videoMatch != null) {
        var videoUrl = videoMatch.group(1)!.replaceAll('\\u002F', '/');
        videoUrl = videoUrl.replaceAll('playwm', 'play');

        final tempDir = await getTemporaryDirectory();
        final ts = DateTime.now().millisecondsSinceEpoch;
        final filePath = '${tempDir.path}/douyin_share_$ts.mp4';
        await _createDio().download(videoUrl, filePath);
        return [ResolvedMedia(localPath: filePath, isVideo: true)];
      }
      throw Exception('分享页未提取到视频信息');
    }

    return await _downloadDouyinByVideoId(videoId);
  }

  /// 通用：根据 videoId 下载抖音媒体
  static Future<List<ResolvedMedia>> _downloadDouyinByVideoId(
      String videoId) async {
    final dio = _createDio();
    final apiUrl =
        'https://www.iesdouyin.com/web/api/v2/aweme/iteminfo/?item_ids=$videoId';
    final apiResp = await dio.get(apiUrl);
    final data = apiResp.data is Map ? apiResp.data as Map : <String, dynamic>{};

    final itemList = data['item_list'] as List?;
    if (itemList == null || itemList.isEmpty) {
      throw Exception('抖音 API 返回空数据');
    }

    final item = itemList[0] as Map;
    final video = item['video'] as Map?;
    final images = item['images'] as List?;

    final results = <ResolvedMedia>[];
    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;

    // 下载视频
    if (video != null) {
      final playAddr = video['play_addr'] as Map?;
      final urlList = playAddr?['url_list'] as List?;
      if (urlList != null && urlList.isNotEmpty) {
        var videoUrl = urlList[0].toString().replaceAll('playwm', 'play');
        final filePath = '${tempDir.path}/douyin_${videoId}_$ts.mp4';
        await _createDio().download(videoUrl, filePath);
        results.add(ResolvedMedia(localPath: filePath, isVideo: true));
      }
    }

    // 下载图片（图文作品）
    if (images != null) {
      for (int i = 0; i < images.length; i++) {
        final imgMap = images[i] as Map;
        final urlList = imgMap['url_list'] as List?;
        if (urlList != null && urlList.isNotEmpty) {
          var imgUrl = urlList[0].toString().replaceFirst('http://', 'https://');
          final filePath = '${tempDir.path}/douyin_${videoId}_${i}_$ts.jpg';
          await _createDio().download(imgUrl, filePath);
          results.add(ResolvedMedia(localPath: filePath, isVideo: false));
        }
      }
    }

    if (results.isEmpty) throw Exception('未能提取到视频或图片');
    return results;
  }

  // ==================== B站 ====================

  static Future<List<ResolvedMedia>> _resolveBilibili(String url) async {
    final dio = _createDio();

    // 提取 BV 号
    final bvMatch = RegExp(r'/(BV[\w]+)').firstMatch(url) ??
        RegExp(r'bvid=(BV[\w]+)').firstMatch(url);
    if (bvMatch == null) throw Exception('无法提取B站视频ID');
    final bvid = bvMatch.group(1)!;

    // 调用 API 获取视频信息
    final apiUrl = 'https://api.bilibili.com/x/web-interface/view?bvid=$bvid';
    final resp = await dio.get(apiUrl);
    final data = resp.data is Map ? resp.data['data'] as Map? : null;
    if (data == null) throw Exception('B站 API 未返回数据');

    final cid = data['cid'];
    final aid = data['aid'];

    // 获取视频流
    final streamApiUrl =
        'https://api.bilibili.com/x/player/playurl?aid=$aid&cid=$cid&qn=80&fnval=1';
    final streamResp = await dio.get(streamApiUrl);
    final streamData =
        streamResp.data is Map ? streamResp.data['data'] as Map? : null;
    if (streamData == null) throw Exception('无法获取B站视频流');

    final durl = streamData['durl'] as List?;
    final dash = streamData['dash']?['video'] as List?;

    final results = <ResolvedMedia>[];
    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;

    String? videoUrl;
    if (durl != null && durl.isNotEmpty) {
      videoUrl = durl[0]['url'].toString();
    } else if (dash != null && dash.isNotEmpty) {
      videoUrl = dash[0]['baseUrl'].toString();
    }

    if (videoUrl == null) throw Exception('未能获取B站视频流地址');

    final filePath = '${tempDir.path}/bilibili_${bvid}_$ts.mp4';
    await dio.download(
      videoUrl,
      filePath,
      options: Options(headers: {'Referer': 'https://www.bilibili.com/'}),
    );
    results.add(ResolvedMedia(localPath: filePath, isVideo: true));

    return results;
  }
}
