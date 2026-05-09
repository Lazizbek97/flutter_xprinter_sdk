// ignore_for_file: avoid_print
//
// Setup helper for flutter_xprinter_sdk.
//
// Copies user-downloaded XPrinter SDK files into the host Flutter app:
// - iOS:     <project>/ios/Frameworks/libPrinterSDK.a + Headers/
// - Android: <project>/android/app/libs/printer-lib-*.aar
//
// Also patches android/app/build.gradle(.kts) with the
// `implementation fileTree(libs, *.aar)` line if missing.
//
// Usage:
//   dart run flutter_xprinter_sdk:setup --ios=<path> --android=<path>
//   dart run flutter_xprinter_sdk:setup --auto    (scans ~/Downloads)
//
// Each --path may point at either a .zip file or an unzipped directory.

import 'dart:io';

void main(List<String> args) async {
  if (args.contains('-h') || args.contains('--help')) {
    _printUsage();
    return;
  }

  final iosPath = _argValue(args, '--ios');
  final androidPath = _argValue(args, '--android');
  final auto = args.contains('--auto');

  if (iosPath == null && androidPath == null && !auto) {
    _printUsage();
    exit(1);
  }

  final project = await _findFlutterProject();
  if (project == null) {
    _err('Run this from your Flutter project root (must contain pubspec.yaml + ios/ + android/).');
    exit(1);
  }
  print('• Flutter project: ${project.path}');

  if (iosPath != null) {
    await _installIos(project, iosPath);
  } else if (auto) {
    final found = await _autoFindIos();
    if (found != null) await _installIos(project, found.path);
  }

  if (androidPath != null) {
    await _installAndroid(project, androidPath);
  } else if (auto) {
    final found = await _autoFindAndroid();
    if (found != null) await _installAndroid(project, found.path);
  }

  print('');
  print('✅ Setup complete.');
  print('');
  print('Next steps (run from your project root):');
  print('  1. cd ios && pod install && cd ..');
  print('  2. flutter clean && flutter run');
  print('');
  print('You still need to (script can\'t do these):');
  print('  • Android 12+ runtime permissions — request bluetoothScan +');
  print('    bluetoothConnect in your Dart code via permission_handler');
  print('    BEFORE calling any plugin scan/connect method.  Add to your');
  print('    pubspec.yaml:  permission_handler: ^11.3.1');
  print('  • iOS simulator on Apple Silicon — XPrinter\'s static lib has no');
  print('    arm64-simulator slice, so test on a REAL iPhone (not simulator).');
}

void _printUsage() {
  stdout.writeln('''
flutter_xprinter_sdk setup — copies XPrinter SDK binaries into your Flutter app.

USAGE
  dart run flutter_xprinter_sdk:setup --ios=<path>     [--android=<path>]
  dart run flutter_xprinter_sdk:setup --auto

OPTIONS
  --ios=<path>      Path to the iOS XPrinter SDK (.zip or unzipped directory)
  --android=<path>  Path to the Android XPrinter SDK (.zip or unzipped directory)
  --auto            Scan ~/Downloads for SDK files automatically
  -h, --help        Show this help

EXAMPLES
  dart run flutter_xprinter_sdk:setup \\
      --ios=~/Downloads/iOS-SDK-3.2.0 \\
      --android=~/Downloads/Android-SDK-3.2.0/printer-lib-3.2.0.aar
''');
}

// ── iOS ──────────────────────────────────────────────────────────────────

Future<void> _installIos(Directory project, String input) async {
  print('');
  print('▶ iOS');
  final source = await _resolveDir(input);
  if (source == null) return;

  final lib = await _findFile(source, 'libPrinterSDK.a');
  if (lib == null) {
    _err('  libPrinterSDK.a not found in ${source.path}');
    return;
  }
  final headers = await _findHeadersDir(source);
  if (headers == null) {
    _err('  Headers/ folder not found (expected POSPrinter.h, POSCommand.h, …)');
    return;
  }

  final dest = Directory('${project.path}/ios/Frameworks');
  await dest.create(recursive: true);
  await _copyFile(lib, '${dest.path}/libPrinterSDK.a');
  await _copyDir(headers, '${dest.path}/Headers');
  print('  ✓ ios/Frameworks/libPrinterSDK.a');
  print('  ✓ ios/Frameworks/Headers/  (${await _countFiles(headers, '.h')} headers)');

  await _patchInfoPlist(project);
}

/// Adds the Bluetooth usage-description strings to the host's Info.plist
/// if they're missing.  Apple requires both keys for any app that scans /
/// connects to BT peripherals; without them the OS silently denies access.
Future<void> _patchInfoPlist(Directory project) async {
  final plist = File('${project.path}/ios/Runner/Info.plist');
  if (!await plist.exists()) {
    _err('  ⚠ Info.plist not found at ${plist.path} — add Bluetooth usage strings manually.');
    return;
  }

  var content = await plist.readAsString();
  const usage = 'Used to connect to thermal receipt printers.';
  final keys = <String, String>{
    'NSBluetoothAlwaysUsageDescription': usage,
    'NSBluetoothPeripheralUsageDescription': usage,
  };

  var added = 0;
  for (final entry in keys.entries) {
    if (content.contains('<key>${entry.key}</key>')) continue;
    final block = '\t<key>${entry.key}</key>\n\t<string>${entry.value}</string>\n';
    final closingDict = RegExp(r'</dict>\s*</plist>\s*$');
    if (!closingDict.hasMatch(content)) {
      _err('  ⚠ Info.plist has unexpected structure — add ${entry.key} manually.');
      return;
    }
    content = content.replaceFirst(closingDict, '$block</dict>\n</plist>\n');
    added++;
  }

  if (added > 0) {
    await plist.writeAsString(content);
    print('  ✓ ios/Runner/Info.plist  ($added Bluetooth usage description${added == 1 ? '' : 's'} added)');
  } else {
    print('  ✓ ios/Runner/Info.plist already has Bluetooth usage descriptions');
  }
}

Future<Directory?> _autoFindIos() async {
  final home = Platform.environment['HOME'] ?? '';
  final downloads = Directory('$home/Downloads');
  if (!await downloads.exists()) return null;
  await for (final entry in downloads.list()) {
    final name = entry.path.toLowerCase();
    if (entry is Directory && (name.contains('ios') && name.contains('sdk'))) {
      print('• Auto-found iOS SDK: ${entry.path}');
      return entry;
    }
  }
  return null;
}

// ── Android ──────────────────────────────────────────────────────────────

Future<void> _installAndroid(Directory project, String input) async {
  print('');
  print('▶ Android');
  final source = await _resolveDir(input);
  if (source == null) return;

  final aar = await _findFile(source, RegExp(r'^printer-lib-.*\.aar$'));
  if (aar == null) {
    _err('  No printer-lib-*.aar found in ${source.path}');
    return;
  }

  final libs = Directory('${project.path}/android/app/libs');
  await libs.create(recursive: true);
  final destAar = '${libs.path}/${aar.uri.pathSegments.last}';
  await _copyFile(aar, destAar);
  print('  ✓ android/app/libs/${aar.uri.pathSegments.last}');

  await _patchBuildGradle(project);
}

Future<Directory?> _autoFindAndroid() async {
  final home = Platform.environment['HOME'] ?? '';
  final downloads = Directory('$home/Downloads');
  if (!await downloads.exists()) return null;
  await for (final entry in downloads.list()) {
    final name = entry.path.toLowerCase();
    if (entry is Directory && name.contains('android') && name.contains('sdk')) {
      print('• Auto-found Android SDK: ${entry.path}');
      return entry;
    }
  }
  return null;
}

Future<void> _patchBuildGradle(Directory project) async {
  final groovy = File('${project.path}/android/app/build.gradle');
  final kts = File('${project.path}/android/app/build.gradle.kts');
  final target = await kts.exists() ? kts : (await groovy.exists() ? groovy : null);
  if (target == null) {
    _err('  Neither build.gradle nor build.gradle.kts found in android/app/');
    return;
  }

  final content = await target.readAsString();
  final marker = 'fileTree';
  final libsHint = 'libs';
  if (content.contains(marker) && content.contains(libsHint) && content.contains('*.aar')) {
    print('  ✓ ${target.uri.pathSegments.last} already has fileTree(libs, *.aar)');
    return;
  }

  final isKts = target.path.endsWith('.kts');
  final depLine = isKts
      ? '    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar"))))'
      : "    implementation fileTree(dir: 'libs', include: ['*.aar'])";

  final patched = _injectDependency(content, depLine, isKts: isKts);
  if (patched == null) {
    _err('  Could not auto-patch ${target.uri.pathSegments.last} — add this line manually:');
    _err('  $depLine');
    return;
  }
  await target.writeAsString(patched);
  print('  ✓ patched ${target.uri.pathSegments.last} with implementation fileTree(libs, *.aar)');
}

/// Adds [depLine] inside an existing top-level `dependencies { … }` block.
/// Returns null if no such block exists.
String? _injectDependency(String content, String depLine, {required bool isKts}) {
  final pattern = RegExp(
    r'(\n\s*dependencies\s*\{\s*)(\n)',
    multiLine: true,
  );
  final match = pattern.firstMatch(content);
  if (match == null) {
    // No top-level dependencies block — append one.
    return '$content\n\ndependencies {\n$depLine\n}\n';
  }
  return content.replaceFirst(
    pattern,
    '${match.group(1)}\n$depLine${match.group(2)}',
  );
}

// ── Helpers ──────────────────────────────────────────────────────────────

Future<Directory?> _findFlutterProject() async {
  var dir = Directory.current;
  for (var i = 0; i < 6; i++) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    final ios = Directory('${dir.path}/ios');
    final android = Directory('${dir.path}/android');
    if (await pubspec.exists() && await ios.exists() && await android.exists()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

/// Resolves a user-provided path to a Directory.  If the path is a `.zip`,
/// unzips it to a temp directory.  If it's already a directory, returns it.
Future<Directory?> _resolveDir(String input) async {
  final expanded = _expandHome(input);
  final entity = FileSystemEntity.typeSync(expanded);
  if (entity == FileSystemEntityType.directory) {
    return Directory(expanded);
  }
  if (entity == FileSystemEntityType.file && expanded.toLowerCase().endsWith('.zip')) {
    final tmp = await Directory.systemTemp.createTemp('xprinter_');
    final result = await Process.run('unzip', ['-q', expanded, '-d', tmp.path]);
    if (result.exitCode != 0) {
      _err('  Failed to unzip $expanded:\n${result.stderr}');
      return null;
    }
    return tmp;
  }
  if (entity == FileSystemEntityType.file && expanded.toLowerCase().endsWith('.aar')) {
    // User pointed directly at an AAR — wrap its parent as the source dir.
    return File(expanded).parent;
  }
  _err('  Path not found or unsupported: $input');
  return null;
}

Future<File?> _findFile(Directory root, Pattern name) async {
  await for (final entry in root.list(recursive: true, followLinks: false)) {
    if (entry is File) {
      final base = entry.uri.pathSegments.last;
      if (name is String && base == name) return entry;
      if (name is RegExp && name.hasMatch(base)) return entry;
    }
  }
  return null;
}

Future<Directory?> _findHeadersDir(Directory root) async {
  // A folder named "Headers" containing POSPrinter.h or POSCommand.h.
  await for (final entry in root.list(recursive: true, followLinks: false)) {
    if (entry is Directory && entry.uri.pathSegments.where((s) => s.isNotEmpty).last == 'Headers') {
      final has = await File('${entry.path}/POSPrinter.h').exists() ||
          await File('${entry.path}/POSCommand.h').exists();
      if (has) return entry;
    }
  }
  return null;
}

Future<int> _countFiles(Directory dir, String suffix) async {
  var n = 0;
  await for (final e in dir.list(recursive: true, followLinks: false)) {
    if (e is File && e.path.endsWith(suffix)) n++;
  }
  return n;
}

Future<void> _copyFile(File src, String destPath) async {
  await src.copy(destPath);
}

Future<void> _copyDir(Directory src, String destPath) async {
  final dest = Directory(destPath);
  if (await dest.exists()) await dest.delete(recursive: true);
  await dest.create(recursive: true);
  await for (final entry in src.list(recursive: true, followLinks: false)) {
    final rel = entry.path.substring(src.path.length);
    final out = '${dest.path}$rel';
    if (entry is Directory) {
      await Directory(out).create(recursive: true);
    } else if (entry is File) {
      await Directory(File(out).parent.path).create(recursive: true);
      await entry.copy(out);
    }
  }
}

String _expandHome(String path) {
  final home = Platform.environment['HOME'];
  if (home != null && path.startsWith('~/')) {
    return '$home${path.substring(1)}';
  }
  return path;
}

String? _argValue(List<String> args, String key) {
  for (final a in args) {
    if (a.startsWith('$key=')) return a.substring(key.length + 1);
  }
  final i = args.indexOf(key);
  if (i >= 0 && i + 1 < args.length) return args[i + 1];
  return null;
}

void _err(String msg) => stderr.writeln(msg);
