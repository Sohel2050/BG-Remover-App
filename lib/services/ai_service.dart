import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'color_space_utils.dart';
import 'package:path_provider/path_provider.dart';

/// Runs u2net.onnx on-device to produce a background-removed (transparent PNG)
/// version of an input image. Model input/output: 320x320 RGB, single-channel
/// saliency mask output (standard U2Net export).
///
/// Uses the `flutter_onnxruntime` package (NOT the older/unmaintained
/// `onnxruntime` package — that one is stuck on an old Android compileSdk
/// and will fail to build against modern androidx dependencies).
class AiService {
  static const String _modelAssetPath = 'assets/models/u2net.onnx';
  static const int _inputSize = 320;

  final OnnxRuntime _ort = OnnxRuntime();
  OrtSession? _session;
  bool get isLoaded => _session != null;

  /// Loads the ONNX model from assets into memory. Call once (e.g. at app
  /// start or lazily before first use).
  Future<void> loadModel() async {
    if (_session != null) return; // already loaded
    _session = await _ort.createSessionFromAsset(_modelAssetPath);
  }

  /// Runs background removal on [inputImage] and returns a new PNG file
  /// with the background made transparent.
  Future<File> removeBackground(File inputImage) async {
    if (_session == null) {
      await loadModel();
    }
    final session = _session!;

    // 1. Decode input image
    final inputBytes = await inputImage.readAsBytes();
    var decoded = img.decodeImage(inputBytes);
    if (decoded == null) {
      throw Exception('Could not decode input image');
    }
    // Fix wide-gamut (e.g. iPhone Display P3) photos looking oversaturated
    // once re-encoded — see color_space_utils.dart for why this matters.
    decoded = ColorSpaceUtils.normalizeToSrgb(decoded);

    final originalWidth = decoded.width;
    final originalHeight = decoded.height;

    // 2. Resize to model input size (320x320) and normalize to [0,1]
    final resized = img.copyResize(
      decoded,
      width: _inputSize,
      height: _inputSize,
      interpolation: img.Interpolation.linear,
    );

    final inputTensorData = _imageToCHWFloat32(resized);

    final inputName = session.inputNames.first;
    final outputName = session.outputNames.first;

    final inputValue = await OrtValue.fromList(
      inputTensorData.toList(),
      [1, 3, _inputSize, _inputSize],
    );

    // 3. Run inference
    final outputs = await session.run({inputName: inputValue});
    await inputValue.dispose();

    final outputValue = outputs[outputName];
    if (outputValue == null) {
      throw Exception('Model produced no output');
    }

    // 4. Extract mask (shape typically [1,1,320,320])
    final rawOutput = await outputValue.asList();
    final maskFlat = _flattenToFloat32(rawOutput);

    for (final v in outputs.values) {
      await v.dispose();
    }

    // 5. Build alpha mask, resize back to original dimensions
    final maskImage = _maskToImage(maskFlat, _inputSize, _inputSize);
    final maskResized = img.copyResize(
      maskImage,
      width: originalWidth,
      height: originalHeight,
      interpolation: img.Interpolation.linear,
    );

    // 6. Apply mask as alpha channel onto the original full-res image
    final result = img.Image(
      width: originalWidth,
      height: originalHeight,
      numChannels: 4,
    );

    for (int y = 0; y < originalHeight; y++) {
      for (int x = 0; x < originalWidth; x++) {
        final srcPixel = decoded.getPixel(x, y);
        final alpha = maskResized.getPixel(x, y).r; // 0-255 grayscale used as alpha
        result.setPixelRgba(
          x,
          y,
          srcPixel.r.toInt(),
          srcPixel.g.toInt(),
          srcPixel.b.toInt(),
          alpha.toInt(),
        );
      }
    }

    // 7. Save as PNG to a temp file
    final pngBytes = img.encodePng(result);
    final tempDir = await getTemporaryDirectory();
    final outFile = File(
      '${tempDir.path}/bg_removed_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await outFile.writeAsBytes(pngBytes);

    return outFile;
  }

  /// Converts an [img.Image] to a CHW (channel-first) Float32 list normalized
  /// to [0,1], matching the standard U2Net preprocessing.
  Float32List _imageToCHWFloat32(img.Image image) {
    final w = image.width;
    final h = image.height;
    final data = Float32List(3 * w * h);

    int rIndex = 0;
    int gIndex = w * h;
    int bIndex = 2 * w * h;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final pixel = image.getPixel(x, y);
        data[rIndex++] = pixel.r / 255.0;
        data[gIndex++] = pixel.g / 255.0;
        data[bIndex++] = pixel.b / 255.0;
      }
    }
    return data;
  }

  /// Flattens whatever nested/flat list structure asList() returns into a
  /// single Float32List (defensive — shape of the returned data can vary
  /// slightly by platform backend).
  Float32List _flattenToFloat32(dynamic value) {
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

  /// Converts a flat [0,1] saliency mask into a grayscale img.Image where
  /// pixel value = alpha (0-255). Also applies min-max normalization since
  /// raw U2Net output isn't always perfectly bounded to [0,1].
  img.Image _maskToImage(Float32List mask, int width, int height) {
    double minV = mask.first;
    double maxV = mask.first;
    for (final v in mask) {
      minV = math.min(minV, v);
      maxV = math.max(maxV, v);
    }
    final range = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);

    final maskImage = img.Image(width: width, height: height, numChannels: 1);
    int i = 0;
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final normalized = ((mask[i] - minV) / range).clamp(0.0, 1.0);
        final gray = (normalized * 255).round();
        maskImage.setPixelRgba(x, y, gray, gray, gray, 255);
        i++;
      }
    }
    return maskImage;
  }

  void dispose() {
    _session?.close();
    _session = null;
  }
}
