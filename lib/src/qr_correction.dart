/// QR-code error correction level, mapping to `POSConst.QRCODE_EC_LEVEL_*`
/// (48..51).
enum XprinterQrCorrection {
  /// L — recovers ~7 % of data.
  l(48),

  /// M — recovers ~15 %.
  m(49),

  /// Q — recovers ~25 %.
  q(50),

  /// H — recovers ~30 % (densest module pattern).
  h(51);

  const XprinterQrCorrection(this.nativeValue);

  /// Native integer value passed through the Method Channel.
  final int nativeValue;
}
