// ignore_for_file: document_ignores

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_xprinter_sdk/src/method_channel.dart';
import 'package:flutter_xprinter_sdk/src/xprinter_exception.dart';

/// A Bluetooth device the OS knows about — either currently bonded
/// (`getBondedDevices`) or seen during the latest discovery sweep
/// (`startDiscovery`).
///
/// `name` may be empty for a freshly-found device that hasn't completed
/// SDP yet, or when the name lookup raised SecurityException — the address
/// is always present.
class XprinterBluetoothDevice {
  /// Creates a device record — usually constructed by the platform layer,
  /// but exposed publicly so consumers can build fixtures in tests.
  const XprinterBluetoothDevice({
    required this.address,
    required this.name,
  });

  factory XprinterBluetoothDevice._fromMap(Map<dynamic, dynamic> map) {
    return XprinterBluetoothDevice(
      address: (map['address'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
    );
  }

  /// Hardware MAC address (`AA:BB:CC:DD:EE:FF`).
  final String address;

  /// Friendly name advertised by the device, or empty.
  final String name;

  @override
  String toString() => 'XprinterBluetoothDevice($address, "$name")';
}

/// Bluetooth scanner + bonded-list helpers backed by the platform
/// native Bluetooth APIs on Android and iOS.
///
/// The XPrinter SDK itself doesn't expose Bluetooth discovery — it
/// expects you to hand it a MAC.  This class fills that gap so the app
/// only needs one Bluetooth dependency for printers.
///
/// The vendor Windows SDK does not expose Bluetooth discovery, so Windows
/// returns an empty bonded-device list and [startDiscovery] emits an
/// `unsupported_transport` error.
///
/// **Permissions:**
/// - Android 12+ (API 31+): `BLUETOOTH_CONNECT` and `BLUETOOTH_SCAN`
///   runtime permissions must be granted by the app before calling.
/// - Pre-Android-12 (API < 31): `ACCESS_FINE_LOCATION` is required by the
///   OS to receive discovery results.
abstract final class XprinterBluetooth {
  static const EventChannel _discoveryChannel =
      EventChannel('dev.lazizbekfayziev.flutter_xprinter_sdk/discovery');

  /// Returns every Bluetooth device the OS already remembers as bonded —
  /// i.e. paired in the system Bluetooth settings.
  ///
  /// This is the path that catches cheap thermal printers (XP-58IIT,
  /// GP-58, Bixolon, …) that go silent on inquiry once they've been
  /// paired with the phone.  They never appear in [startDiscovery] but
  /// they're still here.
  ///
  /// Throws [XprinterException] if the runtime permission is missing or
  /// the platform call fails.
  static Future<List<XprinterBluetoothDevice>> getBondedDevices() async {
    try {
      // ignore: lines_longer_than_80_chars
      final raw =
          await xprinterMethodChannel.invokeListMethod<Map<dynamic, dynamic>>(
        'getBondedDevices',
      );
      if (raw == null) return const [];
      return raw.map(XprinterBluetoothDevice._fromMap).toList(growable: false);
    } on PlatformException catch (e) {
      throw XprinterException(e.code, e.message ?? 'unknown');
    }
  }

  /// Streams classic-Bluetooth devices as the OS finds them.
  ///
  /// Listening starts inquiry; cancelling the subscription (or letting
  /// [timeout] elapse, if provided) stops inquiry and unregisters the
  /// underlying receiver.
  ///
  /// Each event is one device.  Duplicates *can* be emitted across runs
  /// or back-to-back inquiries — callers should dedupe by `address`.
  ///
  /// Errors surface as [XprinterException] inside the stream.
  static Stream<XprinterBluetoothDevice> startDiscovery({
    Duration? timeout,
  }) {
    final controller = StreamController<XprinterBluetoothDevice>();
    StreamSubscription<dynamic>? sub;
    Timer? timer;
    var closing = false;

    Future<void> cancelPlatformStream() {
      final activeSub = sub;
      sub = null;
      return activeSub?.cancel() ?? Future<void>.value();
    }

    void closeAll({
      Object? error,
      StackTrace? stack,
      bool cancelPlatformSubscription = true,
    }) {
      if (closing) return;
      closing = true;
      timer?.cancel();
      timer = null;
      if (cancelPlatformSubscription) {
        unawaited(cancelPlatformStream());
      } else {
        sub = null;
      }
      if (error != null && !controller.isClosed) {
        controller.addError(error, stack);
      }
      if (!controller.isClosed) controller.close();
    }

    controller
      ..onListen = () {
        sub = _discoveryChannel.receiveBroadcastStream().listen(
          (event) {
            if (event is Map) {
              controller.add(XprinterBluetoothDevice._fromMap(event));
            }
          },
          onError: (Object e, StackTrace st) {
            final mapped = e is PlatformException
                ? XprinterException(
                    e.code,
                    e.message ?? 'unknown',
                  )
                : e;
            closeAll(error: mapped, stack: st);
          },
          onDone: () {
            closeAll(cancelPlatformSubscription: false);
          },
        );
        if (timeout != null) {
          timer = Timer(timeout, closeAll);
        }
      }
      ..onCancel = () {
        timer?.cancel();
        timer = null;
        return cancelPlatformStream();
      };

    return controller.stream;
  }
}
