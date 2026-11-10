import AppKit
import AVFAudio
import ClipoutCore
import Carbon.HIToolbox
import Translation
import Vision

/// Apple's on-device translation: free, offline, no API key. The language
/// pack has to be downloaded once (Settings → "Sprachpaket laden").
@MainActor
final class Translator: ObservableObject {
    @Published private(set) var status: LanguageAvailability.Status?
    private var session: TranslationSession?
    private var pair = ""

    var isReady: Bool { status == .installed }

    func refresh() async {
        status = await LanguageAvailability().status(from: Locale.Language(identifier: Prefs.sourceLang),
                                                     to: Locale.Language(identifier: Prefs.targetLang))
    }

    func translate(_ text: String) async -> String? {
        if status == nil { await refresh() }
        guard isReady else { return nil }
        let wanted = Prefs.sourceLang + ">" + Prefs.targetLang
        if session == nil || pair != wanted {
            session = TranslationSession(installedSource: Locale.Language(identifier: Prefs.sourceLang),
                                         target: Locale.Language(identifier: Prefs.targetLang))
            pair = wanted
        }
        return try? await session?.translate(text).targetText
    }
}

/// Reads the sentence aloud with the best installed system voice and saves it
/// as .m4a for the back of the card.
@MainActor
final class SpeechMaker {
    private let synthesizer = AVSpeechSynthesizer()

    static func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .max { $0.quality.rawValue < $1.quality.rawValue }
    }

    func makeAudio(_ text: String, language: String, to url: URL) async -> Bool {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice(for: language)
        var file: AVAudioFile?
        var done = false
        let ok: Bool = await withCheckedContinuation { continuation in
            func finish(_ result: Bool) {
                guard !done else { return }
                done = true
                continuation.resume(returning: result)
            }
            synthesizer.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength == 0 {
                    finish(file != nil)
                    return
                }
                do {
                    if file == nil {
                        let settings: [String: Any] = [
                            AVFormatIDKey: kAudioFormatMPEG4AAC,
                            AVSampleRateKey: pcm.format.sampleRate,
                            AVNumberOfChannelsKey: pcm.format.channelCount,
                            AVEncoderBitRateKey: 64_000,
                        ]
                        file = try AVAudioFile(forWriting: url, settings: settings,
                                               commonFormat: pcm.format.commonFormat,
                                               interleaved: pcm.format.isInterleaved)
                    }
                    try file?.write(from: pcm)
                } catch {
                    finish(false)
                }
            }
            // Some voices never send the final empty buffer.
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { finish(file != nil) }
        }
        file = nil   // closes the file so AAC is finalized
        return ok
    }
}

/// Text inside images (screenshots, photos of book pages).
enum TextRecognizer {
    static func text(in imageURL: URL, language: String) async -> String {
        guard let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "" }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.recognitionLanguages = [language, "en"]
                try? VNImageRequestHandler(cgImage: cgImage).perform([request])
                let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: " "))
            }
        }
    }
}

/// Where the text came from: the page URL in browsers, else the window title.
@MainActor
enum SourceDetector {
    private static let scripts: [String: String] = [
        "com.google.Chrome": "tell application id \"com.google.Chrome\" to return (URL of active tab of front window) & linefeed & (title of active tab of front window)",
        "com.brave.Browser": "tell application id \"com.brave.Browser\" to return (URL of active tab of front window) & linefeed & (title of active tab of front window)",
        "com.microsoft.edgemac": "tell application id \"com.microsoft.edgemac\" to return (URL of active tab of front window) & linefeed & (title of active tab of front window)",
        "company.thebrowser.Browser": "tell application id \"company.thebrowser.Browser\" to return (URL of active tab of front window) & linefeed & (title of active tab of front window)",
        "com.apple.Safari": "tell application id \"com.apple.Safari\" to return (URL of front document) & linefeed & (name of front document)",
    ]

    static func detect(_ app: NSRunningApplication?) -> (url: String, title: String) {
        if let id = app?.bundleIdentifier, let source = scripts[id] {
            var error: NSDictionary?
            if let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue {
                let parts = result.components(separatedBy: "\n")
                if parts.count >= 2, parts[0].hasPrefix("http") {
                    return (parts[0], parts[1...].joined(separator: " "))
                }
            }
        }
        let title = SelectionReader.frontWindowTitle(of: app) ?? ""
        let name = app?.localizedName ?? ""
        if title.isEmpty || title == name { return ("", name) }
        return ("", name.isEmpty ? title : "\(name) – \(title)")
    }
}

/// System-wide ⌥⌘A. Carbon hotkeys need no permission and keep the other
/// app in front, so its selection is still readable.
final class HotKey {
    private static var action: (() -> Void)?
    private var ref: EventHotKeyRef?

    init(keyCode: Int = kVK_ANSI_A, modifiers: Int = cmdKey | optionKey, action: @escaping () -> Void) {
        HotKey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.action?() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x434C_4F55), id: 1)   // "CLOU"
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref)
    }
}

/// Word meanings from the English Wiktionary. Online (sends only the word),
/// so it can be switched off in the settings.
@MainActor
final class DictionaryLookup {
    private var cache: [String: WordExplanation?] = [:]

    func explain(_ word: String) async -> WordExplanation? {
        let key = Prefs.sourceLang + ":" + word
        if let hit = cache[key] { return hit }
        var result: WordExplanation?
        // German nouns are capitalized, other words not; at a sentence start
        // the case is misleading, so try both.
        for candidate in [word, word.lowercased(), word.prefix(1).uppercased() + word.dropFirst()]
            where result == nil {
            guard let parsed = await fetch(candidate) else { continue }
            if !parsed.definitions.isEmpty {
                result = WordExplanation(word: word, lemma: candidate == word ? nil : candidate,
                                         definitions: parsed.definitions)
            } else if let lemma = parsed.lemma, let base = await fetch(lemma), !base.definitions.isEmpty {
                result = WordExplanation(word: word, lemma: lemma, definitions: base.definitions)
            }
        }
        if result?.lemma == word { result?.lemma = nil }
        cache[key] = result
        return result
    }

    private func fetch(_ word: String) async -> Wiktionary.Parsed? {
        guard let url = Wiktionary.url(for: word) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Clipout/0.1 (macOS language-learning app)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return Wiktionary.parse(data, language: Prefs.sourceLang)
    }
}

/// System voices are downloaded in System Settings → Accessibility → Spoken
/// Content (macOS moves it around; the search field finds "Stimme").
enum VoiceSettings {
    static func open() {
        let urls = [
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?SpokenContent",
            "x-apple.systempreferences:com.apple.preference.universalaccess?SpeakableItems",
            "x-apple.systempreferences:com.apple.preference.universalaccess",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }
}
