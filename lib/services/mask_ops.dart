import 'dart:math' as math;
import 'dart:typed_data';

/// Pure-Dart mask helpers (no Flutter imports) so they can run inside a
/// background isolate.
class MaskOps {
  static int clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

  /// Separable box blur on a single-channel float buffer (edge-clamped).
  static Float32List boxBlur(Float32List src, int w, int h, int radius) {
    if (radius <= 0) return src;
    final tmp = Float32List(w * h);
    final out = Float32List(w * h);
    final win = (radius * 2 + 1).toDouble();

    for (int y = 0; y < h; y++) {
      final row = y * w;
      double sum = 0;
      for (int k = -radius; k <= radius; k++) {
        sum += src[row + clampInt(k, 0, w - 1)];
      }
      for (int x = 0; x < w; x++) {
        tmp[row + x] = sum / win;
        final addX = math.min(x + radius + 1, w - 1);
        final subX = math.max(x - radius, 0);
        sum += src[row + addX] - src[row + subX];
      }
    }

    for (int x = 0; x < w; x++) {
      double sum = 0;
      for (int k = -radius; k <= radius; k++) {
        sum += tmp[clampInt(k, 0, h - 1) * w + x];
      }
      for (int y = 0; y < h; y++) {
        out[y * w + x] = sum / win;
        final addY = math.min(y + radius + 1, h - 1);
        final subY = math.max(y - radius, 0);
        sum += tmp[addY * w + x] - tmp[subY * w + x];
      }
    }
    return out;
  }

  /// Grows a 0/1 mask outward by [radius] pixels (separable max filter).
  static Float32List dilate(Float32List src, int w, int h, int radius) {
    if (radius <= 0) return src;
    final tmp = Float32List(w * h);
    final out = Float32List(w * h);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double m = 0;
        final from = math.max(0, x - radius);
        final to = math.min(w - 1, x + radius);
        for (int k = from; k <= to; k++) {
          if (src[y * w + k] > m) m = src[y * w + k];
        }
        tmp[y * w + x] = m;
      }
    }
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        double m = 0;
        final from = math.max(0, y - radius);
        final to = math.min(h - 1, y + radius);
        for (int k = from; k <= to; k++) {
          if (tmp[k * w + x] > m) m = tmp[k * w + x];
        }
        out[y * w + x] = m;
      }
    }
    return out;
  }
}
