/// Horizontal alignment for text and other printable elements.
///
/// Maps to `POSConst.ALIGNMENT_*` integer constants:
/// `LEFT = 0`, `CENTER = 1`, `RIGHT = 2`.
enum XprinterAlignment {
  /// Left-aligned (`POSConst.ALIGNMENT_LEFT = 0`).
  left,

  /// Center-aligned (`POSConst.ALIGNMENT_CENTER = 1`).
  center,

  /// Right-aligned (`POSConst.ALIGNMENT_RIGHT = 2`).
  right;

  /// Native integer value passed through the Method Channel.
  int get nativeValue => index;
}
