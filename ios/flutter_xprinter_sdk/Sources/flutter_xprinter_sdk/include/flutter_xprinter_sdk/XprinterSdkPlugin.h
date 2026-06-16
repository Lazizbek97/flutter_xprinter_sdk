#import <Flutter/Flutter.h>

/**
 * Flutter plugin entry point for the XPrinter iOS SDK wrapper.
 *
 * Mirrors the Android `XprinterSdkPlugin` (Kotlin): one MethodChannel for
 * connection + print operations, one EventChannel for Bluetooth-discovery
 * stream events.  The shared Dart layer (`xprinter_sdk` package) is the
 * single API surface — callers shouldn't need to know which platform this
 * runs on.
 */
@interface XprinterSdkPlugin : NSObject <FlutterPlugin>
@end
