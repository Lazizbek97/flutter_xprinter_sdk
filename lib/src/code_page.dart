/// Printer code page selection, mapping to `POSConst.CODE_PAGE_*`.
///
/// Only the values we actually need are exposed.  `pc866` (= 17) is the
/// Cyrillic page used for Russian / Uzbek receipts.
enum XprinterCodePage {
  /// PC437 — US, standard Europe.
  pc437(0),

  /// Katakana.
  katakana(1),

  /// PC850 — Multilingual.
  pc850(2),

  /// PC860 — Portuguese.
  pc860(3),

  /// PC863 — Canadian-French.
  pc863(4),

  /// PC865 — Nordic.
  pc865(5),

  /// Cyrillic — Russian, Uzbek (Cyrillic), etc.
  pc866(17),

  /// PC858 — Multilingual + Euro.
  pc858(19),

  /// Windows-1252 (Latin 1).
  wpc1252(16);

  const XprinterCodePage(this.nativeValue);

  /// Native integer value passed through the Method Channel.
  final int nativeValue;
}
