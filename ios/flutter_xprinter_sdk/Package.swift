// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flutter_xprinter_sdk",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "flutter-xprinter-sdk", targets: ["flutter_xprinter_sdk"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "flutter_xprinter_sdk",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .target(name: "PrinterSDK")
            ],
            cSettings: [
                .headerSearchPath("include/flutter_xprinter_sdk"),
                .headerSearchPath("../../Frameworks/Headers")
            ],
            linkerSettings: [
                .linkedFramework("CFNetwork"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("UIKit")
            ]
        ),
        .binaryTarget(
            name: "PrinterSDK",
            path: "Frameworks/PrinterSDK.xcframework"
        )
    ]
)
