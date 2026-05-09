#
# CocoaPods spec for flutter_xprinter_sdk.
#
# XPrinter's iOS SDK (`libPrinterSDK.a` + `Headers/`) lives in the HOST
# app's `ios/Frameworks/` — `bin/setup.dart` places it there.  The SDK
# binary ships device slices only (no arm64-simulator), so we link the
# library only for device builds (`OTHER_LDFLAGS[sdk=iphoneos*]`) — host
# apps build cleanly on every simulator and the manager returns
# `SIMULATOR_UNSUPPORTED` errors at runtime there.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_xprinter_sdk'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin for XPrinter thermal receipt printers.'
  s.description      = <<-DESC
    Bluetooth / USB / TCP connectivity and ESC/POS printing for XPrinter
    thermal printers, with first-class Cyrillic and image-dithering helpers.
  DESC
  s.homepage         = 'https://github.com/Lazizbek97/flutter_xprinter_sdk'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Lazizbek Fayziev' => 'lazizbekfayziyev@gmail.com' }
  s.source           = { :path => '.' }

  s.source_files     = 'Classes/**/*.{h,m}'
  s.public_header_files = 'Classes/**/*.h'

  s.platform         = :ios, '12.0'
  s.dependency 'Flutter'

  # Header search path points at the HOST app's ios/Frameworks/.
  # `$(PROJECT_DIR)` for a pod is `<host-ios>/Pods/` — works the same for
  # both pub-cache installs and `path:` dev pods.
  #
  # `-lPrinterSDK` is only added on device builds (`[sdk=iphoneos*]`) —
  # the static lib has no arm64-simulator slice, so simulator builds skip
  # the library entirely.  Source files are guarded with
  # `#if !TARGET_OS_SIMULATOR`, so the plugin compiles cleanly on
  # simulator without referencing any SDK symbols.
  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(PROJECT_DIR)/../Frameworks/Headers"',
    'LIBRARY_SEARCH_PATHS[sdk=iphoneos*]' => '$(inherited) "$(PROJECT_DIR)/../Frameworks"',
    'OTHER_LDFLAGS' => '$(inherited) -ObjC',
    'OTHER_LDFLAGS[sdk=iphoneos*]' => '$(inherited) -ObjC -lPrinterSDK',
    'DEFINES_MODULE' => 'YES',
  }

  # System frameworks the SDK relies on.
  s.frameworks = 'CoreBluetooth', 'SystemConfiguration', 'CFNetwork', 'UIKit'
end
