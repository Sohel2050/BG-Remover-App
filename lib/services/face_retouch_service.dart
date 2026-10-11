import 'dart:io';
import 'dart:isolate';

import 'package:path_provider/path_provider.dart';

import 'image_decode.dart';
import 'image_ops.dart';

/// Skin smoothing WITHOUT any AI model.
///
/// It finds skin-colored pixels (YCbCr chroma thresholds, which work across
/// skin tones), feathers that mask, and blends a blurred copy of the photo
/// into those areas. Because it is color-based rather than face detection:
///  * it smooths ANY skin-toned area (hands, arms), and
///  * it can also soften skin-toned objects (wood, sand) in the frame.
/// Uses an edge-preserving filter so eyes, lips and hair stay sharp.
/// Keep [strength] moderate for natural results.
///
/// The pixel work runs in a background isolate so the screen stays
/// responsive.
class FaceRetouchService {
  static const int _maxSide = 1800;

  Future<File> smoothSkin(File input, {double strength = 0.6}) async {
    final photo = await ImageDecode.fromFile(input, maxSide: _maxSide);
    final w = photo.width, h = photo.height;
    final rgb = ImageDecode.rgbBytes(photo);

    final jpg = await Isolate.run(() => smoothSkinJpg(rgb, w, h, strength));

    final dir = await getTemporaryDirectory();
    final out = File(
      '${dir.path}/retouched_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    await out.writeAsBytes(jpg);
    return out;
  }
}
