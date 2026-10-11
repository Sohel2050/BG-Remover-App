import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import 'image_decode.dart';
import 'package:path_provider/path_provider.dart';
import 'tool_utils.dart';
import 'model_store.dart';

const List<String> _cocoLabels = [
  'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train',
  'truck', 'boat', 'traffic light', 'fire hydrant', 'stop sign',
  'parking meter', 'bench', 'bird', 'cat', 'dog', 'horse', 'sheep', 'cow',
  'elephant', 'bear', 'zebra', 'giraffe', 'backpack', 'umbrella', 'handbag',
  'tie', 'suitcase', 'frisbee', 'skis', 'snowboard', 'sports ball', 'kite',
  'baseball bat', 'baseball glove', 'skateboard', 'surfboard',
  'tennis racket', 'bottle', 'wine glass', 'cup', 'fork', 'knife', 'spoon',
  'bowl', 'banana', 'apple', 'sandwich', 'orange', 'broccoli', 'carrot',
  'hot dog', 'pizza', 'donut', 'cake', 'chair', 'couch', 'potted plant',
  'bed', 'dining table', 'toilet', 'tv', 'laptop', 'mouse', 'remote',
  'keyboard', 'cell phone', 'microwave', 'oven', 'toaster', 'sink',
  'refrigerator', 'book', 'clock', 'vase', 'scissors', 'teddy bear',
  'hair drier', 'toothbrush',
];

class DetectedSubject {
  final int id;
  final String label;
  final double score;

  /// Bounding box in working-image pixel coordinates.
  final Rect box;

  /// Mask probabilities (protoW x protoH) in the model's letterboxed space.
  final Float32List proto;
  final int protoW;
  final int protoH;
  DetectedSubject(this.id, this.label, this.score, this.box, this.proto,
      this.protoW, this.protoH);
}

class SubjectDetectionResult {
  /// The (possibly downscaled) image the detections refer to. Use this
  /// file as the "original" so sizes line up with the extracted result.
  final File workingImageFile;
  final img.Image image;
  final int width;
  final int height;
  final double scale;
  final int offX;
  final int offY;
  final List<DetectedSubject> subjects;
  SubjectDetectionResult({
    required this.workingImageFile,
    required this.image,
    required this.width,
    required this.height,
    required this.scale,
    required this.offX,
    required this.offY,
    required this.subjects,
  });
}

/// Finds individual objects/people with YOLOv8n-seg (instance
/// segmentation) so the user can pick which ones to keep.
/// Model contract (standard Ultralytics ONNX export, fixed size HxW):
///  input  `images` float32[1,3,H,W] RGB /255 (letterboxed)
///  output0 float32[1, 4+nc+32, 8400]  (cx,cy,w,h | class scores | 32 mask coeffs)
///  output1 float32[1,32,H/4,W/4]      (mask prototypes)
class SubjectDetectionService {
  // Model input size. Defaults to 640x640 but adapts to models exported
  // with another fixed size (the size is read from the runtime error).
  int _inH = 640;
  int _inW = 640;
  static const int _nm = 32;
  static const int _maxWorkSide = 2048;

  final OnnxRuntime _ort = OnnxRuntime();
  OrtSession? _session;

  Future<void> loadModel() async {
    _session ??= await ModelStore.load(_ort, ModelStore.yolo);
  }

  double _sigmoid(double x) => 1.0 / (1.0 + math.exp(-x));

  Future<SubjectDetectionResult> detect(
    File input, {
    double confThreshold = 0.25,
    double iouThreshold = 0.5,
    int maxSubjects = 12,
  }) async {
    await loadModel();
    final session = _session!;

    var work = await ImageDecode.fromFile(input, maxSide: _maxWorkSide);
    final longSide = math.max(work.width, work.height);
    if (longSide > _maxWorkSide) {
      final s = _maxWorkSide / longSide;
      work = img.copyResize(
        work,
        width: (work.width * s).round(),
        height: (work.height * s).round(),
        interpolation: img.Interpolation.linear,
      );
    }
    final W = work.width, H = work.height;

    final dir = await getTemporaryDirectory();
    final workFile = File(
      '${dir.path}/subjects_work_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await workFile.writeAsBytes(img.encodeJpg(work, quality: 95));

    List<double>? detOut;
    List<double>? protoOut;
    late double scale;
    late int offX, offY;
    for (int attempt = 0; attempt < 3; attempt++) {
      final inH = _inH, inW = _inW;
      scale = math.min(inW / W, inH / H);
      final nw = (W * scale).round().clamp(1, inW).toInt();
      final nh = (H * scale).round().clamp(1, inH).toInt();
      offX = ((inW - nw) / 2).floor();
      offY = ((inH - nh) / 2).floor();
      final resized = img.copyResize(
        work,
        width: nw,
        height: nh,
        interpolation: img.Interpolation.linear,
      );
      final plane = inW * inH;
      final data = Float32List(3 * plane)..fillRange(0, 3 * plane, 114 / 255);
      for (int y = 0; y < nh; y++) {
        for (int x = 0; x < nw; x++) {
          final p = resized.getPixel(x, y);
          final i = (y + offY) * inW + (x + offX);
          data[i] = p.r / 255.0;
          data[plane + i] = p.g / 255.0;
          data[2 * plane + i] = p.b / 255.0;
        }
      }
      try {
        final inVal = await OrtValue.fromList(data.toList(), [1, 3, inH, inW]);
        final outputs = await session.run({session.inputNames.first: inVal});
        await inVal.dispose();
        final names = session.outputNames;
        if (names.length < 2) {
          throw Exception('Expected a segmentation model with 2 outputs.');
        }
        detOut = ToolUtils.flatten(await outputs[names[0]]!.asList());
        protoOut = ToolUtils.flatten(await outputs[names[1]]!.asList());
        for (final v in outputs.values) {
          await v.dispose();
        }
        break;
      } catch (e) {
        // "index: 2 Got: 640 Expected: 480" -> adopt the expected size.
        final msg = e.toString();
        final m = RegExp(r'index:\s*(\d)\s*Got:\s*\d+\s*Expected:\s*(\d+)')
            .allMatches(msg)
            .toList();
        if (m.isEmpty || attempt == 2) rethrow;
        bool changed = false;
        for (final mm in m) {
          final idx = int.parse(mm.group(1)!);
          final v = int.parse(mm.group(2)!);
          if (idx == 2 && v != _inH) {
            _inH = v;
            changed = true;
          } else if (idx == 3 && v != _inW) {
            _inW = v;
            changed = true;
          }
        }
        if (!changed) rethrow;
      }
    }
    if (detOut == null || protoOut == null) {
      throw Exception('Subject detection failed.');
    }
    var det = detOut;
    var proto = protoOut;

    final protoH = _inH ~/ 4, protoW = _inW ~/ 4;
    final protoSize = protoW * protoH;
    final anchors = (_inH ~/ 8) * (_inW ~/ 8) +
        (_inH ~/ 16) * (_inW ~/ 16) +
        (_inH ~/ 32) * (_inW ~/ 32);
    if (det.length == _nm * protoSize) {
      final t = det;
      det = proto;
      proto = t;
    }
    if (proto.length != _nm * protoSize || det.length % anchors != 0) {
      throw Exception(
        'Unexpected model output. Use a YOLOv8-seg ONNX export.',
      );
    }
    final channels = det.length ~/ anchors;
    final nc = channels - 4 - _nm;
    if (nc < 1) throw Exception('Unexpected model output layout.');

    // Candidates above the confidence threshold.
    final cands = <_Cand>[];
    for (int a = 0; a < anchors; a++) {
      double best = -1;
      int bestC = 0;
      for (int c = 0; c < nc; c++) {
        final s = det[(4 + c) * anchors + a];
        if (s > best) {
          best = s;
          bestC = c;
        }
      }
      if (best < confThreshold) continue;
      final cx = det[a], cy = det[anchors + a];
      final w = det[2 * anchors + a], h = det[3 * anchors + a];
      cands.add(_Cand(a, bestC, best, cx - w / 2, cy - h / 2, cx + w / 2,
          cy + h / 2));
    }
    cands.sort((p, q) => q.score.compareTo(p.score));

    // Non-maximum suppression (class-agnostic).
    final kept = <_Cand>[];
    for (final c in cands) {
      bool overlaps = false;
      for (final k in kept) {
        if (_iou(c, k) > iouThreshold) {
          overlaps = true;
          break;
        }
      }
      if (!overlaps) kept.add(c);
      if (kept.length >= maxSubjects) break;
    }

    // Build a soft mask for each kept detection.
    final protoPlane = protoSize;
    final subjects = <DetectedSubject>[];
    for (int idx = 0; idx < kept.length; idx++) {
      final c = kept[idx];
      final coefs = Float32List(_nm);
      for (int k = 0; k < _nm; k++) {
        coefs[k] = det[(4 + nc + k) * anchors + c.anchor];
      }
      final mask = Float32List(protoPlane);
      // Grow the box a little so limbs and clothes near the edge are kept.
      final padX = (c.x2 - c.x1) * 0.06, padY = (c.y2 - c.y1) * 0.06;
      final bx1 = (c.x1 - padX) / 4, by1 = (c.y1 - padY) / 4;
      final bx2 = (c.x2 + padX) / 4, by2 = (c.y2 + padY) / 4;
      for (int y = 0; y < protoH; y++) {
        if (y < by1 || y > by2) continue;
        for (int x = 0; x < protoW; x++) {
          if (x < bx1 || x > bx2) continue;
          final p = y * protoW + x;
          double sum = 0;
          for (int k = 0; k < _nm; k++) {
            sum += coefs[k] * proto[k * protoPlane + p];
          }
          mask[p] = _sigmoid(sum).toDouble();
        }
      }

      final box = Rect.fromLTRB(
        ((c.x1 - offX) / scale).clamp(0, W.toDouble()).toDouble(),
        ((c.y1 - offY) / scale).clamp(0, H.toDouble()).toDouble(),
        ((c.x2 - offX) / scale).clamp(0, W.toDouble()).toDouble(),
        ((c.y2 - offY) / scale).clamp(0, H.toDouble()).toDouble(),
      );
      final label = nc == 80 ? _cocoLabels[c.cls] : 'object';
      subjects.add(DetectedSubject(idx, label, c.score, box, mask, protoW, protoH));
    }

    return SubjectDetectionResult(
      workingImageFile: workFile,
      image: work,
      width: W,
      height: H,
      scale: scale,
      offX: offX,
      offY: offY,
      subjects: subjects,
    );
  }

  double _iou(_Cand a, _Cand b) {
    final ix1 = math.max(a.x1, b.x1), iy1 = math.max(a.y1, b.y1);
    final ix2 = math.min(a.x2, b.x2), iy2 = math.min(a.y2, b.y2);
    final iw = math.max(0.0, ix2 - ix1), ih = math.max(0.0, iy2 - iy1);
    final inter = iw * ih;
    final union = (a.x2 - a.x1) * (a.y2 - a.y1) +
        (b.x2 - b.x1) * (b.y2 - b.y1) -
        inter;
    return union <= 0 ? 0 : inter / union;
  }

  double _sample(Float32List m, int pw, int ph, double px, double py) {
    final double x = px.clamp(0.0, pw - 1.0).toDouble();
    final double y = py.clamp(0.0, ph - 1.0).toDouble();
    final x0 = x.floor(), y0 = y.floor();
    final x1 = math.min(x0 + 1, pw - 1);
    final y1 = math.min(y0 + 1, ph - 1);
    final fx = x - x0, fy = y - y0;
    final a = m[y0 * pw + x0] * (1 - fx) + m[y0 * pw + x1] * fx;
    final b = m[y1 * pw + x0] * (1 - fx) + m[y1 * pw + x1] * fx;
    return a * (1 - fy) + b * fy;
  }

  /// Cuts out the selected subjects (everything else becomes transparent).
  Future<File> extract(
    SubjectDetectionResult result,
    Set<int> selectedIds,
  ) async {
    final chosen =
        result.subjects.where((s) => selectedIds.contains(s.id)).toList();
    if (chosen.isEmpty) throw Exception('Select at least one subject.');

    final W = result.width, H = result.height;
    final out = img.Image(width: W, height: H, numChannels: 4);
    for (int y = 0; y < H; y++) {
      final ly = y * result.scale + result.offY;
      final py = (ly + 0.5) / 4 - 0.5;
      for (int x = 0; x < W; x++) {
        final lx = x * result.scale + result.offX;
        final px = (lx + 0.5) / 4 - 0.5;
        double p = 0;
        for (final s in chosen) {
          final v = _sample(s.proto, s.protoW, s.protoH, px, py);
          if (v > p) p = v;
        }
        // Soft edge: fully out below 0.25, fully in above 0.55.
        final double t = ((p - 0.25) / 0.3).clamp(0.0, 1.0).toDouble();
        final double a = t * t * (3 - 2 * t);
        final src = result.image.getPixel(x, y);
        out.setPixelRgba(x, y, src.r, src.g, src.b, (a * 255).round());
      }
    }

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/subjects_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(img.encodePng(out));
    return file;
  }

  void dispose() {
    _session?.close();
    _session = null;
  }
}

class _Cand {
  final int anchor;
  final int cls;
  final double score;
  final double x1, y1, x2, y2;
  _Cand(this.anchor, this.cls, this.score, this.x1, this.y1, this.x2, this.y2);
}
