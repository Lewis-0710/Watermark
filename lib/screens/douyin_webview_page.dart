import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/douyin_webview_extractor.dart';
import '../utils/url_resolver.dart';
import 'process_page.dart';

class DouyinWebViewPage extends StatefulWidget {
  const DouyinWebViewPage({super.key, required this.shareUrl});

  final String shareUrl;

  @override
  State<DouyinWebViewPage> createState() => _DouyinWebViewPageState();
}

class _DouyinWebViewPageState extends State<DouyinWebViewPage> {
  late final WebViewController _controller;
  bool _extracting = false;
  bool _downloading = false;
  bool _started = false;
  String _status = '正在准备...';
  int _retryCount = 0;
  static const int _maxRetries = 3;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();

    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null || (!uri.scheme.toLowerCase().startsWith('http'))) {
              // 拦截非 http/https 协议（如 snssdk1128://, douyin:// 等唤端 scheme），避免 WebKit 报 unsupported URL 错误
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _status = '正在打开分享页...');
          },
          onPageFinished: (_) => _extractAndDownload(),
          onWebResourceError: (error) {
            final desc = error.description.trim();
            if (desc.isNotEmpty &&
                !desc.toLowerCase().contains('unsupported url') &&
                !desc.toLowerCase().contains('frame load interrupted')) {
              debugPrint('WebView 资源提示: $desc');
            }
          },
        ),
      );
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _extracting = true;
      _status = '正在准备解析...';
      _progress = 0;
    });

    // 优先尝试直接解析（支持 TikTok、YouTube、B站及免验证抖音链接）
    try {
      final results = await UrlResolver.resolve(
        widget.shareUrl,
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _progress = progress;
              _status = status;
              _downloading = progress > 0.2;
            });
          }
        },
      );
      if (results.isNotEmpty) {
        if (mounted) setState(() => _status = '下载完成');
        _openProcessPage(results.map((r) => r.localPath).toList());
        return;
      }
    } catch (e) {
      debugPrint('快速直接解析未成功，尝试 WebView 方式: $e');
    }

    // 桌面端无内置 mobile webview，如果直接解析失败则提示用户
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux)) {
      if (mounted) {
        setState(() {
          _extracting = false;
          _downloading = false;
          _status = '解析失败，请检查链接有效性或网络连接';
        });
      }
      return;
    }

    try {
      if (mounted) setState(() => _status = '正在打开分享页...');
      await _controller.loadRequest(Uri.parse(widget.shareUrl));
    } catch (error) {
      debugPrint('WebView 初始化失败: $error');
      if (mounted) {
        setState(() {
          _extracting = false;
          _status = 'WebView 初始化失败: $error';
        });
      }
    }
  }

  Future<void> _extractAndDownload() async {
    if (_started || !mounted) return;
    _started = true;
    setState(() {
      _extracting = true;
      _status = '正在识别媒体类型...';
    });

    try {
      final media =
          await DouyinWebViewExtractor.extractFromController(_controller);
      if (media.isEmpty) throw Exception('未提取到可下载媒体');

      final video = media.where((item) => item.isVideo).toList();
      final images = media.where((item) => !item.isVideo).toList();
      if (video.isNotEmpty) {
        await _downloadVideo(video.first.url);
      } else if (images.isNotEmpty) {
        await _downloadImages(images.map((item) => item.url).toList());
      } else {
        throw Exception('未识别到视频或图集');
      }
    } catch (error) {
      debugPrint('媒体提取失败: $error');
      if (!mounted) return;
      if (_retryCount < _maxRetries) {
        _retryCount++;
        await Future.delayed(const Duration(seconds: 2));
        _started = false;
        if (mounted) {
          setState(() {
            _extracting = false;
            _status = '正在重试提取 ($_retryCount/$_maxRetries)...';
          });
          _extractAndDownload();
        }
      } else {
        setState(() {
          _extracting = false;
          _status = '提取超时或未找到媒体，请检查链接有效性';
        });
      }
    }
  }

  Dio _dio() {
    final lower = widget.shareUrl.toLowerCase();
    final isTiktok = lower.contains('tiktok.com');
    final referer = isTiktok ? 'https://www.tiktok.com/' : widget.shareUrl;
    return Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 120),
          headers: {
            'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) '
                'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
            'Referer': referer,
          },
        ),
      );
  }

  Future<void> _downloadVideo(String url) async {
    setState(() {
      _downloading = true;
      _status = '正在下载视频...';
      _progress = 0;
    });

    final directory = await getTemporaryDirectory();
    final isTiktok = widget.shareUrl.toLowerCase().contains('tiktok.com');
    final filePath =
        '${directory.path}/${isTiktok ? "tiktok" : "media"}_video_${DateTime.now().millisecondsSinceEpoch}.mp4';
    try {
      await _dio().download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        },
      );
      if (mounted) setState(() => _status = '下载完成');
      _openProcessPage([filePath]);
    } catch (error) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _status = '视频下载失败: $error';
        });
      }
      rethrow;
    }
  }

  Future<void> _downloadImages(List<String> urls) async {
    setState(() {
      _downloading = true;
      _status = '正在下载图集...';
      _progress = 0;
    });

    final directory = await getTemporaryDirectory();
    final paths = <String>[];
    try {
      for (var index = 0; index < urls.length; index++) {
        final url = urls[index];
        final extensionMatch =
            RegExp(r'\.(jpe?g|png|webp|heic)', caseSensitive: false)
                .firstMatch(url);
        final extension = extensionMatch?.group(1)?.toLowerCase() ?? 'jpg';
        final filePath =
            '${directory.path}/douyin_gallery_${DateTime.now().millisecondsSinceEpoch}_$index.$extension';
        await _dio().download(url, filePath);
        paths.add(filePath);
        if (mounted) {
          setState(() => _progress = (index + 1) / urls.length);
        }
      }
      if (paths.isEmpty) throw Exception('图集下载失败');
      if (mounted) setState(() => _status = '下载完成');
      _openProcessPage(paths);
    } catch (error) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _status = '图集下载失败: $error';
        });
      }
      rethrow;
    }
  }

  void _openProcessPage(List<String> paths) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ProcessPage(inputUrl: '', localPaths: paths),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          if (!kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.android))
          Positioned.fill(
            child: Opacity(
              opacity: 0.01,
              child: IgnorePointer(
                child: WebViewWidget(controller: _controller),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_extracting || _downloading) ...[
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 18),
                ],
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                if (_downloading && _progress > 0) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: 220,
                    child: LinearProgressIndicator(value: _progress),
                  ),
                ],
                if (!_extracting &&
                    !_downloading &&
                    _retryCount >= _maxRetries) ...[
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _retryCount = 0;
                        _started = false;
                      });
                      _start();
                    },
                    child: const Text('重新尝试'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
