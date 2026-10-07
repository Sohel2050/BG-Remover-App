import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'color_space_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'tool_utils.dart';

/// One brush stroke painted over the object to remove. Coordinates are
/// normalized to the image (0..1) so they're independent of screen size.
class MaskStroke {
  final List<Offset> points;

  /// Brush radius as a fraction of the image WIDTH.
  final double radiusNorm;
  MaskStroke(this.points, this.radiusNorm);
}

/// Object removal using LaMa (lama_fp32.onnx, Carve export).
/// Model contract (fixed 512x512): inputs `image` float32[1,3,512,512]
/// RGB /255 and `mask` float32[1,1,512,512] (1 = erase); output
/// float32[1,3,512,512] RGB in [0,255].
///
/// Because the model is fixed at 512x512, we don't squash the whole photo
/// into 512px. Instead we crop a square region around the painted area,
/// inpaint that crop, and blend only the masked pixels back — so the rest
/// of the photo keeps its full original quality.
class InpaintService {
  static const String _asset = 'assets/models/lama_fp32.onnx';
  static const int _size = 512;

  final OnnxRuntime _ort = OnnxRuntime();
  OrtSession? _session;

  Future<void> loadModel() async {
    _session ??= await ToolUtils.loadSession(
      _ort,
      _asset,
      hint: 'See assets/models/MODELS_SETUP.md (LaMa).',
    );
  }

  Future<File> removeObjects(File input, List<MaskStroke> strokes) async {
    if (strokes.isEmpty) {
      throw Exception('Paint over the object you want to remove first.');
    }
    await loadModel();
    final session = _session!;

    final decoded0 = img.decodeImage(await input.readAsBytes());
    if (decoded0 == null) throw Exception('Could not decode image');
    final photo = ColorSpaceUtils.normalizeToSrgb(img.bakeOrientation(decoded0));
    final W = photo.width;
    final H = photo.height;

    // 1. Bounding box of everything painted (pixel coordinates).
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (final s in strokes) {
      final r = s.radiusNorm * W;
      for (final p in s.points) {
        final px = p.dx * W, py = p.dy * H;
        minX = math.min(minX, px - r);
        maxX = math.max(maxX, px + r);
        minY = math.min(minY, py - r);
        maxY = math.max(maxY, py + r);
      }
    }
    minX = minX.clamp(0, W.toDouble()).toDouble();
    maxX = maxX.clamp(0, W.toDouble()).toDouble();
    minY = minY.clamp(0, H.toDouble()).toDouble();
    maxY = maxY.clamp(0, H.toDouble()).toDouble();

    // 2. Square crop around it, with generous context (2x the painted area).
    double side = math.max(maxX - minX, maxY - minY) * 2.0;
    side = math.max(side, 256);
    side = math.min(side, math.min(W, H).toDouble());
    final sideI = side.round();
    final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    final x0 = (cx - sideI / 2).round().clamp(0, W - sideI).toInt();
    final y0 = (cy - sideI / 2).round().clamp(0, H - sideI).toInt();

    // 3. Rasterize the strokes into a 512x512 mask in crop space.
    final mask = Float32List(_size * _size);
    final k = _size / sideI;
    void stamp(double sx, double sy, double r) {
      final yFrom = math.max(0, (sy - r).floor());
      final yTo = math.min(_size - 1, (sy + r).ceil());
      final xFrom = math.max(0, (sx - r).floor());
      final xTo = math.min(_size - 1, (sx + r).ceil());
      for (int yy = yFrom; yy <= yTo; yy++) {
        for (int xx = xFrom; xx <= xTo; xx++) {
          final dx = xx - sx, dy = yy - sy;
          if (dx * dx + dy * dy <= r * r) mask[yy * _size + xx] = 1;
        }
      }
    }

    for (final s in strokes) {
      final r = math.max(2.0, s.radiusNorm * W * k);
      Offset? prev;
      for (final p in s.points) {
        final cur = Offset((p.dx * W - x0) * k, (p.dy * H - y0) * k);
        if (prev == null) {
          stamp(cur.dx, cur.dy, r);
        } else {
          final dist = (cur - prev).distance;
          final steps = math.max(1, (dist / (r / 2)).ceil());
          for (int i = 1; i <= steps; i++) {
            final q = Offset.lerp(prev, cur, i / steps)!;
            stamp(q.dx, q.dy, r);
          }
        }
        prev = cur;
      }
    }
    // LaMa works best when the mask fully covers the object's edges.
    final dilated = ToolUtils.dilate(mask, _size, _size, 6);
    final feather = ToolUtils.boxBlur(dilated, _size, _size, 4);

    // 4. Preprocess the crop.
    final crop = img.copyCrop(photo, x: x0, y: y0, width: sideI, height: sideI);
    final small = img.copyResize(
      crop,
      width: _size,
      height: _size,
      interpolation: img.Interpolation.linear,
    );
    final plane = _size * _size;
    final chw = Float32List(3 * plane);
    for (int y = 0; y < _size; y++) {
      for (int x = 0; x < _size; x++) {
        final p = small.getPixel(x, y);
        final i = y * _size + x;
        chw[i] = p.r / 255.0;
        chw[plane + i] = p.g / 255.0;
        chw[2 * plane + i] = p.b / 255.0;
      }
    }

    // 5. Inference.
    final names = session.inputNames;
    final imageName = names.firstWhere(
      (n) => n.toLowerCase().contains('image'),
      orElse: () => names.first,
    );
    final maskName = names.firstWhere(
      (n) => n.toLowerCase().contains('mask'),
      orElse: () => names.length > 1 ? names[1] : names.first,
    );
    final imageVal =
        await OrtValue.fromList(chw.toList(), [1, 3, _size, _size]);
    final maskVal =
        await OrtValue.fromList(dilated.toList(), [1, 1, _size, _size]);
    final outputs = await session.run({imageName: imageVal, maskName: maskVal});
    await imageVal.dispose();
    await maskVal.dispose();

    final outVal = outputs[session.outputNames.first];
    if (outVal == null) throw Exception('Inpainting model produced no output');
    final flat = ToolUtils.flatten(await outVal.asList());
    for (final v in outputs.values) {
      await v.dispose();
    }
    if (flat.length != 3 * plane) {
      throw Exception(
        'Unexpected model output size (${flat.length}). '
        'Expected a 512x512 LaMa export.',
      );
    }

    // Output is documented as [0,255]; if a variant returns [0,1], rescale.
    double maxV = 0;
    for (int i = 0; i < flat.length; i += 97) {
      if (flat[i] > maxV) maxV = flat[i];
    }
    final mul = maxV <= 2.0 ? 255.0 : 1.0;

    final filled512 = img.Image(width: _size, height: _size, numChannels: 3);
    for (int y = 0; y < _size; y++) {
      for (int x = 0; x < _size; x++) {
        final i = y * _size + x;
        filled512.setPixelRgb(
          x,
          y,
          (flat[i] * mul).clamp(0, 255),
          (flat[plane + i] * mul).clamp(0, 255),
          (flat[2 * plane + i] * mul).clamp(0, 255),
        );
      }
    }
    final filled = img.copyResize(
      filled512,
      width: sideI,
      height: sideI,
      interpolation: img.Interpolation.cubic,
    );

    // 6. Blend only the painted (feathered) area back into the photo.
    for (int yy = 0; yy < sideI; yy++) {
      final my = math.min(_size - 1, (yy * _size / sideI).floor());
      for (int xx = 0; xx < sideI; xx++) {
        final mx = math.min(_size - 1, (xx * _size / sideI).floor());
        final a = feather[my * _size + mx];
        if (a <= 0.01) continue;
        final f = filled.getPixel(xx, yy);
        final o = photo.getPixel(x0 + xx, y0 + yy);
        photo.setPixelRgb(
          x0 + xx,
          y0 + yy,
          o.r * (1 - a) + f.r * a,
          o.g * (1 - a) + f.g * a,
          o.b * (1 - a) + f.b * a,
        );
      }
    }

    final dir = await getTemporaryDirectory();
    final out = File(
      '${dir.path}/inpaint_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await out.writeAsBytes(img.encodeJpg(photo, quality: 95));
    return out;
  }

  void dispose() {
    _session?.close();
    _session = null;
  }
}
