import 'dart:io';
import 'dart:ui' as ui;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'image_decode.dart';

/// Crops image files by a rectangle given in fractions (0..1) of the image,
/// so the same rectangle can be applied to the original photo and to the
/// cut-out even when their pixel sizes differ.
class CropService {
  /// Opaque photo -> JPEG (high quality).
  static Future<File> cropPhoto(File file, ui.Rect norm) async {
    final src = await ImageDecode.fromFile(file, maxSide: 4096);
    final x = (norm.left * src.width).round().clamp(0, src.width - 1).toInt();
    final y = (norm.top * src.height).round().clamp(0, src.height - 1).toInt();
    final w = (norm.width * src.width).round().clamp(1, src.width - x).toInt();
    final h =
        (norm.height * src.height).round().clamp(1, src.height - y).toInt();
    final out = img.copyCrop(src, x: x, y: y, width: w, height: h);
    final dir = await getTemporaryDirectory();
    final f = File(
        '${dir.path}/crop_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await f.writeAsBytes(img.encodeJpg(out, quality: 95));
    return f;
  }

  /// Image with transparency -> PNG (alpha kept).
  static Future<File> cropPng(File file, ui.Rect norm) async {
    final codec = await ui.instantiateImageCodec(await file.readAsBytes());
    final im = (await codec.getNextFrame()).image;
    final sx = norm.left * im.width, sy = norm.top * im.height;
    final sw = (norm.width * im.width).clamp(1, im.width).toDouble();
    final sh = (norm.height * im.height).clamp(1, im.height).toDouble();
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.drawImageRect(
      im,
      ui.Rect.fromLTWH(sx, sy, sw, sh),
      ui.Rect.fromLTWH(0, 0, sw.roundToDouble(), sh.roundToDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final res = await rec.endRecording().toImage(sw.round(), sh.round());
    final bd = await res.toByteData(format: ui.ImageByteFormat.png);
    im.dispose();
    res.dispose();
    final dir = await getTemporaryDirectory();
    final f = File(
        '${dir.path}/crop_${DateTime.now().microsecondsSinceEpoch}.png');
    await f.writeAsBytes(bd!.buffer.asUint8List());
    return f;
  }
}
