/// Transport used to reach an XPrinter device.
///
/// Maps to the underlying SDK's `POSConnect.DEVICE_TYPE_*` constants:
/// - [bluetooth] — `DEVICE_TYPE_BLUETOOTH` (covers both Bluetooth Classic SPP
///   and BLE; the SDK / Android stack picks the right radio)
/// - [usb] — `DEVICE_TYPE_USB`
/// - [tcp] — `DEVICE_TYPE_ETHERNET` (WiFi or wired Ethernet, address is `ip` or
///   `ip:port`)
enum XprinterConnectionType {
  /// Bluetooth Classic SPP or BLE.
  bluetooth,

  /// USB host connection.
  usb,

  /// TCP/IP over WiFi or Ethernet (`POSConnect.DEVICE_TYPE_ETHERNET`).
  tcp,
}
