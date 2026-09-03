import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path_provider/path_provider.dart';

/// 解析后的媒体信息
class ResolvedMedia {
  final String localPath;
  final bool isVideo;
  ResolvedMedia({required this.localPath, required this.isVideo});
}

/// 链接解析器：从抖音/B站分享链接提取无水印媒体并下载到本地
class UrlResolver {
  static Dio _createDio({String? baseUrl}) {
    return Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
        if (baseUrl != null) 'Referer': baseUrl,
      },
    ));
  }

  /// 从分享文本中提取 URL
  static String? extractUrl(String text) {
    final cleaned = text.replaceAll('`', '').trim();
    final regex = RegExp(r'''https?://[^\s，。、,)"']+''');
    final match = regex.firstMatch(cleaned);
    return match?.group(0);
  }

  static Future<List<ResolvedMedia>> resolve(
    String inputUrl, {
    void Function(double progress, String status)? onProgress,
  }) async {
    final url = extractUrl(inputUrl) ?? inputUrl.trim();
    if (url.isEmpty) throw Exception('未检测到有效链接');

    final platform = _detectPlatform(url);
    switch (platform) {
      case 'douyin':
        return _resolveDouyin(url, onProgress: onProgress);
      case 'tiktok':
        return _resolveTiktok(url, onProgress: onProgress);
      case 'bilibili':
        return _resolveBilibili(url, onProgress: onProgress);
      case 'youtube':
        return _resolveYoutube(url, onProgress: onProgress);
      default:
        throw Exception('不支持的平台，请粘贴抖音/TikTok/B站/YouTube链接');
    }
  }

  static String _detectPlatform(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('douyin.com') || lower.contains('iesdouyin.com')) {
      return 'douyin';
    }
    if (lower.contains('tiktok.com')) {
      return 'tiktok';
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

  static Future<List<ResolvedMedia>> _resolveDouyin(
    String shareUrl, {
    void Function(double progress, String status)? onProgress,
  }) async {
    final videoId = await _resolveDouyinVideoId(shareUrl);
    if (videoId != null) {
      return _fetchAndDownloadDouyin(videoId, onProgress: onProgress);
    }
    throw Exception('抖音链接解析失败，请使用自动 WebView 解析流程');
  }

  /// 跟随重定向解析视频ID
  static Future<String?> _resolveDouyinVideoId(String shareUrl) async {
    final dio = _createDio(baseUrl: 'https://www.douyin.com/');

    // 方案A：直接跟随 v.douyin.com 重定向
    try {
      final resp = await dio.get(
        shareUrl,
        options: Options(
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      final realUrl = resp.realUri.toString();
      debugPrint('重定向到: $realUrl');

      // 从 URL 提取视频ID
      final idFromUrl = _extractVideoIdFromUrl(realUrl);
      if (idFromUrl != null) return idFromUrl;

      // 从页面内容提取
      final idFromHtml = _extractVideoIdFromHtml(resp.data.toString());
      if (idFromHtml != null) return idFromHtml;
    } catch (e) {
      debugPrint('重定向失败: $e');
    }

    // 方案B：如果是 v.douyin.com 短链，直接请求短链页面并提取
    try {
      final match =
          RegExp(r'douyin\.com/([A-Za-z0-9_\-]+)').firstMatch(shareUrl);
      if (match != null) {
        final code = match.group(1)!;
        final shareUrl2 = 'https://www.douyin.com/share/$code';
        final resp = await dio.get(
          shareUrl2,
          options: Options(followRedirects: true, maxRedirects: 5),
        );
        final idFromUrl = _extractVideoIdFromUrl(resp.realUri.toString());
        if (idFromUrl != null) return idFromUrl;

        final idFromHtml = _extractVideoIdFromHtml(resp.data.toString());
        if (idFromHtml != null) return idFromHtml;
      }
    } catch (e) {
      debugPrint('分享页方案失败: $e');
    }

    return null;
  }

  static String? _extractVideoIdFromUrl(String url) {
    final m1 = RegExp(r'/video/(\d+)').firstMatch(url);
    if (m1 != null) return m1.group(1);

    final m2 = RegExp(r'/share/video/(\d+)').firstMatch(url);
    if (m2 != null) return m2.group(1);

    final m3 = RegExp(r'aweme_id=(\d+)').firstMatch(url);
    if (m3 != null) return m3.group(1);

    final m4 = RegExp(r'item_ids=(\d+)').firstMatch(url);
    if (m4 != null) return m4.group(1);

    return null;
  }

  static String? _extractVideoIdFromHtml(String html) {
    // SSR 数据中的 awemeId
    final m1 = RegExp(r'"awemeId"\s*:\s*"(\d+)"').firstMatch(html) ??
        RegExp(r'"awemeId"\s*:\s*(\d+)').firstMatch(html);
    if (m1 != null) return m1.group(1);

    // REQUEST_CONF itemId
    final m2 = RegExp(r'"itemId"\s*:\s*"(\d+)"').firstMatch(html) ??
        RegExp(r'"itemId"\s*:\s*(\d+)').firstMatch(html);
    if (m2 != null) return m2.group(1);

    // _ROUTER_DATA
    final m3 = RegExp(r'/video/(\d+)').firstMatch(html);
    if (m3 != null) return m3.group(1);

    // REACT_APP_DATA / __NEXT_DATA__
    final m4 = RegExp(r'aweme_id["\s:]+(\d+)').firstMatch(html);
    if (m4 != null) return m4.group(1);

    return null;
  }

  /// 通过视频ID获取信息并下载
  static Future<List<ResolvedMedia>> _fetchAndDownloadDouyin(
    String videoId, {
    void Function(double progress, String status)? onProgress,
  }) async {
    final dio = _createDio(baseUrl: 'https://www.douyin.com/');

    // 访问视频页面，从 SSR 数据中提取播放地址
    final pageUrl = 'https://www.douyin.com/video/$videoId';
    final resp = await dio.get(pageUrl);
    final html = resp.data.toString();

    final results = <ResolvedMedia>[];

    // 方法1：尝试从 SSR JSON 中解析
    final videoInfo = _parseVideoInfoFromHtml(html, videoId);
    if (videoInfo != null) {
      results.addAll(videoInfo);
    }

    // 方法2：直接在 HTML 中搜索视频 URL 并下载
    if (results.isEmpty) {
      final htmlResults =
          await _extractAndDownloadVideoUrlsFromHtml(html, videoId);
      results.addAll(htmlResults);
    }

    if (results.isEmpty) {
      throw Exception('未能从页面中提取视频地址。可能是该视频已设为私密或已被删除。');
    }

    return results;
  }

  /// 从 HTML 解析视频信息
  static List<ResolvedMedia>? _parseVideoInfoFromHtml(
      String html, String videoId) {
    // 查找 __REACT_APP_DATA__ JSON
    final reactMatch =
        RegExp(r'__REACT_APP_DATA__\s*=\s*(\{[\s\S]*?\});').firstMatch(html);
    if (reactMatch == null) {
      // 尝试 __NEXT_DATA__
      final nextMatch =
          RegExp(r'__NEXT_DATA__\s*=\s*(\{[\s\S]*?\})\s*</script>')
              .firstMatch(html);
      if (nextMatch == null) return null;
      return _parseNextData(nextMatch.group(1)!, videoId);
    }

    try {
      final jsonStr = reactMatch.group(1)!;
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      return _extractFromReactData(data, videoId);
    } catch (e) {
      debugPrint('SSR JSON 解析失败: $e');
      return null;
    }
  }

  static List<ResolvedMedia> _parseNextData(String jsonStr, String videoId) {
    final results = <ResolvedMedia>[];
    try {
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      // Navigate the Next.js data structure
      final props = data['props'] as Map?;
      final pageProps = props?['pageProps'] as Map?;
      if (pageProps != null) {
        final videoData =
            pageProps['videoInfo'] as Map? ?? pageProps['RENDER_DATA'] as Map?;
        if (videoData != null) {
          _findAndExtractMedia(videoData, videoId, results);
        }
      }
    } catch (e) {
      debugPrint('Next.js 数据解析失败: $e');
    }
    return results;
  }

  static List<ResolvedMedia> _extractFromReactData(
      Map<String, dynamic> data, String videoId) {
    final results = <ResolvedMedia>[];
    // 递归搜索包含 playAddr 的 Map
    _findAndExtractMedia(data, videoId, results);
    return results;
  }

  static void _findAndExtractMedia(
      dynamic obj, String videoId, List<ResolvedMedia> results) {
    if (results.isNotEmpty) return;

    if (obj is Map) {
      // 检查是否是视频对象
      final video = obj['video'];
      if (video is Map) {
        final playAddr = video['play_addr'];
        if (playAddr is Map) {
          _extractPlayUrls(playAddr, videoId, results);
        }
        // Also try download_addr for no-watermark
        final downloadAddr = video['download_addr'];
        if (downloadAddr is Map) {
          _extractPlayUrls(downloadAddr, videoId, results);
        }
      }

      // 检查是否是图文对象
      final images = obj['images'];
      if (images is List && images.isNotEmpty) {
        _extractImageUrls(images, videoId, results);
      }

      // 递归
      for (final key in obj.keys) {
        if (results.isNotEmpty) return;
        _findAndExtractMedia(obj[key], videoId, results);
      }
    } else if (obj is List) {
      for (final item in obj) {
        if (results.isNotEmpty) return;
        _findAndExtractMedia(item, videoId, results);
      }
    }
  }

  static Future<void> _extractPlayUrls(
      Map playAddr, String videoId, List<ResolvedMedia> results) async {
    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;

    final urlList = playAddr['url_list'];
    if (urlList is List && urlList.isNotEmpty) {
      for (int i = 0; i < urlList.length && i < 2; i++) {
        var url = urlList[i].toString();
        // 尝试无水印
        url = url.replaceAll('playwm', 'play');
        url = url.replaceAll('watermark=1', 'watermark=0');
        final filePath = '${tempDir.path}/douyin_${videoId}_$ts.mp4';
        try {
          await _createDio().download(url, filePath);
          results.add(ResolvedMedia(localPath: filePath, isVideo: true));
          return;
        } catch (_) {
          // 尝试下一个 URL
        }
      }
    }
  }

  static Future<void> _extractImageUrls(
      List images, String videoId, List<ResolvedMedia> results) async {
    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < images.length; i++) {
      final img = images[i] as Map;
      final urlList = img['url_list'];
      if (urlList is List && urlList.isNotEmpty) {
        var url = urlList[0].toString();
        url = url.replaceFirst('http://', 'https://');
        final filePath = '${tempDir.path}/douyin_${videoId}_${i}_$ts.jpg';
        try {
          await _createDio().download(url, filePath);
          results.add(ResolvedMedia(localPath: filePath, isVideo: false));
        } catch (_) {
          // skip failed image
        }
      }
    }
  }

  /// 备用：直接从 HTML 正则提取视频 URL 并下载
  static Future<List<ResolvedMedia>> _extractAndDownloadVideoUrlsFromHtml(
      String html, String videoId) async {
    final results = <ResolvedMedia>[];
    final tempDir = await getTemporaryDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;

    // 搜索 mp4 URL
    final urlRegex =
        RegExp(r'''(https?://[^"'\s<>\\]+?\.(?:mp4|m3u8)[^"'\s<>\\]*)''');
    final matches = urlRegex.allMatches(html);

    for (final m in matches) {
      var url = m.group(1)!.replaceAll('\\u002F', '/');
      url = url.replaceAll('playwm', 'play');
      url = url.replaceAll('watermark=1', 'watermark=0');
      url = Uri.decodeComponent(url);

      if (url.length < 30) continue;

      final filePath = '${tempDir.path}/douyin_raw_${videoId}_$ts.mp4';
      try {
        await _createDio().download(url, filePath);
        results.add(ResolvedMedia(localPath: filePath, isVideo: true));
        break; // 取第一个成功的
      } catch (_) {
        continue; // 尝试下一个
      }
    }

    return results;
  }

  // ==================== B站 ====================

  static Future<List<ResolvedMedia>> _resolveBilibili(
    String url, {
    void Function(double progress, String status)? onProgress,
  }) async {
    onProgress?.call(0.1, '正在解析 B站 视频信息...');
    final dio = _createDio(baseUrl: 'https://www.bilibili.com/');

    final bvMatch = RegExp(r'/(BV[\w]+)').firstMatch(url) ??
        RegExp(r'bvid=(BV[\w]+)').firstMatch(url);
    if (bvMatch == null) throw Exception('无法提取B站视频ID');
    final bvid = bvMatch.group(1)!;

    final apiUrl = 'https://api.bilibili.com/x/web-interface/view?bvid=$bvid';
    final resp = await dio.get(apiUrl);
    final data = resp.data is Map ? resp.data['data'] as Map? : null;
    if (data == null) throw Exception('B站 API 未返回数据');

    final cid = data['cid'];
    final aid = data['aid'];

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
    onProgress?.call(0.3, '正在下载 B站 视频...');
    await dio.download(
      videoUrl,
      filePath,
      onReceiveProgress: (received, total) {
        if (total > 0 && onProgress != null) {
          final progress = 0.3 + (received / total) * 0.7;
          final mb = (received / 1024 / 1024).toStringAsFixed(1);
          final totalMb = (total / 1024 / 1024).toStringAsFixed(1);
          onProgress(progress, '正在下载 B站 视频 $mb MB / $totalMb MB');
        }
      },
      options: Options(headers: {'Referer': 'https://www.bilibili.com/'}),
    );
    results.add(ResolvedMedia(localPath: filePath, isVideo: true));

    return results;
  }

  // ==================== TikTok ====================

  static Future<List<ResolvedMedia>> _resolveTiktok(
    String shareUrl, {
    void Function(double progress, String status)? onProgress,
  }) async {
    onProgress?.call(0.1, '正在解析 TikTok 链接...');
    final client = HttpClient();
    client.badCertificateCallback = (cert, host, port) => true;

    try {
      final req = await client.getUrl(Uri.parse(shareUrl));
      req.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
      );
      req.headers.set(
        HttpHeaders.acceptHeader,
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      );
      req.headers.set(
        HttpHeaders.acceptLanguageHeader,
        'en-US,en;q=0.9,zh-CN,zh;q=0.8',
      );
      req.followRedirects = true;
      req.maxRedirects = 10;

      final resp = await req.close();
      final cookies = <Cookie>[];
      resp.cookies.forEach(cookies.add);

      final html = await resp.transform(utf8.decoder).join();
      final finalUrl = resp.redirects.isNotEmpty
          ? resp.redirects.last.location.toString()
          : shareUrl;

      final videoIdMatch = RegExp(r'/video/(\d+)').firstMatch(finalUrl) ??
          RegExp(r'/video/(\d+)').firstMatch(shareUrl);
      final videoId = videoIdMatch?.group(1) ??
          DateTime.now().millisecondsSinceEpoch.toString();

      String? videoUrl;
      final imageUrls = <String>[];

      void extractMedia(dynamic obj) {
        if (videoUrl != null || imageUrls.isNotEmpty) return;
        if (obj is Map) {
          final imgPost = obj['imagePostInfo'];
          if (imgPost is Map && imgPost['images'] is List) {
            for (final item in imgPost['images']) {
              if (item is Map) {
                final disp = item['displayImage'] ?? item['display_image'];
                if (disp is Map &&
                    disp['urlList'] is List &&
                    (disp['urlList'] as List).isNotEmpty) {
                  imageUrls.add(disp['urlList'][0].toString());
                } else if (item['urlList'] is List &&
                    (item['urlList'] as List).isNotEmpty) {
                  imageUrls.add(item['urlList'][0].toString());
                }
              }
            }
            if (imageUrls.isNotEmpty) return;
          }

          final video = obj['video'];
          if (video is Map) {
            final pAddr = video['playAddr'] ?? video['play_addr'];
            final dlAddr = video['downloadAddr'] ?? video['download_addr'];
            if (pAddr is String && pAddr.isNotEmpty) {
              videoUrl = pAddr;
              return;
            } else if (pAddr is Map &&
                pAddr['url_list'] is List &&
                (pAddr['url_list'] as List).isNotEmpty) {
              videoUrl = (pAddr['url_list'] as List).first.toString();
              return;
            } else if (dlAddr is String && dlAddr.isNotEmpty) {
              videoUrl = dlAddr;
              return;
            }
          }

          for (final v in obj.values) {
            extractMedia(v);
          }
        } else if (obj is List) {
          for (final v in obj) {
            extractMedia(v);
          }
        }
      }

      dynamic parseScript(String id) {
        final match = RegExp('<script id="$id"[^>]*>(.*?)</script>',
                dotAll: true)
            .firstMatch(html);
        if (match != null) {
          try {
            return jsonDecode(match.group(1)!);
          } catch (_) {}
        }
        return null;
      }

      final universal = parseScript('__UNIVERSAL_DATA_FOR_REHYDRATION__');
      if (universal != null) extractMedia(universal);

      if (videoUrl == null && imageUrls.isEmpty) {
        final apiData = parseScript('api-data');
        if (apiData != null) extractMedia(apiData);
      }

      if (videoUrl == null && imageUrls.isEmpty) {
        final sigi = parseScript('SIGI_STATE');
        if (sigi != null) extractMedia(sigi);
      }

      // 正则兜底
      if (videoUrl == null && imageUrls.isEmpty) {
        final m = RegExp(r'"playAddr"\s*:\s*"([^"]+)"').firstMatch(html) ??
            RegExp(r'"downloadAddr"\s*:\s*"([^"]+)"').firstMatch(html);
        if (m != null) {
          videoUrl =
              m.group(1)!.replaceAll(r'\u002F', '/').replaceAll(r'\/', '/');
        }
      }

      final tempDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final results = <ResolvedMedia>[];

      if (videoUrl != null) {
        onProgress?.call(0.2, '正在连接 TikTok 视频流...');
        final cleanUrl = Uri.decodeFull(
            videoUrl!.replaceAll(r'\u002F', '/').replaceAll(r'\/', '/'));
        final filePath = '${tempDir.path}/tiktok_${videoId}_$ts.mp4';

        final dlReq = await client.getUrl(Uri.parse(cleanUrl));
        dlReq.headers.set(
          HttpHeaders.userAgentHeader,
          'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
        );
        dlReq.headers.set('Referer', 'https://www.tiktok.com/');
        for (final c in cookies) {
          dlReq.cookies.add(c);
        }

        final dlResp = await dlReq.close();
        if (dlResp.statusCode >= 400) {
          throw Exception('TikTok 视频流下载失败 (HTTP ${dlResp.statusCode})');
        }

        final totalBytes = dlResp.contentLength;
        int receivedBytes = 0;
        final file = File(filePath);
        final sink = file.openWrite();

        await for (final chunk in dlResp) {
          sink.add(chunk);
          receivedBytes += chunk.length;
          if (totalBytes > 0 && onProgress != null) {
            final progress = 0.2 + (receivedBytes / totalBytes) * 0.8;
            final mb = (receivedBytes / 1024 / 1024).toStringAsFixed(1);
            final totalMb = (totalBytes / 1024 / 1024).toStringAsFixed(1);
            onProgress(progress, '正在下载 TikTok 视频 $mb MB / $totalMb MB');
          }
        }
        await sink.flush();
        await sink.close();

        results.add(ResolvedMedia(localPath: filePath, isVideo: true));
        return results;
      }

      if (imageUrls.isNotEmpty) {
        for (var i = 0; i < imageUrls.length; i++) {
          onProgress?.call(
            (i + 1) / imageUrls.length,
            '正在下载 TikTok 图集 (${i + 1}/${imageUrls.length})...',
          );
          final imgUrl = imageUrls[i];
          final extMatch =
              RegExp(r'\.(jpe?g|png|webp|heic)', caseSensitive: false)
                  .firstMatch(imgUrl);
          final ext = extMatch?.group(1)?.toLowerCase() ?? 'jpg';
          final filePath = '${tempDir.path}/tiktok_${videoId}_${i}_$ts.$ext';

          final dlReq = await client.getUrl(Uri.parse(imgUrl));
          dlReq.headers.set(
            HttpHeaders.userAgentHeader,
            'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
            'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
          );
          dlReq.headers.set('Referer', 'https://www.tiktok.com/');
          for (final c in cookies) {
            dlReq.cookies.add(c);
          }
          final dlResp = await dlReq.close();
          if (dlResp.statusCode < 400) {
            final file = File(filePath);
            final sink = file.openWrite();
            await dlResp.pipe(sink);
            results.add(ResolvedMedia(localPath: filePath, isVideo: false));
          }
        }
        if (results.isNotEmpty) return results;
      }

      throw Exception('未能从 TikTok 页面提取到可播放的媒体');
    } finally {
      client.close();
    }
  }

  // ==================== YouTube ====================

  static Future<List<ResolvedMedia>> _resolveYoutube(
    String url, {
    void Function(double progress, String status)? onProgress,
  }) async {
    onProgress?.call(0.1, '正在解析 YouTube 视频信息...');
    final yt = YoutubeExplode();
    try {
      final video = await yt.videos.get(url);
      onProgress?.call(0.2, '正在检索最佳画质视频流...');
      final manifest = await yt.videos.streamsClient.getManifest(video.id);

      StreamInfo? selectedStream;
      final mp4Muxed = manifest.muxed
          .where((s) => s.container.name.toLowerCase() == 'mp4')
          .toList();
      if (mp4Muxed.isNotEmpty) {
        selectedStream = mp4Muxed.withHighestBitrate();
      } else if (manifest.muxed.isNotEmpty) {
        selectedStream = manifest.muxed.withHighestBitrate();
      } else if (manifest.video.isNotEmpty) {
        final mp4Video = manifest.video
            .where((s) => s.container.name.toLowerCase() == 'mp4')
            .toList();
        if (mp4Video.isNotEmpty) {
          selectedStream = mp4Video.withHighestBitrate();
        } else {
          selectedStream = manifest.video.withHighestBitrate();
        }
      }

      if (selectedStream == null) {
        throw Exception('未找到可下载的 YouTube 视频流');
      }

      final tempDir = await getTemporaryDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = selectedStream.container.name.toLowerCase();
      final filePath = '${tempDir.path}/youtube_${video.id}_$ts.$ext';

      final totalBytes = selectedStream.size.totalBytes;
      int receivedBytes = 0;

      onProgress?.call(0.3, '正在下载 YouTube 视频...');
      final stream = yt.videos.streamsClient.get(selectedStream);
      final file = File(filePath);
      final sink = file.openWrite();

      await for (final chunk in stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0 && onProgress != null) {
          final progress = 0.3 + (receivedBytes / totalBytes) * 0.7;
          final mb = (receivedBytes / 1024 / 1024).toStringAsFixed(1);
          final totalMb = (totalBytes / 1024 / 1024).toStringAsFixed(1);
          onProgress(progress, '正在下载 YouTube 视频 $mb MB / $totalMb MB');
        }
      }
      await sink.flush();
      await sink.close();

      return [ResolvedMedia(localPath: filePath, isVideo: true)];
    } catch (e) {
      debugPrint('YouTube 下载失败: $e');
      throw Exception('YouTube 视频下载失败: $e');
    } finally {
      yt.close();
    }
  }
}
