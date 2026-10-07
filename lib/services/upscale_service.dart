import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'color_space_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'tool_utils.dart';

/// 4x super-resolution using a Real-ESRGAN ONNX model.
/// Model contract (dynamic H/W): input float32[1,3,h,w] RGB in [0,1];
/// output float32[1,3,4h,4w] RGB in [0,1].
///
/// The image is processed in small overlapping tiles so memory stays
/// bounded on phones; only the tile interiors are kept when stitching, so
/// there are no visible seams.
class UpscaleService {
  static const String _asset = 'assets/models/esrgan_x4.onnx';
  static const int _scale = 4;
  static const int _tile = 128;
  static const int _pad = 8;

  /// Larger inputs would produce huge outputs and take very long on-device.
  static const int maxInputSide = 1024;

  final OnnxRuntime _ort = OnnxRuntime();
  OrtSession? _session;

  Future<void> loadModel() async {
    _session ??= await ToolUtils.loadSession(
      _ort,
      _asset,
      hint: 'See assets/models/MODELS_SETUP.md (Real-ESRGAN).',
    );
  }

  Future<File> upscale(
    File input, {
    void Function(double progress)? onProgress,
  }) async {
    await loadModel();
    final session = _session!;

    final decoded0 = img.decodeImage(await input.readAsBytes());
    if (decoded0 == null) throw Exception('Could not decode image');
    final src = ColorSpaceUtils.normalizeToSrgb(img.bakeOrientation(decoded0));
    final W = src.width, H = src.height;
    if (math.max(W, H) > maxInputSide) {
      throw Exception(
        'This image is already large (${W}x$H). Upscaling works on images up '
        'to ${maxInputSide}px on the longest side — try a smaller/cropped one.',
      );
    }

    final inputName = session.inputNames.first;
    final outputName = session.outputNames.first;
    final result =
        img.Image(width: W * _scale, height: H * _scale, numChannels: 3);

    final tilesX = (W / _tile).ceil();
    final tilesY = (H / _tile).ceil();
    final total = tilesX * tilesY;
    int done = 0;

    for (int ty = 0; ty < tilesY; ty++) {
      for (int tx = 0; tx < tilesX; tx++) {
        final x0 = tx * _tile, y0 = ty * _tile;
        final x1 = math.min(x0 + _tile, W), y1 = math.min(y0 + _tile, H);
        // Padded region gives the model context around the tile edges.
        final px0 = math.max(0, x0 - _pad), py0 = math.max(0, y0 - _pad);
        final px1 = math.min(W, x1 + _pad), py1 = math.min(H, y1 + _pad);
        final tw = px1 - px0, th = py1 - py0;

        final plane = tw * th;
        final chw = Float32List(3 * plane);
        for (int y = 0; y < th; y++) {
          for (int x = 0; x < tw; x++) {
            final p = src.getPixel(px0 + x, py0 + y);
            final i = y * tw + x;
            chw[i] = p.r / 255.0;
            chw[plane + i] = p.g / 255.0;
            chw[2 * plane + i] = p.b / 255.0;
          }
        }

        final inVal = await OrtValue.fromList(chw.toList(), [1, 3, th, tw]);
        final outputs = await session.run({inputName: inVal});
        await inVal.dispose();
        final outVal = outputs[outputName];
        if (outVal == null) throw Exception('Upscaler produced no output');
        final flat = ToolUtils.flatten(await outVal.asList());
        for (final v in outputs.values) {
          await v.dispose();
        }

        final ow = tw * _scale, oh = th * _scale;
        if (flat.length != 3 * ow * oh) {
          throw Exception(
            'Unexpected output size from the upscaler model '
            '(got ${flat.length}, expected ${3 * ow * oh}). '
            'Make sure it is a 4x Real-ESRGAN export.',
          );
        }

        // Copy only the tile interior (drop the padding) into the result.
        final oPlane = ow * oh;
        final startX = (x0 - px0) * _scale, endX = (x1 - px0) * _scale;
        final startY = (y0 - py0) * _scale, endY = (y1 - py0) * _scale;
        for (int oy = startY; oy < endY; oy++) {
          for (int ox = startX; ox < endX; ox++) {
            final i = oy * ow + ox;
            result.setPixelRgb(
              px0 * _scale + ox,
              py0 * _scale + oy,
              (flat[i] * 255).clamp(0, 255),
              (flat[oPlane + i] * 255).clamp(0, 255),
              (flat[2 * oPlane + i] * 255).clamp(0, 255),
            );
          }
        }

        done++;
        onProgress?.call(done / total);
      }
    }

    final dir = await getTemporaryDirectory();
    final out = File(
      '${dir.path}/upscaled_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await out.writeAsBytes(img.encodePng(result));
    return out;
  }

  void dispose() {
    _session?.close();
    _session = null;
  }
}
