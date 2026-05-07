/// Barcode symbology, mapping to `POSConst.BCS_*` integer constants.
///
/// `EAN8 = 68` and `JAN8 = 68` collide in the SDK; same for `EAN13/JAN13 = 67`.
/// We expose only the EAN names.
enum XprinterBarcodeType {
  /// UPC-A.
  upcA(65),

  /// UPC-E.
  upcE(66),

  /// EAN-8 (also JAN-8).
  ean8(68),

  /// EAN-13 (also JAN-13).
  ean13(67),

  /// Interleaved 2 of 5 (ITF).
  itf(70),

  /// Codabar (NW-7).
  codabar(71),

  /// Code 39.
  code39(69),

  /// Code 93.
  code93(72),

  /// Code 128 — most flexible, commonly used for receipts.
  code128(73);

  const XprinterBarcodeType(this.nativeValue);

  /// Native integer value passed through the Method Channel.
  final int nativeValue;
}

/// Position of human-readable interpretation (HRI) text relative to the
/// barcode.  Maps to `POSConst.HRI_TEXT_*`.
enum XprinterBarcodeHri {
  /// No HRI text.
  none(0),

  /// HRI text printed above the barcode.
  above(1),

  /// HRI text printed below the barcode.
  below(2),

  /// HRI text printed both above and below.
  both(3);

  const XprinterBarcodeHri(this.nativeValue);

  /// Native integer value passed through the Method Channel.
  final int nativeValue;
}
