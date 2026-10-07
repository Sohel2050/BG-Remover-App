import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Effects that work on an already background-removed PNG. For best
/// results, use an export with a TRANSPARENT background (so the alpha
/// channel is meaningful) — these effects rely on real per-pixel alpha.
class AdvancedEffects {
  static Future<ui.Image> _decode(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  static Future<File> _saveCanvas(
    ui.PictureRecorder recorder,
    Size size,
    String prefix,
  ) async {
    final picture = recorder.endRecording();
    final rendered =
        await picture.toImage(size.width.round(), size.height.round());
    final byteData =
        await rendered.toByteData(format: ui.ImageByteFormat.png);
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(byteData!.buffer.asUint8List());
    return file;
  }

  /// "Sticker" look: a solid-color outline traced around the subject's
  /// silhouette, achieved by stamping a solid-colored copy of the image at
  /// several offsets around a ring (a cheap but effective dilation), then
  /// drawing the original on top.
  static Future<File> addStickerOutline(
    File input, {
    required Color outlineColor,
    double thickness = 12,
  }) async {
    final image = await _decode(input);
    final size = Size(image.width.toDouble(), image.height.toDouble());
    final rect = Offset.zero & size;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, rect);

    final silhouettePaint = Paint()
      ..colorFilter = ColorFilter.mode(outlineColor, BlendMode.srcIn);

    const steps = 16;
    for (int i = 0; i < steps; i++) {
      final angle = (2 * math.pi * i) / steps;
      final dx = thickness * math.cos(angle);
      final dy = thickness * math.sin(angle);
      canvas.drawImageRect(
        image,
        rect,
        rect.translate(dx, dy),
        silhouettePaint,
      );
    }

    canvas.drawImageRect(image, rect, rect, Paint());

    return _saveCanvas(recorder, size, 'sticker');
  }

  /// Drop shadow beneath the subject — a blurred, offset, tinted-black
  /// copy of the subject's own alpha silhouette, drawn under the subject.
  static Future<File> addDropShadow(
    File input, {
    Offset offset = const Offset(12, 16),
    double blurSigma = 14,
    double opacity = 0.45,
  }) async {
    final image = await _decode(input);
    final size = Size(image.width.toDouble(), image.height.toDouble());
    final rect = Offset.zero & size;

    final recorder = ui.PictureRecorder();
    // Canvas is padded so the offset shadow doesn't get clipped.
    final padded = Size(size.width + offset.dx.abs() * 2,
        size.height + offset.dy.abs() * 2);
    final canvas = Canvas(recorder, Offset.zero & padded);
    final origin = Offset(offset.dx.abs(), offset.dy.abs());

    // Shadow layer.
    canvas.saveLayer(
      Offset.zero & padded,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
    );
    canvas.drawImageRect(
      image,
      rect,
      (origin + offset) & size,
      Paint()
        ..colorFilter = ColorFilter.mode(
          Colors.black.withOpacity(opacity),
          BlendMode.srcIn,
        ),
    );
    canvas.restore();

    // Subject on top, un-shifted.
    canvas.drawImageRect(image, rect, origin & size, Paint());

    return _saveCanvas(recorder, padded, 'shadow');
  }

  /// Places text behind the subject. Works correctly (text hidden behind
  /// opaque subject pixels) when [input] still has real transparency;
  /// otherwise it just renders as a text overlay behind a flat image.
  static Future<File> addTextBehindSubject(
    File input, {
    required String text,
    required Color textColor,
    double fontSize = 64,
    FontWeight fontWeight = FontWeight.bold,
    Alignment alignment = Alignment.center,
  }) async {
    final image = await _decode(input);
    final size = Size(image.width.toDouble(), image.height.toDouble());
    final rect = Offset.zero & size;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, rect);

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: textColor,
          fontSize: fontSize,
          fontWeight: fontWeight,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: size.width * 0.9);

    final textOffset = Offset(
      (size.width - textPainter.width) / 2 +
          alignment.x * (size.width - textPainter.width) / 2,
      (size.height - textPainter.height) / 2 +
          alignment.y * (size.height - textPainter.height) / 2,
    );

    textPainter.paint(canvas, textOffset);
    canvas.drawImageRect(image, rect, rect, Paint());

    return _saveCanvas(recorder, size, 'text_behind');
  }

  /// Overlays [text] as a watermark (e.g. a signature or brand name) at
  /// the given corner, or overlays a [logoFile] image instead if provided.
  /// Position options: bottomRight (default), bottomLeft, topRight, topLeft,
  /// center.
  static Future<File> addWatermark(
    File input, {
    String? text,
    File? logoFile,
    Color textColor = Colors.white,
    double fontSize = 28,
    double opacity = 0.7,
    Alignment position = Alignment.bottomRight,
    double marginPercent = 0.04,
  }) async {
    final image = await _decode(input);
    final size = Size(image.width.toDouble(), image.height.toDouble());
    final rect = Offset.zero & size;
    final margin = size.width * marginPercent;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, rect);
    canvas.drawImageRect(image, rect, rect, Paint());

    if (logoFile != null) {
      final logoBytes = await logoFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(logoBytes);
      final frame = await codec.getNextFrame();
      final logo = frame.image;

      // Logo width = ~20% of the image width, aspect-ratio preserved.
      final logoTargetWidth = size.width * 0.2;
      final logoScale = logoTargetWidth / logo.width;
      final logoSize = Size(logoTargetWidth, logo.height * logoScale);

      final logoOffset = _alignedOffset(position, size, logoSize, margin);
      final paint = Paint()..color = Colors.white.withOpacity(opacity);
      canvas.drawImageRect(
        logo,
        Offset.zero & Size(logo.width.toDouble(), logo.height.toDouble()),
        logoOffset & logoSize,
        paint,
      );
    } else if (text != null && text.trim().isNotEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: textColor.withOpacity(opacity),
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final textOffset = _alignedOffset(
        position,
        size,
        Size(textPainter.width, textPainter.height),
        margin,
      );
      textPainter.paint(canvas, textOffset);
    }

    return _saveCanvas(recorder, size, 'watermark');
  }

  static Offset _alignedOffset(
    Alignment alignment,
    Size canvasSize,
    Size contentSize,
    double margin,
  ) {
    double x, y;
    if (alignment.x <= -0.5) {
      x = margin;
    } else if (alignment.x >= 0.5) {
      x = canvasSize.width - contentSize.width - margin;
    } else {
      x = (canvasSize.width - contentSize.width) / 2;
    }
    if (alignment.y <= -0.5) {
      y = margin;
    } else if (alignment.y >= 0.5) {
      y = canvasSize.height - contentSize.height - margin;
    } else {
      y = (canvasSize.height - contentSize.height) / 2;
    }
    return Offset(x, y);
  }

  /// Adds a decorative frame/border around the image.
  /// styles: 'solid' (single color band), 'double' (thin+thick double line),
  /// 'polaroid' (white border with a larger bottom margin, classic look).
  static Future<File> addFrame(
    File input, {
    String style = 'solid',
    Color color = Colors.white,
    double thicknessPercent = 0.04,
  }) async {
    final image = await _decode(input);
    final imgW = image.width.toDouble();
    final imgH = image.height.toDouble();
    final thickness = imgW * thicknessPercent;

    late Size canvasSize;
    late Offset imageOffset;
    double bottomExtra = 0;

    if (style == 'polaroid') {
      bottomExtra = thickness * 2.5; // extra white space at the bottom
      canvasSize = Size(imgW + thickness * 2, imgH + thickness * 2 + bottomExtra);
      imageOffset = Offset(thickness, thickness);
    } else {
      canvasSize = Size(imgW + thickness * 2, imgH + thickness * 2);
      imageOffset = Offset(thickness, thickness);
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & canvasSize);

    // Background = frame color.
    canvas.drawRect(Offset.zero & canvasSize, Paint()..color = color);

    if (style == 'double') {
      // Thin inner accent line just outside the photo.
      final lineThickness = thickness * 0.15;
      final lineRect = Rect.fromLTWH(
        imageOffset.dx - lineThickness,
        imageOffset.dy - lineThickness,
        imgW + lineThickness * 2,
        imgH + lineThickness * 2,
      );
      canvas.drawRect(
        lineRect,
        Paint()
          ..color = Colors.black.withOpacity(0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = lineThickness,
      );
    }

    canvas.drawImageRect(
      image,
      Offset.zero & Size(imgW, imgH),
      imageOffset & Size(imgW, imgH),
      Paint(),
    );

    return _saveCanvas(recorder, canvasSize, 'framed');
  }

  /// Simple auto-enhance: stretches the histogram (auto contrast) and
  /// nudges saturation slightly, using the `image` package.
  static Future<File> autoEnhance(File input) async {
    final bytes = await input.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Could not decode image');

    var enhanced = img.normalize(decoded, min: 0, max: 255);
    enhanced = img.adjustColor(enhanced, saturation: 1.1, contrast: 1.05);

    final pngBytes = img.encodePng(enhanced);
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/enhanced_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(pngBytes);
    return file;
  }
}

