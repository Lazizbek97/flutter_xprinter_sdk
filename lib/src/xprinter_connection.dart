import 'package:flutter/services.dart';
import 'package:flutter_xprinter_sdk/src/connection_type.dart';
import 'package:flutter_xprinter_sdk/src/method_channel.dart';
import 'package:flutter_xprinter_sdk/src/xprinter_exception.dart';

/// Connection lifecycle for an XPrinter device.
///
/// Single-connection model: only one printer connection at a time.  Calling
/// [connect] while another connection is open closes the previous one
/// automatically.
abstract final class XprinterConnection {
  /// Opens a connection to a printer.
  ///
  /// [type] selects the transport.  [address] is interpreted per transport:
  ///
  /// - [XprinterConnectionType.bluetooth]: MAC address (e.g. `AA:BB:CC:00`)
  /// - [XprinterConnectionType.usb]: USB device name from
  ///   `POSConnect.getUsbDevices` (e.g. `/dev/bus/usb/001/002`)
  /// - [XprinterConnectionType.tcp]: IPv4 address, optionally with `:port`
  ///   (default port is the printer's default — usually 9100)
  ///
  /// Throws [XprinterException] on failure.  Returns when the underlying
  /// `connectSync` reports success (call blocks on the native side).
  static Future<void> connect({
    required XprinterConnectionType type,
    required String address,
  }) async {
    try {
      await xprinterMethodChannel.invokeMethod<bool>(
        'connect',
        <String, Object?>{'type': type.name, 'address': address},
      );
    } on PlatformException catch (e) {
      throw XprinterException(e.code, e.message ?? 'unknown');
    }
  }

  /// Closes the current connection if one is open.  Safe to call when nothing
  /// is connected — completes silently.
  static Future<void> disconnect() async {
    try {
      await xprinterMethodChannel.invokeMethod<void>('disconnect');
    } on PlatformException catch (e) {
      throw XprinterException(e.code, e.message ?? 'unknown');
    }
  }

  /// Returns whether a printer connection is currently open and reachable.
  static Future<bool> isConnected() async {
    try {
      final result = await xprinterMethodChannel.invokeMethod<bool>(
        'isConnected',
      );
      return result ?? false;
    } on PlatformException catch (e) {
      throw XprinterException(e.code, e.message ?? 'unknown');
    }
  }
}
