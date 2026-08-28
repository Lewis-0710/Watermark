import 'package:flutter/foundation.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'process_page.dart';
import 'douyin_webview_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late final TextEditingController _urlController;
  late final AnimationController _sunController;
  late final AnimationController _orbit1Controller;
  late final AnimationController _orbit2Controller;
  late final AnimationController _orbit3Controller;
  late final AnimationController _orbit4Controller;
  late final AnimationController _orbit5Controller;
  final List<String> _localFilePaths = [];
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _sunController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _orbit1Controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _orbit2Controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
    _orbit3Controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 22),
    )..repeat();
    _orbit4Controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 32),
    )..repeat();
    _orbit5Controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 45),
    )..repeat();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _sunController.dispose();
    _orbit1Controller.dispose();
    _orbit2Controller.dispose();
    _orbit3Controller.dispose();
    _orbit4Controller.dispose();
    _orbit5Controller.dispose();
    super.dispose();
  }

  Future<void> _pickLocalFiles() async {
    try {
      final List<PlatformFile> files = await FilePicker.pickFiles(
        type: FileType.media,
        allowMultiple: true,
      );
      if (files.isNotEmpty) {
        for (var f in files) {
          if (f.path != null) {
            _localFilePaths.add(f.path!);
          }
        }
        if (mounted) {
          setState(() {
            _urlController.text = _localFilePaths.join(' | ');
          });
        }
      }
    } catch (e) {
      debugPrint('pickLocalFiles error: $e');
    }
  }

  Future<void> _onStart() async {
    if (_isStarting) return;
    final url = _urlController.text.trim();
    if (url.isEmpty && _localFilePaths.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入链接或选择本地图片/视频')),
      );
      return;
    }
    // 任意链接：通过 WebView 通用抓取器提取媒体
    final urlMatch = RegExp(r'''https?://[^\s，。、,)"']+''').firstMatch(url);
    if (urlMatch != null) {
      final shareUrl = urlMatch.group(0)!;
      setState(() => _isStarting = true);
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DouyinWebViewPage(shareUrl: shareUrl),
        ),
      );
      if (mounted) setState(() => _isStarting = false);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProcessPage(
          inputUrl: url,
          localPaths: List<String>.from(_localFilePaths),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 星空背景
          Positioned.fill(child: _buildStarBackground()),
          // 太阳系动态
          Positioned.fill(child: _buildSolarSystem()),
          // 内容：输入框（手机端左右间距18，桌面端左右间距128）
          SafeArea(
            child: Center(
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: (!kIsWeb &&
                          (defaultTargetPlatform == TargetPlatform.windows ||
                              defaultTargetPlatform == TargetPlatform.macOS ||
                              defaultTargetPlatform == TargetPlatform.linux))
                      ? 128.0
                      : 18.0,
                ),
                child: _buildInputRow(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStarBackground() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          painter: _StarPainter(seed: 42),
          size: Size(constraints.maxWidth, constraints.maxHeight),
        );
      },
    );
  }

  Widget _buildSolarSystem() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        return SizedBox(
          width: size.width,
          height: size.height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 轨道圈
              _buildOrbit(90),
              _buildOrbit(150),
              _buildOrbit(210),
              _buildOrbit(280),
              _buildOrbit(360),
              // 太阳
              AnimatedBuilder(
                animation: _sunController,
                builder: (_, __) {
                  return Transform.rotate(
                    angle: _sunController.value * 2 * pi,
                    child: _buildSun(),
                  );
                },
              ),
              // 行星 1 (水星)
              _buildPlanet(
                controller: _orbit1Controller,
                radius: 90,
                color: Colors.grey[400]!,
                planetSize: 10,
              ),
              // 行星 2 (金星)
              _buildPlanet(
                controller: _orbit2Controller,
                radius: 150,
                color: Colors.orange[300]!,
                planetSize: 16,
              ),
              // 行星 3 (地球)
              _buildPlanet(
                controller: _orbit3Controller,
                radius: 210,
                color: Colors.lightBlueAccent,
                planetSize: 20,
                withMoon: true,
              ),
              // 行星 4 (火星)
              _buildPlanet(
                controller: _orbit4Controller,
                radius: 280,
                color: Colors.redAccent,
                planetSize: 18,
              ),
              // 行星 5 (木星)
              _buildPlanet(
                controller: _orbit5Controller,
                radius: 360,
                color: Colors.amber[300]!,
                planetSize: 34,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOrbit(double radius) {
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withOpacity(0.12),
          width: 1,
        ),
      ),
    );
  }

  Widget _buildSun() {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.yellow[700],
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.8),
            blurRadius: 40,
            spreadRadius: 15,
          ),
          BoxShadow(
            color: Colors.yellow.withOpacity(0.6),
            blurRadius: 80,
            spreadRadius: 30,
          ),
        ],
        gradient: const RadialGradient(
          colors: [Colors.yellow, Colors.orangeAccent, Colors.deepOrange],
          stops: [0.2, 0.6, 1.0],
        ),
      ),
    );
  }

  Widget _buildPlanet({
    required AnimationController controller,
    required double radius,
    required Color color,
    required double planetSize,
    bool withMoon = false,
  }) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final angle = controller.value * 2 * pi;
        final dx = cos(angle) * radius;
        final dy = sin(angle) * radius;
        return Transform.translate(
          offset: Offset(dx, dy),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Container(
                width: planetSize,
                height: planetSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withOpacity(0.5),
                      blurRadius: planetSize,
                      spreadRadius: 2,
                    ),
                  ],
                  gradient: RadialGradient(
                    colors: [
                      color.withOpacity(1),
                      color.withOpacity(0.5),
                    ],
                  ),
                ),
              ),
              if (withMoon)
                Positioned(
                  right: -planetSize - 4,
                  child: Container(
                    width: planetSize * 0.3,
                    height: planetSize * 0.3,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white60,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        return Center(
          child: Container(
            width: totalWidth,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 20,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 左侧添加按钮（宽32高50，靠左对齐，背景透明，圆角与输入框一致）
                  InkWell(
                    onTap: _pickLocalFiles,
                    borderRadius: const BorderRadius.horizontal(
                        left: Radius.circular(16)),
                    child: Container(
                      width: 32,
                      height: 50,
                      alignment: Alignment.center,
                      color: Colors.transparent,
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  // 中间输入框
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15),
                      textInputAction: TextInputAction.go,
                      keyboardType: TextInputType.url,
                      decoration: InputDecoration(
                        hintText: '粘贴抖音/B站/YouTube链接...',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 14,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 14),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      onSubmitted: (_) => _isStarting ? null : _onStart(),
                    ),
                  ),
                  // 右侧开始箭头（宽32高50，靠右对齐，背景透明，圆角与输入框一致）
                  InkWell(
                    onTap: _isStarting ? null : _onStart,
                    borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(16)),
                    child: Container(
                      width: 32,
                      height: 50,
                      alignment: Alignment.center,
                      color: Colors.transparent,
                      child: _isStarting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StarPainter extends CustomPainter {
  final int seed;
  _StarPainter({this.seed = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(seed);
    // 背景渐变
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF0a0420),
          Color(0xFF050118),
          Color(0xFF000008),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

    // 星云
    final nebulaPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.purple.withOpacity(0.25),
          Colors.blue.withOpacity(0.1),
          Colors.transparent,
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(
          center: Offset(size.width * 0.2, size.height * 0.3),
          radius: size.width * 0.6));
    canvas.drawRect(Offset.zero & size, nebulaPaint);

    // 星星
    final starCount = (size.width * size.height / 3500).round();
    for (int i = 0; i < starCount; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final r = random.nextDouble() * 1.4 + 0.3;
      final a = random.nextDouble() * 0.6 + 0.3;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = Colors.white.withOpacity(a),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
