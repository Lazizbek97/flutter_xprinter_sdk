#import <Flutter/Flutter.h>
#import <Foundation/Foundation.h>

/**
 * Single-connection, single-instance manager owning the active XPrinter
 * connection (BT or TCP) and dispatching all MethodChannel calls from the
 * Flutter side.
 *
 * Doubles as the [FlutterStreamHandler] for the discovery EventChannel:
 * `onListen` starts a BLE scan via `POSBLEManager`, each peripheral
 * surfaces in `POSbleUpdatePeripheralList:RSSIList:`, and we forward it
 * to the Dart side as a `{address, name}` map.  Cancelling stops the
 * scan and releases the sink.
 *
 * Mirrors the Android `XprinterSdkManager` Kotlin class one-for-one so
 * the Dart layer stays platform-agnostic.
 */
@interface XprinterSdkManager : NSObject <FlutterStreamHandler>

// ── Connection layer ───────────────────────────────────────────────────
- (void)connect:(NSDictionary *)args result:(FlutterResult)result;
- (void)disconnect:(FlutterResult)result;
- (void)isConnected:(FlutterResult)result;

// ── Bluetooth scan / pair helpers ─────────────────────────────────────
- (void)getBondedDevices:(FlutterResult)result;

// ── Print methods ──────────────────────────────────────────────────────
- (void)initialize:(FlutterResult)result;
- (void)printText:(NSDictionary *)args result:(FlutterResult)result;
- (void)printBitmap:(NSDictionary *)args result:(FlutterResult)result;
- (void)printHorizontalLine:(NSDictionary *)args result:(FlutterResult)result;
- (void)printQRCode:(NSDictionary *)args result:(FlutterResult)result;
- (void)printBarCode:(NSDictionary *)args result:(FlutterResult)result;
- (void)feedLine:(NSDictionary *)args result:(FlutterResult)result;
- (void)cutPaper:(NSDictionary *)args result:(FlutterResult)result;
- (void)selectCodePage:(NSDictionary *)args result:(FlutterResult)result;
- (void)setAlignment:(NSDictionary *)args result:(FlutterResult)result;
- (void)getStatus:(FlutterResult)result;
- (void)sendRawCommand:(NSDictionary *)args result:(FlutterResult)result;

@end
