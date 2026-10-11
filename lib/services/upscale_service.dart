import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:path_provider/path_provider.dart';

import 'image_decode.dart';
import 'image_ops.dart';
import 'model_store.dart';
import 'tool_utils.dart';

/// 4x super-resolution using a Real-ESRGAN ONNX model.
/// Model contract (dynamic H/W): input float32[1,3,h,w] RGB in [0,1];
/// output float32[1,3,4h,4w] RGB in [0,1].
///
/// The image is processed in small overlapping tiles so memory stays
/// bounded on phones; only the tile interiors are kept when stitching, so
/// there are no visible seams. Every tile is fed to the model at the same
/// size (edges are padded by repeating border pixels).
class UpscaleService {
  static const int _scale = 4;
  static const int _tile = 128;
  static const int _pad = 8;

  /// Photos larger than this are scaled down first (the result is still
  /// 4x that size) so on-device processing stays fast and safe.
  static const int maxInputSide = 1024;

  final OnnxRuntime _ort = OnnxRuntime();
  OrtSession? _session;

  Future<void> loadModel() async {
    _session ??= await ModelStore.load(_ort, ModelStore.esrgan);
  }

  /// Size the photo will be processed at (after the optional shrink).
  static ({int width, int height}) workingSize(int w, int h) {
    final longSide = math.max(w, h);
    if (longSide <= maxInputSide) return (width: w, height: h);
    final k = maxInputSide / longSide;
    return (
      width: math.max(1, (w * k).round()),
      height: math.max(1, (h * k).round()),
    );
  }

  Future<File> upscale(
    File input, {
    void Function(double progress)? onProgress,
  }) async {
    await loadModel();
    final session = _session!;

    final src = await ImageDecode.fromFile(input, maxSide: maxInputSide);
    final W = src.width, H = src.height;
    final rgb = ImageDecode.rgbBytes(src);

    final inputName = session.inputNames.first;
    final outputName = session.outputNames.first;

    final OW = W * _scale, OH = H * _scale;
    final outRgb = Uint8List(OW * OH * 3);

    const inSide = _tile + 2 * _pad;
    const outSide = inSide * _scale;
    const outPlane = outSide * outSide;

    final tilesX = (W / _tile).ceil();
    final tilesY = (H / _tile).ceil();
    final total = tilesX * tilesY;
    int done = 0;

    for (int ty = 0; ty < tilesY; ty++) {
      for (int tx = 0; tx < tilesX; tx++) {
        final x0 = tx * _tile, y0 = ty * _tile;
        final x1 = math.min(x0 + _tile, W), y1 = math.min(y0 + _tile, H);

        // Fixed-size input: tile + padding, repeating the border pixels
        // where the window sticks out of the photo.
        const plane = inSide * inSide;
        final chw = Float32List(3 * plane);
        for (int y = 0; y < inSide; y++) {
          final sy = ToolUtils.clampInt(y0 - _pad + y, 0, H - 1);
          for (int x = 0; x < inSide; x++) {
            final sx = ToolUtils.clampInt(x0 - _pad + x, 0, W - 1);
            final p = (sy * W + sx) * 3;
            final i = y * inSide + x;
            chw[i] = rgb[p] / 255.0;
            chw[plane + i] = rgb[p + 1] / 255.0;
            chw[2 * plane + i] = rgb[p + 2] / 255.0;
          }
        }

        final inVal =
            await OrtValue.fromList(chw.toList(), [1, 3, inSide, inSide]);
        final outputs = await session.run({inputName: inVal});
        await inVal.dispose();
        final outVal = outputs[outputName];
        if (outVal == null) throw Exception('Upscaler produced no output');
        final flat = ToolUtils.flatten(await outVal.asList());
        for (final v in outputs.values) {
          await v.dispose();
        }

        if (flat.length != 3 * outPlane) {
          throw Exception(
            'Unexpected output size from the upscaler model '
            '(got ${flat.length}, expected ${3 * outPlane}). '
            'Make sure it is a 4x Real-ESRGAN export.',
          );
        }

        // Copy only the tile interior (drop the padding) into the result.
        final tw = (x1 - x0) * _scale, th = (y1 - y0) * _scale;
        for (int oy = 0; oy < th; oy++) {
          final srcRow = (_pad * _scale + oy) * outSide + _pad * _scale;
          final dstRow = ((y0 * _scale + oy) * OW + x0 * _scale) * 3;
          for (int ox = 0; ox < tw; ox++) {
            final i = srcRow + ox;
            final d = dstRow + ox * 3;
            outRgb[d] = _toByte(flat[i]);
            outRgb[d + 1] = _toByte(flat[outPlane + i]);
            outRgb[d + 2] = _toByte(flat[2 * outPlane + i]);
          }
        }

        done++;
        onProgress?.call(done / total);
      }
    }

    final png = await Isolate.run(() => encodeRgbPng(outRgb, OW, OH));
    final dir = await getTemporaryDirectory();
    final out = File(
      '${dir.path}/upscaled_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await out.writeAsBytes(png);
    return out;
  }

  static int _toByte(double v) {
    final x = (v * 255).round();
    return x < 0 ? 0 : (x > 255 ? 255 : x);
  }

  void dispose() {
    _session?.close();
    _session = null;
  }
}
