import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:uuid/uuid.dart';

import '../utils/inpainting.dart';
import '../utils/url_resolver.dart';

class ProcessPage extends StatefulWidget {
  final String inputUrl;
  final List<String> localPaths;

  const ProcessPage({
    super.key,
    required this.inputUrl,
    required this.localPaths,
  });

  @override
  State<ProcessPage> createState() => _ProcessPageState();
}

enum MediaType { image, video }

class MediaItem {
  final MediaType type;
  final String path;
  final ui.Image? decodedImage; // 本地图片解码后
  final VideoPlayerController? videoController;
  img.Image? dartImage; // 用于处理
  Uint8List? processedBytes; // 处理后
  final List<List<DrawPoint>> strokeList = []; // 涂鸦笔画

  MediaItem({
    required this.type,
    required this.path,
    this.decodedImage,
    this.videoController,
    this.dartImage,
    this.processedBytes,
  });

  bool get isProcessed => processedBytes != null;
}

class DrawPoint {
  final Offset localOffset; // 相对于绘制区域的坐标（0-1的比例坐标? 这里采用实际像素点再配合缩放）
  final double pressure;
  DrawPoint(this.localOffset, this.pressure);
}

class _ProcessPageState extends State<ProcessPage> {
  late final List<MediaItem> _items;
  int _currentIndex = 0;

  // 变换
  double _scale = 1.0;
  double _baseScale = 1.0;
  Offset _offset = Offset.zero;
  Offset _baseOffset = Offset.zero;

  // 手势
  final Set<_Pointer> _pointers = {};
  Offset? _lastFocalPoint;
  double _lastPinchDist = 0;

  // 绘制
  final List<DrawPoint> _currentStroke = [];
  bool _isDrawing = false;

  bool _isProcessing = false;
  bool _isLoadingUrl = false;
  String _loadingText = '';
  double _processProgress = 0;
  String _progressText = '';

  @override
  void initState() {
    super.initState();
    _items = [];
    _loadMedia();
  }

  @override
  void dispose() {
    for (var it in _items) {
      it.decodedImage?.dispose();
      it.videoController?.dispose();
    }
    super.dispose();
  }

  Future<void> _loadMedia() async {
    // 先加载本地路径
    for (final p in widget.localPaths) {
      final type = _detectType(p);
      final item = await _buildMediaItem(type, p);
      if (item != null) _items.add(item);
    }

    // 如果有 URL 且没有本地文件，尝试解析下载
    if (_items.isEmpty && widget.inputUrl.trim().isNotEmpty) {
      setState(() {
        _isLoadingUrl = true;
        _loadingText = '正在解析链接...';
      });
      try {
        _loadingText = '正在下载媒体...';
        if (mounted) setState(() {});
        final results = await UrlResolver.resolve(widget.inputUrl);
        for (final r in results) {
          final type = r.isVideo ? MediaType.video : MediaType.image;
          final item = await _buildMediaItem(type, r.localPath);
          if (item != null) _items.add(item);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('链接解析失败: $e'),
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isLoadingUrl = false);
      }
    }

    if (mounted) setState(() {});
  }

  MediaType _detectType(String path) {
    final ext = path.toLowerCase();
    if (ext.endsWith('.mp4') ||
        ext.endsWith('.mov') ||
        ext.endsWith('.m4v') ||
        ext.endsWith('.avi') ||
        ext.endsWith('.mkv') ||
        ext.endsWith('.webm')) {
      return MediaType.video;
    }
    return MediaType.image;
  }

  Future<MediaItem?> _buildMediaItem(MediaType type, String path) async {
    try {
      if (type == MediaType.image) {
        final bytes = await File(path).readAsBytes();
        final dartImg = img.decodeImage(bytes);
        final decoded = await _decodeImageFromBytes(bytes);
        if (dartImg == null) return null;
        return MediaItem(
          type: type,
          path: path,
          decodedImage: decoded,
          dartImage: dartImg,
        );
      } else {
        final vCtrl = VideoPlayerController.file(File(path));
        await vCtrl.initialize();
        vCtrl.setLooping(true);
        vCtrl.play();
        return MediaItem(
          type: type,
          path: path,
          videoController: vCtrl,
        );
      }
    } catch (e) {
      debugPrint('load media error: $e');
      return null;
    }
  }

  Future<ui.Image> _decodeImageFromBytes(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  // 撤回
  void _undo() {
    final item = _currentItem();
    if (item == null) {
      Navigator.of(context).pop();
      return;
    }
    if (item.strokeList.isNotEmpty) {
      item.strokeList.removeLast();
      setState(() {});
    } else {
      Navigator.of(context).pop();
    }
  }

  // 开始处理
  Future<void> _startProcess() async {
    final item = _currentItem();
    if (item == null) return;
    if (item.strokeList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先用涂鸦标记需要去除的水印位置')),
      );
      return;
    }
    if (item.type == MediaType.video) return;
    setState(() {
      _isProcessing = true;
      _processProgress = 0;
      _progressText = '准备图像...';
    });

    try {
      img.Image source;
      if (item.type == MediaType.image && item.dartImage != null) {
        source = img.copyResize(item.dartImage!,
            width: item.dartImage!.width, height: item.dartImage!.height);
      } else {
        // 视频：占位，用默认颜色 200x200
        source = img.Image(width: 720, height: 1280);
        img.fill(source, color: img.ColorRgb8(30, 30, 40));
      }

      // 构造遮罩：根据涂鸦笔画填充
      _processProgress = 0.1;
      _progressText = '生成遮罩...';
      if (mounted) setState(() {});
      await Future.delayed(const Duration(milliseconds: 80));

      final mask = img.Image(width: source.width, height: source.height);
      img.fill(mask, color: img.ColorRgba8(0, 0, 0, 0));

      final painter = _MaskPainter(
        strokes: item.strokeList,
        containerSize: _contentSize,
        imageSize: Size(source.width.toDouble(), source.height.toDouble()),
      );
      painter.drawOn(mask);

      _processProgress = 0.3;
      _progressText = '执行图像修复（inpainting）...';
      if (mounted) setState(() {});
      await Future.delayed(const Duration(milliseconds: 80));

      // 执行 inpainting
      final result = await runInpainting(
        source,
        mask,
        progressCallback: (p) {
          if (mounted) {
            setState(() {
              _processProgress = 0.3 + p * 0.6;
            });
          }
        },
      );

      _processProgress = 0.95;
      _progressText = '导出结果...';
      if (mounted) setState(() {});
      await Future.delayed(const Duration(milliseconds: 80));

      final outBytes = img.encodeJpg(result, quality: 95);
      item.processedBytes = Uint8List.fromList(outBytes);

      if (mounted) {
        setState(() {
          _isProcessing = false;
          _processProgress = 1.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('处理完成，点击底部下载按钮保存')),
        );
      }
    } catch (e, s) {
      debugPrint('process error: $e\n$s');
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('处理失败: $e')),
        );
      }
    }
  }

  // 下载保存
  Future<void> _download() async {
    final item = _currentItem();
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有可下载的媒体')),
      );
      return;
    }
    final extension = _mediaExtension(item);
    final name = _downloadName(extension);

    try {
      setState(() => _isProcessing = true);

      if (_isDesktop) {
        final directory = await getDownloadsDirectory();
        if (directory == null) {
          throw Exception('无法获取下载目录');
        }
        await directory.create(recursive: true);
        final file = File('${directory.path}/$name');
        final bytes =
            item.processedBytes ?? await File(item.path).readAsBytes();
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已保存到下载: ${file.path}')),
          );
        }
      } else {
        if (item.type == MediaType.video) {
          if (item.processedBytes != null) {
            throw Exception('视频处理后文件不存在，无法保存到相册');
          }
          await Gal.putVideo(item.path);
        } else if (item.processedBytes != null) {
          await Gal.putImageBytes(item.processedBytes!, name: name);
        } else {
          await Gal.putImage(item.path);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已保存到相册: $name')),
          );
        }
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  bool get _isDesktop {
    return !kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
  }

  String _mediaExtension(MediaItem item) {
    if (item.processedBytes != null) return '.jpg';
    final extension = p.extension(item.path);
    if (extension.isNotEmpty) return extension;
    return item.type == MediaType.video ? '.mp4' : '.jpg';
  }

  String _downloadName(String extension) {
    return 'watermark_${const Uuid().v4().substring(0, 8)}$extension';
  }

  MediaItem? _currentItem() {
    if (_items.isEmpty) return null;
    return _items[_currentIndex.clamp(0, _items.length - 1)];
  }

  Size _contentSize = Size.zero;

  final GlobalKey _viewportKey = GlobalKey();

  RenderBox? _viewportBox() {
    final ctx = _viewportKey.currentContext;
    if (ctx == null) return null;
    return ctx.findRenderObject() as RenderBox?;
  }

  // 手势处理
  void _onPointerDown(PointerDownEvent event) {
    _pointers.add(_Pointer(event.pointer, event.localPosition));
    if (_pointers.length >= 2) {
      final pts = _pointers.toList();
      final dx = pts[0].position.dx - pts[1].position.dx;
      final dy = pts[0].position.dy - pts[1].position.dy;
      _lastPinchDist = sqrt(dx * dx + dy * dy);
      _baseScale = _scale;
      _baseOffset = _offset;
      final a = pts[0].position;
      final b = pts[1].position;
      _lastFocalPoint = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    }
    if (_pointers.length == 1) {
      final item = _currentItem();
      if (item != null && item.type == MediaType.image) {
        final drawLocal = _toDrawingLocal(event.localPosition);
        if (drawLocal != null) {
          _isDrawing = true;
          _currentStroke.clear();
          _currentStroke.add(DrawPoint(drawLocal, event.pressure));
        }
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    // 更新指针位置
    final p = _pointers.firstWhere((x) => x.id == event.pointer,
        orElse: () => _Pointer(-1, Offset.zero));
    if (p.id == -1) return;
    p.position = event.localPosition;

    if (_pointers.length >= 2) {
      final pts = _pointers.toList();
      final a = pts[0].position;
      final b = pts[1].position;
      final focal = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      final dx = a.dx - b.dx;
      final dy = a.dy - b.dy;
      final dist = sqrt(dx * dx + dy * dy);
      if (_lastPinchDist > 0) {
        final scale = (dist / _lastPinchDist) * _baseScale;
        _scale = scale.clamp(0.3, 6.0);
      }
      if (_lastFocalPoint != null) {
        final delta = focal - _lastFocalPoint!;
        _offset = _baseOffset + delta;
      }
      setState(() {});
    } else if (_isDrawing) {
      final drawLocal = _currentItem()?.type == MediaType.image
          ? _toDrawingLocal(event.localPosition)
          : null;
      if (drawLocal != null) {
        _currentStroke.add(DrawPoint(drawLocal, event.pressure));
        setState(() {});
      }
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointers.removeWhere((p) => p.id == event.pointer);
    if (_pointers.length < 2) {
      _lastPinchDist = 0;
    }
    if (_isDrawing && _pointers.isEmpty) {
      // 结束一笔
      final item = _currentItem();
      if (item != null && _currentStroke.isNotEmpty) {
        item.strokeList.add(List.from(_currentStroke));
      }
      _currentStroke.clear();
      _isDrawing = false;
      setState(() {});
    }
  }

  Offset? _toDrawingLocal(Offset globalLocal) {
    // 简单处理：内容居中，大小为 _contentSize
    final cs = _contentSize;
    if (cs.isEmpty) return null;
    final box = _viewportBox();
    final boxSize = box?.size ?? context.size;
    if (boxSize == null) return null;
    final topLeft = Offset(
        (boxSize.width - cs.width) / 2, (boxSize.height - cs.height) / 2);
    final rect = topLeft & cs;
    if (!rect.contains(globalLocal)) return null;
    return globalLocal - topLeft;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Listener(
          key: _viewportKey,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: (e) => _onPointerUp(PointerUpEvent(
            pointer: e.pointer,
            position: e.position,
          )),
          child: Stack(
            children: [
              Center(child: _buildMediaView()),
              _buildGallery(),
              // 链接解析中遮罩
              if (_isLoadingUrl)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 16),
                        Text(
                          _loadingText,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              // 处理中遮罩
              if (_isProcessing)
                Container(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 16),
                        Text(
                          '${(_processProgress * 100).toStringAsFixed(0)}% - $_progressText',
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: 220,
                          child: LinearProgressIndicator(
                            value: _processProgress,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Colors.blueAccent),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Positioned(
                left: 20,
                bottom: 32,
                child: _buildUndoButton(),
              ),
              Positioned(
                right: 20,
                bottom: 32,
                child: _buildDownloadButton(),
              ),
              if (_currentItem()?.strokeList.isNotEmpty == true)
                Positioned(
                  bottom: 32,
                  left: 0,
                  right: 0,
                  child: Center(child: _buildStartProcessButton()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGallery() {
    if (_items.length < 2) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        height: 88,
        color: Colors.black54,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 70, vertical: 10),
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final item = _items[index];
            final selected = index == _currentIndex;
            return GestureDetector(
              onTap: () => _selectItem(index),
              child: Container(
                width: 68,
                height: 68,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: selected ? Colors.blueAccent : Colors.white24,
                    width: selected ? 3 : 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: item.type == MediaType.video
                    ? const Icon(Icons.videocam, color: Colors.white70)
                    : Image.file(File(item.path), fit: BoxFit.cover),
              ),
            );
          },
        ),
      ),
    );
  }

  void _selectItem(int index) {
    if (index == _currentIndex || index < 0 || index >= _items.length) return;
    setState(() {
      _currentIndex = index;
      _scale = 1;
      _offset = Offset.zero;
    });
  }

  Widget _buildMediaView() {
    final item = _currentItem();
    if (item == null) {
      return const Text(
        '没有可预览的媒体\n请返回首页选择本地图片或视频',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white70),
      );
    }
    // 决定显示尺寸
    final maxW = MediaQuery.of(context).size.width - 32;
    final maxH = MediaQuery.of(context).size.height - 220;

    Size srcSize;
    if (item.type == MediaType.image && item.decodedImage != null) {
      srcSize = Size(item.decodedImage!.width.toDouble(),
          item.decodedImage!.height.toDouble());
    } else if (item.type == MediaType.video && item.videoController != null) {
      srcSize = Size(item.videoController!.value.size.width,
          item.videoController!.value.size.height);
    } else {
      srcSize = const Size(400, 400);
    }
    // 计算 contentSize
    final ratio = srcSize.width / srcSize.height;
    double w, h;
    if (ratio > maxW / maxH) {
      w = maxW;
      h = maxW / ratio;
    } else {
      h = maxH;
      w = maxH * ratio;
    }
    _contentSize = Size(w, h);

    final transform = Matrix4.identity()
      ..translate(_offset.dx, _offset.dy)
      ..scale(_scale);

    return Transform(
      transform: transform,
      alignment: Alignment.center,
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          children: [
            // 媒体
            Positioned.fill(child: _buildMedia(item)),
            // 涂鸦
            Positioned.fill(child: _buildDrawings(item)),
            // 外框
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24, width: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedia(MediaItem item) {
    if (item.type == MediaType.image) {
      if (item.isProcessed && item.processedBytes != null) {
        return Image.memory(item.processedBytes!, fit: BoxFit.fill);
      }
      if (item.decodedImage != null) {
        return RawImage(
          image: item.decodedImage,
          fit: BoxFit.fill,
        );
      }
      return Image.file(File(item.path), fit: BoxFit.fill);
    } else {
      final vc = item.videoController;
      if (vc == null) return const SizedBox();
      if (!vc.value.isInitialized) {
        return const Center(child: CircularProgressIndicator());
      }
      return FittedBox(
        fit: BoxFit.fill,
        child: SizedBox(
          width: vc.value.size.width,
          height: vc.value.size.height,
          child: VideoPlayer(vc),
        ),
      );
    }
  }

  Widget _buildDrawings(MediaItem item) {
    return CustomPaint(
      painter: _DrawingPainter(
        strokes: item.strokeList,
        current: _currentStroke,
      ),
      size: Size.infinite,
    );
  }

  Widget _buildUndoButton() {
    return FloatingActionButton(
      heroTag: 'undo',
      backgroundColor: Colors.orange[700],
      foregroundColor: Colors.white,
      onPressed: _undo,
      child: const Icon(Icons.undo),
    );
  }

  Widget _buildStartProcessButton() {
    return FloatingActionButton(
      heroTag: 'start',
      backgroundColor: Colors.green[700],
      foregroundColor: Colors.white,
      onPressed: _isProcessing ? null : _startProcess,
      child: const Icon(Icons.auto_fix_high),
    );
  }

  Widget _buildDownloadButton() {
    final item = _currentItem();
    return FloatingActionButton(
      heroTag: 'download',
      backgroundColor: Colors.blue[700],
      foregroundColor: Colors.white,
      onPressed: item == null || _isProcessing ? null : _download,
      child: const Icon(Icons.download),
    );
  }
}

class _Pointer {
  final int id;
  Offset position;
  _Pointer(this.id, this.position);
}

class _DrawingPainter extends CustomPainter {
  final List<List<DrawPoint>> strokes;
  final List<DrawPoint> current;

  _DrawingPainter({required this.strokes, required this.current});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.redAccent.withOpacity(0.65)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      _drawStroke(canvas, paint, stroke);
    }
    if (current.isNotEmpty) {
      _drawStroke(canvas, paint, current);
    }
  }

  void _drawStroke(Canvas canvas, Paint paint, List<DrawPoint> stroke) {
    if (stroke.length == 1) {
      canvas.drawCircle(stroke[0].localOffset, 18, paint..strokeWidth = 36);
      return;
    }
    for (int i = 1; i < stroke.length; i++) {
      final p1 = stroke[i - 1].localOffset;
      final p2 = stroke[i].localOffset;
      final w = 32 + (stroke[i].pressure - 0.5) * 10;
      canvas.drawLine(p1, p2, paint..strokeWidth = w.clamp(18, 56));
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) => true;
}

class _MaskPainter {
  final List<List<DrawPoint>> strokes;
  final Size containerSize;
  final Size imageSize;

  _MaskPainter({
    required this.strokes,
    required this.containerSize,
    required this.imageSize,
  });

  void drawOn(img.Image mask) {
    if (containerSize.isEmpty) return;
    final scaleX = imageSize.width / containerSize.width;
    final scaleY = imageSize.height / containerSize.height;
    final scale = scaleX > scaleY ? scaleX : scaleY; // 覆盖模式 -> 取较大值
    // 计算图片在容器内的位置偏移
    final scaledImgW = imageSize.width / scale;
    final scaledImgH = imageSize.height / scale;
    final offX = (containerSize.width - scaledImgW) / 2;
    final offY = (containerSize.height - scaledImgH) / 2;

    // color 用于 mask 填充，实际 setPixelRgba 已直接传参
    for (final stroke in strokes) {
      for (final p in stroke) {
        final local = p.localOffset;
        // 相对于图片区域的坐标
        final rx = local.dx - offX;
        final ry = local.dy - offY;
        if (rx < 0 || ry < 0 || rx > scaledImgW || ry > scaledImgH) continue;
        final ix = (rx * scale).round();
        final iy = (ry * scale).round();
        // 画一个圆
        final radius = (22 * scale).round().clamp(2, 80);
        for (int y = -radius; y <= radius; y++) {
          for (int x = -radius; x <= radius; x++) {
            if (x * x + y * y <= radius * radius) {
              final nx = ix + x;
              final ny = iy + y;
              if (nx >= 0 && ny >= 0 && nx < mask.width && ny < mask.height) {
                mask.setPixelRgba(nx, ny, 255, 255, 255, 255);
              }
            }
          }
        }
      }
      // 连线
      for (int i = 1; i < stroke.length; i++) {
        final a = stroke[i - 1].localOffset;
        final b = stroke[i].localOffset;
        _drawLine(mask, a, b, scale, offX, offY, scaledImgW, scaledImgH);
      }
    }
  }

  void _drawLine(
    img.Image mask,
    Offset a,
    Offset b,
    double scale,
    double offX,
    double offY,
    double scaledImgW,
    double scaledImgH,
  ) {
    final ax = a.dx - offX;
    final ay = a.dy - offY;
    final bx = b.dx - offX;
    final by = b.dy - offY;
    final steps = (sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay))).ceil();
    final radius = (22 * scale).round().clamp(2, 80);
    for (int s = 0; s <= steps; s++) {
      final t = steps == 0 ? 0.0 : s / steps;
      final x = ax + (bx - ax) * t;
      final y = ay + (by - ay) * t;
      if (x < 0 || y < 0 || x > scaledImgW || y > scaledImgH) continue;
      final ix = (x * scale).round();
      final iy = (y * scale).round();
      for (int yy = -radius; yy <= radius; yy++) {
        for (int xx = -radius; xx <= radius; xx++) {
          if (xx * xx + yy * yy <= radius * radius) {
            final nx = ix + xx;
            final ny = iy + yy;
            if (nx >= 0 && ny >= 0 && nx < mask.width && ny < mask.height) {
              mask.setPixelRgba(nx, ny, 255, 255, 255, 255);
            }
          }
        }
      }
    }
  }
}
