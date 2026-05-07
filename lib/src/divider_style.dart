/// Visual style of [XprinterLayout.printSectionDivider].
enum XprinterDividerStyle {
  /// Solid black bar, paper-width — the default.  Heavy visual break.
  solid,

  /// `--------` repeated to fill the line.  Lighter than solid.
  dashed,

  /// `........` repeated.  Lightest visible divider.
  dotted,

  /// Just a blank line for breathing space — no visible mark.
  blank,
}
