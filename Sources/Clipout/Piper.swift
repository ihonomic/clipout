import AVFoundation
import CryptoKit
import CSherpaOnnx
import Foundation

/// A neural Piper voice, run offline by sherpa-onnx.
///
/// The voices aren't shipped with Clipout: they are 27–116 MB each and carry
/// their own licenses (see the voice's MODEL_CARD). Settings downloads one on
/// request from sherpa-onnx's releases, where each comes packed with what it
/// needs (model, tokens, espeak-ng data), and checks it against its SHA-256.
struct PiperVoice: Identifiable, Hashable, Sendable {
    /// Piper's name, e.g. "de_DE-thorsten-high".
    let id: String
    let bytes: Int
    let sha256: String

    var language: String { String(id.prefix(2)) }
    /// "Thorsten (high)"
    var name: String {
        let parts = id.split(separator: "-")
        guard parts.count >= 3 else { return id }
        let speaker = parts[1].replacingOccurrences(of: "_", with: " ").capitalized
        return "\(speaker) (\(parts[2]))"
    }
    /// The tag used for the voice picker and stored in Prefs.voice.
    var tag: String { "piper:\(id)" }
    var folder: URL { PiperCatalog.folder.appendingPathComponent(id, isDirectory: true) }
    var model: URL { folder.appendingPathComponent("\(id).onnx") }
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: model.path)
            && FileManager.default.fileExists(atPath: folder.appendingPathComponent("tokens.txt").path)
    }
    var download: URL {
        URL(string: "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-\(id).tar.bz2")!
    }
}

enum PiperCatalog {
    static let folder = Paths.root.appendingPathComponent("voices", isDirectory: true)

    /// One or two good voices per language Clipout offers, from
    /// github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models.
    static let all: [PiperVoice] = [
        PiperVoice(id: "de_DE-thorsten-high", bytes: 115_591_546,
                   sha256: "dd4ed1b0d42c30a1a4862fc2b243e8044d52b8889c9ff3d1e99e92028888bc4a"),
        PiperVoice(id: "de_DE-thorsten-medium", bytes: 67_214_254,
                   sha256: "50487d9c95fdf2191f31d2588569381063ba1591dcd4c7d4bdd30f12b2191714"),
        PiperVoice(id: "de_DE-kerstin-low", bytes: 67_107_768,
                   sha256: "4bfe121d5f690a3b87acecd7ae1e70b48f4589ce6ae9f45a1809e6eb19fad97b"),
        PiperVoice(id: "en_US-ryan-high", bytes: 115_630_708,
                   sha256: "6a71edf4d308b9cb2eaeadc8d1f3c6bf96120ecb7fe52c29a2b6e139c59760ed"),
        PiperVoice(id: "en_US-amy-medium", bytes: 67_223_746,
                   sha256: "9a5d1fc497f85e8022b785bff5f8105203b1e33099ee6265203efc70b0cb0264"),
        PiperVoice(id: "en_GB-alba-medium", bytes: 67_212_349,
                   sha256: "fcd45962906933eec4431d3688f7d74aaac8713c87c6717f91fd3b23463aa1a1"),
        PiperVoice(id: "es_ES-davefx-medium", bytes: 67_184_952,
                   sha256: "a3f6beb54a9cb893279f72978a22f807a4d9fc9c7848157b524d5cc7b7f58b22"),
        PiperVoice(id: "es_ES-sharvard-medium", bytes: 80_318_184,
                   sha256: "b30a7a83df0518f0ee1c7039506648cade99f1f9b498fc49ed2ced2e2536bb5a"),
        PiperVoice(id: "fr_FR-siwis-medium", bytes: 67_207_459,
                   sha256: "375909aa30842b3a4efa10b1beb1d761af792960ae6873b4d53889f96c66195b"),
        PiperVoice(id: "fr_FR-tom-medium", bytes: 67_202_955,
                   sha256: "3d8258ef8466b5d5f2cc46c06e1415d3d01c9cbaeed8b6d5b3d152073672472c"),
        PiperVoice(id: "it_IT-paola-medium", bytes: 67_221_173,
                   sha256: "7541f75778afa164e44e34baaef63befad7698595df26a95ca944b63ef1a16b4"),
        PiperVoice(id: "pt_PT-tugao-medium", bytes: 67_195_014,
                   sha256: "6b4f0a7bfc957bef26d6ac0703a8fa1ba659c8ab2df8b294f20206551859070c"),
        PiperVoice(id: "pt_BR-faber-medium", bytes: 67_183_065,
                   sha256: "7add3f923ad6bc25ca8a192805fd1a64d1b3893e4611c4a9719545a825039a83"),
        PiperVoice(id: "nl_NL-pim-medium", bytes: 67_240_538,
                   sha256: "e78ed301bf6fc66561a04c110754cd6928d772630a3b80b09a83f89410130171"),
        PiperVoice(id: "nl_NL-ronnie-medium", bytes: 67_194_164,
                   sha256: "d2cc688abf46054eba1d47b3b1406c742ccf66732cd47998a3ee727c1b96c09f"),
        PiperVoice(id: "pl_PL-gosia-medium", bytes: 67_211_182,
                   sha256: "75bd34dcbdc4dd98d763954756b4b34b4208100497c836381542e4d73dcefa9c"),
        PiperVoice(id: "pl_PL-darkman-medium", bytes: 67_215_635,
                   sha256: "444727aa46eb6db645a2bc88fe73868e4bd7596b7f56ca39fad5ef53c41210d4"),
        PiperVoice(id: "tr_TR-dfki-medium", bytes: 67_201_221,
                   sha256: "b63babaefcdd63202c7079aba25b72a2013825ad5895e2aeff03d1ae5a5b3bbf"),
        PiperVoice(id: "ru_RU-irina-medium", bytes: 67_153_308,
                   sha256: "1fc0f54e5e084fe287c07909f2f6e0ba6d857864cf800e3ab80286a4e8233008"),
        PiperVoice(id: "ru_RU-dmitri-medium", bytes: 67_188_551,
                   sha256: "c86d0803737de13d441923ff3b3f309482fab8d7af3ec85949942809eb9a3660"),
    ]

    static func voices(for language: String) -> [PiperVoice] { all.filter { $0.language == language } }

    /// The Piper voice chosen in Settings, if it is installed and speaks the language.
    static func selected(for language: String) -> PiperVoice? {
        guard Prefs.voice.hasPrefix("piper:") else { return nil }
        return all.first { $0.tag == Prefs.voice && $0.language == language && $0.isInstalled }
    }
}

/// Downloads, checks and unpacks voices; Settings shows the progress.
@MainActor
final class PiperDownloads: ObservableObject {
    static let shared = PiperDownloads()

    /// Voice id → fraction done, while downloading.
    @Published private(set) var progress: [String: Double] = [:]
    @Published private(set) var error: String?
    /// Bumped after installing or deleting, so views re-read isInstalled.
    @Published private(set) var revision = 0

    private var observations: [String: NSKeyValueObservation] = [:]

    func install(_ voice: PiperVoice) {
        guard progress[voice.id] == nil else { return }
        error = nil
        progress[voice.id] = 0
        let task = URLSession.shared.downloadTask(with: voice.download) { file, response, error in
            // The file disappears when this handler returns: move it first.
            let kept = file.flatMap { try? Self.keep($0) }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            Task.detached(priority: .userInitiated) {
                let problem: String?
                if let error {
                    problem = error.localizedDescription
                } else if let kept, status == 200 {
                    problem = Self.unpack(kept, as: voice)
                } else {
                    problem = L("Download fehlgeschlagen (HTTP %@).", String(status))
                }
                if let kept { try? FileManager.default.removeItem(at: kept) }
                await MainActor.run { self.finish(voice, problem: problem) }
            }
        }
        observations[voice.id] = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            let done = progress.fractionCompleted
            Task { @MainActor in
                if self?.progress[voice.id] != nil { self?.progress[voice.id] = done }
            }
        }
        task.resume()
    }

    /// `Clipout --install-voice de_DE-thorsten-high`
    func installFromCommandLine(_ id: String) async {
        Paths.ensure()
        guard let voice = PiperCatalog.all.first(where: { $0.id == id }) else {
            print("Unbekannte Stimme. Verfügbar: " + PiperCatalog.all.map(\.id).joined(separator: ", "))
            exit(1)
        }
        install(voice)
        while progress[voice.id] != nil { try? await Task.sleep(for: .milliseconds(200)) }
        print(error ?? "Installiert: \(voice.folder.path)")
        exit(error == nil ? 0 : 1)
    }

    func remove(_ voice: PiperVoice) {
        PiperSpeaker.shared.forget(voice)
        try? FileManager.default.removeItem(at: voice.folder)
        if Prefs.voice == voice.tag { UserDefaults.standard.set("", forKey: Prefs.voiceKey) }
        revision += 1
    }

    private func finish(_ voice: PiperVoice, problem: String?) {
        progress[voice.id] = nil
        observations[voice.id] = nil
        error = problem.map { "\(voice.name): \($0)" }
        if problem == nil, Prefs.voice.isEmpty || !Prefs.voice.hasPrefix("piper:") {
            // A freshly downloaded voice is what the user wants to hear.
            UserDefaults.standard.set(voice.tag, forKey: Prefs.voiceKey)
        }
        revision += 1
    }

    private nonisolated static func keep(_ file: URL) throws -> URL {
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("clipout-voice-\(UUID().uuidString)")
        try FileManager.default.moveItem(at: file, to: kept)
        return kept
    }

    /// Checks the archive and unpacks it into voices/<id>. Returns a problem, or nil.
    private nonisolated static func unpack(_ archive: URL, as voice: PiperVoice) -> String? {
        guard sha256(of: archive) == voice.sha256 else { return L("Prüfsumme stimmt nicht – Datei verworfen.") }
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("clipout-voice-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: scratch) }
        try? fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xjf", archive.path, "-C", scratch.path]
        do {
            try tar.run()
            tar.waitUntilExit()
        } catch {
            return error.localizedDescription
        }
        let unpacked = scratch.appendingPathComponent("vits-piper-\(voice.id)", isDirectory: true)
        guard tar.terminationStatus == 0,
              fm.fileExists(atPath: unpacked.appendingPathComponent("\(voice.id).onnx").path) else {
            return L("Das Archiv enthält keine Stimme.")
        }
        try? fm.createDirectory(at: PiperCatalog.folder, withIntermediateDirectories: true)
        try? fm.removeItem(at: voice.folder)
        do {
            try fm.moveItem(at: unpacked, to: voice.folder)
        } catch {
            return error.localizedDescription
        }
        return nil
    }

    private nonisolated static func sha256(of file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Speaks with a Piper voice. Loading a voice takes a moment, so the last
/// one stays loaded; generating runs off the main thread.
final class PiperSpeaker: @unchecked Sendable {
    static let shared = PiperSpeaker()

    private let lock = NSLock()
    private var loaded: (id: String, tts: OpaquePointer)?

    /// The sentence as mono float samples, or nil.
    func speak(_ text: String, with voice: PiperVoice) async -> AVAudioPCMBuffer? {
        await Task.detached(priority: .userInitiated) { self.generate(text, voice) }.value
    }

    func forget(_ voice: PiperVoice) {
        lock.lock()
        defer { lock.unlock() }
        if let loaded, loaded.id == voice.id {
            SherpaOnnxDestroyOfflineTts(loaded.tts)
            self.loaded = nil
        }
    }

    private func generate(_ text: String, _ voice: PiperVoice) -> AVAudioPCMBuffer? {
        lock.lock()
        defer { lock.unlock() }
        guard let tts = engine(for: voice),
              let audio = SherpaOnnxOfflineTtsGenerate(tts, text, 0, 1.0) else { return nil }
        defer { SherpaOnnxDestroyOfflineTtsGeneratedAudio(audio) }
        let count = Int(audio.pointee.n)
        guard count > 0, let samples = audio.pointee.samples,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: Double(audio.pointee.sample_rate), channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        channel.update(from: samples, count: count)
        buffer.frameLength = AVAudioFrameCount(count)
        return buffer
    }

    /// Call with the lock held.
    private func engine(for voice: PiperVoice) -> OpaquePointer? {
        if let loaded, loaded.id == voice.id { return loaded.tts }
        if let loaded { SherpaOnnxDestroyOfflineTts(loaded.tts) }
        loaded = nil
        guard voice.isInstalled else { return nil }
        // The config holds C strings; they must live until the engine is made.
        let strings = [voice.model.path, voice.folder.appendingPathComponent("tokens.txt").path,
                       voice.folder.appendingPathComponent("espeak-ng-data").path, "cpu"].map { strdup($0) }
        defer { strings.forEach { free($0) } }
        var config = SherpaOnnxOfflineTtsConfig()
        config.model.vits.model = UnsafePointer(strings[0])
        config.model.vits.tokens = UnsafePointer(strings[1])
        config.model.vits.data_dir = UnsafePointer(strings[2])
        config.model.vits.noise_scale = 0.667
        config.model.vits.noise_scale_w = 0.8
        config.model.vits.length_scale = 1.0
        config.model.num_threads = 2
        config.model.provider = UnsafePointer(strings[3])
        config.max_num_sentences = 1
        guard let tts = SherpaOnnxCreateOfflineTts(&config) else { return nil }
        loaded = (voice.id, tts)
        return tts
    }
}
