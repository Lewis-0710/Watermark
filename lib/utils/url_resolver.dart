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
  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
      'Referer': 'https://www.douyin.com/',
    },
  ));

  /// 从分享文本中提取 URL（支持被 backtick 包裹的情况）
  static String? extractUrl(String text) {
    final cleaned = text.replaceAll('`', '').trim();
    final regex = RegExp(r'https?://[^\s，。、,\)]+');
    final match = regex.firstMatch(cleaned);
    return match?.group(0);
  }

  /// 解析并下载媒体，返回本地文件路径列表
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
        throw Exception('YouTube 暂不支持直接解析，请用本地文件');
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
    // 1. 跟随短链接重定向，获取真实 URL
    final resp = await _dio.get(
      shareUrl,
      options: Options(
        followRedirects: true,
        maxRedirects: 5,
        validateStatus: (s) => s != null && s < 400,
      ),
    );
    final realUrl = resp.realUri.toString();

    // 2. 从 URL 中提取视频 ID
    final idMatch = RegExp(r'/video/(\d+)').firstMatch(realUrl) ??
        RegExp(r'/share/video/(\d+)').firstMatch(realUrl) ??
        RegExp(r'aweme_id=(\d+)').firstMatch(realUrl);

    String? videoId = idMatch?.group(1);

    // 如果 URL 没有直接拿到 ID，从页面内容提取
    if (videoId == null) {
      final body = resp.data.toString();
      final bodyMatch = RegExp(r'"awemeId":"?(\d+)"?').firstMatch(body) ??
          RegExp(r'aweme_id[=:"]+(\d+)').firstMatch(body) ??
          RegExp(r'/video/(\d+)').firstMatch(body);
      videoId = bodyMatch?.group(1);
    }

    if (videoId == null) throw Exception('无法提取抖音视频ID');

    // 3. 调用 API 获取视频信息
    final apiUrl =
        'https://www.iesdouyin.com/web/api/v2/aweme/iteminfo/?item_ids=$videoId';
    final apiResp = await _dio.get(apiUrl);
    final data = apiResp.data is Map ? apiResp.data as Map : <String, dynamic>{};

    final itemList = data['item_list'] as List?;
    if (itemList == null || itemList.isEmpty) {
      // 尝试备用 API：解析页面 SSR JSON
      return _resolveDouyinFromPage(resp.data.toString(), videoId);
    }

    final item = itemList[0] as Map;
    final video = item['video'] as Map?;
    final images = item['images'] as List?;

    final results = <ResolvedMedia>[];
    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;

    // 4. 下载视频
    if (video != null) {
      final playAddr = video['play_addr'] as Map?;
      final urlList = playAddr?['url_list'] as List?;
      if (urlList != null && urlList.isNotEmpty) {
        var videoUrl = urlList[0].toString();
        // playwm → play = 无水印版本
        videoUrl = videoUrl.replaceAll('playwm', 'play');

        final filePath = '${tempDir.path}/douyin_${videoId}_$ts.mp4';
        await _dio.download(videoUrl, filePath);
        results.add(ResolvedMedia(localPath: filePath, isVideo: true));
      }
    }

    // 5. 下载图片（图文作品）
    if (images != null) {
      for (int i = 0; i < images.length; i++) {
        final img = images[i] as Map;
        final urlList = img['url_list'] as List?;
        if (urlList != null && urlList.isNotEmpty) {
          var imgUrl = urlList[0].toString();
          imgUrl = imgUrl.replaceFirst('http://', 'https://');
          final filePath =
              '${tempDir.path}/douyin_${videoId}_${i}_$ts.jpg';
          await _dio.download(imgUrl, filePath);
          results.add(ResolvedMedia(localPath: filePath, isVideo: false));
        }
      }
    }

    if (results.isEmpty) throw Exception('未能提取到视频或图片');
    return results;
  }

  /// 备用方案：从页面 HTML 中提取视频信息
  static Future<List<ResolvedMedia>> _resolveDouyinFromPage(
      String html, String videoId) async {
    // 查找页面中的视频 URL
    final videoMatch = RegExp(r'"playAddr"[^[]*"urlList":\[?\s*"([^"]+)"')
            .firstMatch(html) ??
        RegExp(r'"play_addr".*?"url_list":\[?"([^"]+)"').firstMatch(html) ??
        RegExp(r'(https?://[^"]+douyin[^"]+\.mp4[^"]*)').firstMatch(html);

    if (videoMatch == null) throw Exception('抖音页面中未找到视频地址');

    var videoUrl = videoMatch.group(1)!.replaceAll('\\u002F', '/');
    videoUrl = videoUrl.replaceAll('playwm', 'play');

    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final filePath = '${tempDir.path}/douyin_${videoId}_$ts.mp4';
    await _dio.download(videoUrl, filePath);

    return [ResolvedMedia(localPath: filePath, isVideo: true)];
  }

  // ==================== B站 ====================

  static Future<List<ResolvedMedia>> _resolveBilibili(String url) async {
    // 提取 BV 号
    final bvMatch = RegExp(r'/(BV[\w]+)').firstMatch(url) ??
        RegExp(r'bvid=(BV[\w]+)').firstMatch(url);
    if (bvMatch == null) throw Exception('无法提取B站视频ID');
    final bvid = bvMatch.group(1)!;

    // 调用 API 获取视频信息
    final apiUrl = 'https://api.bilibili.com/x/web-interface/view?bvid=$bvid';
    final resp = await _dio.get(apiUrl);
    final data = resp.data is Map ? resp.data['data'] as Map? : null;
    if (data == null) throw Exception('B站 API 未返回数据');

    final cid = data['cid'];
    final aid = data['aid'];

    // 获取视频流
    final streamApiUrl =
        'https://api.bilibili.com/x/player/playurl?aid=$aid&cid=$cid&qn=80&fnval=1';
    final streamResp = await _dio.get(streamApiUrl);
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
    await _dio.download(
      videoUrl,
      filePath,
      options: Options(headers: {'Referer': 'https://www.bilibili.com/'}),
    );
    results.add(ResolvedMedia(localPath: filePath, isVideo: true));

    return results;
  }
}
