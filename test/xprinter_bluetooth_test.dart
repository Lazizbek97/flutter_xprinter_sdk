import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_xprinter_sdk/flutter_xprinter_sdk.dart';

const _discoveryChannel =
    MethodChannel('dev.lazizbekfayziev.flutter_xprinter_sdk/discovery');

/// Shorthand for the test binding's binary messenger — keeps lines under
// ignore: lines_longer_than_80_chars
TestDefaultBinaryMessengerBinding get _binding =>
    TestDefaultBinaryMessengerBinding.instance;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    _binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _discoveryChannel,
      null,
    );
  });

  group('XprinterBluetooth.startDiscovery', () {
    test('timeout cancels the EventChannel subscription only once', () async {
      final calls = <MethodCall>[];
      _binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _discoveryChannel,
        (call) async {
          calls.add(call);
          return null;
        },
      );

      final devices = await XprinterBluetooth.startDiscovery(
        timeout: Duration.zero,
      ).toList();

      expect(devices, isEmpty);
      expect(
        calls.map((call) => call.method),
        <String>['listen', 'cancel'],
      );
    });
  });
}
