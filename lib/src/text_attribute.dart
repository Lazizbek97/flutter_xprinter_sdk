/// Bit flags combinable via `|` for the `attribute` parameter of
/// `PosPrinter.printText`.
///
/// Values come straight from `POSConst.FNT_*`:
/// - `FNT_DEFAULT = 0`
/// - `FNT_FONTB = 1`
/// - `FNT_BOLD = 8`
/// - `FNT_REVERSE = 16`
/// - `FNT_UNDERLINE = 128`
/// - `FNT_UNDERLINE2 = 256`  (thicker underline)
abstract final class XprinterTextAttribute {
  /// Plain text.
  static const int normal = 0;

  /// Use Font B (smaller, denser).  Most receipts stay on Font A.
  static const int fontB = 1;

  /// Emphasis (bold).
  static const int bold = 8;

  /// White-on-black inverse.
  static const int reverse = 16;

  /// Single-line underline.
  static const int underline = 128;

  /// Double-line underline (thicker).
  static const int underline2 = 256;
}

/// Bit flags combinable via `|` for the `textSize` parameter of
/// `PosPrinter.printText`.
///
/// Width values are the high nibble (`POSConst.TXT_*WIDTH`), height values
/// are the low nibble (`POSConst.TXT_*HEIGHT`).  Combine one of each via
/// `XprinterTextSize.width2 | XprinterTextSize.height2` for 2× scale.
abstract final class XprinterTextSize {
  /// Width 1× (normal).
  static const int width1 = 0;

  /// Width 2×.
  static const int width2 = 16;

  /// Width 3×.
  static const int width3 = 32;

  /// Width 4×.
  static const int width4 = 48;

  /// Width 5×.
  static const int width5 = 64;

  /// Width 6×.
  static const int width6 = 80;

  /// Width 7×.
  static const int width7 = 96;

  /// Width 8×.
  static const int width8 = 112;

  /// Height 1× (normal).
  static const int height1 = 0;

  /// Height 2×.
  static const int height2 = 1;

  /// Height 3×.
  static const int height3 = 2;

  /// Height 4×.
  static const int height4 = 3;

  /// Height 5×.
  static const int height5 = 4;

  /// Height 6×.
  static const int height6 = 5;

  /// Height 7×.
  static const int height7 = 6;

  /// Height 8×.
  static const int height8 = 7;

  /// Default — 1×1 (normal).
  static const int normal = width1 | height1;
}
