import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'color_space_utils.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'model_store.dart';
import 'package:path_provider/path_provider.dart';

/// Runs a dedicated sky-segmentation ONNX model to produce a binary/soft
/// mask of "which pixels are sky". Mirrors the same load/preprocess/
/// infer/postprocess shape as AiService (lib/services/ai_service.dart),
/// but points at a different model file trained specifically for sky vs.
/// non-sky, since U2Net has no sky-specific concept.
///
/// NOTE: unlike u2net.onnx, a sky-segmentation model file is NOT provided
/// or downloaded automatically — see assets/models/SKY_MODEL_SETUP.md for
/// where to get one and how to place it. Until that file exists, this
/// service will throw when loadModel()/replaceSky() is called — that's
/// intentional so the app fails loudly instead of silently no-op'ing.
class SkySegmentationService {
  static const String _modelAssetPath = 'assets/models/sky_seg.onnx';
  static const int _inputSize = 256; // matches common sky-seg export sizes

  final OnnxRuntime _ort = OnnxRuntime();
  OrtSession? _session;
  bool get isLoaded => _session != null;

  Future<void> loadModel() async {
    if (_session != null) return;
    _session = await ModelStore.load(_ort, ModelStore.sky);
  }

  /// Returns a new image where sky pixels have been replaced by
  /// [skyReplacementImage] (fit with cover, matching original dimensions),
  /// blended at the sky mask's edges for a soft transition.
  Future<File> replaceSky(File inputImage, File skyReplacementImage) async {
    if (_session == null) {
      await loadModel();
    }
    final session = _session!;

    final inputBytes = await inputImage.readAsBytes();
    var decoded = img.decodeImage(inputBytes);
    if (decoded == null) throw Exception('Could not decode input image');
    decoded = ColorSpaceUtils.normalizeToSrgb(decoded);

    final originalWidth = decoded.width;
    final originalHeight = decoded.height;

    // 1. Preprocess: resize to model input size, normalize to [0,1] CHW.
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

    // 2. Inference.
    final outputs = await session.run({inputName: inputValue});
    await inputValue.dispose();

    final outputValue = outputs[outputName];
    if (outputValue == null) {
      throw Exception('Sky model produced no output');
    }

    // 3. Sky mask (1 = sky, 0 = not sky), resized back to full resolution.
    final rawOutput = await outputValue.asList();
    final maskFlat = _flattenToFloat32(rawOutput);
    final maskImage = _maskToImage(maskFlat, _inputSize, _inputSize);
    final maskFullRes = img.copyResize(
      maskImage,
      width: originalWidth,
      height: originalHeight,
      interpolation: img.Interpolation.linear,
    );
    for (final v in outputs.values) {
      await v.dispose();
    }

    // 4. Load + cover-fit the replacement sky to the original dimensions.
    final skyBytes = await skyReplacementImage.readAsBytes();
    var skyDecoded = img.decodeImage(skyBytes);
    if (skyDecoded == null) throw Exception('Could not decode sky image');
    skyDecoded = ColorSpaceUtils.normalizeToSrgb(skyDecoded);
    final skyFitted = _coverResize(skyDecoded, originalWidth, originalHeight);

    // 5. Composite: blend original and replacement sky using the mask as
    // alpha (mask value 255 = fully sky/replaced, 0 = keep original).
    final result = img.Image(
      width: originalWidth,
      height: originalHeight,
      numChannels: 3,
    );
    for (int y = 0; y < originalHeight; y++) {
      for (int x = 0; x < originalWidth; x++) {
        final maskValue = maskFullRes.getPixel(x, y).r / 255.0; // 0..1
        final orig = decoded.getPixel(x, y);
        final sky = skyFitted.getPixel(x, y);
        final r = (orig.r * (1 - maskValue) + sky.r * maskValue).round();
        final g = (orig.g * (1 - maskValue) + sky.g * maskValue).round();
        final b = (orig.b * (1 - maskValue) + sky.b * maskValue).round();
        result.setPixelRgb(x, y, r, g, b);
      }
    }

    final pngBytes = img.encodePng(result);
    final tempDir = await getTemporaryDirectory();
    final outFile = File(
      '${tempDir.path}/sky_replaced_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await outFile.writeAsBytes(pngBytes);
    return outFile;
  }

  img.Image _coverResize(img.Image source, int targetW, int targetH) {
    final srcRatio = source.width / source.height;
    final targetRatio = targetW / targetH;
    img.Image cropped;
    if (srcRatio > targetRatio) {
      final newWidth = (source.height * targetRatio).round();
      final x = ((source.width - newWidth) / 2).round();
      cropped = img.copyCrop(source, x: x, y: 0, width: newWidth, height: source.height);
    } else {
      final newHeight = (source.width / targetRatio).round();
      final y = ((source.height - newHeight) / 2).round();
      cropped = img.copyCrop(source, x: 0, y: y, width: source.width, height: newHeight);
    }
    return img.copyResize(cropped, width: targetW, height: targetH);
  }

  Float32List _imageToCHWFloat32(img.Image image) {
    final w = image.width;
    final h = image.height;
    final data = Float32List(3 * w * h);
    int rIndex = 0, gIndex = w * h, bIndex = 2 * w * h;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        data[rIndex++] = p.r / 255.0;
        data[gIndex++] = p.g / 255.0;
        data[bIndex++] = p.b / 255.0;
      }
    }
    return data;
  }

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

  img.Image _maskToImage(Float32List mask, int width, int height) {
    double minV = mask.first, maxV = mask.first;
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
