import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:path_provider/path_provider.dart';
import '../services/prefs_service.dart';

enum BrushMode { erase, restore, move }

/// Background to composite behind the subject at export time — must match
/// whatever the live preview is showing (see edit_screen.dart).
enum BackgroundChoice { transparent, solid, blur, custom }

/// One continuous drag gesture, recorded as a filled path (built from
/// circles along the drag points) so it can be redrawn every frame and
/// reused for undo/redo. [points] + [brushSize] are kept alongside the
/// built [path] so the stroke can be serialized and rebuilt later (see
/// toJson/fromJson) — a dart:ui Path itself can't be serialized directly.
class BrushStroke {
  final BrushMode mode;
  final Path path;
  final List<Offset> points;
  final double brushSize;

  BrushStroke({
    required this.mode,
    required this.path,
    required this.points,
    required this.brushSize,
  });

  static Path _pathFromPoints(List<Offset> points, double brushSize) {
    final path = Path();
    for (final p in points) {
      path.addOval(Rect.fromCircle(center: p, radius: brushSize / 2));
    }
    return path;
  }

  factory BrushStroke.fromPoints({
    required BrushMode mode,
    required List<Offset> points,
    required double brushSize,
  }) {
    return BrushStroke(
      mode: mode,
      points: points,
      brushSize: brushSize,
      path: _pathFromPoints(points, brushSize),
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'brushSize': brushSize,
        'points': points.map((p) => [p.dx, p.dy]).toList(),
      };

  factory BrushStroke.fromJson(Map<String, dynamic> json) {
    final points = (json['points'] as List)
        .map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
        .toList();
    final brushSize = (json['brushSize'] as num).toDouble();
    final mode = BrushMode.values.firstWhere((m) => m.name == json['mode']);
    return BrushStroke.fromPoints(mode: mode, points: points, brushSize: brushSize);
  }
}

/// Interactive canvas that lets the user erase parts of the AI-processed
/// (background-removed) image, or restore parts of the original image
/// back in — via single-finger drag brush strokes. Two-finger gestures
/// pinch-zoom and pan the canvas instead of drawing.
///
/// Compositing: the processed image is the base; every stroke is then
/// applied in the order it was made (erase punches a soft hole, restore
/// paints the original back through a soft stencil), so a later restore
/// can undo an earlier erase. In Move mode one finger pans the view.
class BrushCanvas extends StatefulWidget {
  final File originalImageFile;
  final File processedImageFile;
  final BrushMode mode;
  final double brushSize;

  /// 0.0 (hard edge) to 1.0 (very soft edge). Maps internally to a
  /// Gaussian blur sigma applied to each stroke's mask.
  final double edgeSoftness;

  /// Called whenever the stroke list changes (add/undo/redo), so the
  /// parent can enable/disable undo/redo buttons etc.
  final ValueChanged<List<BrushStroke>>? onStrokesChanged;

  /// When provided, brush strokes are auto-saved under this key and
  /// restored the next time a BrushCanvas is built with the same key —
  /// e.g. pass the processed image's file path so re-opening the same
  /// edit session brings back prior erase/restore work. Leave null to
  /// disable persistence (session is lost when the widget is disposed).
  final String? sessionKey;

  const BrushCanvas({
    super.key,
    required this.originalImageFile,
    required this.processedImageFile,
    required this.mode,
    required this.brushSize,
    this.edgeSoftness = 0.3,
    this.onStrokesChanged,
    this.sessionKey,
  });

  @override
  State<BrushCanvas> createState() => BrushCanvasState();
}

class BrushCanvasState extends State<BrushCanvas> {
  ui.Image? _originalImage;
  ui.Image? _processedImage;

  final List<BrushStroke> _strokes = [];
  final List<BrushStroke> _redoStack = [];
  Path? _currentPath;
  Offset? _lastPoint;
  List<Offset> _currentPoints = [];

  // Pan/zoom transform state.
  double _scale = 1.0;
  Offset _panOffset = Offset.zero;
  double _gestureStartScale = 1.0;
  Offset _gestureStartPanOffset = Offset.zero;
  Offset _gestureStartFocalPoint = Offset.zero;
  bool _isDrawingGesture = false;
  Size _widgetSize = Size.zero;
  Offset? _cursor; // finger position (widget space) while drawing

  bool get isReady => _originalImage != null && _processedImage != null;
  List<BrushStroke> get strokes => List.unmodifiable(_strokes);
  bool get canUndo => _strokes.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadImages();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final key = widget.sessionKey;
    if (key == null) return;
    final jsonStr = await PrefsService().loadBrushSessionJson(key);
    if (jsonStr == null || !mounted) return;
    try {
      final list = jsonDecode(jsonStr) as List;
      final restored = list
          .map((e) => BrushStroke.fromJson(e as Map<String, dynamic>))
          .toList();
      if (restored.isEmpty) return;
      setState(() => _strokes.addAll(restored));
      widget.onStrokesChanged?.call(strokes);
    } catch (_) {
      // Corrupt/incompatible saved session — ignore and start fresh.
    }
  }

  void _persistSession() {
    final key = widget.sessionKey;
    if (key == null) return;
    final jsonStr = jsonEncode(_strokes.map((s) => s.toJson()).toList());
    PrefsService().saveBrushSessionJson(key, jsonStr);
  }

  @override
  void didUpdateWidget(covariant BrushCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.processedImageFile.path != widget.processedImageFile.path ||
        oldWidget.originalImageFile.path != widget.originalImageFile.path) {
      _strokes.clear();
      _redoStack.clear();
      _loadImages();
    }
  }

  Future<void> _loadImages() async {
    final original = await _decodeFile(widget.originalImageFile);
    final processed = await _decodeFile(widget.processedImageFile);
    if (!mounted) return;
    setState(() {
      _originalImage = original;
      _processedImage = processed;
    });
  }

  Future<ui.Image> _decodeFile(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Converts a point in the widget's screen space into the CustomPaint's
  /// own (untransformed) local coordinate space, undoing the current
  /// pan/zoom so brush strokes always line up with what's drawn.
  Offset _toCanvasSpace(Offset screenPoint) {
    return (screenPoint - _panOffset) / _scale;
  }

  void _addCircle(Path path, Offset center) {
    path.addOval(
      Rect.fromCircle(center: center, radius: widget.brushSize / 2),
    );
  }

  void _startDrawing(Offset canvasPoint) {
    final path = Path();
    _addCircle(path, canvasPoint);
    _currentPath = path;
    _lastPoint = canvasPoint;
    _currentPoints = [canvasPoint];
  }

  void _extendDrawing(Offset canvasPoint) {
    if (_currentPath == null || _lastPoint == null) return;
    final distance = (canvasPoint - _lastPoint!).distance;
    final steps = (distance / (widget.brushSize / 4)).ceil().clamp(1, 50);
    for (int i = 1; i <= steps; i++) {
      final t = i / steps;
      final point = Offset.lerp(_lastPoint!, canvasPoint, t)!;
      _addCircle(_currentPath!, point);
      _currentPoints.add(point);
    }
    _lastPoint = canvasPoint;
  }

  void _endDrawing() {
    if (_currentPath != null) {
      _strokes.add(BrushStroke.fromPoints(
        mode: widget.mode,
        points: _currentPoints,
        brushSize: widget.brushSize,
      ));
      _redoStack.clear(); // new action invalidates redo history
      widget.onStrokesChanged?.call(strokes);
      _persistSession();
    }
    _currentPath = null;
    _lastPoint = null;
    _currentPoints = [];
  }

  void undo() {
    if (_strokes.isEmpty) return;
    setState(() => _redoStack.add(_strokes.removeLast()));
    widget.onStrokesChanged?.call(strokes);
    _persistSession();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    setState(() => _strokes.add(_redoStack.removeLast()));
    widget.onStrokesChanged?.call(strokes);
    _persistSession();
  }

  void clearStrokes() {
    setState(() {
      _strokes.clear();
      _redoStack.clear();
    });
    widget.onStrokesChanged?.call(strokes);
    _persistSession();
  }

  void resetView() {
    setState(() {
      _scale = 1.0;
      _panOffset = Offset.zero;
    });
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartScale = _scale;
    _gestureStartPanOffset = _panOffset;
    _gestureStartFocalPoint = details.focalPoint;
    _isDrawingGesture =
        details.pointerCount == 1 && widget.mode != BrushMode.move;

    if (_isDrawingGesture) {
      HapticFeedback.selectionClick();
      _startDrawing(_toCanvasSpace(details.localFocalPoint));
      setState(() => _cursor = details.localFocalPoint);
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount == 1 && _isDrawingGesture) {
      _extendDrawing(_toCanvasSpace(details.localFocalPoint));
      setState(() => _cursor = details.localFocalPoint);
      return;
    }

    // Two+ fingers (or gesture escalated to a pinch): pan & zoom instead.
    if (_isDrawingGesture) {
      // A second finger touched down mid-stroke — abandon the stroke and
      // switch to pan/zoom so it doesn't leave a stray mark.
      _currentPath = null;
      _lastPoint = null;
      _isDrawingGesture = false;
      _cursor = null;
    }

    setState(() {
      _scale = (_gestureStartScale * details.scale).clamp(0.5, 10.0);
      _panOffset =
          _gestureStartPanOffset + (details.focalPoint - _gestureStartFocalPoint);
    });
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_isDrawingGesture) {
      _endDrawing();
      setState(() => _cursor = null);
    }
    _isDrawingGesture = false;
  }

  double get _featherSigma => widget.edgeSoftness.clamp(0.0, 1.0) * 12.0;

  @override
  Widget build(BuildContext context) {
    if (!isReady) {
      return const Center(child: CircularProgressIndicator());
    }

    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _widgetSize = constraints.biggest;
          return GestureDetector(
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onScaleEnd: _onScaleEnd,
            child: Stack(
              fit: StackFit.expand,
              children: [
            Transform(
              transform: Matrix4.identity()
                ..translate(_panOffset.dx, _panOffset.dy)
                ..scale(_scale),
              child: CustomPaint(
                painter: _BrushPainter(
                  original: _originalImage!,
                  processed: _processedImage!,
                  strokes: _strokes,
                  inProgress: _currentPath,
                  inProgressMode: widget.mode,
                  featherSigma: _featherSigma,
                  inProgressBrush: widget.brushSize,
                ),
                size: Size.infinite,
              ),
            ),
                if (_cursor != null)
                  Positioned(
                    left: _cursor!.dx - widget.brushSize * _scale / 2,
                    top: _cursor!.dy - widget.brushSize * _scale / 2,
                    width: widget.brushSize * _scale,
                    height: widget.brushSize * _scale,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: widget.mode == BrushMode.erase
                                ? Colors.redAccent
                                : Colors.greenAccent,
                            width: 2,
                          ),
                          color: Colors.white24,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Renders the current subject (processed image + all brush edits) over
  /// the chosen [background], at the ORIGINAL image's full resolution
  /// (not the screen's on-screen size), and saves it as a PNG file.
  ///
  /// Stroke paths were recorded in the on-screen widget's coordinate
  /// space, so they're transformed into full-resolution image-pixel space
  /// before being redrawn here.
  Future<File> exportComposite({
    required BackgroundChoice background,
    Color solidColor = Colors.white,
    File? customBackgroundFile,
    File? subjectOverride,
  }) async {
    final imageSize = Size(
      processedImageSize.width,
      processedImageSize.height,
    );

    // Map from on-screen "contain fit" widget space -> full image pixel
    // space, inverting the same fit the painter used while drawing.
    final fittedSizes = applyBoxFit(BoxFit.contain, imageSize, _widgetSize);
    final destSize = fittedSizes.destination;
    final destOffset = Offset(
      (_widgetSize.width - destSize.width) / 2,
      (_widgetSize.height - destSize.height) / 2,
    );

    final scaleX = imageSize.width / destSize.width;
    final scaleY = imageSize.height / destSize.height;
    final toImageSpace = Matrix4.identity()
      ..scale(scaleX, scaleY)
      ..translate(-destOffset.dx, -destOffset.dy);

    final imageSpaceStrokes = _strokes
        .map(
          (s) => BrushStroke(
            mode: s.mode,
            path: s.path.transform(toImageSpace.storage),
            // Only .path is used from here on (rendering the final export);
            // points/brushSize aren't meaningful post-transform.
            points: const [],
            brushSize: s.brushSize,
          ),
        )
        .toList();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, imageSize.width, imageSize.height),
    );
    final fullRect = Offset.zero & imageSize;

    // Background (drawn first, sits beneath everything else).
    switch (background) {
      case BackgroundChoice.transparent:
        break; // leave transparent
      case BackgroundChoice.solid:
        canvas.drawRect(fullRect, Paint()..color = solidColor);
        break;
      case BackgroundChoice.blur:
        canvas.saveLayer(
          fullRect,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        );
        canvas.drawImageRect(
            _originalImage!,
            Offset.zero &
                Size(_originalImage!.width.toDouble(),
                    _originalImage!.height.toDouble()),
            fullRect,
            Paint());
        canvas.restore();
        break;
      case BackgroundChoice.custom:
        if (customBackgroundFile != null) {
          final bytes = await customBackgroundFile.readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          final bgImage = frame.image;
          final bgSize =
              Size(bgImage.width.toDouble(), bgImage.height.toDouble());
          final fitted = applyBoxFit(BoxFit.cover, bgSize, imageSize);
          final srcRect =
              Alignment.center.inscribe(fitted.source, Offset.zero & bgSize);
          canvas.drawImageRect(bgImage, srcRect, fullRect, Paint());
        }
    }

    // Subject: same layered erase/restore/processed compositing as the
    // live preview, but 1:1 with the source image (srcRect == destRect).

    if (subjectOverride != null) {
      final codec =
          await ui.instantiateImageCodec(await subjectOverride.readAsBytes());
      final subj = (await codec.getNextFrame()).image;
      canvas.drawImageRect(
        subj,
        Offset.zero & Size(subj.width.toDouble(), subj.height.toDouble()),
        fullRect,
        Paint()..filterQuality = FilterQuality.high,
      );
    }
    canvas.saveLayer(fullRect, Paint());
    if (subjectOverride == null) {
      canvas.drawImageRect(_processedImage!, fullRect, fullRect,
          Paint()..filterQuality = FilterQuality.high);
    }
    for (final stroke in subjectOverride != null
        ? <BrushStroke>[]
        : imageSpaceStrokes) {
      final mf = _maskFor(_featherSigma * scaleX, stroke.brushSize * scaleX);
      if (stroke.mode == BrushMode.erase) {
        _softDraw(canvas, stroke.path, mf, BlendMode.dstOut);
      } else if (stroke.mode == BrushMode.restore) {
        canvas.saveLayer(fullRect, Paint());
        _softDraw(canvas, stroke.path, mf, BlendMode.srcOver);
        canvas.drawImageRect(
          _originalImage!,
          Offset.zero &
              Size(_originalImage!.width.toDouble(),
                  _originalImage!.height.toDouble()),
          fullRect,
          Paint()
            ..blendMode = BlendMode.srcIn
            ..filterQuality = FilterQuality.high,
        );
        canvas.restore();
      }
    }
    canvas.restore();

    final picture = recorder.endRecording();
    final renderedImage = await picture.toImage(
      imageSize.width.round(),
      imageSize.height.round(),
    );
    final byteData =
        await renderedImage.toByteData(format: ui.ImageByteFormat.png);
    final pngBytes = byteData!.buffer.asUint8List();

    final tempDir = await getTemporaryDirectory();
    final outFile = File(
      '${tempDir.path}/export_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await outFile.writeAsBytes(pngBytes);
    return outFile;
  }

  /// Current view reset helper kept above; returns the edited subject as a
  /// transparent PNG at the processed image's resolution.
  Future<File> bakeTransparent() =>
      exportComposite(background: BackgroundChoice.transparent);

  Size get processedImageSize => Size(
        _processedImage!.width.toDouble(),
        _processedImage!.height.toDouble(),
      );
}

/// Feather blur capped relative to the brush so the stroke core stays solid.
MaskFilter? _maskFor(double sigma, double brush) {
  final s = sigma < brush * 0.15 ? sigma : brush * 0.15;
  return s > 0.3 ? MaskFilter.blur(BlurStyle.normal, s) : null;
}

/// Draws a stroke path soft-edged with a guaranteed solid core.
void _softDraw(Canvas canvas, Path path, MaskFilter? mf, BlendMode mode) {
  final paint = Paint()
    ..color = Colors.black
    ..blendMode = mode;
  if (mf == null) {
    canvas.drawPath(path, paint);
    return;
  }
  canvas.drawPath(path, paint..maskFilter = mf);
  canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black
        ..blendMode = mode
        ..maskFilter = mf);
}

class _BrushPainter extends CustomPainter {
  final ui.Image original;
  final ui.Image processed;
  final List<BrushStroke> strokes;
  final Path? inProgress;
  final BrushMode inProgressMode;
  final double featherSigma;
  final double inProgressBrush;

  _BrushPainter({
    required this.inProgressBrush,
    required this.original,
    required this.processed,
    required this.strokes,
    required this.inProgress,
    required this.inProgressMode,
    required this.featherSigma,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final imageSize = Size(
      processed.width.toDouble(),
      processed.height.toDouble(),
    );

    final fittedSizes = applyBoxFit(BoxFit.contain, imageSize, size);
    final destSize = fittedSizes.destination;
    final offset = Offset(
      (size.width - destSize.width) / 2,
      (size.height - destSize.height) / 2,
    );
    final destRect = offset & destSize;
    final srcRect = Offset.zero & imageSize;

    final allStrokes = [
      ...strokes,
      if (inProgress != null)
        BrushStroke(
          mode: inProgressMode,
          path: inProgress!,
          points: const [],
          brushSize: 0,
        ),
    ];

    canvas.saveLayer(Offset.zero & size, Paint());

    final filter = FilterQuality.medium;

    // Base: processed image, then every stroke in the order it was made,
    // so a later restore can bring back what an earlier erase removed.
    canvas.drawImageRect(
        processed, srcRect, destRect, Paint()..filterQuality = filter);
    for (final stroke in allStrokes) {
      final bs = stroke.brushSize > 0 ? stroke.brushSize : inProgressBrush;
      final mf = _maskFor(featherSigma, bs);
      if (stroke.mode == BrushMode.erase) {
        _softDraw(canvas, stroke.path, mf, BlendMode.dstOut);
      } else if (stroke.mode == BrushMode.restore) {
        canvas.saveLayer(Offset.zero & size, Paint());
        _softDraw(canvas, stroke.path, mf, BlendMode.srcOver);
        canvas.drawImageRect(
          original,
          Offset.zero &
              Size(original.width.toDouble(), original.height.toDouble()),
          destRect,
          Paint()
            ..blendMode = BlendMode.srcIn
            ..filterQuality = filter,
        );
        canvas.restore();
      }
    }

    canvas.restore(); // finish outer saveLayer
  }

  @override
  bool shouldRepaint(covariant _BrushPainter oldDelegate) => true;
}
