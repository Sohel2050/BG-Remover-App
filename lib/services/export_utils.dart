import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Common aspect ratios / fixed sizes used by social presets and ID photos.
class SizePreset {
  final String label;
  final int width;
  final int height;
  const SizePreset(this.label, this.width, this.height);
}

class ExportUtils {
  static const List<SizePreset> socialPresets = [
    SizePreset('Instagram Post (1:1)', 1080, 1080),
    SizePreset('Instagram Story (9:16)', 1080, 1920),
    SizePreset('Facebook Cover', 820, 312),
    SizePreset('Twitter/X Post', 1200, 675),
  ];

  static const List<SizePreset> idPhotoPresets = [
    SizePreset('Passport (2x2 in @300dpi)', 600, 600),
    SizePreset('Visa Photo (35x45mm @300dpi)', 413, 531),
  ];

  /// Rotates the image 90 degrees clockwise (call 3x for counter-clockwise).
  static Future<File> rotate90(File input) async {
    final bytes = await input.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Could not decode image');
    final rotated = img.copyRotate(decoded, angle: 90);
    return _saveTemp(rotated, 'rotated');
  }

  /// Crops to the given target aspect ratio (width/height), centered,
  /// then optionally resizes to exact preset dimensions.
  static Future<File> cropToAspectAndResize(
    File input, {
    required int targetWidth,
    required int targetHeight,
  }) async {
    final bytes = await input.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Could not decode image');

    final targetRatio = targetWidth / targetHeight;
    final currentRatio = decoded.width / decoded.height;

    img.Image cropped;
    if (currentRatio > targetRatio) {
      // Too wide — crop left/right.
      final newWidth = (decoded.height * targetRatio).round();
      final x = ((decoded.width - newWidth) / 2).round();
      cropped = img.copyCrop(
        decoded,
        x: x,
        y: 0,
        width: newWidth,
        height: decoded.height,
      );
    } else {
      // Too tall — crop top/bottom.
      final newHeight = (decoded.width / targetRatio).round();
      final y = ((decoded.height - newHeight) / 2).round();
      cropped = img.copyCrop(
        decoded,
        x: 0,
        y: y,
        width: decoded.width,
        height: newHeight,
      );
    }

    final resized = img.copyResize(
      cropped,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.linear,
    );

    return _saveTemp(resized, 'cropped');
  }

  /// Applies brightness (-100..100) and contrast (-100..100) adjustments.
  static Future<File> applyBrightnessContrast(
    File input, {
    required double brightness,
    required double contrast,
  }) async {
    final bytes = await input.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Could not decode image');

    final adjusted = img.adjustColor(
      decoded,
      brightness: 1.0 + (brightness / 100),
      contrast: 1.0 + (contrast / 100),
    );

    return _saveTemp(adjusted, 'adjusted');
  }

  /// Crops tightly around the subject using the image's own alpha channel
  /// — no extra AI model needed, since the background-removal step already
  /// produced per-pixel transparency. Finds the bounding box of all
  /// non-transparent pixels (above [alphaThreshold]) and crops to it, with
  /// an optional [paddingPercent] of breathing room on each side.
  static Future<File> autoCropToSubject(
    File input, {
    int alphaThreshold = 10,
    double paddingPercent = 0.05,
  }) async {
    final bytes = await input.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Could not decode image');

    if (!decoded.hasAlpha) {
      // No transparency to crop to (e.g. background was already flattened
      // to solid/blur) — nothing meaningful to do, return as-is.
      return _saveTemp(decoded, 'autocrop');
    }

    int minX = decoded.width, minY = decoded.height, maxX = 0, maxY = 0;
    bool foundAny = false;

    for (int y = 0; y < decoded.height; y++) {
      for (int x = 0; x < decoded.width; x++) {
        final alpha = decoded.getPixel(x, y).a;
        if (alpha > alphaThreshold) {
          foundAny = true;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (!foundAny) {
      throw Exception('No visible subject found (image is fully transparent)');
    }

    // Add padding around the tight bounding box.
    final boxWidth = maxX - minX + 1;
    final boxHeight = maxY - minY + 1;
    final padX = (boxWidth * paddingPercent).round();
    final padY = (boxHeight * paddingPercent).round();

    final cropX = (minX - padX).clamp(0, decoded.width - 1);
    final cropY = (minY - padY).clamp(0, decoded.height - 1);
    final cropRight = (maxX + padX).clamp(0, decoded.width - 1);
    final cropBottom = (maxY + padY).clamp(0, decoded.height - 1);

    final cropped = img.copyCrop(
      decoded,
      x: cropX,
      y: cropY,
      width: cropRight - cropX + 1,
      height: cropBottom - cropY + 1,
    );

    return _saveTemp(cropped, 'autocrop');
  }

  static Future<File> _saveTemp(img.Image image, String prefix) async {
    final pngBytes = img.encodePng(image);
    final tempDir = await getTemporaryDirectory();
    final file = File(
      '${tempDir.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(pngBytes);
    return file;
  }
}
