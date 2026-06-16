# Changelog

## 0.2.0

### Added
- **Windows 10+** support through XPrinter's ESC/POS Windows SDK 2.0.4.
- USB and TCP/IP connections on Windows.
- Windows implementations for text, bitmap, divider, QR code, barcode, feed,
  cut, code-page, alignment, status, and raw-command APIs.
- The x64 `printer.sdk.dll` is bundled with the plugin and copied into the
  Windows runner automatically by Flutter's build.
- The Android `printer-lib-3.2.0.aar` is bundled with the plugin, including
  its native libraries, so host apps no longer need a separate AAR copy.
- The iOS `libPrinterSDK.a` and vendor headers are bundled with the plugin,
  so host apps no longer need to run the setup command.

### Platform note
- The vendor Windows SDK does not provide direct Bluetooth discovery or
  MAC-address connections. Windows Bluetooth calls return an explicit
  `unsupported_transport` error.

## 0.1.1

### Fixed
- **Android**: `BLUETOOTH` and `BLUETOOTH_ADMIN` permissions no longer capped at API 30.  Some XPrinter SDK code paths still call legacy `BluetoothAdapter` APIs on Android 12+ devices and require these permissions at runtime; capping them at `maxSdkVersion="30"` produced `SecurityException` on certain MIUI / OEM-modified devices at `XprinterConnection.connect`.

## 0.1.0

Initial release.

### Connectivity
- Bluetooth Classic (Android) and BLE (iOS) discovery, pairing, and connect.
- USB host transport (Android only).
- TCP/IP transport (Wi-Fi / Ethernet).

### Printing
- Text rows (single line, with optional bold and alignment).
- Bold-label / plain-value information rows.
- Dotted-leader value rows (`label .... value`) with auto-fallback to two-line layout when content overflows.
- Fully bold rows (totals, section headers).
- Section dividers — paper-width solid line with breathing space.
- QR codes and barcodes (Code128, EAN13).
- Bitmap printing (raster, with widthDots).
- Paper feed and cut.

### Cyrillic
- `encodeToCp866(String)` — pure-Dart Cyrillic-to-CP866 encoder. Bypasses Android `Charset` API which silently returns `?` on devices without the CP866 charset registered.

### Image preparation
- `XprinterImageDither.binarise()` — Floyd-Steinberg or hard threshold, auto-detects content type (logo vs photo).
- `XprinterImageLoader.fromUrl()` / `.fromAsset()` / `.fromBytes()` — download or load + resize + binarise in one call. Returns print-ready PNG bytes.

### Receipt layout helpers
- `XprinterLayout.configure(paperSizeMm:)` — adapts character count + dot width for 58 / 72 / 80 mm.
- Public layout API: `printLine`, `printInfoRow`, `printValueRow`, `printPlainRow`, `printBoldRow`, `printDiscountRow`, `printSectionDivider`, `printAssetIcon`, `printIconTextRow`.

### Compatibility
- Tested on XP-58IIT (58 mm), XP-C260M (80 mm).
- iOS 14+, Android 5+ (`minSdkVersion 21`).
