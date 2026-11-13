// swift-tools-version:6.0
import PackageDescription

let sherpaLibraries = [
    "sherpa-onnx-c-api", "sherpa-onnx-core", "sherpa-onnx-fstfar", "sherpa-onnx-fst",
    "sherpa-onnx-kaldifst-core", "kaldi-decoder-core", "kaldi-native-fbank-core", "kissfft-float",
    "ssentencepiece_core", "piper_phonemize", "espeak-ng", "ucd", "onnxruntime",
].map { "sherpa/lib/lib\($0).a" }
let staticLibraries = (["lame/libmp3lame.a"] + sherpaLibraries)
    .map { "\(Context.packageDirectory)/.build/\($0)" }

let package = Package(
    name: "Clipout",
    platforms: [.macOS("26.0")],
    targets: [
        // Pure logic (cards, history, AnkiConnect messages): testable without AppKit.
        .target(name: "ClipoutCore"),
        // sherpa-onnx's C API: Piper voices (make-sherpa.sh fetches the libraries).
        .target(name: "CSherpaOnnx"),
        // LAME (MP3) and sherpa-onnx are linked in statically: make-lame.sh and
        // make-sherpa.sh put them into .build.
        .executableTarget(name: "Clipout", dependencies: ["ClipoutCore", "CSherpaOnnx"],
                          linkerSettings: [.unsafeFlags(staticLibraries), .linkedLibrary("c++")]),
        .testTarget(name: "ClipoutCoreTests", dependencies: ["ClipoutCore"]),
    ],
    swiftLanguageModes: [.v5]
)
