// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Clipout",
    platforms: [.macOS("26.0")],
    targets: [
        // Pure logic (cards, history, AnkiConnect messages): testable without AppKit.
        .target(name: "ClipoutCore"),
        // LAME (MP3) is linked in statically; make-lame.sh builds it into .build/lame.
        .executableTarget(name: "Clipout", dependencies: ["ClipoutCore"],
                          linkerSettings: [.unsafeFlags(["\(Context.packageDirectory)/.build/lame/libmp3lame.a"])]),
        .testTarget(name: "ClipoutCoreTests", dependencies: ["ClipoutCore"]),
    ],
    swiftLanguageModes: [.v5]
)
