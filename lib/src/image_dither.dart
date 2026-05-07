import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Binarisation algorithm.
enum XprinterImageMode {
  /// Auto-detect by mid-tone pixel count.  Default for unknown content.
  auto,

  /// Force hard threshold.  Use for known logos / line art.
  threshold,

  /// Force Floyd–Steinberg dither.  Reserved for explicit photo handling.
  dither,
}

/// Binarises images to 0/255 pixels for the thermal printer.  Threshold
/// for logos (sharp), Floyd–Steinberg for photos (smooth).  Done in Dart
/// so iOS and Android render identical output.
abstract final class XprinterImageDither {
  /// Threshold-path cutoff.  Slightly above 128 to thicken thin strokes
  /// for darker print on cheap thermal paper.
  static const int defaultThresholdCutoff = 140;

  /// Mid-tone band for content classification.
  static const int _logoMidLow = 50;
  static const int _logoMidHigh = 200;

  /// Above this fraction of mid-tones, image is treated as a photo.
  static const double _logoMaxMidToneFraction = 0.10;

  /// Returns PNG bytes for [source] where every pixel is 0 or 255.
  static Uint8List binarise(
    img.Image source, {
    int thresholdCutoff = defaultThresholdCutoff,
    XprinterImageMode mode = XprinterImageMode.auto,
  }) {
    final width = source.width;
    final height = source.height;
    final luminance = _luminanceBuffer(source);
    final useThreshold = switch (mode) {
      XprinterImageMode.threshold => true,
      XprinterImageMode.dither => false,
      XprinterImageMode.auto => _isLogoLike(luminance),
    };
    final binary = useThreshold
        ? _threshold(width, height, luminance, thresholdCutoff)
        : _floydSteinberg(width, height, luminance);
    return Uint8List.fromList(img.encodePng(binary));
  }

  // ── Internals ──────────────────────────────────────────────────────────

  /// Per-pixel luminance via ITU-R BT.601 weights, fixed-point.
  static Uint8List _luminanceBuffer(img.Image source) {
    final out = Uint8List(source.width * source.height);
    var i = 0;
    for (var y = 0; y < source.height; y++) {
      for (var x = 0; x < source.width; x++) {
        final p = source.getPixel(x, y);
        final l = (77 * p.r.toInt() + 150 * p.g.toInt() + 29 * p.b.toInt()) >> 8;
        out[i++] = l < 0 ? 0 : (l > 255 ? 255 : l);
      }
    }
    return out;
  }

  /// True when the image is dominated by near-black/white pixels.
  static bool _isLogoLike(Uint8List luminance) {
    var midTone = 0;
    for (final l in luminance) {
      if (l > _logoMidLow && l < _logoMidHigh) midTone++;
    }
    return midTone / luminance.length < _logoMaxMidToneFraction;
  }

  /// Hard threshold against [cutoff] — pixel → pure black or pure white.
  static img.Image _threshold(
    int width,
    int height,
    Uint8List luminance,
    int cutoff,
  ) {
    final out = img.Image(width: width, height: height);
    var i = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final v = luminance[i++] > cutoff ? 255 : 0;
        out.setPixelRgb(x, y, v, v, v);
      }
    }
    return out;
  }

  /// Floyd–Steinberg error-diffusion to black/white (kernel: 7/16 right,
  /// 3/16 below-left, 5/16 below, 1/16 below-right).
  static img.Image _floydSteinberg(
    int width,
    int height,
    Uint8List luminance,
  ) {
    final buf = Int16List(luminance.length);
    for (var i = 0; i < luminance.length; i++) {
      buf[i] = luminance[i];
    }

    final out = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = y * width + x;
        final old = buf[i] < 0 ? 0 : (buf[i] > 255 ? 255 : buf[i]);
        final v = old < 128 ? 0 : 255;
        final err = old - v;
        out.setPixelRgb(x, y, v, v, v);

        // Distribute error to unprocessed neighbours.
        if (x + 1 < width) {
          buf[i + 1] += (err * 7) ~/ 16;
        }
        if (y + 1 < height) {
          if (x > 0) {
            buf[i + width - 1] += (err * 3) ~/ 16;
          }
          buf[i + width] += (err * 5) ~/ 16;
          if (x + 1 < width) {
            buf[i + width + 1] += err ~/ 16;
          }
        }
      }
    }
    return out;
  }
}
