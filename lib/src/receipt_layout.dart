import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:flutter_xprinter_sdk/src/alignment.dart';
import 'package:flutter_xprinter_sdk/src/cp866_encoder.dart';
import 'package:flutter_xprinter_sdk/src/divider_style.dart';
import 'package:flutter_xprinter_sdk/src/image_dither.dart';
import 'package:flutter_xprinter_sdk/src/pos_printer.dart';

/// Layout primitives for receipt rows on XPrinter hardware.  Each helper
/// composes one atomic LF-terminated row; rate-limited by [_interRowPause]
/// to keep the printer's input buffer from overflowing.
abstract final class XprinterLayout {
  /// Per-row pause to keep the print head ahead of the input buffer.
  static const Duration _interRowPause = Duration(milliseconds: 50);

  /// Chars per line at Font A.  Set per print job by [configure].
  static int _charsPerLine = 32;

  /// Print head width in dots.  Set per print job by [configure].
  static int _widthDots = 384;

  static int get widthDots => _widthDots;
  static int get charsPerLine => _charsPerLine;

  /// Configures layout for a paper size.  Call before any helper.
  /// Supports 58 / 72 / 80 mm; unknown sizes fall back to 58 mm.
  static void configure({required int paperSizeMm}) {
    switch (paperSizeMm) {
      case 80:
        _charsPerLine = 48;
        _widthDots = 576;
      case 72:
        _charsPerLine = 42;
        _widthDots = 512;
      case 58:
      default:
        _charsPerLine = 32;
        _widthDots = 384;
    }
  }

  static const List<int> _boldOn = <int>[0x1B, 0x45, 0x01]; // ESC E 1
  static const List<int> _boldOff = <int>[0x1B, 0x45, 0x00]; // ESC E 0
  static const int _lf = 0x0A;

  /// ESC a 0 — reset alignment to LEFT.  Prefixed to raw-byte rows
  /// because `printBitmap` leaves the printer in CENTER alignment.
  static const List<int> _alignLeft = <int>[0x1B, 0x61, 0x00];

  /// Section divider, paper-width.  [style] picks the look; [heightRows]
  /// only applies to [XprinterDividerStyle.solid].
  static Future<void> printSectionDivider({
    XprinterDividerStyle style = XprinterDividerStyle.solid,
    int heightRows = 2,
  }) async {
    switch (style) {
      case XprinterDividerStyle.solid:
        await PosPrinter.sendRawCommand(Uint8List.fromList(<int>[_lf]));
        await PosPrinter.printHorizontalLine(
          heightRows: heightRows,
          widthDots: _widthDots,
        );
        await PosPrinter.sendRawCommand(Uint8List.fromList(<int>[_lf]));
      case XprinterDividerStyle.dashed:
        await PosPrinter.sendRawCommand(Uint8List.fromList(<int>[_lf]));
        await printLine('-' * _charsPerLine);
      case XprinterDividerStyle.dotted:
        await PosPrinter.sendRawCommand(Uint8List.fromList(<int>[_lf]));
        await printLine('.' * _charsPerLine);
      case XprinterDividerStyle.blank:
        await PosPrinter.sendRawCommand(Uint8List.fromList(<int>[_lf]));
    }
    await Future<void>.delayed(_interRowPause);
  }

  /// Prints one line of [text] using CP866 raw bytes (Cyrillic-safe).
  static Future<void> printLine(
    String text, {
    XprinterAlignment alignment = XprinterAlignment.left,
    bool bold = false,
  }) async {
    final alignBytes = switch (alignment) {
      XprinterAlignment.left => const <int>[0x1B, 0x61, 0x00],
      XprinterAlignment.center => const <int>[0x1B, 0x61, 0x01],
      XprinterAlignment.right => const <int>[0x1B, 0x61, 0x02],
    };
    final bytes = <int>[
      ...alignBytes,
      if (bold) ..._boldOn,
      ...encodeToCp866(text),
      if (bold) ..._boldOff,
      _lf,
    ];
    await PosPrinter.sendRawCommand(Uint8List.fromList(bytes));
    await Future<void>.delayed(_interRowPause);
  }

  /// Bold `Label:` + plain value.  Empty value → label only.
  static Future<void> printInfoRow(String label, String value) async {
    final bytes = <int>[
      ..._alignLeft,
      ..._boldOn,
      ...encodeToCp866('$label:'),
      ..._boldOff,
    ];
    if (value.isNotEmpty) {
      bytes.addAll(encodeToCp866(' $value'));
    }
    bytes.add(_lf);
    await PosPrinter.sendRawCommand(Uint8List.fromList(bytes));
    await Future<void>.delayed(_interRowPause);
  }

  /// `label .... value` row with bold value, filled to [_charsPerLine].
  /// Falls back to two lines when content doesn't fit.
  ///
  /// [leader] is the fill char between label and value.  Pass `''` for
  /// space-padded right-aligned value (no visible leader).
  static Future<void> printValueRow(
    String label,
    String value, {
    String leader = '.',
  }) async {
    if (leader.isEmpty) {
      final padCount = _charsPerLine - label.length - value.length;
      if (padCount >= 1) {
        final bytes = <int>[
          ..._alignLeft,
          ...encodeToCp866('$label${' ' * padCount}'),
          ..._boldOn,
          ...encodeToCp866(value),
          ..._boldOff,
          _lf,
        ];
        await PosPrinter.sendRawCommand(Uint8List.fromList(bytes));
        await Future<void>.delayed(_interRowPause);
        return;
      }
    } else {
      const minLeaderLen = 2;
      final fillCount = _charsPerLine - label.length - value.length - 2;
      if (fillCount >= minLeaderLen) {
        final fill = leader.substring(0, 1) * fillCount;
        final left = '$label $fill ';
        final bytes = <int>[
          ..._alignLeft,
          ...encodeToCp866(left),
          ..._boldOn,
          ...encodeToCp866(value),
          ..._boldOff,
          _lf,
        ];
        await PosPrinter.sendRawCommand(Uint8List.fromList(bytes));
        await Future<void>.delayed(_interRowPause);
        return;
      }
    }

    // Two-line fallback: label, then right-aligned value chunks.
    await printLine(label);
    for (final chunk in _rightAlignChunks(value)) {
      final bytes = <int>[
        ..._alignLeft,
        ..._boldOn,
        ...encodeToCp866(chunk),
        ..._boldOff,
        _lf,
      ];
      await PosPrinter.sendRawCommand(Uint8List.fromList(bytes));
      await Future<void>.delayed(_interRowPause);
    }
  }

  /// Bold label + dotted leader + regular value.
  /// Used in the TBC payslip section where labels are emphasised.
  static Future<void> printFieldRow(String label, String value) async {
    const minDots = 2;
    final fillCount = _charsPerLine - label.length - value.length - 2;

    if (fillCount >= minDots) {
      final leader = '.' * fillCount;
      final bytes = <int>[
        ..._alignLeft,
        ..._boldOn,
        ...encodeToCp866(label),
        ..._boldOff,
        ...encodeToCp866(' $leader $value'),
        _lf,
      ];
      await PosPrinter.sendRawCommand(Uint8List.fromList(bytes));
      await Future<void>.delayed(_interRowPause);
      return;
    }

    // Two-line fallback: bold label, then right-aligned value.
    await printLine(label, bold: true);
    for (final chunk in _rightAlignChunks(value)) {
      await printLine(chunk, alignment: XprinterAlignment.right);
    }
  }

  /// Same as [printValueRow] but value is regular weight.  Pass
  /// [leader] = `''` for space-padded right-align with no visible leader.
  static Future<void> printPlainRow(
    String label,
    String value, {
    String leader = '.',
  }) async {
    if (leader.isEmpty) {
      final padCount = _charsPerLine - label.length - value.length;
      if (padCount >= 1) {
        return printLine('$label${' ' * padCount}$value');
      }
    } else {
      const minLeaderLen = 2;
      final fillCount = _charsPerLine - label.length - value.length - 2;
      if (fillCount >= minLeaderLen) {
        final fill = leader.substring(0, 1) * fillCount;
        return printLine('$label $fill $value');
      }
    }

    await printLine(label);
    for (final chunk in _rightAlignChunks(value)) {
      await printLine(chunk);
    }
  }

  /// Right-aligns / chunks [value] for the two-line fallback.
  static List<String> _rightAlignChunks(String value) {
    if (value.length <= _charsPerLine) {
      final pad = _charsPerLine - value.length;
      return [' ' * pad + value];
    }
    final out = <String>[];
    var remaining = value;
    while (remaining.length > _charsPerLine) {
      out.add(remaining.substring(0, _charsPerLine));
      remaining = remaining.substring(_charsPerLine);
    }
    if (remaining.isNotEmpty) {
      final pad = _charsPerLine - remaining.length;
      out.add(' ' * pad + remaining);
    }
    return out;
  }

  /// Fully-bold row — ИТОГО / section headers.  Empty value → label only.
  /// Pass [leader] = `''` for space-padded right-align (no visible leader).
  static Future<void> printBoldRow(
    String label,
    String value, {
    String leader = '.',
  }) {
    if (value.isEmpty) {
      return printLine(label, bold: true);
    }
    if (leader.isEmpty) {
      final padCount = _charsPerLine - label.length - value.length;
      final pad = padCount >= 1 ? ' ' * padCount : ' ';
      return printLine('$label$pad$value', bold: true);
    }
    final fillCount = _charsPerLine - label.length - value.length - 2;
    final fill = fillCount >= 1 ? leader.substring(0, 1) * fillCount : '';
    final row = fill.isEmpty ? '$label $value' : '$label $fill $value';
    return printLine(row, bold: true);
  }

  /// Discount row — alias for [printValueRow] for semantic clarity.
  static Future<void> printDiscountRow(String label, String value) {
    return printValueRow(label, value);
  }

  /// Prints a bundled PNG asset, resized to [heightDots] tall.  Cached
  /// in memory; silent no-op on missing/decode failure.
  static Future<void> printAssetIcon(
    String assetPath, {
    int heightDots = 32,
    XprinterAlignment alignment = XprinterAlignment.center,
  }) async {
    final bytes = await _resolveAssetIconBytes(assetPath, heightDots);
    if (bytes == null) return;
    await PosPrinter.printBitmap(
      bytes.pngBytes,
      alignment: alignment,
      widthDots: bytes.widthDots,
    );
    await Future<void>.delayed(_interRowPause);
  }

  /// Prints `(icon + text)` pairs side-by-side, wrapping to fit width.
  /// Latin text only — uses bundled `arial24` font.
  static Future<void> printIconTextRow(
    List<({String iconAsset, String text})> entries,
  ) async {
    if (entries.isEmpty) return;

    final targetWidth = _widthDots;
    const iconHeight = 32;
    const gapIconText = 8; // dots between icon and text
    const gapBetweenUnits = 24; // dots between (icon+text) pairs
    const rowSpacing = 6; // dots between wrapped rows
    final font = img.arial24;
    final textHeight = font.lineHeight;
    final unitHeight = iconHeight > textHeight ? iconHeight : textHeight;

    // Load + flatten each icon, compute the rendered width of each pair.
    final units = <({img.Image icon, String text, int width})>[];
    for (final e in entries) {
      final icon = await _loadIconForCompose(e.iconAsset, iconHeight);
      if (icon == null) continue;
      final tw = _measureString(e.text, font);
      units.add((icon: icon, text: e.text, width: icon.width + gapIconText + tw));
    }
    if (units.isEmpty) return;

    // Pack pairs into rows that fit `targetWidth`.
    final rows = <List<({img.Image icon, String text, int width})>>[];
    var current = <({img.Image icon, String text, int width})>[];
    var consumed = 0;
    for (final u in units) {
      final addWidth = current.isEmpty ? u.width : gapBetweenUnits + u.width;
      if (consumed + addWidth > targetWidth && current.isNotEmpty) {
        rows.add(current);
        current = <({img.Image icon, String text, int width})>[];
        consumed = 0;
      }
      current.add(u);
      consumed += current.length == 1 ? u.width : gapBetweenUnits + u.width;
    }
    if (current.isNotEmpty) rows.add(current);

    // Compose canvas: one row per packed row.
    final canvasHeight = rows.length * unitHeight + (rows.length - 1) * rowSpacing;
    final canvas = img.Image(width: targetWidth, height: canvasHeight);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

    for (var rIdx = 0; rIdx < rows.length; rIdx++) {
      final row = rows[rIdx];
      final rowWidth = row.fold<int>(0, (s, u) => s + u.width) + (row.length - 1) * gapBetweenUnits;
      var x = ((targetWidth - rowWidth) ~/ 2).clamp(0, targetWidth);
      final yBase = rIdx * (unitHeight + rowSpacing);

      for (var i = 0; i < row.length; i++) {
        final u = row[i];
        // Icon vertically centred within the row band.
        final iconY = yBase + (unitHeight - u.icon.height) ~/ 2;
        img.compositeImage(canvas, u.icon, dstX: x, dstY: iconY);
        x += u.icon.width + gapIconText;

        // Text vertically centred within the row band.
        final textY = yBase + (unitHeight - textHeight) ~/ 2;
        img.drawString(
          canvas,
          u.text,
          font: font,
          x: x,
          y: textY,
          color: img.ColorRgb8(0, 0, 0),
        );
        x += u.width - u.icon.width - gapIconText;
        if (i < row.length - 1) x += gapBetweenUnits;
      }
    }

    // Force threshold — known logo-like content, skip auto-detector
    // (small icons trip the mid-tone gate and print stippled).
    final pngBytes = XprinterImageDither.binarise(
      canvas,
      mode: XprinterImageMode.threshold,
    );
    await PosPrinter.printBitmap(
      pngBytes,
      alignment: XprinterAlignment.center,
      widthDots: targetWidth,
    );
    await Future<void>.delayed(_interRowPause);
  }

  /// Loads + resizes an icon as an [img.Image] for composite layouts.
  static Future<img.Image?> _loadIconForCompose(
    String assetPath,
    int heightDots,
  ) async {
    try {
      final byteData = await rootBundle.load(assetPath);
      final source = img.decodeImage(byteData.buffer.asUint8List());
      if (source == null || source.width <= 0 || source.height <= 0) {
        return null;
      }
      final aspect = source.width / source.height;
      final w = (heightDots * aspect).round().clamp(1, 384);
      final resized = img.copyResize(
        source,
        width: w,
        height: heightDots,
        interpolation: img.Interpolation.linear,
      );
      final flat = img.Image(width: w, height: heightDots);
      img.fill(flat, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(flat, resized);
      return flat;
    } catch (_) {
      return null;
    }
  }

  /// Measures rendered width of [text] in [font].
  static int _measureString(String text, img.BitmapFont font) {
    var w = 0;
    final fallback = font.lineHeight ~/ 2;
    for (final rune in text.runes) {
      final ch = font.characters[rune];
      w += ch?.xAdvance ?? fallback;
    }
    return w;
  }

  /// In-memory icon cache, keyed by `<assetPath>@<heightDots>`.
  static final Map<String, _IconBytes> _iconCache = <String, _IconBytes>{};

  static Future<_IconBytes?> _resolveAssetIconBytes(
    String assetPath,
    int heightDots,
  ) async {
    final cacheKey = '$assetPath@$heightDots';
    final cached = _iconCache[cacheKey];
    if (cached != null) return cached;

    try {
      final byteData = await rootBundle.load(assetPath);
      final source = img.decodeImage(byteData.buffer.asUint8List());
      if (source == null || source.width <= 0 || source.height <= 0) {
        return null;
      }
      final aspectRatio = source.width / source.height;
      final targetH = heightDots;
      final targetW = (targetH * aspectRatio).round().clamp(1, 384);
      final resized = img.copyResize(
        source,
        width: targetW,
        height: targetH,
        interpolation: img.Interpolation.linear,
      );

      // Flatten alpha onto white — SDK treats transparent as black otherwise.
      final flat = img.Image(width: targetW, height: targetH);
      img.fill(flat, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(flat, resized);

      // Force threshold — known logo asset.
      final pngBytes = XprinterImageDither.binarise(
        flat,
        mode: XprinterImageMode.threshold,
      );
      final entry = _IconBytes(pngBytes: pngBytes, widthDots: targetW);
      _iconCache[cacheKey] = entry;
      return entry;
    } catch (_) {
      return null;
    }
  }
}

class _IconBytes {
  const _IconBytes({required this.pngBytes, required this.widthDots});
  final Uint8List pngBytes;
  final int widthDots;
}
