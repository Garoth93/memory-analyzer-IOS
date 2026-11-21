// swift-tools-version: 5.9
// Logic package for the MemoryAnalyzer app. Pure Swift, no UIKit/SwiftUI:
// it must build and test on Linux with `swift test`.
import PackageDescription

let package = Package(
    name: "StorageCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "StorageCore", targets: ["StorageCore"])
    ],
    targets: [
        .target(
            name: "StorageCore",
            path: "Sources/StorageCore"
        ),
        .testTarget(
            name: "StorageCoreTests",
            dependencies: ["StorageCore"],
            path: "Tests/StorageCoreTests"
        )
    ]
)
