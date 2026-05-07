/// Parsed result of `PosPrinter.getStatus`.
///
/// The XPrinter SDK's `printerStatus` callback returns a single integer.
/// `POSConst.STS_*` defines the bit values:
/// - `STS_UNKNOWN = -1` — communication failure
/// - `STS_NORMAL = 0` — no flags set
/// - `STS_PRESS_FEED = 8` — paper-feed button pressed
/// - `STS_COVEROPEN = 16` — cover open
/// - `STS_PAPEREMPTY = 32` — out of paper
/// - `STS_PRINTER_ERR = 64` — generic printer error (cutter / overheat /
///   anything else the firmware flags)
class PrinterStatus {
  /// Creates a status with the parsed flags and the original raw value.
  const PrinterStatus({
    required this.isOnline,
    required this.isCoverOpen,
    required this.isPaperOut,
    required this.isPaperFeedPressed,
    required this.hasError,
    required this.rawValue,
  });

  /// Parses the integer returned by `IStatusCallback.receive`.
  factory PrinterStatus.fromNativeValue(int value) {
    if (value < 0) {
      // STS_UNKNOWN — can't reach the printer.
      return PrinterStatus(
        isOnline: false,
        isCoverOpen: false,
        isPaperOut: false,
        isPaperFeedPressed: false,
        hasError: true,
        rawValue: value,
      );
    }
    return PrinterStatus(
      isOnline: true,
      isCoverOpen: (value & _stsCoverOpen) != 0,
      isPaperOut: (value & _stsPaperEmpty) != 0,
      isPaperFeedPressed: (value & _stsPressFeed) != 0,
      hasError: (value & _stsPrinterErr) != 0,
      rawValue: value,
    );
  }

  /// Whether the printer responded at all.  False means `STS_UNKNOWN` (-1).
  final bool isOnline;

  /// Cover / lid is open.
  final bool isCoverOpen;

  /// Paper roll is empty.
  final bool isPaperOut;

  /// The paper-feed button is currently pressed.
  final bool isPaperFeedPressed;

  /// Generic printer error flag (cutter jam, overheat, etc.).
  final bool hasError;

  /// Original integer value reported by the SDK.
  final int rawValue;

  /// True iff none of the error / abnormal flags are set.
  bool get isReady => isOnline && !isCoverOpen && !isPaperOut && !hasError;

  static const int _stsPressFeed = 0x08;
  static const int _stsCoverOpen = 0x10;
  static const int _stsPaperEmpty = 0x20;
  static const int _stsPrinterErr = 0x40;

  @override
  String toString() => 'PrinterStatus(raw=$rawValue, online=$isOnline, '
      'coverOpen=$isCoverOpen, paperOut=$isPaperOut, error=$hasError)';
}
