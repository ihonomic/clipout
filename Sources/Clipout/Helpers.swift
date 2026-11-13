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

/// Reads the sentence aloud with the chosen system voice and saves it for the
/// card: MP3 or AAC (.m4a), after the file name's extension.
///
/// The voice's buffers are first collected in memory and the file is written
/// in one go once speaking has finished. Writing while the voice was still
/// delivering broke the files of enhanced voices (several buffers, empty ones
/// in between): Anki showed a play button that played nothing.
@MainActor
final class SpeechMaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var finished: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Installed voices for the language, best quality first.
    static func voices(for language: String) -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(language) }
            .sorted { ($0.quality.rawValue, $1.name) > ($1.quality.rawValue, $0.name) }
    }

    /// The voice chosen in Settings if it speaks the language (it doesn't
    /// after the language was changed), otherwise the best installed one.
    static func voice(for language: String) -> AVSpeechSynthesisVoice? {
        let all = voices(for: language)
        return all.first { $0.identifier == Prefs.voice } ?? all.first
    }

    static func label(_ voice: AVSpeechSynthesisVoice) -> String {
        // Some names already carry it, e.g. "Helena (erweitert)".
        if voice.name.contains("(") { return voice.name }
        switch voice.quality {
        case .premium: return "\(voice.name) (\(L("Premium")))"
        case .enhanced: return "\(voice.name) (\(L("Erweitert")))"
        default: return voice.name
        }
    }

    func makeAudio(_ text: String, language: String, to url: URL) async -> Bool {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: language)
        var buffers: [AVAudioPCMBuffer] = []
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var done = false
            let finish = {
                guard !done else { return }
                done = true
                continuation.resume()
            }
            finished = finish
            synthesizer.write(utterance) { buffer in
                // The buffer may be reused by the synthesizer: keep a copy.
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0,
                      let copy = Self.copy(pcm) else { return }
                DispatchQueue.main.async { buffers.append(copy) }
            }
            // Safety net if the voice never reports the end.
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { finish() }
        }
        finished = nil
        // Let buffers already queued on the main thread arrive.
        try? await Task.sleep(for: .milliseconds(100))
        guard !buffers.isEmpty else { return false }
        return Self.write(buffers, to: url)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.finished?() } }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { MainActor.assumeIsolated { self.finished?() } }
    }

    private nonisolated static func copy(_ pcm: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: pcm.format, frameCapacity: pcm.frameLength) else { return nil }
        copy.frameLength = pcm.frameLength
        let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: pcm.audioBufferList))
        let dst = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(src, dst) {
            guard let fromData = from.mData, let toData = to.mData else { return nil }
            memcpy(toData, fromData, Int(min(from.mDataByteSize, to.mDataByteSize)))
        }
        return copy
    }

    /// Writes MP3 or AAC (.m4a) and checks that the file can be read back.
    static func write(_ buffers: [AVAudioPCMBuffer], to url: URL) -> Bool {
        if url.pathExtension == "mp3" { return MP3Encoder.write(buffers, to: url) }
        let format = buffers[0].format
        try? FileManager.default.removeItem(at: url)
        do {
            // Scoped so the file is closed (and the AAC finalized) before reading it back.
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderBitRateKey: 64_000,
            ]
            let file = try AVAudioFile(forWriting: url, settings: settings,
                                       commonFormat: format.commonFormat, interleaved: format.isInterleaved)
            for buffer in buffers where buffer.format == format {
                try file.write(from: buffer)
            }
        } catch {
            return false
        }
        guard let check = try? AVAudioFile(forReading: url), check.length > 0 else { return false }
        return true
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

/// Speaks a short sample with the chosen voice, in the language learned.
@MainActor
enum VoicePreview {
    private static let synthesizer = AVSpeechSynthesizer()
    private static let samples = [
        "de": "Das ist meine Stimme für deine Karten.",
        "en": "This is my voice for your cards.",
        "es": "Esta es mi voz para tus tarjetas.",
        "fr": "Voici ma voix pour tes cartes.",
        "it": "Questa è la mia voce per le tue carte.",
        "pt": "Esta é a minha voz para os teus cartões.",
        "nl": "Dit is mijn stem voor je kaarten.",
        "pl": "To jest mój głos dla twoich fiszek.",
        "tr": "Bu, kartların için benim sesim.",
        "ru": "Это мой голос для твоих карточек.",
    ]

    static func play(language: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let voice = SpeechMaker.voice(for: language)
        let utterance = AVSpeechUtterance(string: samples[language] ?? voice?.name ?? "Clipout")
        utterance.voice = voice
        synthesizer.speak(utterance)
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
