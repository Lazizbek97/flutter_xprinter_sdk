import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_xprinter_sdk/flutter_xprinter_sdk.dart';

void main() {
  group('PrinterStatus.fromNativeValue', () {
    test('STS_UNKNOWN (-1): isOnline=false, hasError=true', () {
      final s = PrinterStatus.fromNativeValue(-1);
      expect(s.isOnline, isFalse);
      expect(s.hasError, isTrue);
      expect(s.isReady, isFalse);
      expect(s.rawValue, -1);
    });

    test('STS_NORMAL (0): everything clean', () {
      final s = PrinterStatus.fromNativeValue(0);
      expect(s.isOnline, isTrue);
      expect(s.isCoverOpen, isFalse);
      expect(s.isPaperOut, isFalse);
      expect(s.hasError, isFalse);
      expect(s.isReady, isTrue);
    });

    test('STS_COVEROPEN (0x10) only', () {
      final s = PrinterStatus.fromNativeValue(0x10);
      expect(s.isCoverOpen, isTrue);
      expect(s.isPaperOut, isFalse);
      expect(s.hasError, isFalse);
      expect(s.isReady, isFalse);
    });

    test('STS_PAPEREMPTY (0x20) only', () {
      final s = PrinterStatus.fromNativeValue(0x20);
      expect(s.isPaperOut, isTrue);
      expect(s.isCoverOpen, isFalse);
      expect(s.hasError, isFalse);
      expect(s.isReady, isFalse);
    });

    test('STS_PRINTER_ERR (0x40) only', () {
      final s = PrinterStatus.fromNativeValue(0x40);
      expect(s.hasError, isTrue);
      expect(s.isReady, isFalse);
    });

    test('STS_PRESS_FEED (0x08) only', () {
      final s = PrinterStatus.fromNativeValue(0x08);
      expect(s.isPaperFeedPressed, isTrue);
      expect(s.isReady, isTrue);
    });

    test('combined cover-open + paper-out (0x30)', () {
      final s = PrinterStatus.fromNativeValue(0x30);
      expect(s.isCoverOpen, isTrue);
      expect(s.isPaperOut, isTrue);
      expect(s.isReady, isFalse);
    });
  });
}
