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

  setUp(
    () {
      calls = <MethodCall>[];
      _binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        (call) async {
          calls.add(call);
          switch (call.method) {
            case 'connect':
              return true;
            case 'isConnected':
              return true;
            case 'disconnect':
              return null;
          }
          return null;
        },
      );
    },
  );

  tearDown(() {
    _binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
  });

  group('XprinterConnection.connect', () {
    test('bluetooth: encodes type and address into native args', () async {
      await XprinterConnection.connect(
        type: XprinterConnectionType.bluetooth,
        address: 'AA:BB:CC:DD:EE:FF',
      );

      expect(calls, hasLength(1));
      expect(calls.single.method, 'connect');
      expect(calls.single.arguments, <String, Object?>{
        'type': 'bluetooth',
        'address': 'AA:BB:CC:DD:EE:FF',
      });
    });

    test('usb: encodes type "usb"', () async {
      await XprinterConnection.connect(
        type: XprinterConnectionType.usb,
        address: '/dev/bus/usb/001/002',
      );

      expect(calls.single.arguments, <String, Object?>{
        'type': 'usb',
        'address': '/dev/bus/usb/001/002',
      });
    });

    test('tcp: encodes type "tcp"', () async {
      await XprinterConnection.connect(
        type: XprinterConnectionType.tcp,
        address: '192.168.1.50',
      );

      expect(calls.single.arguments, <String, Object?>{
        'type': 'tcp',
        'address': '192.168.1.50',
      });
    });

    test('platform exception is wrapped into XprinterException', () async {
      _binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _channel,
        (call) async {
          throw PlatformException(code: 'connect_fail', message: 'no device');
        },
      );

      expect(
        () => XprinterConnection.connect(
          type: XprinterConnectionType.bluetooth,
          address: 'AA:BB:CC:DD:EE:FF',
        ),
        throwsA(
          isA<XprinterException>()
              .having((e) => e.code, 'code', 'connect_fail')
              .having((e) => e.message, 'message', 'no device'),
        ),
      );
    });
  });

  group('XprinterConnection.disconnect', () {
    test('invokes "disconnect" with no args', () async {
      await XprinterConnection.disconnect();
      expect(calls.single.method, 'disconnect');
      expect(calls.single.arguments, isNull);
    });
  });

  group('XprinterConnection.isConnected', () {
    test('returns native boolean result', () async {
      final result = await XprinterConnection.isConnected();
      expect(result, isTrue);
      expect(calls.single.method, 'isConnected');
    });

    test('returns false when native returns null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async => null);

      final result = await XprinterConnection.isConnected();
      expect(result, isFalse);
    });
  });
}
