import 'dart:math';
import 'package:image/image.dart' as img;

/// 简单图像修复（inpainting）：基于邻域像素均值 + 多次扩散迭代
///
/// 思路：
/// 1. 根据 mask 得到目标修复区域
/// 2. 用周围已知像素均值做初始化填充
/// 3. 使用多次邻域均值扩散（各向异性，取周围未修复像素多的方向优先）逐步平滑
///
/// 这是一种轻量级算法，能较好地去除纯色背景水印和边缘型文字水印；
/// 对于复杂纹理的高质量去除通常需要深度学习模型，此处用 Dart 纯 CPU 方案。
typedef ProgressCallback = void Function(double progress);

Future<img.Image> runInpainting(
  img.Image source,
  img.Image mask, {
  ProgressCallback? progressCallback,
}) async {
  final out = img.copyResize(source, width: source.width, height: source.height);
  final w = out.width;
  final h = out.height;
  // 构造 mask 标记：255 = 需要修复
  final target = List<bool>.filled(w * h, false);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final p = mask.getPixel(x, y);
      final alpha = img.getAlpha(p);
      final lum = (img.getRed(p) + img.getGreen(p) + img.getBlue(p)) ~/ 3;
      if (lum > 128 && alpha > 0) {
        target[y * w + x] = true;
      }
    }
  }

  int targetCount = 0;
  for (int i = 0; i < target.length; i++) {
    if (target[i]) targetCount++;
  }
  if (targetCount == 0) return out;

  // Step 1: 初始化：每个要修复的像素取其最近的 3x3 ~ 9x9 邻域里的非目标像素均值
  progressCallback?.call(0.05);
  await Future.microtask(() {});

  // 先找每个点的邻域有效值（多尺度，逐步扩散）
  final rInit = 5;
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      if (!target[y * w + x]) continue;
      int rSum = 0, gSum = 0, bSum = 0, cnt = 0;
      for (int r = 1; r <= rInit && cnt < 8; r++) {
        for (int dy = -r; dy <= r; dy++) {
          for (int dx = -r; dx <= r; dx++) {
            final nx = x + dx;
            final ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            if (target[ny * w + nx]) continue;
            final p = out.getPixel(nx, ny);
            rSum += img.getRed(p);
            gSum += img.getGreen(p);
            bSum += img.getBlue(p);
            cnt++;
          }
        }
      }
      if (cnt > 0) {
        out.setPixelRgba(
          x,
          y,
          rSum ~/ cnt,
          gSum ~/ cnt,
          bSum ~/ cnt,
          255,
        );
      }
    }
  }

  // Step 2: 多次迭代 —— 交替 4 邻域平均 + 加权双边扩散
  progressCallback?.call(0.25);
  await Future.microtask(() {});

  final iterations = 12;
  final random = Random(7);
  for (int it = 0; it < iterations; it++) {
    // 每迭代更新一次，分两阶段：先计算新值，再写入
    final bufR = List<int>.filled(w * h, 0);
    final bufG = List<int>.filled(w * h, 0);
    final bufB = List<int>.filled(w * h, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final idx = y * w + x;
        if (!target[idx]) {
          final p = out.getPixel(x, y);
          bufR[idx] = img.getRed(p);
          bufG[idx] = img.getGreen(p);
          bufB[idx] = img.getBlue(p);
          continue;
        }
        // 只对 target 区域做平均，考虑周边距离加权
        int rSum = 0, gSum = 0, bSum = 0;
        double wSum = 0;
        // 7x7 高斯核近似
        const k = 3;
        for (int dy = -k; dy <= k; dy++) {
          for (int dx = -k; dx <= k; dx++) {
            final nx = x + dx;
            final ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            final d = sqrt(dx * dx + dy * dy);
            final wgt = exp(-d * d / 8.0);
            final p = out.getPixel(nx, ny);
            rSum += (img.getRed(p) * wgt).round();
            gSum += (img.getGreen(p) * wgt).round();
            bSum += (img.getBlue(p) * wgt).round();
            wSum += wgt;
          }
        }
        if (wSum > 0) {
          bufR[idx] = (rSum / wSum).round().clamp(0, 255);
          bufG[idx] = (gSum / wSum).round().clamp(0, 255);
          bufB[idx] = (bSum / wSum).round().clamp(0, 255);
        } else {
          final p = out.getPixel(x, y);
          bufR[idx] = img.getRed(p);
          bufG[idx] = img.getGreen(p);
          bufB[idx] = img.getBlue(p);
        }
      }
    }
    // 写回
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final idx = y * w + x;
        out.setPixelRgba(x, y, bufR[idx], bufG[idx], bufB[idx], 255);
      }
    }
    progressCallback?.call(0.25 + 0.7 * ((it + 1) / iterations));
    // 让 UI 有机会刷新
    if (it % 3 == 2) await Future.delayed(Duration.zero);
  }

  // Step 3: 边界混合，防止修复区域和非修复区域间出现色差 —— 对目标区域的边缘做轻度羽化
  progressCallback?.call(0.95);
  await Future.microtask(() {});

  const feather = 2;
  // 备份
  final temp = img.copyResize(out, width: w, height: h);
  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      if (target[y * w + x]) continue;
      // 检查是否靠近目标
      bool near = false;
      int dMin = feather + 1;
      for (int dy = -feather; dy <= feather && !near; dy++) {
        for (int dx = -feather; dx <= feather && !near; dx++) {
          final nx = x + dx;
          final ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          if (target[ny * w + nx]) {
            final d = sqrt(dx * dx + dy * dy).toInt();
            if (d < dMin) dMin = d;
            near = true;
          }
        }
      }
      if (near) {
        // 以 dMin 距离的反比做加权混合：越靠近目标越用修复值（平滑边界）
        final alpha = 1.0 - dMin / (feather + 1);
        final pO = out.getPixel(x, y);
        final pT = temp.getPixel(x, y);
        int r = (img.getRed(pT) * (1 - alpha) + img.getRed(pO) * alpha).round();
        int g =
            (img.getGreen(pT) * (1 - alpha) + img.getGreen(pO) * alpha).round();
        int b =
            (img.getBlue(pT) * (1 - alpha) + img.getBlue(pO) * alpha).round();
        out.setPixelRgba(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255), 255);
      }
    }
  }

  progressCallback?.call(1.0);
  return out;
}
