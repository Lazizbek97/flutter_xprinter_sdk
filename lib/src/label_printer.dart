import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_xprinter_sdk/src/method_channel.dart';
import 'package:flutter_xprinter_sdk/src/xprinter_exception.dart';
import 'package:image/image.dart' as img;

/// A TSPL label job for printers such as the Xprinter XP-245B.
///
/// Coordinates are dots (203 dpi is approximately 8 dots/mm). Create one job
/// per label format. [print] sends the complete job through the connection
/// opened with [XprinterConnection]. Do not initialize the POS printer first.
class LabelPrinter {
  LabelPrinter({
    required this.widthMm,
    required this.heightMm,
    this.gapMm = 2,
    this.density = 8,
    this.direction = 0,
  }) {
    _checkMm(widthMm, 'widthMm');
    _checkMm(heightMm, 'heightMm');
    if (!gapMm.isFinite || gapMm < 0 || gapMm > 25) {
      throw ArgumentError.value(gapMm, 'gapMm', 'must be between 0 and 25');
    }
    if (density < 0 || density > 15) {
      throw ArgumentError.value(density, 'density', 'must be between 0 and 15');
    }
    if (direction != 0 && direction != 1) {
      throw ArgumentError.value(direction, 'direction', 'must be 0 or 1');
    }
  }

  final double widthMm;
  final double heightMm;
  final double gapMm;
  final int density;
  final int direction;
  final List<Uint8List> _items = [];

  /// Adds text using one of the printer's built-in fonts (1–5).
  ///
  /// Built-in font encoding varies by firmware. This method accepts printable
  /// ASCII only; render Cyrillic and other Unicode text into an image and use
  /// [addImage] for predictable results.
  void addText(String value,
      {required int x,
      required int y,
      int font = 3,
      int scaleX = 1,
      int scaleY = 1,
      int rotation = 0}) {
    _position(x, y);
    if (font < 1 ||
        font > 5 ||
        scaleX < 1 ||
        scaleX > 10 ||
        scaleY < 1 ||
        scaleY > 10 ||
        !_validRotation(rotation)) {
      throw ArgumentError('invalid text font, scale, or rotation');
    }
    _quotedAscii(value, 'value');
    _items.add(_line('TEXT $x,$y,"$font",$rotation,$scaleX,$scaleY,"$value"'));
  }

  /// Adds a Code 128 barcode. [height] and coordinates are dots.
  void addBarcode(String value,
      {required int x,
      required int y,
      int height = 80,
      bool showText = true,
      int narrow = 2,
      int wide = 2}) {
    _position(x, y);
    _quotedAscii(value, 'value');
    if (value.isEmpty ||
        height < 1 ||
        narrow < 1 ||
        narrow > 10 ||
        wide < narrow ||
        wide > 10) {
      throw ArgumentError('invalid barcode value or dimensions');
    }
    _items.add(_line(
        'BARCODE $x,$y,"128",$height,${showText ? 1 : 0},0,$narrow,$wide,"$value"'));
  }

  /// Adds a QR code. [cellSize] is the size of one module in dots.
  void addQrCode(String value,
      {required int x,
      required int y,
      int cellSize = 4,
      String correction = 'M'}) {
    _position(x, y);
    _quotedAscii(value, 'value');
    if (value.isEmpty ||
        cellSize < 1 ||
        cellSize > 10 ||
        !const {'L', 'M', 'Q', 'H'}.contains(correction)) {
      throw ArgumentError('invalid QR value, cellSize, or correction');
    }
    _items.add(_line('QRCODE $x,$y,$correction,$cellSize,A,0,"$value"'));
  }

  /// Adds a PNG/JPEG/BMP/GIF as a 1-bit TSPL BITMAP command.
  ///
  /// TSPL prints a dot for a 0 bit, so black pixels clear bits; transparent
  /// pixels and row padding stay white. Images wider than the print head or
  /// outside the label are rejected.
  void addImage(Uint8List bytes,
      {required int x, required int y, int threshold = 128}) {
    _position(x, y);
    if (threshold < 0 || threshold > 255) {
      throw ArgumentError.value(threshold, 'threshold');
    }
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw ArgumentError.value(bytes, 'bytes', 'invalid image');
    }
    final widthDots = (widthMm * 8).floor();
    final heightDots = (heightMm * 8).floor();
    if (x + image.width > widthDots || y + image.height > heightDots) {
      throw ArgumentError(
          'image exceeds label bounds ($widthDots x $heightDots dots)');
    }
    final rowBytes = (image.width + 7) ~/ 8;
    // Starts white: the vendor SDK also sends 1 for white in TSPL bitmaps.
    final bitmap = Uint8List(rowBytes * image.height);
    bitmap.fillRange(0, bitmap.length, 0xff);
    for (var py = 0; py < image.height; py++) {
      for (var px = 0; px < image.width; px++) {
        final pixel = image.getPixel(px, py);
        final alpha = pixel.a / 255;
        final luminance =
            (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b) * alpha +
                255 * (1 - alpha);
        if (luminance < threshold) {
          bitmap[py * rowBytes + px ~/ 8] &= ~(0x80 >> (px % 8));
        }
      }
    }
    _items.add(Uint8List.fromList(<int>[
      ...ascii.encode('BITMAP $x,$y,$rowBytes,${image.height},0,'),
      ...bitmap,
      0x0d,
      0x0a,
    ]));
  }

  /// Builds one complete TSPL job. Useful for inspecting or custom transport.
  Uint8List build({int copies = 1}) {
    if (copies < 1 || copies > 999) {
      throw ArgumentError.value(copies, 'copies', 'must be between 1 and 999');
    }
    return Uint8List.fromList(<int>[
      ..._line('SIZE ${_mm(widthMm)} mm,${_mm(heightMm)} mm'),
      ..._line('GAP ${_mm(gapMm)} mm,0 mm'),
      ..._line('DENSITY $density'),
      ..._line('DIRECTION $direction'),
      ..._line('CLS'),
      for (final item in _items) ...item,
      ..._line('PRINT $copies'),
    ]);
  }

  /// Sends and flushes the label job, including on iOS BLE.
  Future<void> print({int copies = 1}) async {
    try {
      await xprinterMethodChannel.invokeMethod<void>(
        'printLabel',
        <String, Object?>{'bytes': build(copies: copies)},
      );
    } on PlatformException catch (e) {
      throw XprinterException(e.code, e.message ?? 'unknown');
    }
  }

  static void _checkMm(double value, String name) {
    if (!value.isFinite || value <= 0 || value > 300) {
      throw ArgumentError.value(value, name, 'must be between 0 and 300 mm');
    }
  }

  void _position(int x, int y) {
    if (x < 0 ||
        y < 0 ||
        x >= (widthMm * 8).floor() ||
        y >= (heightMm * 8).floor()) {
      throw ArgumentError('position outside label');
    }
  }

  static void _quotedAscii(String value, String name) {
    if (value.codeUnits.any((c) => c < 32 || c > 126 || c == 34)) {
      throw ArgumentError.value(
          value, name, 'requires printable ASCII without quotes');
    }
  }

  static bool _validRotation(int degrees) =>
      degrees == 0 || degrees == 90 || degrees == 180 || degrees == 270;

  static String _mm(double value) => value.toStringAsFixed(2);
  static Uint8List _line(String command) =>
      Uint8List.fromList(ascii.encode('$command\r\n'));
}
