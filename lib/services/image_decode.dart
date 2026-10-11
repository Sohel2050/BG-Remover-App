import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

import 'color_space_utils.dart';

/// Opens photos for the editing tools.
///
/// The phone's own image decoder is used first. It is colour-managed,
/// applies the camera's rotation and handles every JPEG variant. The pure
/// Dart `image` decoder can show a green tint on some camera photos, so it
/// is only the fallback.
///
/// Photos longer than [maxSide] are decoded at a smaller size so a 50+ MP
/// camera photo cannot run the phone out of memory.
class ImageDecode {
  /// Exact RGBA pixels (alpha preserved) of an image file, via the native codec.
  static Future<({Uint8List rgba, int width, int height})> rgbaFromFile(
    File file,
  ) async {
    final codec = await ui.instantiateImageCodec(await file.readAsBytes());
    final frame = await codec.getNextFrame();
    final im = frame.image;
    final bd = await im.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    final res = (
      rgba: Uint8List.fromList(bd!.buffer.asUint8List()),
      width: im.width,
      height: im.height,
    );
    im.dispose();
    return res;
  }

  static Future<img.Image> fromFile(File file, {int maxSide = 4096}) async {
    return fromBytes(await file.readAsBytes(), maxSide: maxSide);
  }

  static Future<img.Image> fromBytes(
    Uint8List bytes, {
    int maxSide = 4096,
  }) async {
    try {
      final native = await _nativeDecode(bytes, maxSide);
      if (native != null) return native;
    } catch (_) {
      // Fall back to the Dart decoder below.
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('Could not decode image');
    var out = ColorSpaceUtils.normalizeToSrgb(img.bakeOrientation(decoded));
    final longSide = math.max(out.width, out.height);
    if (longSide > maxSide) {
      final k = maxSide / longSide;
      out = img.copyResize(
        out,
        width: (out.width * k).round(),
        height: (out.height * k).round(),
        interpolation: img.Interpolation.linear,
      );
    }
    return out.numChannels == 3 ? out : out.convert(numChannels: 3);
  }

  static Future<img.Image?> _nativeDecode(Uint8List bytes, int maxSide) async {
    int? targetWidth;
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final w = descriptor.width, h = descriptor.height;
      descriptor.dispose();
      final longSide = math.max(w, h);
      if (longSide > maxSide) {
        targetWidth = math.max(1, (w * maxSide / longSide).round());
      }
    } finally {
      buffer.dispose();
    }

    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: targetWidth,
    );
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) return null;
        final rgba = img.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: data.buffer,
          numChannels: 4,
          order: img.ChannelOrder.rgba,
        );
        return rgba.convert(numChannels: 3);
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  /// Raw RGB bytes (3 per pixel) in a buffer that starts at offset 0, ready
  /// to send to a background isolate.
  static Uint8List rgbBytes(img.Image image) {
    return Uint8List.fromList(image.getBytes(order: img.ChannelOrder.rgb));
  }
}
