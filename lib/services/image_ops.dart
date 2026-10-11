import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'mask_ops.dart';

// Heavy pixel work lives here as plain top-level functions with only
// simple arguments (byte lists, ints, doubles) so the services can run it
// in a background isolate with Isolate.run and keep the UI responsive.
// This file must not import Flutter.

int _ci(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

// ---------------------------------------------------------------------
// Background removal (U2Net / ISNet)
// ---------------------------------------------------------------------

/// Resizes to [size]x[size], scales by the image max and normalizes the
/// way U2Net / ISNet were trained. Returns channel-first float data.
Float32List prepareSalientInput(
  Uint8List rgb,
  int w,
  int h,
  int size,
  bool isnet,
) {
  final src = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: rgb.buffer,
    numChannels: 3,
  );
  final resized = img.copyResize(
    src,
    width: size,
    height: size,
    interpolation: img.Interpolation.cubic,
  );
  final px = resized.getBytes(order: img.ChannelOrder.rgb);
  final plane = size * size;

  int maxV = 1;
  for (int i = 0; i < plane * 3; i++) {
    if (px[i] > maxV) maxV = px[i];
  }
  final mean = isnet ? const [0.5, 0.5, 0.5] : const [0.485, 0.456, 0.406];
  final std = isnet ? const [1.0, 1.0, 1.0] : const [0.229, 0.224, 0.225];

  final out = Float32List(3 * plane);
  for (int i = 0; i < plane; i++) {
    out[i] = (px[3 * i] / maxV - mean[0]) / std[0];
    out[plane + i] = (px[3 * i + 1] / maxV - mean[1]) / std[1];
    out[2 * plane + i] = (px[3 * i + 2] / maxV - mean[2]) / std[2];
  }
  return out;
}

/// Turns the raw model output into a clean alpha mask, applies it to the
/// photo and returns a transparent PNG.
Uint8List composeCutoutPng(
  Uint8List rgb,
  int w,
  int h,
  Float32List raw,
  int size,
) {
  final n = size * size;
  final norm = _normalize01(raw, n);
  var mask = _cleanSalientMask(norm, size, size);
  // Safety net: if cleaning left (almost) nothing, fall back to the raw
  // normalized matte so the result is never an empty image.
  double cover = 0;
  for (int i = 0; i < n; i++) {
    cover += mask[i];
  }
  if (cover / n < 0.002) {
    mask = Float32List(n);
    for (int i = 0; i < n; i++) {
      final v = (norm[i] - 0.35) / 0.3;
      mask[i] = v < 0 ? 0 : (v > 1 ? 1 : v);
    }
  }
  final alpha = _resizeMaskToBytes(mask, size, size, w, h);

  final out = Uint8List(w * h * 4);
  for (int i = 0; i < w * h; i++) {
    out[4 * i] = rgb[3 * i];
    out[4 * i + 1] = rgb[3 * i + 1];
    out[4 * i + 2] = rgb[3 * i + 2];
    out[4 * i + 3] = alpha[i];
  }
  final px = (math.max(w, h) / 1000).round().clamp(1, 4).toInt();
  return refineEdgePng(out, w, h, px, 1);
}

Float32List _normalize01(Float32List m, int n) {
  double minV = m[0], maxV = m[0];
  for (int i = 0; i < n; i++) {
    if (m[i] < minV) minV = m[i];
    if (m[i] > maxV) maxV = m[i];
  }
  final range = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);
  final out = Float32List(n);
  for (int i = 0; i < n; i++) {
    final v = (m[i] - minV) / range;
    out[i] = v < 0 ? 0 : (v > 1 ? 1 : v);
  }
  return out;
}

/// Keeps the main subject (and other big regions), drops small stray
/// blobs, and applies a gentle alpha curve that favors keeping the face,
/// body and clothes while staying soft at the edges.
Float32List _cleanSalientMask(Float32List m, int w, int h) {
  final labels = Int32List(w * h);
  final areas = <int>[0];
  int next = 0;
  final stack = <int>[];
  for (int s = 0; s < w * h; s++) {
    if (m[s] < 0.45 || labels[s] != 0) continue;
    next++;
    int area = 0;
    labels[s] = next;
    stack.add(s);
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      area++;
      final x = p % w, y = p ~/ w;
      if (x > 0 && m[p - 1] >= 0.45 && labels[p - 1] == 0) {
        labels[p - 1] = next;
        stack.add(p - 1);
      }
      if (x < w - 1 && m[p + 1] >= 0.45 && labels[p + 1] == 0) {
        labels[p + 1] = next;
        stack.add(p + 1);
      }
      if (y > 0 && m[p - w] >= 0.45 && labels[p - w] == 0) {
        labels[p - w] = next;
        stack.add(p - w);
      }
      if (y < h - 1 && m[p + w] >= 0.45 && labels[p + w] == 0) {
        labels[p + w] = next;
        stack.add(p + w);
      }
    }
    areas.add(area);
  }

  Float32List keep = Float32List(w * h);
  if (next > 0) {
    int biggest = 0;
    for (int i = 1; i <= next; i++) {
      biggest = math.max(biggest, areas[i]);
    }
    // Keep any region at least 12% the size of the largest one.
    for (int p = 0; p < w * h; p++) {
      final l = labels[p];
      if (l != 0 && areas[l] >= biggest * 0.12) keep[p] = 1;
    }
    keep = MaskOps.dilate(keep, w, h, math.max(2, w ~/ 64));
  } else {
    keep.fillRange(0, w * h, 1);
  }

  // Alpha curve: below 0.15 gone, above 0.65 solid, smooth in between.
  final out = Float32List(w * h);
  for (int p = 0; p < w * h; p++) {
    double t = (m[p] - 0.15) / 0.5;
    t = t < 0 ? 0 : (t > 1 ? 1 : t);
    out[p] = (t * t * (3 - 2 * t)) * keep[p];
  }
  // Small see-through patches inside the subject (bright skin highlights,
  // shiny cloth) are filled so the face and body stay solid.
  _fillHoles(out, w, h, 0.06);
  return MaskOps.boxBlur(out, w, h, math.max(1, w ~/ 320));
}

/// Fills transparent areas that are completely enclosed by the subject and
/// smaller than [maxShare] of the subject's area. Large gaps (between an
/// arm and the body, for example) stay transparent. Edits [a] in place.
void _fillHoles(Float32List a, int w, int h, double maxShare) {
  final n = w * h;
  final labels = Int32List(n);
  final areas = <int>[0];
  final touchesBorder = <bool>[false];
  final stack = <int>[];
  int solid = 0;
  int next = 0;

  for (int s = 0; s < n; s++) {
    if (a[s] >= 0.5) {
      solid++;
      continue;
    }
    if (labels[s] != 0) continue;
    next++;
    int area = 0;
    bool border = false;
    labels[s] = next;
    stack.add(s);
    while (stack.isNotEmpty) {
      final p = stack.removeLast();
      area++;
      final x = p % w, y = p ~/ w;
      if (x == 0 || y == 0 || x == w - 1 || y == h - 1) border = true;
      if (x > 0 && a[p - 1] < 0.5 && labels[p - 1] == 0) {
        labels[p - 1] = next;
        stack.add(p - 1);
      }
      if (x < w - 1 && a[p + 1] < 0.5 && labels[p + 1] == 0) {
        labels[p + 1] = next;
        stack.add(p + 1);
      }
      if (y > 0 && a[p - w] < 0.5 && labels[p - w] == 0) {
        labels[p - w] = next;
        stack.add(p - w);
      }
      if (y < h - 1 && a[p + w] < 0.5 && labels[p + w] == 0) {
        labels[p + w] = next;
        stack.add(p + w);
      }
    }
    areas.add(area);
    touchesBorder.add(border);
  }

  final limit = solid * maxShare;
  for (int p = 0; p < n; p++) {
    final l = labels[p];
    if (l != 0 && !touchesBorder[l] && areas[l] <= limit) a[p] = 1;
  }
}

/// Bilinear resize of a 0..1 mask to 0..255 bytes.
Uint8List _resizeMaskToBytes(Float32List src, int sw, int sh, int dw, int dh) {
  final out = Uint8List(dw * dh);
  final xs = sw / dw, ys = sh / dh;
  for (int y = 0; y < dh; y++) {
    final fy = (y + 0.5) * ys - 0.5;
    final y0 = _ci(fy.floor(), 0, sh - 1);
    final y1 = _ci(y0 + 1, 0, sh - 1);
    final wy = fy < 0 ? 0.0 : (fy - fy.floor());
    for (int x = 0; x < dw; x++) {
      final fx = (x + 0.5) * xs - 0.5;
      final x0 = _ci(fx.floor(), 0, sw - 1);
      final x1 = _ci(x0 + 1, 0, sw - 1);
      final wx = fx < 0 ? 0.0 : (fx - fx.floor());
      final a = src[y0 * sw + x0] * (1 - wx) + src[y0 * sw + x1] * wx;
      final b = src[y1 * sw + x0] * (1 - wx) + src[y1 * sw + x1] * wx;
      final v = (a * (1 - wy) + b * wy) * 255;
      out[y * dw + x] = _ci(v.round(), 0, 255);
    }
  }
  return out;
}

// ---------------------------------------------------------------------
// Skin smoothing (no AI model)
// ---------------------------------------------------------------------

/// Edge-preserving skin smoothing.
///
/// A guided filter smooths flat skin while keeping real edges (eyes, lips,
/// hair, jawline) sharp, a "protect" map keeps high-contrast detail
/// untouched, and a little of the original fine texture is mixed back in
/// so skin looks clean rather than blurry or plastic. Returns a JPEG.
Uint8List smoothSkinJpg(Uint8List rgb, int w, int h, double strength) {
  final n = w * h;
  final s = strength < 0 ? 0.0 : (strength > 1 ? 1.0 : strength);

  final chan = <Float32List>[Float32List(n), Float32List(n), Float32List(n)];
  final lum = Float32List(n);
  for (int i = 0; i < n; i++) {
    final r = rgb[3 * i] / 255.0;
    final g = rgb[3 * i + 1] / 255.0;
    final b = rgb[3 * i + 2] / 255.0;
    chan[0][i] = r;
    chan[1][i] = g;
    chan[2][i] = b;
    lum[i] = 0.299 * r + 0.587 * g + 0.114 * b;
  }

  final radius = _ci((math.max(w, h) / 170).round(), 3, 14);
  final eps = 0.002 + 0.010 * s;

  // Local luminance variance -> where real detail/edges are.
  final meanL = MaskOps.boxBlur(lum, w, h, radius);
  final lumSq = Float32List(n);
  for (int i = 0; i < n; i++) {
    lumSq[i] = lum[i] * lum[i];
  }
  final corrL = MaskOps.boxBlur(lumSq, w, h, radius);
  final protect = Float32List(n);
  for (int i = 0; i < n; i++) {
    final v = corrL[i] - meanL[i] * meanL[i];
    double t = (v - 0.004) / 0.011;
    t = t < 0 ? 0 : (t > 1 ? 1 : t);
    protect[i] = t * t * (3 - 2 * t);
  }

  // Skin mask: YCbCr range AND a classic RGB rule, so skin-like colours
  // are found but orange cloth, wood or sky are mostly left alone.
  var mask = Float32List(n);
  for (int i = 0; i < n; i++) {
    final r = rgb[3 * i].toDouble();
    final g = rgb[3 * i + 1].toDouble();
    final b = rgb[3 * i + 2].toDouble();
    final cb = 128 - 0.168736 * r - 0.331264 * g + 0.5 * b;
    final cr = 128 + 0.5 * r - 0.418688 * g - 0.081312 * b;
    final mx = math.max(r, math.max(g, b));
    final mn = math.min(r, math.min(g, b));
    final ycc = lum[i] > 0.16 && cb >= 77 && cb <= 127 && cr >= 133 && cr <= 173;
    final rule = r > 95 && g > 40 && b > 20 && (mx - mn) > 15 && r > g && r > b;
    mask[i] = (ycc && rule) ? 1.0 : 0.0;
  }
  final feather = _ci((math.max(w, h) / 150).round(), 2, 14);
  mask = MaskOps.boxBlur(mask, w, h, feather);
  mask = MaskOps.boxBlur(mask, w, h, feather);

  // Spot / blemish map: small dark patches on skin (moles, acne marks,
  // dark spots) compared with their surroundings.
  final midR = _ci((math.max(w, h) / 60).round(), 6, 30);
  final surround = MaskOps.boxBlur(lum, w, h, midR);
  final spotThr = 0.085 - 0.045 * s;
  var spot = Float32List(n);
  for (int i = 0; i < n; i++) {
    if (mask[i] < 0.5) continue;
    final d = surround[i] - lum[i];
    double t = (d - spotThr) / spotThr;
    t = t < 0 ? 0 : (t > 1 ? 1 : t);
    spot[i] = t;
  }
  spot = MaskOps.dilate(spot, w, h, 1);
  spot = MaskOps.boxBlur(spot, w, h, 1);
  // Fill colour: neighbourhood average that ignores the spot pixels.
  final keepW = Float32List(n);
  for (int i = 0; i < n; i++) {
    keepW[i] = (1 - spot[i]) * (mask[i] > 0.3 ? 1.0 : 0.0);
  }
  final keepWSum = MaskOps.boxBlur(keepW, w, h, midR);
  final fill = <Float32List>[];
  for (int c = 0; c < 3; c++) {
    final t = Float32List(n);
    for (int i = 0; i < n; i++) {
      t[i] = chan[c][i] * keepW[i];
    }
    final b = MaskOps.boxBlur(t, w, h, midR);
    final f = Float32List(n);
    for (int i = 0; i < n; i++) {
      f[i] = keepWSum[i] > 0.02 ? b[i] / keepWSum[i] : chan[c][i];
    }
    fill.add(f);
  }

  // Guided (self-guided) filter per channel.
  final smooth = <Float32List>[];
  for (int c = 0; c < 3; c++) {
    final p = chan[c];
    final meanP = MaskOps.boxBlur(p, w, h, radius);
    final sq = Float32List(n);
    for (int i = 0; i < n; i++) {
      sq[i] = p[i] * p[i];
    }
    final corrP = MaskOps.boxBlur(sq, w, h, radius);
    final a = Float32List(n);
    final bb = Float32List(n);
    for (int i = 0; i < n; i++) {
      double v = corrP[i] - meanP[i] * meanP[i];
      if (v < 0) v = 0;
      final ai = v / (v + eps);
      a[i] = ai;
      bb[i] = meanP[i] * (1 - ai);
    }
    final meanA = MaskOps.boxBlur(a, w, h, radius);
    final meanB = MaskOps.boxBlur(bb, w, h, radius);
    final q = Float32List(n);
    for (int i = 0; i < n; i++) {
      q[i] = meanA[i] * p[i] + meanB[i];
    }
    smooth.add(q);
  }

  final amount = s * 1.15 > 1 ? 1.0 : s * 1.15;
  final keepDetail = 0.38 - 0.26 * s; // fine texture mixed back in
  final spotAmt = s;
  final out = Uint8List(n * 3);
  for (int i = 0; i < n; i++) {
    final wgt = mask[i] * (1 - protect[i] * 0.85) * amount;
    final sw = spot[i] * spotAmt;
    for (int c = 0; c < 3; c++) {
      final o = chan[c][i];
      double v = o;
      if (wgt > 0.004) {
        final sm = smooth[c][i];
        final target = sm + (o - sm) * keepDetail;
        v = o * (1 - wgt) + target * wgt;
      }
      if (sw > 0.01) v = v * (1 - sw) + fill[c][i] * sw;
      out[3 * i + c] = _ci((v * 255).round(), 0, 255);
    }
  }
  return img.encodeJpg(
    img.Image.fromBytes(width: w, height: h, bytes: out.buffer, numChannels: 3),
    quality: 95,
  );
}

// ---------------------------------------------------------------------
// Upscale
// ---------------------------------------------------------------------

Uint8List encodeRgbPng(Uint8List rgb, int w, int h) {
  return img.encodePng(
    img.Image.fromBytes(width: w, height: h, bytes: rgb.buffer, numChannels: 3),
  );
}

// ---------------------------------------------------------------------
// Object removal
// ---------------------------------------------------------------------

/// Resizes the inpainted 512x512 patch to the crop size, restores some
/// sharpness and film grain (the model output is soft), and blends it into
/// the photo through the feathered mask. [rgb] is the whole photo
/// (modified in place). Returns a JPEG.
Uint8List blendInpaintJpg(
  Uint8List rgb,
  int W,
  int H,
  Float32List flat,
  double mul,
  Float32List feather,
  int x0,
  int y0,
  int sideI,
  int size,
) {
  final plane = size * size;
  final patch = Uint8List(plane * 3);
  for (int i = 0; i < plane; i++) {
    patch[3 * i] = _ci((flat[i] * mul).round(), 0, 255);
    patch[3 * i + 1] = _ci((flat[plane + i] * mul).round(), 0, 255);
    patch[3 * i + 2] = _ci((flat[2 * plane + i] * mul).round(), 0, 255);
  }
  final patchImg = img.Image.fromBytes(
    width: size,
    height: size,
    bytes: patch.buffer,
    numChannels: 3,
  );
  final filled = img.copyResize(
    patchImg,
    width: sideI,
    height: sideI,
    interpolation: img.Interpolation.cubic,
  );
  final fb = Uint8List.fromList(filled.getBytes(order: img.ChannelOrder.rgb));

  // Unsharp mask: the model works at 512px, so a bigger crop is blown up
  // and looks soft.
  final up = sideI / size;
  final sharpAmount = up > 1.0 ? 0.9 : 0.45;
  final blurRadius = _ci((up * 1.2).round(), 1, 6);
  final blurred = img.gaussianBlur(img.Image.from(filled), radius: blurRadius);
  final bb = blurred.getBytes(order: img.ChannelOrder.rgb);
  for (int i = 0; i < sideI * sideI * 3; i++) {
    fb[i] = _ci((fb[i] + sharpAmount * (fb[i] - bb[i])).round(), 0, 255);
  }

  // Noise level of the surrounding photo, so the filled area gets matching
  // grain instead of looking plastic.
  double sumSq = 0;
  int cnt = 0;
  for (int yy = 2; yy < sideI - 2; yy += 2) {
    final my = math.min(size - 1, (yy * size / sideI).floor());
    for (int xx = 2; xx < sideI - 2; xx += 2) {
      final mx = math.min(size - 1, (xx * size / sideI).floor());
      if (feather[my * size + mx] > 0.01) continue;
      final idx = ((y0 + yy) * W + (x0 + xx)) * 3;
      double l(int d) =>
          0.299 * rgb[idx + d] + 0.587 * rgb[idx + d + 1] + 0.114 * rgb[idx + d + 2];
      final c = l(0);
      final nb = (l(-3) + l(3) + l(-3 * W) + l(3 * W)) / 4;
      final d = c - nb;
      sumSq += d * d;
      cnt++;
    }
  }
  final sigma = cnt > 50 ? math.sqrt(sumSq / cnt) : 0.0;
  final grain = sigma > 8 ? 8.0 : sigma * 0.8;
  final rnd = math.Random(7);

  for (int yy = 0; yy < sideI; yy++) {
    final fy = (yy + 0.5) * size / sideI - 0.5;
    for (int xx = 0; xx < sideI; xx++) {
      final fx = (xx + 0.5) * size / sideI - 0.5;
      final a = _bilinear(feather, size, fx, fy);
      if (a <= 0.01) continue;
      final idx = ((y0 + yy) * W + (x0 + xx)) * 3;
      final fi = (yy * sideI + xx) * 3;
      final noise = grain > 0 ? (rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble() - 1.5) * 2 * grain : 0.0;
      for (int c = 0; c < 3; c++) {
        final v = rgb[idx + c] * (1 - a) + (fb[fi + c] + noise) * a;
        rgb[idx + c] = _ci(v.round(), 0, 255);
      }
    }
  }
  return img.encodeJpg(
    img.Image.fromBytes(width: W, height: H, bytes: rgb.buffer, numChannels: 3),
    quality: 95,
  );
}

double _bilinear(Float32List m, int size, double fx, double fy) {
  final x0 = _ci(fx.floor(), 0, size - 1);
  final y0 = _ci(fy.floor(), 0, size - 1);
  final x1 = _ci(x0 + 1, 0, size - 1);
  final y1 = _ci(y0 + 1, 0, size - 1);
  final wx = fx < 0 ? 0.0 : (fx - fx.floor());
  final wy = fy < 0 ? 0.0 : (fy - fy.floor());
  final a = m[y0 * size + x0] * (1 - wx) + m[y0 * size + x1] * wx;
  final b = m[y1 * size + x0] * (1 - wx) + m[y1 * size + x1] * wx;
  return a * (1 - wy) + b * wy;
}

/// Min filter (erosion) of an 8-bit plane with a square window of radius [r].
Uint8List _erodePlane(Uint8List src, int w, int h, int r) {
  if (r <= 0) return Uint8List.fromList(src);
  final tmp = Uint8List(w * h);
  for (int y = 0; y < h; y++) {
    final row = y * w;
    for (int x = 0; x < w; x++) {
      int m = 255;
      final x0 = x - r < 0 ? 0 : x - r;
      final x1 = x + r >= w ? w - 1 : x + r;
      for (int k = x0; k <= x1; k++) {
        final v = src[row + k];
        if (v < m) m = v;
      }
      tmp[row + x] = m;
    }
  }
  final out = Uint8List(w * h);
  for (int x = 0; x < w; x++) {
    for (int y = 0; y < h; y++) {
      int m = 255;
      final y0 = y - r < 0 ? 0 : y - r;
      final y1 = y + r >= h ? h - 1 : y + r;
      for (int k = y0; k <= y1; k++) {
        final v = tmp[k * w + x];
        if (v < m) m = v;
      }
      out[y * w + x] = m;
    }
  }
  return out;
}

/// Box blur of a Float64 plane (radius [r]) using running sums.
Float64List _boxF(Float64List src, int w, int h, int r) {
  final tmp = Float64List(w * h);
  final out = Float64List(w * h);
  for (int y = 0; y < h; y++) {
    final row = y * w;
    double sum = 0;
    int lo = 0, hi = -1;
    for (int x = 0; x < w; x++) {
      final nh = x + r >= w ? w - 1 : x + r;
      final nl = x - r < 0 ? 0 : x - r;
      while (hi < nh) {
        hi++;
        sum += src[row + hi];
      }
      while (lo < nl) {
        sum -= src[row + lo];
        lo++;
      }
      tmp[row + x] = sum;
    }
  }
  for (int x = 0; x < w; x++) {
    double sum = 0;
    int lo = 0, hi = -1;
    for (int y = 0; y < h; y++) {
      final nh = y + r >= h ? h - 1 : y + r;
      final nl = y - r < 0 ? 0 : y - r;
      while (hi < nh) {
        hi++;
        sum += tmp[hi * w + x];
      }
      while (lo < nl) {
        sum -= tmp[lo * w + x];
        lo++;
      }
      out[y * w + x] = sum;
    }
  }
  return out;
}

/// Cleans the border of a cut-out: shrinks the matte by [shrink] px, softens
/// it slightly, and replaces the colour of edge pixels with the colour of
/// the solid interior next to them so no old background tint is left.
Uint8List refineEdgePng(Uint8List rgba, int w, int h, int shrink, int soften) {
  final n = w * h;
  final a0 = Uint8List(n);
  for (int i = 0; i < n; i++) {
    a0[i] = rgba[4 * i + 3];
  }
  var a = _erodePlane(a0, w, h, shrink);
  if (soften > 0) {
    final f = Float64List(n);
    for (int i = 0; i < n; i++) {
      f[i] = a[i].toDouble();
    }
    final b = _boxF(f, w, h, soften);
    final side = 2 * soften + 1;
    final div = (side * side).toDouble();
    for (int i = 0; i < n; i++) {
      // Only ever lower alpha near the edge (never grow the matte).
      final v = (b[i] / div).round();
      a[i] = v < a[i] ? v : a[i];
    }
  }

  // Interior colour: normalized convolution over solid, eroded-core pixels.
  final core = _erodePlane(a0, w, h, shrink + 2);
  final wt = Float64List(n);
  final cr = Float64List(n), cg = Float64List(n), cb = Float64List(n);
  for (int i = 0; i < n; i++) {
    if (core[i] >= 250) {
      wt[i] = 1;
      cr[i] = rgba[4 * i].toDouble();
      cg[i] = rgba[4 * i + 1].toDouble();
      cb[i] = rgba[4 * i + 2].toDouble();
    }
  }
  const rad = 6;
  final sw = _boxF(wt, w, h, rad);
  final sr = _boxF(cr, w, h, rad);
  final sg = _boxF(cg, w, h, rad);
  final sb = _boxF(cb, w, h, rad);

  final out = Uint8List(n * 4);
  for (int i = 0; i < n; i++) {
    int r = rgba[4 * i], g = rgba[4 * i + 1], b = rgba[4 * i + 2];
    if (core[i] < 250 && sw[i] > 0.5) {
      final ir = sr[i] / sw[i], ig = sg[i] / sw[i], ib = sb[i] / sw[i];
      const k = 0.85;
      r = (r + (ir - r) * k).round();
      g = (g + (ig - g) * k).round();
      b = (b + (ib - b) * k).round();
    }
    out[4 * i] = r;
    out[4 * i + 1] = g;
    out[4 * i + 2] = b;
    out[4 * i + 3] = a[i];
  }
  final result = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: out.buffer,
    numChannels: 4,
  );
  return img.encodePng(result);
}
