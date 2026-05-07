import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_xprinter_sdk/flutter_xprinter_sdk.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'flutter_xprinter_sdk demo',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<XprinterBluetoothDevice> _devices = const [];
  XprinterBluetoothDevice? _selected;
  bool _scanning = false;
  bool _printing = false;
  int _paperSizeMm = 58;
  String _status = 'Idle';

  /// Loads already-paired Bluetooth devices.  For live advertising
  /// devices use `XprinterBluetooth.startDiscovery()` (stream API).
  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _status = 'Requesting permissions…';
    });
    try {
      if (!await _requestBluetoothPermissions()) {
        setState(() => _status = 'Bluetooth permission denied');
        return;
      }
      setState(() => _status = 'Loading paired devices…');
      final devices = await XprinterBluetooth.getBondedDevices();
      setState(() {
        _devices = devices;
        _selected = devices.isNotEmpty ? devices.first : null;
        _status = 'Found ${devices.length} device(s)';
      });
    } catch (e) {
      setState(() => _status = 'Scan failed: $e');
    } finally {
      setState(() => _scanning = false);
    }
  }

  /// Requests the runtime permissions Android 12+ needs for Bluetooth.
  /// iOS handles this through `Info.plist` so this is a no-op there.
  Future<bool> _requestBluetoothPermissions() async {
    if (!Platform.isAndroid) return true;
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    return results.values.every((s) => s.isGranted);
  }

  Future<void> _printDemoReceipt() async {
    final device = _selected;
    if (device == null) {
      setState(() => _status = 'Pick a device first');
      return;
    }

    setState(() {
      _printing = true;
      _status = 'Connecting…';
    });

    try {
      await XprinterConnection.connect(
        type: XprinterConnectionType.bluetooth,
        address: device.address,
      );

      await PosPrinter.initialize();
      // FS . — cancel multi-byte (Chinese) mode on Chinese-market models.
      await PosPrinter.sendRawCommand(Uint8List.fromList(<int>[0x1C, 0x2E]));
      await PosPrinter.selectCodePage(XprinterCodePage.pc866);
      XprinterLayout.configure(paperSizeMm: _paperSizeMm);

      setState(() => _status = 'Printing…');

      // ── 1. Logo from a Flutter asset (centred, top of receipt) ────────
      // Bundled in `assets/`.  Threshold-mode binarisation produces
      // crisp edges for line-art logos.
      final logoBytes = await XprinterImageLoader.fromAsset(
        assetPath: 'assets/dash-logo.png',
        targetWidthDots: XprinterLayout.widthDots,
        mode: XprinterImageMode.threshold,
      );
      if (logoBytes != null) {
        await PosPrinter.printBitmap(
          logoBytes,
          alignment: XprinterAlignment.center,
          widthDots: XprinterLayout.widthDots,
        );
        await PosPrinter.feedLine(1);
      }

      // ── 2. Shop header (centred, name in bold) ────────────────────────
      await XprinterLayout.printLine(
        'МАГАЗИН "АЛЬФА"',
        alignment: XprinterAlignment.center,
        bold: true,
      );
      await XprinterLayout.printLine(
        'ул. Чехова, 12, Ташкент',
        alignment: XprinterAlignment.center,
      );
      await XprinterLayout.printLine(
        'Тел: +998 90 123-45-67',
        alignment: XprinterAlignment.center,
      );
      await PosPrinter.feedLine(1);
      await XprinterLayout.printLine(
        'КАССОВЫЙ ЧЕК',
        alignment: XprinterAlignment.center,
        bold: true,
      );

      // ── 3. Date row, between two dotted dividers ──────────────────────
      await XprinterLayout.printSectionDivider(
        style: XprinterDividerStyle.dotted,
      );
      await XprinterLayout.printValueRow(
        'Дата: 07.05.2026',
        '14:32:18',
        leader: '',
      );
      await XprinterLayout.printSectionDivider(
        style: XprinterDividerStyle.dotted,
      );

      // ── 4. Items (label + price, no leader) ───────────────────────────
      await XprinterLayout.printValueRow(
        'Bonaqua 0,5 л',
        '8 000 сум',
        leader: '',
      );
      await XprinterLayout.printValueRow(
        'Хлеб 400 г x 2',
        '24 000 сум',
        leader: '',
      );
      await XprinterLayout.printValueRow(
        'Кефир 1 л',
        '15 000 сум',
        leader: '',
      );
      await XprinterLayout.printValueRow(
        'Скидка 10%',
        '-4 700 сум',
        leader: '',
      );
      await XprinterLayout.printSectionDivider(
        style: XprinterDividerStyle.dotted,
      );

      // ── 5. Totals (ИТОГО bold) ────────────────────────────────────────
      await XprinterLayout.printBoldRow(
        'ИТОГО',
        '42 300 сум',
        leader: '',
      );
      await XprinterLayout.printValueRow(
        'Наличные',
        '50 000 сум',
        leader: '',
      );
      await XprinterLayout.printValueRow(
        'Сдача',
        '7 700 сум',
        leader: '',
      );
      await XprinterLayout.printSectionDivider(
        style: XprinterDividerStyle.dotted,
      );

      // ── 6. Photo from a Flutter asset (centred, smaller width) ────────
      // Floyd-Steinberg dither preserves the photo's tonal gradients on
      // thermal paper — much better than the threshold path for non-line-art.
      final photoBytes = await XprinterImageLoader.fromAsset(
        assetPath: 'assets/dash.jpg',
        targetWidthDots: XprinterLayout.widthDots ~/ 2,
        mode: XprinterImageMode.dither,
      );
      if (photoBytes != null) {
        await PosPrinter.printBitmap(
          photoBytes,
          alignment: XprinterAlignment.center,
          widthDots: XprinterLayout.widthDots ~/ 2,
        );
        await PosPrinter.feedLine(1);
      }

      // ── 7. Footer ─────────────────────────────────────────────────────
      await XprinterLayout.printLine(
        'СПАСИБО ЗА ПОКУПКУ!',
        alignment: XprinterAlignment.center,
        bold: true,
      );
      await XprinterLayout.printLine(
        'Приходите ещё',
        alignment: XprinterAlignment.center,
      );
      await PosPrinter.feedLine(1);

      // ── 8. QR code (e.g. link to a digital copy of this receipt) ──────
      await PosPrinter.printQRCode(
        'https://github.com/Lazizbek97/flutter_xprinter_sdk',
        moduleSize: 6,
      );
      await PosPrinter.feedLine(1);

      // ── 9. Barcode (e.g. receipt number) ──────────────────────────────
      await PosPrinter.printBarCode(
        '1234567890128',
        type: XprinterBarcodeType.ean13,
        height: 60,
      );

      // ── 10. Cut & finish ──────────────────────────────────────────────
      await PosPrinter.feedLine(3);
      await PosPrinter.cutPaper();

      // Buffer drain before disconnect so the receipt tail isn't truncated.
      await Future<void>.delayed(const Duration(seconds: 2));

      setState(() => _status = 'Done');
    } catch (e) {
      setState(() => _status = 'Print failed: $e');
    } finally {
      try {
        await XprinterConnection.disconnect();
      } catch (_) {}
      setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('flutter_xprinter_sdk demo')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Text('Paper size: '),
                  for (final mm in const [58, 72, 80])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text('${mm}mm'),
                        selected: _paperSizeMm == mm,
                        onSelected: (_) => setState(() => _paperSizeMm = mm),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                icon: _scanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bluetooth_searching),
                label: Text(_scanning ? 'Scanning…' : 'Scan for printers'),
                onPressed: _scanning ? null : _scan,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _devices.isEmpty
                    ? const Center(child: Text('No devices yet — tap Scan'))
                    : RadioGroup<XprinterBluetoothDevice>(
                        groupValue: _selected,
                        onChanged: (v) => setState(() => _selected = v),
                        child: ListView.separated(
                          itemCount: _devices.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final d = _devices[i];
                            return RadioListTile<XprinterBluetoothDevice>(
                              title: Text(d.name),
                              subtitle: Text(d.address),
                              value: d,
                            );
                          },
                        ),
                      ),
              ),
              FilledButton.icon(
                icon: _printing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print),
                label: Text(_printing ? 'Printing…' : 'Print demo receipt'),
                onPressed:
                    (_printing || _selected == null) ? null : _printDemoReceipt,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(6),
                ),
                // text should be copyable to clipboard for debugging, so no SelectableText here.

                child: SelectableText(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
