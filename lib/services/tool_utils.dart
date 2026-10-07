import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

/// Thrown when an optional AI model file hasn't been added to assets/models/.
class ModelMissingException implements Exception {
  final String assetPath;
  final String hint;
  ModelMissingException(this.assetPath, this.hint);

  @override
  String toString() =>
      'Model file "$assetPath" was not found in the app. $hint';
}

/// Shared helpers for the ONNX-based tools (object removal, upscaling,
/// subject detection, face retouch).
class ToolUtils {
  static int clampInt(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

  /// Loads an ONNX session from assets, first checking the asset actually
  /// exists so a missing model gives a clear message instead of a cryptic
  /// platform error. (Checks the manifest — doesn't load the file itself,
  /// which matters for the ~200MB LaMa model.)
  static Future<OrtSession> loadSession(
    OnnxRuntime ort,
    String assetPath, {
    required String hint,
  }) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    if (!manifest.listAssets().contains(assetPath)) {
      throw ModelMissingException(assetPath, hint);
    }
    return ort.createSessionFromAsset(assetPath);
  }

  /// Flattens whatever nested/flat list structure a tensor's asList()
  /// returns into one Float32List.
  static Float32List flatten(dynamic value) {
    final List<double> flat = [];
    void recurse(dynamic v) {
      if (v is List) {
        for (final item in v) {
          recurse(item);
        }
      } else if (v is num) {
        flat.add(v.toDouble());
      }
    }

    recurse(value);
    return Float32List.fromList(flat);
  }

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
