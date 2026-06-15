#
# CocoaPods spec for flutter_xprinter_sdk.
#
# XPrinter's iOS SDK (`libPrinterSDK.a` + `Headers/`) is bundled in this
# plugin. The arm64 slice targets physical devices, so we link the library
# only for device builds (`OTHER_LDFLAGS[sdk=iphoneos*]`). Simulator builds
# skip the library and the manager returns `SIMULATOR_UNSUPPORTED`.
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
  s.preserve_paths   = 'Frameworks/**/*'

  s.platform         = :ios, '12.0'
  s.dependency 'Flutter'

  # `-lPrinterSDK` is only added on device builds (`[sdk=iphoneos*]`) —
  # source files are guarded with `#if !TARGET_OS_SIMULATOR`, so the plugin
  # compiles cleanly on simulator without referencing SDK symbols.
  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/Frameworks/Headers"',
    'LIBRARY_SEARCH_PATHS[sdk=iphoneos*]' => '$(inherited) "$(PODS_TARGET_SRCROOT)/Frameworks"',
    'OTHER_LDFLAGS' => '$(inherited) -ObjC',
    'OTHER_LDFLAGS[sdk=iphoneos*]' => '$(inherited) -ObjC -lPrinterSDK',
    'DEFINES_MODULE' => 'YES',
  }

  # System frameworks the SDK relies on.
  s.frameworks = 'CoreBluetooth', 'SystemConfiguration', 'CFNetwork', 'UIKit'
end
