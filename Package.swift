// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Clipout",
    platforms: [.macOS("26.0")],
    targets: [
        // Pure logic (cards, history, AnkiConnect messages): testable without AppKit.
        .target(name: "ClipoutCore"),
        .executableTarget(name: "Clipout", dependencies: ["ClipoutCore"]),
        .testTarget(name: "ClipoutCoreTests", dependencies: ["ClipoutCore"]),
    ],
    swiftLanguageModes: [.v5]
)
