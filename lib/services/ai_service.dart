import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

import 'image_decode.dart';
import 'image_ops.dart';
import 'model_store.dart';
import 'tool_utils.dart';

/// Cuts the subject out of a photo on-device (ISNet, with U2Net as a
/// lighter fallback).
///
/// Quality notes:
///  - Input uses the same preprocessing the models were trained with
///    (max-scaling + mean/std). Plain /255 makes the model miss faces and
///    clothes.
///  - The mask is cleaned up: stray background blobs are dropped and the
///    alpha curve is tuned so the whole body and clothes stay.
///  - All heavy pixel work runs in a background isolate, so the screen
///    stays responsive.
class AiService {
  /// Longest side kept while working. Bigger photos are scaled down so
  /// the phone does not run out of memory.
  static const int _maxWorkSide = 2560;

  final OnnxRuntime _ort = OnnxRuntime();
  OrtSession? _session;
  bool _isIsnet = true;
  int _inputSize = 1024;
  bool get isLoaded => _session != null;

  /// Loads the high-quality ISNet model (1024px). If it cannot be loaded
  /// or run on this phone, the lighter U2Net (320px) is used instead.
  Future<void> loadModel() async {
    if (_session != null) return;
    try {
      _session = await ModelStore.load(_ort, ModelStore.isnet);
      _isIsnet = true;
      _inputSize = 1024;
    } on ModelMissingException {
      rethrow;
    } catch (_) {
      await _loadLight();
    }
  }

  Future<void> _loadLight() async {
    _session?.close();
    _session = await ModelStore.load(_ort, ModelStore.u2net);
    _isIsnet = false;
    _inputSize = 320;
  }

  Future<File> removeBackground(File inputImage) async {
    await loadModel();
    try {
      return await _run(inputImage);
    } on ModelMissingException {
      rethrow;
    } catch (e) {
      if (!_isIsnet) rethrow;
      // High-quality model failed (usually memory). Retry lighter.
      await _loadLight();
      return _run(inputImage);
    }
  }

  Future<File> _run(File inputImage) async {
    final session = _session!;

    final decoded =
        await ImageDecode.fromFile(inputImage, maxSide: _maxWorkSide);
    final w = decoded.width, h = decoded.height;
    final rgb = ImageDecode.rgbBytes(decoded);
    final size = _inputSize;
    final isnet = _isIsnet;

    final input = await Isolate.run(
      () => prepareSalientInput(rgb, w, h, size, isnet),
    );

    final inputValue = await OrtValue.fromList(
      input.toList(),
      [1, 3, size, size],
    );
    final outputs = await session.run({session.inputNames.first: inputValue});
    await inputValue.dispose();

    // The first output is the fused, final prediction.
    final outputValue = outputs[session.outputNames.first];
    if (outputValue == null) {
      throw Exception('Model produced no output');
    }
    final raw = ToolUtils.flatten(await outputValue.asList());
    for (final v in outputs.values) {
      await v.dispose();
    }
    if (raw.length < size * size) {
      throw Exception('Unexpected model output size.');
    }

    final png = await Isolate.run(
      () => composeCutoutPng(rgb, w, h, raw, size),
    );

    final tempDir = await getTemporaryDirectory();
    final outFile = File(
      '${tempDir.path}/bg_removed_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await outFile.writeAsBytes(png);
    return outFile;
  }

  void dispose() {
    _session?.close();
    _session = null;
  }
}
