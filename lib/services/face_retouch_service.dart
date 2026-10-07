import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'color_space_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'tool_utils.dart';

/// Skin smoothing WITHOUT any AI model.
///
/// It finds skin-colored pixels (YCbCr chroma thresholds, which work across
/// skin tones), feathers that mask, and blends a blurred copy of the photo
/// into those areas. Because it is color-based rather than face detection:
///  * it smooths ANY skin-toned area (hands, arms), and
///  * it can also soften skin-toned objects (wood, sand) in the frame.
/// Keep [strength] moderate for natural results.
class FaceRetouchService {
  static const int _maxSide = 2048;

  Future<File> smoothSkin(File input, {double strength = 0.6}) async {
    final decoded0 = img.decodeImage(await input.readAsBytes());
    if (decoded0 == null) throw Exception('Could not decode image');
    var photo = ColorSpaceUtils.normalizeToSrgb(img.bakeOrientation(decoded0));
    final longSide = math.max(photo.width, photo.height);
    if (longSide > _maxSide) {
      final s = _maxSide / longSide;
      photo = img.copyResize(
        photo,
        width: (photo.width * s).round(),
        height: (photo.height * s).round(),
        interpolation: img.Interpolation.linear,
      );
    }
    final W = photo.width, H = photo.height;
    final amount = strength.clamp(0.0, 1.0) * 0.85;

    // Blurred copy = the "smooth skin" layer.
    final blurRadius = (math.max(W, H) / 220).round().clamp(2, 10).toInt();
    final blurred = img.gaussianBlur(img.Image.from(photo), radius: blurRadius);

    // Skin mask from chroma (Cb/Cr), ignoring very dark pixels.
    var mask = Float32List(W * H);
    for (int y = 0; y < H; y++) {
      for (int x = 0; x < W; x++) {
        final p = photo.getPixel(x, y);
        final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
        final lum = 0.299 * r + 0.587 * g + 0.114 * b;
        final cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
        final cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
        final isSkin = lum > 40 && cb >= 77 && cb <= 127 && cr >= 133 && cr <= 173;
        mask[y * W + x] = isSkin ? 1.0 : 0.0;
      }
    }
    final feather = (math.max(W, H) / 150).round().clamp(2, 14).toInt();
    mask = ToolUtils.boxBlur(mask, W, H, feather);
    mask = ToolUtils.boxBlur(mask, W, H, feather);

    for (int y = 0; y < H; y++) {
      for (int x = 0; x < W; x++) {
        final a = mask[y * W + x] * amount;
        if (a <= 0.005) continue;
        final o = photo.getPixel(x, y);
        final s = blurred.getPixel(x, y);
        photo.setPixelRgb(
          x,
          y,
          o.r * (1 - a) + s.r * a,
          o.g * (1 - a) + s.g * a,
          o.b * (1 - a) + s.b * a,
        );
      }
    }

    final dir = await getTemporaryDirectory();
    final out = File(
      '${dir.path}/retouched_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await out.writeAsBytes(img.encodeJpg(photo, quality: 95));
    return out;
  }
}
