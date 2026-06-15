# flutter_xprinter_sdk example

The example prints the same full receipt on:

- Android/iOS using Bluetooth discovery.
- Windows 10+ using USB or TCP/IP.

## Windows setup

The plugin bundles the vendor x64 `printer.sdk.dll`, so no separate Windows
SDK installation is required. Run:

```bash
flutter run -d windows
```

The example UI lets you choose USB or TCP/IP.

## Minimal Windows code

USB, first connected XPrinter:

```dart
await XprinterConnection.connect(
  type: XprinterConnectionType.usb,
  address: '',
);
```

USB by model or port number:

```dart
await XprinterConnection.connect(
  type: XprinterConnectionType.usb,
  address: 'USB031', // Or a model such as 4B-2054A.
);
```

TCP/IP:

```dart
await XprinterConnection.connect(
  type: XprinterConnectionType.tcp,
  address: '192.168.1.100:9100',
);
```

Print and disconnect:

```dart
await PosPrinter.initialize();
await PosPrinter.printText(
  'Hello from Windows',
  alignment: XprinterAlignment.center,
  attribute: XprinterTextAttribute.bold,
);
await PosPrinter.printQRCode('https://example.com');
await PosPrinter.feedLine(3);
await PosPrinter.cutPaper();
await XprinterConnection.disconnect();
```

The XPrinter Windows SDK does not provide direct Bluetooth discovery or
MAC-address connections.
