import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_xprinter_sdk/flutter_xprinter_sdk.dart';

const _channel = MethodChannel('dev.lazizbekfayziev.flutter_xprinter_sdk');

/// Shorthand for the test binding's binary messenger — keeps lines under
// ignore: lines_longer_than_80_chars
TestDefaultBinaryMessengerBinding get _binding => TestDefaultBinaryMessengerBinding.instance;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    _binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (call) async {
        calls.add(call);
        switch (call.method) {
          case 'getStatus':
            return 0; // STS_NORMAL
        }
        return null;
      },
    );
  });

  tearDown(() {
    _binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  group('PosPrinter.printText', () {
    test('encodes text + alignment + attribute + textSize', () async {
      await PosPrinter.printText(
        'hello',
        alignment: XprinterAlignment.center,
        attribute: XprinterTextAttribute.bold,
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'printText');
      expect(calls.single.arguments, <String, Object?>{
        'text': 'hello',
        'alignment': 1, // CENTER
        'attribute': 8, // BOLD
        'textSize': 0, // normal
      });
    });

    test('combined attribute (bold | underline) is OR-ed correctly', () async {
      await PosPrinter.printText(
        'x',
        attribute: XprinterTextAttribute.bold | XprinterTextAttribute.underline,
      );

      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['attribute'], 8 | 128);
    });

    test('combined textSize (width2 | height2) for 2× scale', () async {
      await PosPrinter.printText(
        'x',
        textSize: XprinterTextSize.width2 | XprinterTextSize.height2,
      );

      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['textSize'], 16 | 1);
    });
  });

  group('PosPrinter.printBitmap', () {
    test('passes byte buffer + alignment + mode', () async {
      final bytes = Uint8List.fromList(List<int>.filled(8, 0xFF));
      await PosPrinter.printBitmap(bytes);
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['bytes'], bytes);
      expect(args['alignment'], 1);
      expect(args['widthDots'], 384);
    });
  });

  group('PosPrinter.printQRCode', () {
    test('encodes module size + correction + alignment', () async {
      await PosPrinter.printQRCode(
        'https://example.com',
        moduleSize: 5,
        errorCorrection: XprinterQrCorrection.h,
      );
      expect(calls.single.arguments, <String, Object?>{
        'content': 'https://example.com',
        'moduleSize': 5,
        'errorCorrection': 51, // EC_LEVEL_H
        'alignment': 1,
      });
    });
  });

  group('PosPrinter.printBarCode', () {
    test('Code128 type maps to 73', () async {
      await PosPrinter.printBarCode(
        '00040123456',
        type: XprinterBarcodeType.code128,
        hri: XprinterBarcodeHri.below,
      );
      final args = calls.single.arguments as Map<Object?, Object?>;
      expect(args['content'], '00040123456');
      expect(args['type'], 73);
      expect(args['hri'], 2);
    });
  });

  group('PosPrinter.cutPaper', () {
    test('half-cut by default', () async {
      await PosPrinter.cutPaper();
      expect(calls.single.arguments, <String, Object?>{'half': true});
    });

    test('full cut when half=false', () async {
      await PosPrinter.cutPaper(half: false);
      expect(calls.single.arguments, <String, Object?>{'half': false});
    });
  });

  group('PosPrinter.feedLine', () {
    test('default 1 line', () async {
      await PosPrinter.feedLine();
      expect(calls.single.arguments, <String, Object?>{'lines': 1});
    });

    test('explicit count', () async {
      await PosPrinter.feedLine(3);
      expect(calls.single.arguments, <String, Object?>{'lines': 3});
    });
  });

  group('PosPrinter.selectCodePage', () {
    test('PC866 = 17 for Cyrillic', () async {
      await PosPrinter.selectCodePage(XprinterCodePage.pc866);
      expect(calls.single.arguments, <String, Object?>{'page': 17});
    });
  });

  group('PosPrinter.getStatus', () {
    test('parses native int into PrinterStatus', () async {
      final status = await PosPrinter.getStatus();
      expect(status.isOnline, isTrue);
      expect(status.isReady, isTrue);
      expect(calls.single.method, 'getStatus');
    });
  });

  group('error wrapping', () {
    test('PlatformException becomes XprinterException', () async {
      _binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        (call) async {
          throw PlatformException(code: 'not_connected', message: 'offline');
        },
      );

      expect(
        () => PosPrinter.printText('x'),
        throwsA(
          isA<XprinterException>()
              .having((e) => e.code, 'code', 'not_connected')
              .having((e) => e.message, 'message', 'offline'),
        ),
      );
    });
  });
}
