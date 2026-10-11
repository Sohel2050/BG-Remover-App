import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import 'mask_ops.dart';

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
  static Float32List boxBlur(Float32List src, int w, int h, int radius) =>
      MaskOps.boxBlur(src, w, h, radius);

  /// Grows a 0/1 mask outward by [radius] pixels (separable max filter).
  static Float32List dilate(Float32List src, int w, int h, int radius) =>
      MaskOps.dilate(src, w, h, radius);
}
