#
# CocoaPods spec for flutter_xprinter_sdk.
#
# Vendors `libPrinterSDK.a` (XPrinter iOS SDK, arm64 + x86_64 only).
# `EXCLUDED_ARCHS[sdk=iphonesimulator*]=arm64` is required so Apple-Silicon
# Macs can build the simulator target.
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

  # Vendor the static library + its headers.  CocoaPods auto-links any
  # `.a` declared in `vendored_libraries` into the pod's framework target;
  # we must NOT add `-lPrinterSDK` ourselves or it'll be linked a second
  # time into the host app's binary, producing duplicate Obj-C class
  # registrations at runtime (POSPrinter, POSBLEManager, etc. → spurious
  # crashes).
  s.vendored_libraries = 'Frameworks/libPrinterSDK.a'
  s.preserve_paths     = 'Frameworks/libPrinterSDK.a', 'Frameworks/Headers/*.h'

  # Pod-target-only config: header path so our Obj-C glue can `#import`
  # the SDK headers, and `-ObjC` so the SDK's Objective-C categories
  # survive static-link dead-code elimination.  No `-l` here — vendored
  # libs are auto-linked.  Apple-Silicon-Mac simulator skips arm64 (the
  # vendored fat lib has arm64-device + x86_64-sim only).
  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/Frameworks/Headers"',
    'OTHER_LDFLAGS' => '$(inherited) -ObjC',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64',
    'DEFINES_MODULE' => 'YES',
  }

  # Propagate only the simulator-arch exclusion to the host app — without
  # this, Apple-Silicon Macs can't build the iOS simulator target.
  s.user_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64',
  }

  # System frameworks the SDK relies on (per Documentation.md in the SDK).
  s.frameworks = 'CoreBluetooth', 'SystemConfiguration', 'CFNetwork', 'UIKit'
end
