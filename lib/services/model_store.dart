import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'tool_utils.dart';

/// One ONNX model file the app can use.
class ModelSpec {
  final String fileName;

  /// Direct download link used on first use when the file is not bundled.
  final String? url;

  final String hint;

  const ModelSpec({required this.fileName, required this.hint, this.url});

  String get assetPath => 'assets/models/$fileName';
}

class ModelDownloadState {
  final String fileName;
  final double? progress; // 0..1, null when the size is unknown
  const ModelDownloadState(this.fileName, this.progress);
}

/// Finds a model in this order: bundled asset, already downloaded file,
/// download now (when the spec has a url).
class ModelStore {
  ModelStore._();

  static final ValueNotifier<ModelDownloadState?> downloading =
      ValueNotifier<ModelDownloadState?>(null);

  static const ModelSpec u2net = ModelSpec(
    fileName: 'u2net.onnx',
    url:
        'https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx',
    hint: 'Check your internet connection and try again, or add u2net.onnx '
        'to assets/models/.',
  );

  static const ModelSpec isnet = ModelSpec(
    fileName: 'isnet-general-use.onnx',
    url:
        'https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-general-use.onnx',
    hint: 'Check your internet connection and try again, or add '
        'isnet-general-use.onnx to assets/models/.',
  );

  static const ModelSpec lama = ModelSpec(
    fileName: 'lama_fp32.onnx',
    url: 'https://huggingface.co/Carve/LaMa-ONNX/resolve/main/lama_fp32.onnx',
    hint: 'Check your internet connection and try again, or add '
        'lama_fp32.onnx to assets/models/.',
  );

  static const ModelSpec esrgan = ModelSpec(
    fileName: 'esrgan_x4.onnx',
    url:
        'https://huggingface.co/SceneWorks/real-esrgan-onnx/resolve/main/real_esrgan_x4.onnx',
    hint: 'Check your internet connection and try again, or add '
        'esrgan_x4.onnx to assets/models/.',
  );

  // YOLOv8 medium segmentation (Ultralytics export, 640x640, 80 classes).
  // Same output layout as the nano model but much cleaner masks (~105MB).
  // For a smaller download use yolov8n-seg.onnx (~14MB) from the same repo.
  static const ModelSpec yolo = ModelSpec(
    fileName: 'yolov8m-seg.onnx',
    url:
        'https://huggingface.co/unileon-robotics/YOLO8-ONNX/resolve/main/yolov8m-seg.onnx',
    hint: 'Check your internet connection and try again, or add '
        'yolov8m-seg.onnx to assets/models/ (see MODELS_SETUP.md).',
  );

  static const ModelSpec sky = ModelSpec(
    fileName: 'sky_seg.onnx',
    hint: 'See assets/models/SKY_MODEL_SETUP.md.',
  );

  static Future<OrtSession> load(OnnxRuntime ort, ModelSpec spec) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    if (manifest.listAssets().contains(spec.assetPath)) {
      return ort.createSessionFromAsset(spec.assetPath);
    }

    final dir = await _modelDir();
    final local = File('${dir.path}/${spec.fileName}');
    if (await local.exists() && await local.length() > 1024 * 1024) {
      return ort.createSession(local.path);
    }

    final url = spec.url;
    if (url == null) {
      throw ModelMissingException(spec.assetPath, spec.hint);
    }
    await _download(url, local, spec);
    return ort.createSession(local.path);
  }

  static Future<Directory> _modelDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/models');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<void> _download(String url, File target, ModelSpec spec) async {
    final part = File('${target.path}.part');
    final client = http.Client();
    IOSink? sink;
    try {
      downloading.value = ModelDownloadState(spec.fileName, null);
      final response = await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        throw Exception(
            'Download failed (HTTP ${response.statusCode}). ${spec.hint}');
      }
      final total = response.contentLength;
      var received = 0;
      sink = part.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        downloading.value = ModelDownloadState(
          spec.fileName,
          (total != null && total > 0) ? received / total : null,
        );
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (total != null && total > 0 && received != total) {
        throw Exception('Download was interrupted. ${spec.hint}');
      }
      if (received < 1024 * 1024) {
        throw Exception('Downloaded file looks invalid. ${spec.hint}');
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
    } on SocketException {
      throw Exception('No internet connection. ${spec.hint}');
    } finally {
      await sink?.close();
      client.close();
      downloading.value = null;
      if (await part.exists()) {
        try {
          await part.delete();
        } catch (_) {}
      }
    }
  }
}
