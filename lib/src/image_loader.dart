import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:flutter_xprinter_sdk/src/image_dither.dart';

/// Prepares images for thermal printing — downloads, decodes, resizes
/// to the print head width preserving aspect, and binarises to 0/255
/// PNG bytes ready for [PosPrinter.printBitmap].
abstract final class XprinterImageLoader {
  /// Downloads from [url], prepares for printing.  Returns null on
  /// network error / non-200 / decode failure.
  static Future<Uint8List?> fromUrl({
    required String url,
    int targetWidthDots = 384,
    XprinterImageMode mode = XprinterImageMode.auto,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final response = await http.get(Uri.parse(url)).timeout(timeout);
      if (response.statusCode != 200) return null;
      return fromBytes(
        bytes: response.bodyBytes,
        targetWidthDots: targetWidthDots,
        mode: mode,
      );
    } catch (_) {
      return null;
    }
  }

  /// Loads from a Flutter asset (`assets/...`), prepares for printing.
  /// Returns null if the asset is missing or fails to decode.
  static Future<Uint8List?> fromAsset({
    required String assetPath,
    int targetWidthDots = 384,
    XprinterImageMode mode = XprinterImageMode.auto,
  }) async {
    try {
      final data = await rootBundle.load(assetPath);
      return fromBytes(
        bytes: data.buffer.asUint8List(),
        targetWidthDots: targetWidthDots,
        mode: mode,
      );
    } catch (_) {
      return null;
    }
  }

  /// Prepares from already-loaded image [bytes].  Decodes, resizes to
  /// [targetWidthDots] preserving aspect, binarises with [mode].
  static Uint8List? fromBytes({
    required Uint8List bytes,
    int targetWidthDots = 384,
    XprinterImageMode mode = XprinterImageMode.auto,
  }) {
    final source = img.decodeImage(bytes);
    if (source == null || source.width <= 0 || source.height <= 0) return null;

    final aspect = source.width / source.height;
    final targetH = (targetWidthDots / aspect).round().clamp(1, 2000);
    final resized = img.copyResize(
      source,
      width: targetWidthDots,
      height: targetH,
      interpolation: img.Interpolation.linear,
    );

    // Flatten alpha onto white — printers treat transparent as black otherwise.
    final flat = img.Image(width: targetWidthDots, height: targetH);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, resized);

    return XprinterImageDither.binarise(flat, mode: mode);
  }
}
