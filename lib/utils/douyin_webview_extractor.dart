import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ExtractedMedia {
  const ExtractedMedia({required this.url, required this.isVideo});

  final String url;
  final bool isVideo;
}

class DouyinWebViewExtractor {
  DouyinWebViewExtractor._();

  static const Duration timeout = Duration(seconds: 45);

  static const String interceptorScript = r'''
    window.__capturedMediaList = window.__capturedMediaList || [];

    if (window.fetch && !window.__lewisFetchHooked) {
      window.__lewisFetchHooked = true;
      var originalFetch = window.fetch;
      window.fetch = function() {
        var url = arguments[0] instanceof Request ? arguments[0].url : String(arguments[0]);
        return originalFetch.apply(this, arguments).then(function(response) {
          window.__capturedMediaList.push(url);
          return response;
        });
      };
    }

    if (!window.__lewisXhrHooked) {
      window.__lewisXhrHooked = true;
      var originalOpen = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(method, url) {
        this.__lewisUrl = String(url);
        window.__capturedMediaList.push(String(url));
        return originalOpen.apply(this, arguments);
      };
    }
  ''';

  static Future<List<ExtractedMedia>> extractFromController(
    WebViewController controller,
  ) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      try {
        await controller.runJavaScript(interceptorScript);
      } catch (_) {}
      await Future<void>.delayed(const Duration(seconds: 2));

      try {
        final raw = await controller.runJavaScriptReturningResult('''
          (function() {
            var urls = [];
            document.querySelectorAll('video').forEach(function(video) {
              [video.src, video.currentSrc].forEach(function(url) {
                if (url && url.indexOf('http') === 0) urls.push(url);
              });
              video.querySelectorAll('source').forEach(function(source) {
                if (source.src && source.src.indexOf('http') === 0) urls.push(source.src);
              });
            });

            document.querySelectorAll('img').forEach(function(image) {
              var url = image.currentSrc || image.src;
              if (image.naturalWidth >= 320 && url && url.indexOf('http') === 0) {
                urls.push(url);
              }
            });

            (window.__capturedMediaList || []).forEach(function(url) {
              if (url && url.indexOf('http') === 0) urls.push(url);
            });

            var globals = [];
            if (window.__NEXT_DATA__) globals.push(JSON.stringify(window.__NEXT_DATA__));
            if (window.__REACT_APP_DATA__) globals.push(JSON.stringify(window.__REACT_APP_DATA__));
            if (window._ROUTER_DATA__) globals.push(JSON.stringify(window._ROUTER_DATA__));
            if (window._ROUTER_DATA) globals.push(JSON.stringify(window._ROUTER_DATA));
            if (window._SSR_DATA) globals.push(JSON.stringify(window._SSR_DATA));
            if (window.__INITIAL_DATA__) globals.push(JSON.stringify(window.__INITIAL_DATA__));
            if (window._INIT_DATA) globals.push(JSON.stringify(window._INIT_DATA));
            if (window.RENDER_DATA) globals.push(JSON.stringify(window.RENDER_DATA));

            var renderDataEl = document.getElementById('RENDER_DATA');
            if (renderDataEl && renderDataEl.innerText) {
              try {
                globals.push(decodeURIComponent(renderDataEl.innerText));
              } catch(e) {
                globals.push(renderDataEl.innerText);
              }
            }
            var universalDataEl = document.getElementById('__UNIVERSAL_DATA_FOR_REHYDRATION__');
            if (universalDataEl && universalDataEl.innerText) {
              globals.push(universalDataEl.innerText);
            }

            document.querySelectorAll('script[type="application/json"]').forEach(function(s) {
              if (s.innerText) globals.push(s.innerText);
            });

            return JSON.stringify({
              urls: urls,
              globals: globals.join('\\n'),
              html: document.documentElement.innerHTML
            });
          })()
        ''');

        final media = _parsePage(raw is String ? raw : raw.toString());
        if (media.isNotEmpty) return media;
      } catch (error) {
        debugPrint('读取页面数据失败: $error');
      }

      await Future<void>.delayed(const Duration(seconds: 3));
    }

    throw TimeoutException('媒体提取超时', timeout);
  }

  static List<ExtractedMedia> _parsePage(String rawJson) {
    if (rawJson == 'null' || rawJson.isEmpty) return const [];
    String cleaned = rawJson.trim();

    dynamic decoded;
    try {
      decoded = jsonDecode(cleaned);
      if (decoded is String) decoded = jsonDecode(decoded);
    } catch (_) {
      return const [];
    }

    if (decoded is! Map<String, dynamic>) return const [];
    final page = decoded;

    final globalsText = page['globals'] as String? ?? '';
    final structuredMedia = _extractStructuredMedia(globalsText);
    if (structuredMedia.isNotEmpty) return structuredMedia;

    final domUrls = (page['urls'] as List<dynamic>? ?? [])
        .whereType<String>()
        .map((url) => Uri.decodeFull(url.replaceAll('&amp;', '&')))
        .toList();
    final domVideos = domUrls.where((url) => _isVideoUrl(url)).toList();
    if (domVideos.isNotEmpty) {
      return [
        ExtractedMedia(url: _noWatermark(domVideos.first), isVideo: true)
      ];
    }

    final htmlText = [
      ...domUrls,
      page['html'] as String? ?? '',
    ].join('\n').replaceAll(r'\/', '/').replaceAll(r'\"', '"');

    final videoUrls = _uniqueUrls(htmlText, _videoPattern);
    if (videoUrls.isNotEmpty) {
      return [
        ExtractedMedia(url: _noWatermark(videoUrls.first), isVideo: true)
      ];
    }

    final imageUrls = _uniqueUrls(htmlText, _imagePattern)
        .where((url) => !_looksLikeAvatar(url))
        .toList();
    if (imageUrls.length == 1) {
      return [ExtractedMedia(url: imageUrls.single, isVideo: false)];
    }
    if (imageUrls.isNotEmpty) {
      return imageUrls
          .map((url) => ExtractedMedia(url: url, isVideo: false))
          .toList();
    }

    return const [];
  }

  static List<ExtractedMedia> _extractStructuredMedia(String globalsText) {
    final media = <ExtractedMedia>[];
    for (final line in globalsText.split('\n')) {
      try {
        final data = jsonDecode(line.trim());
        _collectStructuredMedia(data, media);
      } catch (_) {}
    }
    return media;
  }

  static void _collectStructuredMedia(
      dynamic value, List<ExtractedMedia> media) {
    if (value is Map) {
      final video = value['video'];
      if (video is Map) {
        for (final key in [
          'play_addr',
          'playAddr',
          'play_addr_h264',
          'play_addr_265',
          'download_addr',
          'downloadAddr',
          'play_url',
        ]) {
          final address = video[key];
          final url = _firstListUrl(address);
          if (url != null && !_hasMediaType(media, true)) {
            media.add(ExtractedMedia(url: _noWatermark(url), isVideo: true));
            break;
          }
        }
      }

      final images = value['images'] ??
          value['image_list'] ??
          value['images_list'] ??
          value['display_image'];
      if (images is List) {
        for (final image in images) {
          final url = _firstListUrl(image);
          if (url != null && !_hasMediaType(media, false, url)) {
            media.add(ExtractedMedia(url: url, isVideo: false));
          }
        }
      }

      for (final child in value.values) {
        _collectStructuredMedia(child, media);
      }
    } else if (value is List) {
      for (final child in value) {
        _collectStructuredMedia(child, media);
      }
    }
  }

  static String? _firstListUrl(dynamic value) {
    if (value is! Map) return null;
    final urls = value['url_list'] ??
        value['urlList'] ??
        value['download_url_list'] ??
        value['downloadUrlList'];
    if (urls is! List || urls.isEmpty) return null;
    final url = urls.first.toString().replaceFirst('http://', 'https://');
    return url.startsWith('http') ? Uri.decodeFull(url) : null;
  }

  static bool _hasMediaType(List<ExtractedMedia> media, bool isVideo,
      [String? url]) {
    return media.any(
        (item) => item.isVideo == isVideo && (url == null || item.url == url));
  }

  static bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.mp4') ||
        lower.contains('/playwm/') ||
        lower.contains('/play/') ||
        lower.contains('mime_type=video_mp4');
  }

  static final RegExp _videoPattern = RegExp(
    r'''https?://[^\s"'\''<>\\]+?(?:\.mp4|/playwm?/|mime_type=video_mp4)[^\s"'\''<>\\]*''',
    caseSensitive: false,
  );

  static final RegExp _imagePattern = RegExp(
    r'''https?://[^\s"'\''<>\\]+?(?:douyinpic\.com|douyin\.com/aweme/v1/image)(?:[^\s"'\''<>\\?]*|\?[^\s"'\''<>\\]*)''',
    caseSensitive: false,
  );

  static List<String> _uniqueUrls(String text, RegExp pattern) {
    final urls = <String>[];
    for (final match in pattern.allMatches(text)) {
      final url = Uri.decodeFull(match.group(0)!.replaceAll('&amp;', '&'));
      if (url.startsWith('http') && !urls.contains(url)) {
        urls.add(url);
      }
    }
    return urls;
  }

  static String _noWatermark(String url) {
    return url
        .replaceAll('/playwm/', '/play/')
        .replaceAll('playwm?', 'play?')
        .replaceAll(RegExp(r'watermark=1'), 'watermark=0');
  }

  static bool _looksLikeAvatar(String url) {
    final lower = url.toLowerCase();
    return lower.contains('aweme-avatar') ||
        lower.contains('/avatar/') ||
        lower.contains('is_avatar=1');
  }
}
