#
# CocoaPods spec for flutter_xprinter_sdk.
#
# XPrinter's iOS SDK (`libPrinterSDK.a` + `Headers/`) lives in the HOST
# app's `ios/Frameworks/` — XPrinter's licence is silent on redistribution
# so we don't ship the binary.  `bin/setup.dart` places the files there.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_xprinter_sdk'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin for XPrinter thermal receipt printers.'
  s.description      = <<-DESC
    Bluetooth / USB / TCP connectivity and ESC/POS printing for XPrinter
    thermal printers, with first-class Cyrillic and image-dithering helpers.
  DESC
  s.homepage         = 'https://github.com/lazizbek-fayziev/flutter_xprinter_sdk'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Lazizbek Fayziev' => 'lazizbekfayziyev@gmail.com' }
  s.source           = { :path => '.' }

  s.source_files     = 'Classes/**/*.{h,m}'
  s.public_header_files = 'Classes/**/*.h'

  s.platform         = :ios, '12.0'
  s.dependency 'Flutter'

  # Header + library search paths point at the HOST app's ios/Frameworks/.
  # `$(SRCROOT)` for a pod is `<host-ios>/Pods/flutter_xprinter_sdk/`, so
  # `$(SRCROOT)/../../Frameworks/` resolves to `<host-ios>/Frameworks/`.
  # `-lPrinterSDK` plus the search path makes the linker find
  # `libPrinterSDK.a` there at link time.
  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(SRCROOT)/../../Frameworks/Headers"',
    'LIBRARY_SEARCH_PATHS' => '$(inherited) "$(SRCROOT)/../../Frameworks"',
    'OTHER_LDFLAGS' => '$(inherited) -ObjC -lPrinterSDK',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64',
    'DEFINES_MODULE' => 'YES',
  }

  # Propagate the simulator-arch exclusion to the host app — without this,
  # Apple-Silicon Macs can't build the iOS simulator target.
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64',
  }

  # System frameworks the SDK relies on.
  s.frameworks = 'CoreBluetooth', 'SystemConfiguration', 'CFNetwork', 'UIKit'
end
