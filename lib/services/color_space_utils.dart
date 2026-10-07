import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Fixes the "colors look oversaturated / too vivid" bug: modern phone
/// cameras (iPhone, many recent Android phones) shoot photos tagged with
/// the Display P3 color profile, which has a wider gamut than sRGB. The
/// `image` package decodes raw pixel bytes without honoring that ICC
/// profile and re-encodes a plain (untagged) file — viewers then assume
/// sRGB, so the wider-gamut P3 values render more saturated than
/// intended. Flutter's own Image widget IS color-managed and shows the
/// original file correctly, which is why the shift only becomes visible
/// once the app has re-encoded the photo (after background removal,
/// export, any of the AI tools, etc).
///
/// Call [normalizeToSrgb] right after decoding any user-provided photo,
/// before doing anything else with its pixels.
class ColorSpaceUtils {
  /// If [image] carries a Display-P3 (or other non-sRGB) ICC profile,
  /// converts its pixel data to sRGB in place and clears the profile tag
  /// (so re-encoded files are correctly untagged plain sRGB instead of
  /// wrongly-untagged wide-gamut data). No-ops for already-sRGB images,
  /// which is the common case and keeps this fast.
  static img.Image normalizeToSrgb(img.Image image) {
    final profile = image.iccProfile;
    if (profile == null) return image; // no embedded profile — assume sRGB

    final name = profile.name.toLowerCase();
    final isP3 = name.contains('p3') || name.contains('display p3');
    final isSrgb = name.contains('srgb');
    if (isSrgb || !isP3) {
      // Either already sRGB, or a profile we don't have a specific
      // conversion for — clearing an sRGB tag is harmless; leaving an
      // unknown one alone avoids guessing wrong.
      if (isSrgb) image.iccProfile = null;
      return image;
    }

    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        final rgb = _p3ToSrgb(p.r / 255.0, p.g / 255.0, p.b / 255.0);
        p
          ..r = (rgb[0] * 255).round().clamp(0, 255)
          ..g = (rgb[1] * 255).round().clamp(0, 255)
          ..b = (rgb[2] * 255).round().clamp(0, 255);
      }
    }
    image.iccProfile = null; // now genuinely sRGB — don't mis-tag it
    return image;
  }

  // Display P3 and sRGB share the same transfer function (gamma curve),
  // so conversion only needs the linear-light primary matrix — no
  // separate EOTF/OETF step required.
  static const List<List<double>> _p3ToSrgbLinearMatrix = [
    [1.2249, -0.2247, 0.0000],
    [-0.0420, 1.0419, 0.0000],
    [-0.0197, -0.0786, 1.0979],
  ];

  static double _srgbToLinear(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  static double _linearToSrgb(double c) => c <= 0.0031308
      ? c * 12.92
      : 1.055 * math.pow(c, 1 / 2.4).toDouble() - 0.055;

  static List<double> _p3ToSrgb(double r, double g, double b) {
    final lr = _srgbToLinear(r), lg = _srgbToLinear(g), lb = _srgbToLinear(b);
    final m = _p3ToSrgbLinearMatrix;
    final outR = m[0][0] * lr + m[0][1] * lg + m[0][2] * lb;
    final outG = m[1][0] * lr + m[1][1] * lg + m[1][2] * lb;
    final outB = m[2][0] * lr + m[2][1] * lg + m[2][2] * lb;
    return [
      _linearToSrgb(outR.clamp(0.0, 1.0)),
      _linearToSrgb(outG.clamp(0.0, 1.0)),
      _linearToSrgb(outB.clamp(0.0, 1.0)),
    ];
  }
}
