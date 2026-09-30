import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_xprinter_sdk/flutter_xprinter_sdk.dart';
import 'package:image/image.dart' as img;

const _channel = MethodChannel('dev.lazizbekfayziev.flutter_xprinter_sdk');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds a complete TSPL job for XP-245B', () {
    final label = LabelPrinter(widthMm: 48, heightMm: 30, gapMm: 2)
      ..addText('Milk', x: 16, y: 12)
      ..addBarcode('1234567890', x: 16, y: 55)
      ..addQrCode('SKU-1', x: 280, y: 12);
    final commands = ascii.decode(label.build(copies: 2));
    expect(
        commands, startsWith('SIZE 48.00 mm,30.00 mm\r\nGAP 2.00 mm,0 mm\r\n'));
    expect(commands, contains('CLS\r\nTEXT 16,12,"3",0,1,1,"Milk"\r\n'));
    expect(
        commands, contains('BARCODE 16,55,"128",80,1,0,2,2,"1234567890"\r\n'));
    expect(commands, contains('QRCODE 280,12,M,4,A,0,"SKU-1"\r\n'));
    expect(commands, endsWith('PRINT 2\r\n'));
  });

  test('black pixels clear bits; padding and transparency stay white', () {
    final image = img.Image(width: 9, height: 1, numChannels: 4);
    img.fill(image, color: img.ColorRgba8(255, 255, 255, 255));
    image.setPixelRgba(0, 0, 0, 0, 0, 255);
    image.setPixelRgba(8, 0, 0, 0, 0, 255);
    image.setPixelRgba(1, 0, 0, 0, 0, 0);
    final label = LabelPrinter(widthMm: 48, heightMm: 30)
      ..addImage(Uint8List.fromList(img.encodePng(image)), x: 0, y: 0);
    final bytes = label.build();
    final header = ascii.encode('BITMAP 0,0,2,1,0,');
    final offset = _indexOf(bytes, header) + header.length;
    // TSPL prints the 0 bits: only pixels 0 and 8 are black.
    expect(bytes.sublist(offset, offset + 4), <int>[0x7f, 0x7f, 13, 10]);
  });

  test('sends one label job through printLabel', () async {
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      received = call;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null));

    await LabelPrinter(widthMm: 48, heightMm: 30).print();
    expect(received!.method, 'printLabel');
    final bytes = (received!.arguments as Map<Object?, Object?>)['bytes'];
    expect(ascii.decode(bytes as Uint8List), contains('PRINT 1\r\n'));
  });

  test('rejects invalid dimensions and command injection', () {
    expect(() => LabelPrinter(widthMm: 0, heightMm: 30), throwsArgumentError);
    final label = LabelPrinter(widthMm: 48, heightMm: 30);
    expect(
        () => label.addText('a"\r\nPRINT 99', x: 0, y: 0), throwsArgumentError);
    expect(() => label.build(copies: 0), throwsArgumentError);
  });
}

int _indexOf(List<int> bytes, List<int> pattern) {
  for (var i = 0; i <= bytes.length - pattern.length; i++) {
    var matches = true;
    for (var j = 0; j < pattern.length; j++) {
      if (bytes[i + j] != pattern[j]) matches = false;
    }
    if (matches) return i;
  }
  return -1;
}
