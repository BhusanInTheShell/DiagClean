// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiagClean",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DiagCleanKit", targets: ["DiagCleanKit"]),
        .executable(name: "DiagCleanApp", targets: ["DiagCleanApp"]),
    ],
    targets: [
        // All logic lives here: no SwiftUI, no AppKit, so every safety-critical path
        // is reachable from `swift test` without launching a UI.
        .target(name: "DiagCleanKit"),

        .executableTarget(
            name: "DiagCleanApp",
            dependencies: ["DiagCleanKit"]
        ),

        .testTarget(
            name: "DiagCleanKitTests",
            dependencies: ["DiagCleanKit"]
        ),
    ]
)
