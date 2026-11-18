// swift-tools-version:5.4
import PackageDescription

let package = Package(
    name: "barcode-frames",
    platforms: [.macOS(.v11)],
    products: [
        .library(name: "BarcodeFrames", targets: ["BarcodeFrames"]),
        .library(name: "BarcodeFramesUI", targets: ["BarcodeFramesUI"]),
        .executable(name: "bf", targets: ["bf"]),
    ],
    targets: [
        .target(name: "BarcodeFrames"),
        .target(name: "BarcodeFramesUI", dependencies: ["BarcodeFrames"]),
        .executableTarget(name: "bf", dependencies: ["BarcodeFrames"]),
        .testTarget(name: "BarcodeFramesTests", dependencies: ["BarcodeFrames", "BarcodeFramesUI"]),
    ]
)
