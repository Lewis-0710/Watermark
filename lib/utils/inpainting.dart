import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// 高精度无痕去水印与各向异性边缘保持修复
///
/// 核心原理：
/// 1. 局部定位：以涂鸦作为提示框提取局部裁剪区，涂鸦外原图 100% 保持不动
/// 2. 真 2D 形态学顶帽变换（True Morphological Top-Hat）：
///    - 通过标准开运算（Opening = 先 7x7 腐蚀再 7x7 膨胀），天然消除阶跃边缘（如电梯与腿的边界、腿间阴影缝隙）
///    - 仅对孤立文字笔画与 Logo 产生响应，彻底避免误伤正常身体和电梯轮廓
/// 3. 形态学闭运算闭合字腔（Hole-Filling Closing）：
///    - 自动封闭文字内部闭合环腔（如'0'、'8'、'音'内部空隙），彻底消除文字残影与空心光圈
/// 4. 阴影完全包络（9x9 膨胀）：
///    - 彻底包络字迹下方扩散 3~4 像素的微弱投影与抗锯齿半透明边缘，避免边缘微弱阴影污染修补基色
/// 5. 垂直边界先验插值：利用列方向已知纯净背景像素提供高保真初值，保持竖向纹理连续
/// 6. 各向异性导度扩散（Perona-Malik Anisotropic PDE）：在电梯与皮肤等异质边缘自动切断横向渗色，
///    确保轮廓清晰锐利，实现真正的无痕去除
typedef ProgressCallback = void Function(double progress);

Future<img.Image> runInpainting(
  img.Image source,
  img.Image mask, {
  ProgressCallback? progressCallback,
}) async {
  final w = source.width;
  final h = source.height;

  int minX = w, maxX = 0, minY = h, maxY = 0;
  int scribbleCount = 0;

  for (int y = 0; y < h; y++) {
    for (int x = 0; x < w; x++) {
      final p = mask.getPixel(x, y);
      if (p.a > 128 && (p.r + p.g + p.b) > 384) {
        scribbleCount++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }

  if (scribbleCount == 0) return img.Image.from(source);

  // 扩展局部包围盒
  const margin = 20;
  final cropX0 = max(0, minX - margin);
  final cropY0 = max(0, minY - margin);
  final cropX1 = min(w - 1, maxX + margin);
  final cropY1 = min(h - 1, maxY + margin);
  final cropW = cropX1 - cropX0 + 1;
  final cropH = cropY1 - cropY0 + 1;

  final cropScribble = Uint8List(cropW * cropH);
  final lum = Float32List(cropW * cropH);
  final red = Float32List(cropW * cropH);
  final green = Float32List(cropW * cropH);
  final blue = Float32List(cropW * cropH);

  for (int cy = 0; cy < cropH; cy++) {
    final y = cropY0 + cy;
    final rowOffset = cy * cropW;
    for (int cx = 0; cx < cropW; cx++) {
      final x = cropX0 + cx;
      final cIdx = rowOffset + cx;
      final mp = mask.getPixel(x, y);
      if (mp.a > 128 && (mp.r + mp.g + mp.b) > 384) {
        cropScribble[cIdx] = 1;
      }
      final sp = source.getPixel(x, y);
      red[cIdx] = sp.r.toDouble();
      green[cIdx] = sp.g.toDouble();
      blue[cIdx] = sp.b.toDouble();
      lum[cIdx] = (red[cIdx] + green[cIdx] + blue[cIdx]) * (1.0 / 3.0);
    }
  }

  progressCallback?.call(0.1);

  // 1. 真 2D 形态学开运算（可分离极值滤波：先腐蚀 Min 7x7，再膨胀 Max 7x7）
  const r = 3;
  // 水平极小
  final tempMin = Float32List(cropW * cropH);
  for (int cy = 0; cy < cropH; cy++) {
    final rowOffset = cy * cropW;
    for (int cx = 0; cx < cropW; cx++) {
      final x0 = max(0, cx - r);
      final x1 = min(cropW - 1, cx + r);
      double m = lum[rowOffset + cx];
      for (int x = x0; x <= x1; x++) {
        final v = lum[rowOffset + x];
        if (v < m) m = v;
      }
      tempMin[rowOffset + cx] = m;
    }
  }
  // 垂直极小 -> 得到腐蚀图
  final eroded = Float32List(cropW * cropH);
  for (int cx = 0; cx < cropW; cx++) {
    for (int cy = 0; cy < cropH; cy++) {
      final y0 = max(0, cy - r);
      final y1 = min(cropH - 1, cy + r);
      double m = tempMin[cy * cropW + cx];
      for (int y = y0; y <= y1; y++) {
        final v = tempMin[y * cropW + cx];
        if (v < m) m = v;
      }
      eroded[cy * cropW + cx] = m;
    }
  }

  // 水平极大
  final tempMax = Float32List(cropW * cropH);
  for (int cy = 0; cy < cropH; cy++) {
    final rowOffset = cy * cropW;
    for (int cx = 0; cx < cropW; cx++) {
      final x0 = max(0, cx - r);
      final x1 = min(cropW - 1, cx + r);
      double m = eroded[rowOffset + cx];
      for (int x = x0; x <= x1; x++) {
        final v = eroded[rowOffset + x];
        if (v > m) m = v;
      }
      tempMax[rowOffset + cx] = m;
    }
  }
  // 垂直极大 -> 得到开运算图
  final opened = Float32List(cropW * cropH);
  for (int cx = 0; cx < cropW; cx++) {
    for (int cy = 0; cy < cropH; cy++) {
      final y0 = max(0, cy - r);
      final y1 = min(cropH - 1, cy + r);
      double m = tempMax[cy * cropW + cx];
      for (int y = y0; y <= y1; y++) {
        final v = tempMax[y * cropW + cx];
        if (v > m) m = v;
      }
      opened[cy * cropW + cx] = m;
    }
  }

  progressCallback?.call(0.2);

  // 2. 顶帽提取真实字迹（Top-Hat = Lum - Opened）
  final rawMask = Uint8List(cropW * cropH);
  int rawCount = 0;
  for (int i = 0; i < cropW * cropH; i++) {
    if (cropScribble[i] == 0) continue;
    final topHat = lum[i] - opened[i];
    final rVal = red[i];
    final gVal = green[i];
    final bVal = blue[i];

    final isText = (topHat > 4.0);
    final isCyan = (gVal > 110 && bVal > 110 && bVal > rVal + 10 && topHat > 2.0);
    final isRed = (rVal > 160 && rVal > gVal + 30 && topHat > 2.0);

    if (isText || isCyan || isRed) {
      rawMask[i] = 1;
      rawCount++;
    }
  }

  final targetMask = Uint8List(cropW * cropH);
  final targetIndices = <int>[];

  // 3. 形态学闭合字腔（Closing）与阴影完全包络（9x9 膨胀）
  if (rawCount >= 20) {
    // 闭运算：先 5x5 膨胀
    final closedTemp = Uint8List(cropW * cropH);
    for (int cy = 0; cy < cropH; cy++) {
      for (int cx = 0; cx < cropW; cx++) {
        if (rawMask[cy * cropW + cx] == 0) continue;
        for (int dy = -2; dy <= 2; dy++) {
          final ny = cy + dy;
          if (ny < 0 || ny >= cropH) continue;
          for (int dx = -2; dx <= 2; dx++) {
            final nx = cx + dx;
            if (nx < 0 || nx >= cropW) continue;
            closedTemp[ny * cropW + nx] = 1;
          }
        }
      }
    }
    // 再 3x3 腐蚀 -> 封闭字腔内部小孔
    final closed = Uint8List(cropW * cropH);
    for (int cy = 0; cy < cropH; cy++) {
      for (int cx = 0; cx < cropW; cx++) {
        bool allSet = true;
        for (int dy = -1; dy <= 1 && allSet; dy++) {
          final ny = cy + dy;
          if (ny < 0 || ny >= cropH) {
            allSet = false;
            break;
          }
          for (int dx = -1; dx <= 1 && allSet; dx++) {
            final nx = cx + dx;
            if (nx < 0 || nx >= cropW || closedTemp[ny * cropW + nx] == 0) {
              allSet = false;
            }
          }
        }
        if (allSet) {
          closed[cy * cropW + cx] = 1;
        }
      }
    }
    // 9x9 膨胀（半径 4）：完整包络文字下方 3~4px 的半透明阴影与抗锯齿
    for (int cy = 0; cy < cropH; cy++) {
      for (int cx = 0; cx < cropW; cx++) {
        if (closed[cy * cropW + cx] == 0) continue;
        for (int dy = -4; dy <= 4; dy++) {
          final ny = cy + dy;
          if (ny < 0 || ny >= cropH) continue;
          for (int dx = -4; dx <= 4; dx++) {
            final nx = cx + dx;
            if (nx < 0 || nx >= cropW) continue;
            final nIdx = ny * cropW + nx;
            if (cropScribble[nIdx] == 1 && targetMask[nIdx] == 0) {
              targetMask[nIdx] = 1;
              targetIndices.add(nIdx);
            }
          }
        }
      }
    }
  } else {
    for (int i = 0; i < cropW * cropH; i++) {
      if (cropScribble[i] == 1) {
        targetMask[i] = 1;
        targetIndices.add(i);
      }
    }
  }

  final count = targetIndices.length;
  if (count == 0) return img.Image.from(source);

  final outR = Float32List.fromList(red);
  final outG = Float32List.fromList(green);
  final outB = Float32List.fromList(blue);

  // 4. 初值赋予：垂直方向已知纯净背景边界先验插值
  for (int cx = 0; cx < cropW; cx++) {
    final knownYs = <int>[];
    for (int cy = 0; cy < cropH; cy++) {
      if (targetMask[cy * cropW + cx] == 0) {
        knownYs.add(cy);
      }
    }
    if (knownYs.isEmpty) continue;

    for (int cy = 0; cy < cropH; cy++) {
      final idx = cy * cropW + cx;
      if (targetMask[idx] == 0) continue;

      int ya = -1, yb = -1;
      for (final ky in knownYs) {
        if (ky < cy) {
          ya = ky;
        } else if (ky > cy) {
          yb = ky;
          break;
        }
      }

      if (ya >= 0 && yb >= 0) {
        final t = (cy - ya) / (yb - ya);
        final idxA = ya * cropW + cx;
        final idxB = yb * cropW + cx;
        outR[idx] = (1.0 - t) * red[idxA] + t * red[idxB];
        outG[idx] = (1.0 - t) * green[idxA] + t * green[idxB];
        outB[idx] = (1.0 - t) * blue[idxA] + t * blue[idxB];
      } else if (ya >= 0) {
        final idxA = ya * cropW + cx;
        outR[idx] = red[idxA];
        outG[idx] = green[idxA];
        outB[idx] = blue[idxA];
      } else if (yb >= 0) {
        final idxB = yb * cropW + cx;
        outR[idx] = red[idxB];
        outG[idx] = green[idxB];
        outB[idx] = blue[idxB];
      }
    }
  }

  // 预计算四邻域索引
  final neighborUp = Int32List(count);
  final neighborDown = Int32List(count);
  final neighborLeft = Int32List(count);
  final neighborRight = Int32List(count);

  for (int k = 0; k < count; k++) {
    final idx = targetIndices[k];
    final cy = idx ~/ cropW;
    final cx = idx % cropW;
    final yUp = max(0, cy - 1);
    final yDown = min(cropH - 1, cy + 1);
    final xLeft = max(0, cx - 1);
    final xRight = min(cropW - 1, cx + 1);

    neighborUp[k] = yUp * cropW + cx;
    neighborDown[k] = yDown * cropW + cx;
    neighborLeft[k] = cy * cropW + xLeft;
    neighborRight[k] = cy * cropW + xRight;
  }

  // 5. 各向异性边缘保持扩散迭代（Perona-Malik Anisotropic PDE）
  const iterations = 400;
  const kappa2 = 20.0 * 20.0;

  for (int iter = 0; iter < iterations; iter++) {
    for (int k = 0; k < count; k++) {
      final idx = targetIndices[k];
      final u = neighborUp[k];
      final d = neighborDown[k];
      final l = neighborLeft[k];
      final r = neighborRight[k];

      // R
      final duR = outR[idx] - outR[u];
      final ddR = outR[idx] - outR[d];
      final dlR = outR[idx] - outR[l];
      final drR = outR[idx] - outR[r];
      final wuR = 1.8 / (1.0 + (duR * duR) / kappa2);
      final wdR = 1.8 / (1.0 + (ddR * ddR) / kappa2);
      final wlR = 1.0 / (1.0 + (dlR * dlR) / kappa2);
      final wrR = 1.0 / (1.0 + (drR * drR) / kappa2);
      outR[idx] = (wuR * outR[u] + wdR * outR[d] + wlR * outR[l] + wrR * outR[r]) /
          (wuR + wdR + wlR + wrR);

      // G
      final duG = outG[idx] - outG[u];
      final ddG = outG[idx] - outG[d];
      final dlG = outG[idx] - outG[l];
      final drG = outG[idx] - outG[r];
      final wuG = 1.8 / (1.0 + (duG * duG) / kappa2);
      final wdG = 1.8 / (1.0 + (ddG * ddG) / kappa2);
      final wlG = 1.0 / (1.0 + (dlG * dlG) / kappa2);
      final wrG = 1.0 / (1.0 + (drG * drG) / kappa2);
      outG[idx] = (wuG * outG[u] + wdG * outG[d] + wlG * outG[l] + wrG * outG[r]) /
          (wuG + wdG + wlG + wrG);

      // B
      final duB = outB[idx] - outB[u];
      final ddB = outB[idx] - outB[d];
      final dlB = outB[idx] - outB[l];
      final drB = outB[idx] - outB[r];
      final wuB = 1.8 / (1.0 + (duB * duB) / kappa2);
      final wdB = 1.8 / (1.0 + (ddB * ddB) / kappa2);
      final wlB = 1.0 / (1.0 + (dlB * dlB) / kappa2);
      final wrB = 1.0 / (1.0 + (drB * drB) / kappa2);
      outB[idx] = (wuB * outB[u] + wdB * outB[d] + wlB * outB[l] + wrB * outB[r]) /
          (wuB + wdB + wlB + wrB);
    }

    if (iter % 40 == 0) {
      progressCallback?.call(0.2 + 0.75 * (iter / iterations));
      await Future.microtask(() {});
    }
  }

  // 6. 写回图像（仅修改水印像素，其余完全保持原图）
  final out = img.Image.from(source);
  for (int k = 0; k < count; k++) {
    final idx = targetIndices[k];
    final cy = idx ~/ cropW;
    final cx = idx % cropW;
    final x = cropX0 + cx;
    final y = cropY0 + cy;
    out.setPixelRgba(
      x,
      y,
      outR[idx].round().clamp(0, 255),
      outG[idx].round().clamp(0, 255),
      outB[idx].round().clamp(0, 255),
      255,
    );
  }

  progressCallback?.call(1.0);
  return out;
}
