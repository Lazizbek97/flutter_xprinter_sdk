import 'package:flutter/services.dart';
import 'package:flutter_xprinter_sdk/src/alignment.dart';
import 'package:flutter_xprinter_sdk/src/barcode_type.dart';
import 'package:flutter_xprinter_sdk/src/code_page.dart';
import 'package:flutter_xprinter_sdk/src/method_channel.dart';
import 'package:flutter_xprinter_sdk/src/printer_status.dart';
import 'package:flutter_xprinter_sdk/src/qr_correction.dart';
import 'package:flutter_xprinter_sdk/src/text_attribute.dart';
import 'package:flutter_xprinter_sdk/src/xprinter_exception.dart';

/// Receipt-relevant subset of the XPrinter `POSPrinter` API.
///
/// This intentionally exposes only the methods the receipt service in part 3
/// will use.  `printChar`, `setBold`, `setUnderline`, `beep`, `openCashBox`,
/// `LabelPrinter`, etc. are deferred until a caller emerges.
abstract final class PosPrinter {
  /// Sends ESC @ to the printer and resets transient state.  Call once after
  /// connecting.
  static Future<void> initialize() => _invoke('initialize');

  /// Prints [text] with the given alignment, attributes, and size.
  ///
  /// [attribute] is an `OR` of `XprinterTextAttribute` constants — e.g.,
  /// `XprinterTextAttribute.bold | XprinterTextAttribute.underline`.
  /// [textSize] is an `OR` of `XprinterTextSize.width*` and `height*`
  /// constants — defaults to `XprinterTextSize.normal`.
  ///
  /// The SDK appends an LF.  Call once per logical line.
  static Future<void> printText(
    String text, {
    XprinterAlignment alignment = XprinterAlignment.left,
    int attribute = XprinterTextAttribute.normal,
    int textSize = XprinterTextSize.normal,
  }) {
    return _invoke('printText', <String, Object?>{
      'text': text,
      'alignment': alignment.nativeValue,
      'attribute': attribute,
      'textSize': textSize,
    });
  }

  /// Prints a raster bitmap.  [bytes] must be a PNG / JPEG / BMP byte
  /// buffer that Android's `BitmapFactory.decodeByteArray` can decode.
  ///
  /// [widthDots] is the target print width in dots — the SDK scales the
  /// source bitmap to this width preserving aspect ratio.  Default 384 is
  /// the full 58 mm print head; pass 576 for 80 mm.
  static Future<void> printBitmap(
    Uint8List bytes, {
    XprinterAlignment alignment = XprinterAlignment.center,
    int widthDots = 384,
  }) {
    return _invoke('printBitmap', <String, Object?>{
      'bytes': bytes,
      'alignment': alignment.nativeValue,
      'widthDots': widthDots,
    });
  }

  /// Prints a solid black horizontal line by generating the bitmap natively.
  ///
  /// Useful for section dividers in receipts.  The native side uses
  /// `Bitmap.createBitmap` + `eraseColor(BLACK)` and hands the result to
  /// `POSPrinter.printBitmap` — no PNG round-trip, no encode / decode
  /// dimension surprises.
  static Future<void> printHorizontalLine({
    int widthDots = 384,
    int heightRows = 4,
    XprinterAlignment alignment = XprinterAlignment.center,
  }) {
    return _invoke('printHorizontalLine', <String, Object?>{
      'widthDots': widthDots,
      'heightRows': heightRows,
      'alignment': alignment.nativeValue,
    });
  }

  /// Prints a QR code.
  static Future<void> printQRCode(
    String content, {
    int moduleSize = 4,
    XprinterQrCorrection errorCorrection = XprinterQrCorrection.m,
    XprinterAlignment alignment = XprinterAlignment.center,
  }) {
    return _invoke('printQRCode', <String, Object?>{
      'content': content,
      'moduleSize': moduleSize,
      'errorCorrection': errorCorrection.nativeValue,
      'alignment': alignment.nativeValue,
    });
  }

  /// Prints a barcode.
  static Future<void> printBarCode(
    String content, {
    required XprinterBarcodeType type,
    int width = 2,
    int height = 80,
    XprinterAlignment alignment = XprinterAlignment.center,
    XprinterBarcodeHri hri = XprinterBarcodeHri.none,
  }) {
    return _invoke('printBarCode', <String, Object?>{
      'content': content,
      'type': type.nativeValue,
      'width': width,
      'height': height,
      'alignment': alignment.nativeValue,
      'hri': hri.nativeValue,
    });
  }

  /// Feeds [lines] empty paper rows.
  static Future<void> feedLine([int lines = 1]) {
    return _invoke('feedLine', <String, Object?>{'lines': lines});
  }

  /// Cuts the paper.  When [half] is true, performs a partial cut that
  /// leaves a small connecting strip (preferred for receipt tear-off).
  static Future<void> cutPaper({bool half = true}) {
    return _invoke('cutPaper', <String, Object?>{'half': half});
  }

  /// Selects the printer's character code page.  Use [XprinterCodePage.pc866]
  /// for Cyrillic.  Stays in effect until the next `initialize` or another
  /// `selectCodePage` call.
  static Future<void> selectCodePage(XprinterCodePage page) {
    return _invoke('selectCodePage', <String, Object?>{
      'page': page.nativeValue,
    });
  }

  /// Sets the persistent alignment for subsequent text / bitmap calls.
  /// Most callers should pass alignment per-call to `printText` instead;
  /// this is the persistent variant for code that needs it.
  static Future<void> setAlignment(XprinterAlignment alignment) {
    return _invoke('setAlignment', <String, Object?>{
      'alignment': alignment.nativeValue,
    });
  }

  /// Reads the printer's current status (cover, paper, error).
  ///
  /// Resolves with a [PrinterStatus.fromNativeValue]-parsed result once the
  /// SDK's `IStatusCallback` returns.
  static Future<PrinterStatus> getStatus() async {
    final raw = await _invoke<int>('getStatus');
    return PrinterStatus.fromNativeValue(raw ?? -1);
  }

  /// Escape hatch: send raw ESC/POS bytes that the high-level methods don't
  /// cover.  Use sparingly; prefer the typed methods above.
  static Future<void> sendRawCommand(Uint8List bytes) {
    return _invoke('sendRawCommand', <String, Object?>{'bytes': bytes});
  }

  // ── Internal ─────────────────────────────────────────────────────────────

  static Future<T?> _invoke<T>(String method, [Map<String, Object?>? args]) {
    return xprinterMethodChannel
        .invokeMethod<T>(
      method,
      args,
    )
        .onError<PlatformException>(
      (e, _) {
        throw XprinterException(e.code, e.message ?? 'unknown');
      },
    );
  }
}
