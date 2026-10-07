import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../services/inpaint_service.dart';
import '../widgets/tool_error.dart';
import 'export_screen.dart';

/// Paint over unwanted things, tap Remove, and LaMa fills them in.
/// You can remove several objects one after another; Undo steps back.
class ObjectRemovalScreen extends StatefulWidget {
  final File image;
  const ObjectRemovalScreen({super.key, required this.image});

  @override
  State<ObjectRemovalScreen> createState() => _ObjectRemovalScreenState();
}

class _ObjectRemovalScreenState extends State<ObjectRemovalScreen> {
  final InpaintService _service = InpaintService();
  late File _current;
  final List<File> _history = [];
  final List<MaskStroke> _strokes = [];
  List<Offset> _drawing = [];
  double _brushPx = 36;
  Size? _imageSize;
  Rect _imageRect = Rect.zero;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _current = widget.image;
    _loadSize();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _loadSize() async {
    final bytes = await _current.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = Size(
      frame.image.width.toDouble(),
      frame.image.height.toDouble(),
    );
    frame.image.dispose();
    codec.dispose();
    if (mounted) setState(() => _imageSize = size);
  }

  Offset _toNormalized(Offset local) {
    final dx = (local.dx - _imageRect.left) / _imageRect.width;
    final dy = (local.dy - _imageRect.top) / _imageRect.height;
    return Offset(dx.clamp(0.0, 1.0), dy.clamp(0.0, 1.0));
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      final result = await _service.removeObjects(_current, _strokes);
      _history.add(_current);
      _current = result;
      _strokes.clear();
      await _loadSize();
    } catch (e) {
      showToolError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo() async {
    if (_strokes.isNotEmpty) {
      setState(() => _strokes.removeLast());
    } else if (_history.isNotEmpty) {
      _current = _history.removeLast();
      await _loadSize();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUndo = _strokes.isNotEmpty || _history.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Object Removal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
            onPressed: (!_busy && canUndo) ? _undo : null,
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ExportScreen(exportedFile: _current),
                    )),
            child: const Text('Done'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _imageSize == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final fitted = applyBoxFit(
                        BoxFit.contain,
                        _imageSize!,
                        constraints.biggest,
                      );
                      _imageRect = Alignment.center.inscribe(
                        fitted.destination,
                        Offset.zero & constraints.biggest,
                      );
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(_current, fit: BoxFit.contain),
                          GestureDetector(
                            onPanStart: _busy
                                ? null
                                : (d) => setState(() =>
                                    _drawing = [_toNormalized(d.localPosition)]),
                            onPanUpdate: _busy
                                ? null
                                : (d) => setState(() => _drawing
                                    .add(_toNormalized(d.localPosition))),
                            onPanEnd: _busy
                                ? null
                                : (_) {
                                    if (_drawing.isNotEmpty) {
                                      setState(() {
                                        _strokes.add(MaskStroke(
                                          List.of(_drawing),
                                          (_brushPx / 2) / _imageRect.width,
                                        ));
                                        _drawing = [];
                                      });
                                    }
                                  },
                            child: CustomPaint(
                              painter: _MaskPainter(
                                strokes: _strokes,
                                drawing: _drawing,
                                drawingRadiusNorm:
                                    (_brushPx / 2) / (_imageRect.width == 0 ? 1 : _imageRect.width),
                                rect: _imageRect,
                              ),
                            ),
                          ),
                          if (_busy)
                            Container(
                              color: Colors.black54,
                              alignment: Alignment.center,
                              child: const Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(),
                                  SizedBox(height: 12),
                                  Text(
                                    'Removing… this can take a few seconds',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.brush, size: 18),
                      Expanded(
                        child: Slider(
                          value: _brushPx,
                          min: 12,
                          max: 100,
                          onChanged: (v) => setState(() => _brushPx = v),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: (_busy || _strokes.isEmpty)
                              ? null
                              : () => setState(_strokes.clear),
                          child: const Text('Clear paint'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              (_busy || _strokes.isEmpty) ? null : _remove,
                          icon: const Icon(Icons.auto_fix_high),
                          label: const Text('Remove'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Paint fully over the object (a little beyond its edges).',
                    style: Theme.of(context).textTheme.bodySmall,
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

class _MaskPainter extends CustomPainter {
  final List<MaskStroke> strokes;
  final List<Offset> drawing;
  final double drawingRadiusNorm;
  final Rect rect;

  _MaskPainter({
    required this.strokes,
    required this.drawing,
    required this.drawingRadiusNorm,
    required this.rect,
  });

  void _paintStroke(Canvas canvas, List<Offset> pts, double radiusNorm) {
    if (pts.isEmpty || rect.width == 0) return;
    final paint = Paint()
      ..color = Colors.redAccent.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = radiusNorm * 2 * rect.width;
    Offset toScreen(Offset n) =>
        Offset(rect.left + n.dx * rect.width, rect.top + n.dy * rect.height);
    if (pts.length == 1) {
      canvas.drawCircle(
        toScreen(pts.first),
        radiusNorm * rect.width,
        paint..style = PaintingStyle.fill,
      );
      return;
    }
    final path = Path()..moveTo(toScreen(pts.first).dx, toScreen(pts.first).dy);
    for (final p in pts.skip(1)) {
      final s = toScreen(p);
      path.lineTo(s.dx, s.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      _paintStroke(canvas, s.points, s.radiusNorm);
    }
    _paintStroke(canvas, drawing, drawingRadiusNorm);
  }

  @override
  bool shouldRepaint(covariant _MaskPainter old) => true;
}
