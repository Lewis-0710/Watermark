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
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.media,
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty) {
        for (var f in result.files) {
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
    // 抖音链接：自动识别视频或图集
    final lower = url.toLowerCase();
    if (lower.contains('douyin.com') || lower.contains('iesdouyin.com')) {
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
          // 内容：输入框 + 开始按钮
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '水印清除大师',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 2,
                        shadows: [
                          Shadow(
                            color: Colors.blueAccent,
                            blurRadius: 20,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '支持抖音 / Bilibili / YouTube 链接，或选择本地图片和视频',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 40),
                    _buildInputRow(),
                  ],
                ),
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
                withRing: true,
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
    bool withRing = false,
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
              if (withRing)
                Container(
                  width: planetSize * 2.2,
                  height: planetSize * 0.6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(
                      color: color.withOpacity(0.6),
                      width: 2,
                    ),
                  ),
                ),
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
        final inputWidth = constraints.maxWidth * 0.7;
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: inputWidth,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(18),
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
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      style: const TextStyle(color: Colors.white, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: '粘贴抖音/B站/YouTube链接...',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 14,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 22),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  // ➕ 按钮，右边上下居中
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: InkWell(
                      onTap: _pickLocalFiles,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blueAccent.withOpacity(0.4),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // 开始按钮
            SizedBox(
              height: 64,
              child: ElevatedButton(
                onPressed: _isStarting ? null : _onStart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C5CE7),
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 8,
                  shadowColor: Colors.purpleAccent.withOpacity(0.5),
                ),
                child: Row(
                  children: [
                    if (_isStarting)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else
                      const Icon(Icons.play_arrow, size: 22),
                    SizedBox(width: 6),
                    Text(
                      '开始',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
