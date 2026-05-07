#import "XprinterSdkManager.h"

#import <CoreBluetooth/CoreBluetooth.h>
#import <UIKit/UIKit.h>

#import "POSBLEManager.h"
#import "POSCommand.h"
#import "POSImageTranster.h"
#import "POSWIFIManager.h"

// MARK: - Connection state -------------------------------------------------

typedef NS_ENUM(NSInteger, XprinterTransport) {
    XprinterTransportNone = 0,
    XprinterTransportBluetooth,
    XprinterTransportTcp,
};

// Connect timeout when we have to scan to find a peripheral by UUID.
// The user has already paired and is asking to print — 12 s gives the
// printer two advertising windows on slow links plus some grace for the
// CBCentralManager to power up if this is a cold start.
static const NSTimeInterval kConnectScanTimeout = 12.0;

// All NSLog from the manager goes through this so the user can grep
// Console.app for `[XprinterSdk]` and see exactly what happened.
#define XLog(fmt, ...) NSLog(@"[XprinterSdk] " fmt, ##__VA_ARGS__)

// Default barcode height when caller didn't supply one (matches Android).
static const int kDefaultBarcodeHeight = 162;

// MARK: - Manager ----------------------------------------------------------

@interface XprinterSdkManager () <POSBLEManagerDelegate, POSWIFIManagerDelegate>

// Active transport (BT / TCP / none).
@property (nonatomic, assign) XprinterTransport currentTransport;

// Discovery EventChannel sink — non-nil while a Dart listener is attached.
@property (nonatomic, copy, nullable) FlutterEventSink discoverySink;

// Cache of peripherals seen during scans, keyed by UUID string (lowercase).
// Used by `connect` to find a CBPeripheral after the user picked one.
@property (nonatomic, strong) NSMutableDictionary<NSString *, CBPeripheral *> *peripheralCache;

// Pending BT connect — set when the Dart side asks to connect by UUID and
// we haven't yet seen the peripheral on a scan.  The FlutterResult is held
// so we can complete it once the SDK fires connect / fail-to-connect.
@property (nonatomic, copy, nullable) NSString *pendingConnectAddress;
@property (nonatomic, copy, nullable) FlutterResult pendingConnectResult;

// Pending TCP connect — same idea, resolved on POSwifiConnectedToHost.
@property (nonatomic, copy, nullable) FlutterResult pendingTcpConnectResult;

// Tick set when our connect path has issued startScan and is waiting
// either for the matching peripheral or for the CBCentralManager state
// to transition to poweredOn.  Used by `POSbleCentralManagerDidUpdateState:`
// to retry the scan once Bluetooth comes online.
@property (nonatomic, assign) BOOL pendingConnectScanArmed;

// Receipt-bytes accumulator for the BLE transport.  Allocated on connect,
// appended by every `print*` / `set*` / `select*` MethodChannel call,
// flushed in one shot by `cutPaper` / `disconnect` / `getStatus`.  Mirrors
// the demo app's pattern: build the entire receipt in NSMutableData, then
// do exactly ONE `writeCommandWithData:writeCallBack:`.  See
// `docs/superpowers/specs/2026-04-27-ios-batched-write-design.md`.
@property (nonatomic, strong, nullable) NSMutableData *pendingBleBuffer;

// Held while a `_flushBleBuffer:` is in flight so we can complete the
// triggering call's FlutterResult when the SDK's write callback fires
// (or on disconnect, with a CONNECTION_LOST error).
@property (nonatomic, copy, nullable) FlutterResult pendingFlushResult;

@end

@implementation XprinterSdkManager

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentTransport = XprinterTransportNone;
        _peripheralCache = [NSMutableDictionary dictionary];
        // Deliberately do NOT touch [POSBLEManager sharedInstance] or
        // [POSWIFIManager sharedInstance] here.  The first access lazily
        // creates a CBCentralManager / GCDAsyncSocket inside the SDK,
        // which is too heavy for `+registerWithRegistrar:` (it runs
        // during `application:didFinishLaunchingWithOptions:` — anything
        // expensive there can trip the iOS launch watchdog or stall the
        // Dart VM service handshake).  We attach delegates lazily, just
        // before any operation that actually needs them.
    }
    return self;
}

- (void)_attachBleDelegateIfNeeded {
    POSBLEManager *m = [POSBLEManager sharedInstance];
    if (m.delegate != self) m.delegate = self;
}

- (void)_attachWifiDelegateIfNeeded {
    POSWIFIManager *m = [POSWIFIManager sharedInstance];
    if (m.delegate != self) m.delegate = self;
}

// MARK: - Connection layer -----------------------------------------------

- (void)connect:(NSDictionary *)args result:(FlutterResult)result {
    NSString *type = args[@"type"];
    NSString *address = args[@"address"];

    if (![type isKindOfClass:[NSString class]] || ![address isKindOfClass:[NSString class]]) {
        result([FlutterError errorWithCode:@"INVALID_ARGS"
                                   message:@"connect requires non-null 'type' and 'address' strings"
                                   details:nil]);
        return;
    }

    // Hand-off any prior connection — the Dart side guarantees one
    // active connection at a time, but the user may have killed the
    // app last time without disconnecting cleanly.
    [self _teardownExistingConnectionsForReconnect];

    if ([type isEqualToString:@"tcp"]) {
        [self _connectTcp:address result:result];
        return;
    }

    if ([type isEqualToString:@"bluetooth"]) {
        [self _connectBluetooth:address result:result];
        return;
    }

    if ([type isEqualToString:@"usb"] || [type isEqualToString:@"serial"]) {
        result([FlutterError errorWithCode:@"UNSUPPORTED_TRANSPORT"
                                   message:[NSString stringWithFormat:@"Transport '%@' is not available on iOS", type]
                                   details:nil]);
        return;
    }

    result([FlutterError errorWithCode:@"INVALID_ARGS"
                               message:[NSString stringWithFormat:@"Unknown transport '%@'", type]
                               details:nil]);
}

- (void)_teardownExistingConnectionsForReconnect {
    // Cancel any pending connect that hasn't completed yet.  The
    // dispatch_after block we armed in `_armConnectTimeout` will still
    // fire on schedule, but it self-aborts when `pendingConnectResult` is
    // nil, so there's nothing to invalidate explicitly.
    self.pendingConnectAddress = nil;
    self.pendingConnectScanArmed = NO;
    if (self.pendingConnectResult) {
        FlutterResult prev = self.pendingConnectResult;
        self.pendingConnectResult = nil;
        prev([FlutterError errorWithCode:@"SUPERSEDED"
                                 message:@"connect superseded by a newer connect call"
                                 details:nil]);
    }
    if (self.pendingTcpConnectResult) {
        FlutterResult prev = self.pendingTcpConnectResult;
        self.pendingTcpConnectResult = nil;
        prev([FlutterError errorWithCode:@"SUPERSEDED"
                                 message:@"connect superseded by a newer connect call"
                                 details:nil]);
    }
    if ([[POSBLEManager sharedInstance] printerIsConnect]) {
        [[POSBLEManager sharedInstance] disconnectRootPeripheral];
    }
    if ([[POSWIFIManager sharedInstance] printerIsConnect]) {
        [[POSWIFIManager sharedInstance] disconnect];
    }
    self.currentTransport = XprinterTransportNone;
    // Discard any leftover BLE buffer from a previous connection — its
    // bytes belong to a now-defunct printer and would corrupt the next
    // receipt if accidentally flushed later.
    self.pendingBleBuffer = nil;
    if (self.pendingFlushResult) {
        FlutterResult prev = self.pendingFlushResult;
        self.pendingFlushResult = nil;
        prev([FlutterError errorWithCode:@"SUPERSEDED"
                                 message:@"connection torn down before flush completed"
                                 details:nil]);
    }
}

- (void)_connectTcp:(NSString *)address result:(FlutterResult)result {
    // Address is `host` or `host:port`.  Default port matches Android.
    NSArray<NSString *> *parts = [address componentsSeparatedByString:@":"];
    NSString *host = parts.firstObject;
    UInt16 port = 9100;
    if (parts.count >= 2) {
        NSInteger parsed = parts[1].integerValue;
        if (parsed > 0 && parsed <= UINT16_MAX) port = (UInt16)parsed;
    }

    [self _attachWifiDelegateIfNeeded];
    self.pendingTcpConnectResult = result;
    self.currentTransport = XprinterTransportTcp;
    [[POSWIFIManager sharedInstance] connectWithHost:host port:port];
}

- (void)_connectBluetooth:(NSString *)uuidString result:(FlutterResult)result {
    [self _attachBleDelegateIfNeeded];
    NSString *key = uuidString.lowercaseString;
    CBPeripheral *cached = self.peripheralCache[key];

    XLog(@"connect bluetooth address=%@ cacheCount=%lu cacheHit=%@",
         uuidString, (unsigned long)self.peripheralCache.count,
         cached ? @"YES" : @"NO");

    if (cached) {
        // Fast path: peripheral seen during a recent scan.
        self.pendingConnectAddress = key;
        self.pendingConnectResult = result;
        self.currentTransport = XprinterTransportBluetooth;
        [[POSBLEManager sharedInstance] connectDevice:cached];
        [self _armConnectTimeout];
        return;
    }

    // Cold path: we don't have a CBPeripheral object — start a scan and
    // wait for the matching UUID to advertise.  This is the path that
    // runs after the user kills the app and re-opens it: peripheral
    // cache is empty but they expect to print to the saved printer.
    self.pendingConnectAddress = key;
    self.pendingConnectResult = result;
    self.currentTransport = XprinterTransportBluetooth;
    self.pendingConnectScanArmed = YES;

    XLog(@"cold connect — starting scan, will retry when CB powers on if needed");
    [[POSBLEManager sharedInstance] startScan];
    [self _armConnectTimeout];
}

/// Dispatches the connect-fail timeout on the main queue.  We deliberately
/// avoid `NSTimer scheduledTimerWithTimeInterval:` because it requires the
/// scheduling thread's run loop to be pumping — Flutter's platform thread
/// runs a CFRunLoop but some MethodChannel call paths land us on a
/// transient queue that doesn't, and the NSTimer would never fire.
- (void)_armConnectTimeout {
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                 (int64_t)(kConnectScanTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(),
                   ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (!self.pendingConnectResult) return;  // Already resolved.

        XLog(@"connect timeout fired — no peripheral matched after %.0fs",
             kConnectScanTimeout);
        [[POSBLEManager sharedInstance] stopScan];
        FlutterResult pending = self.pendingConnectResult;
        self.pendingConnectAddress = nil;
        self.pendingConnectResult = nil;
        self.pendingConnectScanArmed = NO;
        self.currentTransport = XprinterTransportNone;
        pending([FlutterError errorWithCode:@"NOT_FOUND"
                                    message:@"Printer not advertising — make sure it's powered on and within Bluetooth range"
                                    details:nil]);
    });
}

- (void)disconnect:(FlutterResult)result {
    // BLE: if there are unflushed bytes (Dart didn't call cutPaper, or
    // hit an error mid-receipt), flush them first so they don't get
    // dropped when we tear down the connection.  Flush errors are
    // swallowed — disconnect must always succeed from the caller's view.
    if (self.currentTransport == XprinterTransportBluetooth &&
        self.pendingBleBuffer.length > 0) {
        XLog(@"disconnect with %lu unflushed bytes — flushing first",
             (unsigned long)self.pendingBleBuffer.length);
        __weak typeof(self) weakSelf = self;
        [self _flushBleBuffer:^(id _Nullable flushResult) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) {
                result(nil);
                return;
            }
            [[POSBLEManager sharedInstance] disconnectRootPeripheral];
            self.currentTransport = XprinterTransportNone;
            self.pendingBleBuffer = nil;
            result(nil);
        }];
        return;
    }

    if (self.currentTransport == XprinterTransportBluetooth) {
        [[POSBLEManager sharedInstance] disconnectRootPeripheral];
    } else if (self.currentTransport == XprinterTransportTcp) {
        [[POSWIFIManager sharedInstance] disconnect];
    }
    self.currentTransport = XprinterTransportNone;
    self.pendingBleBuffer = nil;
    result(nil);
}

- (void)isConnected:(FlutterResult)result {
    BOOL connected = NO;
    if (self.currentTransport == XprinterTransportBluetooth) {
        connected = [[POSBLEManager sharedInstance] printerIsConnect];
    } else if (self.currentTransport == XprinterTransportTcp) {
        connected = [[POSWIFIManager sharedInstance] printerIsConnect];
    }
    result(@(connected));
}

// MARK: - Bluetooth scan / pair helpers ----------------------------------

- (void)getBondedDevices:(FlutterResult)result {
    // iOS doesn't expose a "bonded devices" list to apps — Apple hides
    // the system Bluetooth bond table.  The only way to surface a saved
    // printer is to re-scan and wait for its advertisement.  Returning
    // an empty list here is the right answer; callers fall back to
    // discovery (the Dart `add_device_bloc.dart` already handles this).
    result(@[]);
}

// MARK: - Discovery EventChannel ------------------------------------------

- (FlutterError * _Nullable)onListenWithArguments:(id _Nullable)arguments
                                        eventSink:(FlutterEventSink)events {
    [self _attachBleDelegateIfNeeded];
    self.discoverySink = events;
    [self.peripheralCache removeAllObjects];
    [[POSBLEManager sharedInstance] startScan];
    return nil;
}

- (FlutterError * _Nullable)onCancelWithArguments:(id _Nullable)arguments {
    self.discoverySink = nil;
    // Only stop scanning if there's no pending connect that needs the
    // scan to keep running — otherwise we'd kill our own connect path.
    if (!self.pendingConnectAddress) {
        [[POSBLEManager sharedInstance] stopScan];
    }
    return nil;
}

// MARK: - POSBLEManagerDelegate ------------------------------------------

- (void)POSbleUpdatePeripheralList:(NSArray *)peripherals RSSIList:(NSArray *)rssiList {
    XLog(@"scan callback — %lu peripherals", (unsigned long)peripherals.count);
    for (CBPeripheral *p in peripherals) {
        NSString *uuid = p.identifier.UUIDString.lowercaseString;
        if (uuid.length == 0) continue;
        BOOL isNew = (self.peripheralCache[uuid] == nil);
        self.peripheralCache[uuid] = p;

        if (isNew) {
            XLog(@"discovered %@ name=%@", p.identifier.UUIDString, p.name ?: @"(nil)");
        }

        // Forward to discovery EventChannel listener if attached.
        if (isNew && self.discoverySink) {
            self.discoverySink(@{
                @"address": p.identifier.UUIDString,
                @"name": p.name ?: @"",
            });
        }

        // If this is the peripheral our pendingConnect is waiting on,
        // fire connect now — and only once.  The scan callback can fire
        // back-to-back with the same peripheral; calling `connectDevice:`
        // twice wedges the SDK's internal characteristic-discovery layer
        // (BLE connect succeeds but writes silently never deliver).
        // Clear `pendingConnectAddress` and stop the scan immediately so
        // a second callback can't re-trigger.
        if (self.pendingConnectAddress &&
            [uuid isEqualToString:self.pendingConnectAddress]) {
            XLog(@"pending connect matched — calling connectDevice: (deduped)");
            self.pendingConnectAddress = nil;
            self.pendingConnectScanArmed = NO;
            [[POSBLEManager sharedInstance] stopScan];
            [[POSBLEManager sharedInstance] connectDevice:p];
        }
    }
}

- (void)POSbleConnectPeripheral:(CBPeripheral *)peripheral {
    XLog(@"connect succeeded for %@", peripheral.identifier.UUIDString);
    [[POSBLEManager sharedInstance] stopScan];
    self.pendingConnectScanArmed = NO;
    // Fresh buffer for this connection — every receipt printed during
    // this BT session will accumulate here until cutPaper / disconnect.
    self.pendingBleBuffer = [NSMutableData data];
    if (self.pendingConnectResult) {
        FlutterResult pending = self.pendingConnectResult;
        self.pendingConnectAddress = nil;
        self.pendingConnectResult = nil;
        pending(nil);
    }
}

- (void)POSbleFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    XLog(@"connect failed: %@", error.localizedDescription ?: @"(nil)");
    [[POSBLEManager sharedInstance] stopScan];
    self.pendingConnectScanArmed = NO;
    self.currentTransport = XprinterTransportNone;
    if (self.pendingConnectResult) {
        FlutterResult pending = self.pendingConnectResult;
        self.pendingConnectAddress = nil;
        self.pendingConnectResult = nil;
        pending([FlutterError errorWithCode:@"CONNECT_FAIL"
                                    message:error.localizedDescription ?: @"Bluetooth connect failed"
                                    details:nil]);
    }
}

- (void)POSbleDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    XLog(@"disconnect: %@ error=%@",
         peripheral.identifier.UUIDString,
         error.localizedDescription ?: @"(nil)");
    if (self.currentTransport == XprinterTransportBluetooth) {
        self.currentTransport = XprinterTransportNone;
    }
    // If we were mid-flush, the SDK's write callback is never going to
    // fire.  Resolve the pending result with CONNECTION_LOST so Dart can
    // surface a real error instead of hanging on `await`.
    if (self.pendingFlushResult) {
        FlutterResult pending = self.pendingFlushResult;
        self.pendingFlushResult = nil;
        pending([FlutterError errorWithCode:@"CONNECTION_LOST"
                                    message:error.localizedDescription ?: @"Bluetooth connection lost mid-write"
                                    details:nil]);
    }
    // Discard whatever's still buffered — there's no connection to send it on.
    self.pendingBleBuffer = nil;
}

- (void)POSbleCentralManagerDidUpdateState:(NSInteger)state {
    // States: 0 unknown, 1 resetting, 2 unsupported, 3 unauthorized,
    // 4 poweredOff, 5 poweredOn.
    XLog(@"CB state changed → %ld", (long)state);

    if (state == 5) {
        // poweredOn: if we issued startScan while CB was still in
        // `unknown`/`resetting`, that scan was a silent no-op.  Re-issue
        // it now so the pending connect actually has a chance.
        if (self.pendingConnectScanArmed) {
            XLog(@"CB now poweredOn — restarting scan for pending connect");
            [[POSBLEManager sharedInstance] startScan];
        }
        if (self.discoverySink) {
            // Same idea for an attached discovery listener.
            [[POSBLEManager sharedInstance] startScan];
        }
        return;
    }

    if (state == 4 && self.discoverySink) {
        self.discoverySink([FlutterError errorWithCode:@"BLUETOOTH_OFF"
                                               message:@"Bluetooth is turned off"
                                               details:nil]);
    } else if (state == 3 && self.discoverySink) {
        self.discoverySink([FlutterError errorWithCode:@"BLUETOOTH_UNAUTHORIZED"
                                               message:@"Bluetooth permission denied — enable in Settings"
                                               details:nil]);
    }
}

// MARK: - POSWIFIManagerDelegate -----------------------------------------

- (void)POSwifiConnectedToHost:(NSString *)host port:(UInt16)port {
    if (self.pendingTcpConnectResult) {
        FlutterResult pending = self.pendingTcpConnectResult;
        self.pendingTcpConnectResult = nil;
        pending(nil);
    }
}

- (void)POSwifiDisconnectWithError:(NSError *)error {
    if (self.currentTransport == XprinterTransportTcp) {
        self.currentTransport = XprinterTransportNone;
    }
    if (self.pendingTcpConnectResult) {
        FlutterResult pending = self.pendingTcpConnectResult;
        self.pendingTcpConnectResult = nil;
        pending([FlutterError errorWithCode:@"CONNECT_FAIL"
                                    message:error.localizedDescription ?: @"TCP connect failed"
                                    details:nil]);
    }
}

// MARK: - Print methods ---------------------------------------------------

- (void)initialize:(FlutterResult)result {
    [self _writeData:[POSCommand initializePrinter] result:result];
}

- (void)printText:(NSDictionary *)args result:(FlutterResult)result {
    NSString *text = args[@"text"];
    if (![text isKindOfClass:[NSString class]]) {
        result([FlutterError errorWithCode:@"INVALID_ARGS" message:@"printText requires 'text'" details:nil]);
        return;
    }
    int attribute = [args[@"attribute"] intValue];
    int textWid = [args[@"textWidth"] intValue];
    int textHei = [args[@"textHeight"] intValue];
    int alignment = [args[@"alignment"] intValue];

    NSData *cmd = [POSCommand printText:text
                              alignment:alignment
                              attribute:attribute
                                textWid:textWid
                                textHei:textHei];
    [self _writeData:cmd result:result];
}

- (void)printBitmap:(NSDictionary *)args result:(FlutterResult)result {
    FlutterStandardTypedData *typed = args[@"bytes"];
    NSData *bytes = typed.data;
    int widthDots = [args[@"widthDots"] intValue];
    int alignment = [args[@"alignment"] intValue];
    if (bytes.length == 0) {
        result([FlutterError errorWithCode:@"INVALID_ARGS" message:@"printBitmap requires non-empty 'bytes'" details:nil]);
        return;
    }

    UIImage *raw = [UIImage imageWithData:bytes];
    if (!raw) {
        result([FlutterError errorWithCode:@"DECODE_FAIL" message:@"Could not decode bitmap bytes — expected PNG/JPEG/BMP" details:nil]);
        return;
    }

    // Resize to the requested print width, preserving aspect ratio,
    // matching the behaviour of the Android `printBitmap(bytes, widthDots)`.
    UIImage *sized = (widthDots > 0) ? [self _resizeImage:raw toWidthInDots:widthDots] : raw;

    NSMutableData *cmd = [NSMutableData data];
    [cmd appendData:[POSCommand selectAlignment:alignment]];
    [cmd appendData:[POSCommand printRasteBmpWithM:RasterNolmorWH andImage:sized andType:Dithering]];
    [self _writeData:cmd result:result];
}

- (void)printHorizontalLine:(NSDictionary *)args result:(FlutterResult)result {
    int widthDots = [args[@"widthDots"] intValue];
    int heightRows = [args[@"heightRows"] intValue];
    int alignment = [args[@"alignment"] intValue];
    if (widthDots <= 0) widthDots = 384;
    if (heightRows <= 0) heightRows = 4;
    // The SDK's iOS image encoder quantises away images thinner than ~3
    // rows when using Dithering mode — a 2-row solid black bar comes out
    // blank.  Floor to 4 rows so the section divider always renders.
    if (heightRows < 4) heightRows = 4;

    UIImage *line = [self _solidBlackImageWithWidth:widthDots height:heightRows];
    NSMutableData *cmd = [NSMutableData data];
    [cmd appendData:[POSCommand selectAlignment:alignment]];
    // Threshold mode is the right choice for solid line art — every
    // pixel is pure black so a hard threshold preserves the line
    // perfectly.  Dithering mode (used for photo-like content) tries to
    // spread quantisation error across pixels and on iOS can drop very
    // thin solid fills entirely.
    [cmd appendData:[POSCommand printRasteBmpWithM:RasterNolmorWH andImage:line andType:Threshold]];
    [self _writeData:cmd result:result];
}

- (void)printQRCode:(NSDictionary *)args result:(FlutterResult)result {
    NSString *content = args[@"content"];
    int moduleSize = [args[@"moduleSize"] intValue];
    int errorCorrection = [args[@"errorCorrection"] intValue];
    int alignment = [args[@"alignment"] intValue];
    if (![content isKindOfClass:[NSString class]] || content.length == 0) {
        result([FlutterError errorWithCode:@"INVALID_ARGS" message:@"printQRCode requires non-empty 'content'" details:nil]);
        return;
    }
    if (moduleSize <= 0) moduleSize = 4;
    // SDK uses ASCII codes 48..51 for QR error correction levels.
    if (errorCorrection < 48 || errorCorrection > 51) errorCorrection = 49;  // M

    NSMutableData *cmd = [NSMutableData data];
    [cmd appendData:[POSCommand selectAlignment:alignment]];
    [cmd appendData:[POSCommand printQRCode:moduleSize
                                       level:errorCorrection
                                        code:content
                                useEnCodeing:NSUTF8StringEncoding]];
    [self _writeData:cmd result:result];
}

- (void)printBarCode:(NSDictionary *)args result:(FlutterResult)result {
    NSString *content = args[@"content"];
    int barcodeType = [args[@"barcodeType"] intValue];
    int height = [args[@"height"] intValue];
    int width = [args[@"width"] intValue];
    int alignment = [args[@"alignment"] intValue];
    if (![content isKindOfClass:[NSString class]] || content.length == 0) {
        result([FlutterError errorWithCode:@"INVALID_ARGS" message:@"printBarCode requires non-empty 'content'" details:nil]);
        return;
    }
    if (height <= 0) height = kDefaultBarcodeHeight;
    if (width <= 0) width = 3;

    NSMutableData *cmd = [NSMutableData data];
    [cmd appendData:[POSCommand selectAlignment:alignment]];
    [cmd appendData:[POSCommand setBarcodeHeight:height]];
    [cmd appendData:[POSCommand setBarcodeWidth:width]];
    // Barcode type values 66..73 use the "with N" overload for code length.
    if (barcodeType >= 66 && barcodeType <= 79) {
        [cmd appendData:[POSCommand printBarcodeWithM:barcodeType
                                                 andN:(int)content.length
                                           andContent:content
                                         useEnCodeing:NSUTF8StringEncoding]];
    } else {
        [cmd appendData:[POSCommand printBarcodeWithM:barcodeType
                                           andContent:content
                                         useEnCodeing:NSUTF8StringEncoding]];
    }
    [self _writeData:cmd result:result];
}

- (void)feedLine:(NSDictionary *)args result:(FlutterResult)result {
    int lines = [args[@"lines"] intValue];
    if (lines <= 0) lines = 1;
    [self _writeData:[POSCommand printAndFeedForwardWhitN:lines] result:result];
}

- (void)cutPaper:(NSDictionary *)args result:(FlutterResult)result {
    NSData *cutBytes = [POSCommand selectCutPageModelAndCutpage:1];

    if (self.currentTransport == XprinterTransportBluetooth) {
        if (![[POSBLEManager sharedInstance] printerIsConnect]) {
            result([FlutterError errorWithCode:@"NOT_CONNECTED" message:@"Bluetooth printer not connected" details:nil]);
            return;
        }
        // Append the cut command to the receipt buffer, then flush the
        // entire buffer (init + content + cut) in one BLE write.  The
        // FlutterResult resolves only after the SDK's BLE write callback
        // fires — that's when the bytes are actually on the wire.
        if (!self.pendingBleBuffer) {
            self.pendingBleBuffer = [NSMutableData data];
        }
        [self.pendingBleBuffer appendData:cutBytes];
        XLog(@"buffer append %lu bytes (cut, total %lu)",
             (unsigned long)cutBytes.length,
             (unsigned long)self.pendingBleBuffer.length);
        [self _flushBleBuffer:result];
        return;
    }

    // TCP / unknown — direct write (no batching).
    [self _writeData:cutBytes result:result];
}

- (void)selectCodePage:(NSDictionary *)args result:(FlutterResult)result {
    int page = [args[@"page"] intValue];
    [self _writeData:[POSCommand setCodePage:page] result:result];
}

- (void)setAlignment:(NSDictionary *)args result:(FlutterResult)result {
    int alignment = [args[@"alignment"] intValue];
    [self _writeData:[POSCommand selectAlignment:alignment] result:result];
}

- (void)getStatus:(FlutterResult)result {
    if (self.currentTransport == XprinterTransportBluetooth) {
        // Status is a query, not a print, but it shares the same BLE
        // write characteristic.  Flush any pending receipt bytes first
        // so we never inject a status request mid-receipt.
        if (self.pendingBleBuffer.length > 0) {
            __weak typeof(self) weakSelf = self;
            [self _flushBleBuffer:^(id _Nullable flushResult) {
                __strong typeof(weakSelf) self = weakSelf;
                if (!self) return;
                [[POSBLEManager sharedInstance] printerStatus:^(NSData *status) {
                    result([self _statusByteToInt:status]);
                }];
            }];
            return;
        }
        [[POSBLEManager sharedInstance] printerStatus:^(NSData *status) {
            result([self _statusByteToInt:status]);
        }];
        return;
    }
    if (self.currentTransport == XprinterTransportTcp) {
        [[POSWIFIManager sharedInstance] printerStatus:^(NSData *status) {
            result([self _statusByteToInt:status]);
        }];
        return;
    }
    result([FlutterError errorWithCode:@"NOT_CONNECTED" message:@"Printer not connected" details:nil]);
}

- (void)sendRawCommand:(NSDictionary *)args result:(FlutterResult)result {
    FlutterStandardTypedData *typed = args[@"bytes"];
    if (!typed.data) {
        result([FlutterError errorWithCode:@"INVALID_ARGS" message:@"sendRawCommand requires 'bytes'" details:nil]);
        return;
    }
    [self _writeData:typed.data result:result];
}

// MARK: - Private helpers -------------------------------------------------

- (void)_writeData:(NSData *)data result:(FlutterResult)result {
    if (data.length == 0) {
        result(nil);
        return;
    }

    if (self.currentTransport == XprinterTransportBluetooth) {
        if (![[POSBLEManager sharedInstance] printerIsConnect]) {
            result([FlutterError errorWithCode:@"NOT_CONNECTED" message:@"Bluetooth printer not connected" details:nil]);
            return;
        }
        // BLE path: append bytes to the buffer.  The actual SDK write
        // happens once per receipt in `_flushBleBuffer:`, triggered by
        // `cutPaper` / `disconnect` / `getStatus`.  This matches the
        // demo's "build a single NSMutableData, write once" pattern.
        if (!self.pendingBleBuffer) {
            self.pendingBleBuffer = [NSMutableData data];
        }
        [self.pendingBleBuffer appendData:data];
        XLog(@"buffer append %lu bytes (total %lu)",
             (unsigned long)data.length,
             (unsigned long)self.pendingBleBuffer.length);
        result(nil);
        return;
    }

    if (self.currentTransport == XprinterTransportTcp) {
        if (![[POSWIFIManager sharedInstance] printerIsConnect]) {
            result([FlutterError errorWithCode:@"NOT_CONNECTED" message:@"TCP printer not connected" details:nil]);
            return;
        }
        // TCP is a real socket — kernel-level flow control already.  No
        // batching, no callback dance — the SDK's `writeCommandWithData:`
        // returns when the bytes are accepted by the kernel.
        [[POSWIFIManager sharedInstance] writeCommandWithData:data];
        result(nil);
        return;
    }

    result([FlutterError errorWithCode:@"NOT_CONNECTED" message:@"No active printer connection" details:nil]);
}

/// Flushes the BLE buffer in exactly one `writeCommandWithData:writeCallBack:`
/// call to the SDK.  This is the only place we issue BLE writes for the
/// BT transport.
///
/// The buffer is snapshotted and reset to a fresh empty `NSMutableData`
/// *before* the write fires, so any `print*` calls that arrive while the
/// flush is in flight land in the new buffer and go out on the next flush.
///
/// `result` resolves on the main queue:
/// - `nil` on success
/// - `FlutterError(WRITE_FAIL)` if the SDK callback reports an error
/// - `FlutterError(CONNECTION_LOST)` if `POSbleDisconnectPeripheral:` fires
///   while we're still waiting for the callback (handled in that delegate)
- (void)_flushBleBuffer:(FlutterResult)result {
    NSMutableData *buf = self.pendingBleBuffer;
    if (buf.length == 0) {
        result(nil);
        return;
    }

    NSData *snapshot = [buf copy];
    self.pendingBleBuffer = [NSMutableData data];
    self.pendingFlushResult = result;

    XLog(@"flush %lu bytes", (unsigned long)snapshot.length);
    [[POSBLEManager sharedInstance] writeCommandWithData:snapshot writeCallBack:^(CBCharacteristic *characteristic, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            FlutterResult pending = self.pendingFlushResult;
            if (!pending) {
                // Already resolved (e.g. by POSbleDisconnectPeripheral:
                // firing CONNECTION_LOST before this callback arrived).
                XLog(@"flush callback (orphaned) error=%@", error.localizedDescription ?: @"OK");
                return;
            }
            self.pendingFlushResult = nil;
            if (error) {
                XLog(@"flush callback error: %@", error.localizedDescription);
                pending([FlutterError errorWithCode:@"WRITE_FAIL"
                                            message:error.localizedDescription ?: @"BLE write failed"
                                            details:nil]);
            } else {
                XLog(@"flush callback success: OK");
                pending(nil);
            }
        });
    }];
}

- (UIImage *)_resizeImage:(UIImage *)src toWidthInDots:(int)widthDots {
    CGFloat targetW = (CGFloat)widthDots;
    CGFloat scale = (src.size.width > 0) ? (targetW / src.size.width) : 1.0;
    CGFloat targetH = MAX(1.0, src.size.height * scale);
    CGSize size = CGSizeMake(targetW, targetH);
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    [[UIColor whiteColor] setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    [src drawInRect:CGRectMake(0, 0, size.width, size.height)];
    UIImage *resized = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return resized ?: src;
}

- (UIImage *)_solidBlackImageWithWidth:(int)widthDots height:(int)heightRows {
    CGSize size = CGSizeMake(widthDots, heightRows);
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    [[UIColor blackColor] setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

- (NSNumber *)_statusByteToInt:(NSData *)status {
    if (status.length == 0) return @0;
    const uint8_t *bytes = status.bytes;
    return @(bytes[0]);
}

@end
