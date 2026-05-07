/// A failure originating from the XPrinter SDK or its Method Channel bridge.
///
/// [code] mirrors the native error code (e.g. `connect_fail`, `invalid_args`,
/// `printer_error`) so callers can branch on it.  [message] is human-readable
/// detail forwarded from the SDK or the bridge.
class XprinterException implements Exception {
  /// Creates an exception with a stable [code] and human-readable [message].
  XprinterException(this.code, this.message);

  /// Stable identifier suitable for branching in client code.
  final String code;

  /// Human-readable detail — surfaced in logs, not localized.
  final String message;

  @override
  String toString() => 'XprinterException($code): $message';
}
