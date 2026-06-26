import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_xprinter_sdk/flutter_xprinter_sdk.dart';

const _channel = MethodChannel('dev.lazizbekfayziev.flutter_xprinter_sdk');
const _cp866TextMode = <int>[0x1C, 0x2E, 0x1B, 0x74, 0x11];
const _alignLeft = <int>[0x1B, 0x61, 0x00];
const _alignCenter = <int>[0x1B, 0x61, 0x01];
const _boldOn = <int>[0x1B, 0x45, 0x01];
const _boldOff = <int>[0x1B, 0x45, 0x00];

/// Shorthand for the test binding's binary messenger.
TestDefaultBinaryMessengerBinding get _binding =>
    TestDefaultBinaryMessengerBinding.instance;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;

  setUp(() {
    calls = <MethodCall>[];
    _binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
  });

  tearDown(() {
    _binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  List<int> rawBytesFor(MethodCall call) {
    final args = call.arguments as Map<Object?, Object?>;
    return List<int>.from(args['bytes']! as Uint8List);
  }

  group('XprinterLayout raw text mode', () {
    test('printLine cancels Chinese mode and selects CP866', () async {
      await XprinterLayout.printLine(
        'OK',
        alignment: XprinterAlignment.center,
        bold: true,
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'sendRawCommand');
      expect(rawBytesFor(calls.single), <int>[
        ..._cp866TextMode,
        ..._alignCenter,
        ..._boldOn,
        0x4F,
        0x4B,
        ..._boldOff,
        0x0A,
      ]);
    });

    test('composed rows also reset mode before CP866 bytes', () async {
      await XprinterLayout.printValueRow('A', 'B', leader: '');

      final bytes = rawBytesFor(calls.single);
      expect(
        bytes.take(_cp866TextMode.length + _alignLeft.length).toList(),
        <int>[..._cp866TextMode, ..._alignLeft],
      );
    });
  });
}
