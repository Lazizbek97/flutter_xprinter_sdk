/// Flutter plugin for the XPrinter Android, iOS, and Windows SDKs.
///
/// Exposes a connection layer (Bluetooth / USB / TCP) and a receipt-relevant
/// subset of `POSPrinter` print methods.  See the package README for the full
/// coverage matrix and intentional omissions.
library;

export 'src/alignment.dart';
export 'src/barcode_type.dart';
export 'src/code_page.dart';
export 'src/connection_type.dart';
export 'src/cp866_encoder.dart';
export 'src/divider_style.dart';
export 'src/image_dither.dart';
export 'src/image_loader.dart';
export 'src/pos_printer.dart';
export 'src/printer_status.dart';
export 'src/qr_correction.dart';
export 'src/receipt_layout.dart';
export 'src/text_attribute.dart';
export 'src/xprinter_bluetooth.dart';
export 'src/xprinter_connection.dart';
export 'src/xprinter_exception.dart';
