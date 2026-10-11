import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Lets the user choose a crop rectangle. Pops with the rectangle as
/// fractions (0..1) of the image, or null if cancelled.
class CropScreen extends StatefulWidget {
  final File image;
  const CropScreen({super.key, required this.image});

  @override
  State<CropScreen> createState() => _CropScreenState();
}

enum _Drag { none, move, tl, tr, bl, br, l, r, t, b }

class _CropScreenState extends State<CropScreen> {
  Size? _imgSize;
  // Crop rectangle in image pixels.
  Rect _crop = Rect.zero;
  double? _ratio; // width / height, null = free
  _Drag _drag = _Drag.none;
  Rect _dragStartCrop = Rect.zero;
  Offset _dragStartPos = Offset.zero;

  static const double _minSide = 40;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final codec = await ui.instantiateImageCodec(
      await widget.image.readAsBytes(),
    );
    final im = (await codec.getNextFrame()).image;
    final s = Size(im.width.toDouble(), im.height.toDouble());
    im.dispose();
    if (!mounted) return;
    setState(() {
      _imgSize = s;
      _crop = Offset.zero & s;
    });
  }

  void _setRatio(double? r) {
    final s = _imgSize;
    if (s == null) return;
    setState(() {
      _ratio = r;
      if (r == null) return;
      final c = _crop.center;
      var w = _crop.width, h = w / r;
      if (h > s.height) {
        h = s.height;
        w = h * r;
      }
      if (w > s.width) {
        w = s.width;
        h = w / r;
      }
      var left = (c.dx - w / 2).clamp(0.0, s.width - w).toDouble();
      var top = (c.dy - h / 2).clamp(0.0, s.height - h).toDouble();
      _crop = Rect.fromLTWH(left, top, w, h);
    });
  }

  _Drag _hit(Offset p, double scale) {
    final tol = 28 / scale;
    final r = _crop;
    bool near(double a, double b) => (a - b).abs() < tol;
    final l = near(p.dx, r.left), rr = near(p.dx, r.right);
    final t = near(p.dy, r.top), b = near(p.dy, r.bottom);
    if (l && t) return _Drag.tl;
    if (rr && t) return _Drag.tr;
    if (l && b) return _Drag.bl;
    if (rr && b) return _Drag.br;
    final inY = p.dy > r.top && p.dy < r.bottom;
    final inX = p.dx > r.left && p.dx < r.right;
    if (l && inY) return _Drag.l;
    if (rr && inY) return _Drag.r;
    if (t && inX) return _Drag.t;
    if (b && inX) return _Drag.b;
    if (r.contains(p)) return _Drag.move;
    return _Drag.none;
  }

  void _update(Offset pos) {
    final s = _imgSize!;
    final d = pos - _dragStartPos;
    final o = _dragStartCrop;
    double l = o.left, t = o.top, r = o.right, b = o.bottom;
    switch (_drag) {
      case _Drag.move:
        final nl = (o.left + d.dx).clamp(0.0, s.width - o.width).toDouble();
        final nt = (o.top + d.dy).clamp(0.0, s.height - o.height).toDouble();
        setState(() => _crop = Rect.fromLTWH(nl, nt, o.width, o.height));
        return;
      case _Drag.tl:
        l += d.dx;
        t += d.dy;
      case _Drag.tr:
        r += d.dx;
        t += d.dy;
      case _Drag.bl:
        l += d.dx;
        b += d.dy;
      case _Drag.br:
        r += d.dx;
        b += d.dy;
      case _Drag.l:
        l += d.dx;
      case _Drag.r:
        r += d.dx;
      case _Drag.t:
        t += d.dy;
      case _Drag.b:
        b += d.dy;
      case _Drag.none:
        return;
    }
    l = l.clamp(0.0, r - _minSide).toDouble();
    t = t.clamp(0.0, b - _minSide).toDouble();
    r = r.clamp(l + _minSide, s.width).toDouble();
    b = b.clamp(t + _minSide, s.height).toDouble();
    var rect = Rect.fromLTRB(l, t, r, b);
    final ratio = _ratio;
    if (ratio != null) {
      // Keep the ratio: fit the height to the width, anchored at the
      // corner/edge that is not being dragged.
      var w = rect.width, h = w / ratio;
      if (h > s.height) {
        h = s.height;
        w = h * ratio;
      }
      final anchorRight = _drag == _Drag.tl || _drag == _Drag.bl || _drag == _Drag.l;
      final anchorBottom = _drag == _Drag.tl || _drag == _Drag.tr || _drag == _Drag.t;
      var nl = anchorRight ? rect.right - w : rect.left;
      var nt = anchorBottom ? rect.bottom - h : rect.top;
      nl = nl.clamp(0.0, s.width - w).toDouble();
      nt = nt.clamp(0.0, s.height - h).toDouble();
      rect = Rect.fromLTWH(nl, nt, w, h);
    }
    setState(() => _crop = rect);
  }

  @override
  Widget build(BuildContext context) {
    final s = _imgSize;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Crop'),
        actions: [
          TextButton(
            onPressed: s == null
                ? null
                : () => Navigator.pop(
                      context,
                      Rect.fromLTRB(
                        _crop.left / s.width,
                        _crop.top / s.height,
                        _crop.right / s.width,
                        _crop.bottom / s.height,
                      ),
                    ),
            child: const Text('Done'),
          ),
        ],
      ),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final fit = applyBoxFit(
                        BoxFit.contain,
                        s,
                        Size(c.maxWidth - 24, c.maxHeight - 24),
                      );
                      final dest = fit.destination;
                      final scale = dest.width / s.width;
                      final off = Offset(
                        (c.maxWidth - dest.width) / 2,
                        (c.maxHeight - dest.height) / 2,
                      );
                      Offset toImg(Offset p) => (p - off) / scale;
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (d) {
                          final p = toImg(d.localPosition);
                          _drag = _hit(p, scale);
                          _dragStartCrop = _crop;
                          _dragStartPos = p;
                        },
                        onPanUpdate: (d) {
                          if (_drag != _Drag.none) _update(toImg(d.localPosition));
                        },
                        onPanEnd: (_) => _drag = _Drag.none,
                        child: Stack(
                          children: [
                            Positioned(
                              left: off.dx,
                              top: off.dy,
                              width: dest.width,
                              height: dest.height,
                              child: Image.file(widget.image, fit: BoxFit.fill),
                            ),
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _CropPainter(
                                  crop: _crop,
                                  offset: off,
                                  scale: scale,
                                  imageRect: off & dest,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        for (final e in const [
                          ('Free', null),
                          ('1:1', 1.0),
                          ('4:5', 4 / 5),
                          ('3:4', 3 / 4),
                          ('4:3', 4 / 3),
                          ('16:9', 16 / 9),
                          ('9:16', 9 / 16),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(e.$1),
                              selected: _ratio == e.$2,
                              onSelected: (_) => _setRatio(e.$2),
                            ),
                          ),
                        TextButton(
                          onPressed: () => setState(() {
                            _ratio = null;
                            _crop = Offset.zero & s;
                          }),
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final Rect crop;
  final Offset offset;
  final double scale;
  final Rect imageRect;
  _CropPainter({
    required this.crop,
    required this.offset,
    required this.scale,
    required this.imageRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTRB(
      offset.dx + crop.left * scale,
      offset.dy + crop.top * scale,
      offset.dx + crop.right * scale,
      offset.dy + crop.bottom * scale,
    );
    // Dim everything outside the crop rectangle.
    final dim = Paint()..color = Colors.black54;
    canvas.drawRect(Rect.fromLTRB(imageRect.left, imageRect.top, imageRect.right, r.top), dim);
    canvas.drawRect(Rect.fromLTRB(imageRect.left, r.bottom, imageRect.right, imageRect.bottom), dim);
    canvas.drawRect(Rect.fromLTRB(imageRect.left, r.top, r.left, r.bottom), dim);
    canvas.drawRect(Rect.fromLTRB(r.right, r.top, imageRect.right, r.bottom), dim);

    final line = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(r, line);
    final grid = Paint()
      ..color = Colors.white54
      ..strokeWidth = 1;
    for (int i = 1; i < 3; i++) {
      canvas.drawLine(Offset(r.left + r.width * i / 3, r.top),
          Offset(r.left + r.width * i / 3, r.bottom), grid);
      canvas.drawLine(Offset(r.left, r.top + r.height * i / 3),
          Offset(r.right, r.top + r.height * i / 3), grid);
    }
    final handle = Paint()..color = Colors.white;
    final hl = math.min(18.0, math.min(r.width, r.height) / 3);
    for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      canvas.drawCircle(c, 8, handle);
    }
    // Edge handles
    for (final c in [
      Offset(r.center.dx, r.top),
      Offset(r.center.dx, r.bottom),
      Offset(r.left, r.center.dy),
      Offset(r.right, r.center.dy),
    ]) {
      canvas.drawCircle(c, hl > 0 ? 5 : 5, handle);
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter o) =>
      o.crop != crop || o.scale != scale || o.offset != offset;
}
