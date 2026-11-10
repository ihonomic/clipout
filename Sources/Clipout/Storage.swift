import Foundation

/// ~/Library/Application Support/Clipout
enum Paths {
    static let root = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Clipout", isDirectory: true)
    /// Images from the clipboard history.
    static let clips = root.appendingPathComponent("clips", isDirectory: true)
    /// Audio and images waiting to be uploaded to Anki.
    static let media = root.appendingPathComponent("media", isDirectory: true)
    static let history = root.appendingPathComponent("history.json")
    static let queue = root.appendingPathComponent("queue.json")

    static func ensure() {
        for dir in [root, clips, media] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

enum JSONFile {
    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Settings, shared by the views (@AppStorage with the same keys) and the services.
enum Prefs {
    static let deckKey = "deck"
    static let sourceLangKey = "sourceLang"
    static let targetLangKey = "targetLang"
    static let makeAudioKey = "makeAudio"
    static let showIconKey = "showIcon"
    static let copyFallbackKey = "copyFallback"
    static let historyLimitKey = "historyLimit"
    static let pauseClipboardKey = "pauseClipboard"
    static let ankiPortKey = "ankiPort"
    static let listeningKey = "listening"
    static let dictionaryKey = "dictionary"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            deckKey: "Clipout",
            sourceLangKey: "de",
            targetLangKey: "en",
            makeAudioKey: true,
            showIconKey: true,
            copyFallbackKey: true,
            historyLimitKey: 200,
            pauseClipboardKey: false,
            ankiPortKey: 8765,
            listeningKey: false,
            dictionaryKey: true,
        ])
    }

    private static var d: UserDefaults { .standard }
    static var deck: String {
        let name = d.string(forKey: deckKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Clipout" : name
    }
    static var sourceLang: String { d.string(forKey: sourceLangKey) ?? "de" }
    static var targetLang: String { d.string(forKey: targetLangKey) ?? "en" }
    static var makeAudio: Bool { d.bool(forKey: makeAudioKey) }
    static var showIcon: Bool { d.bool(forKey: showIconKey) }
    static var copyFallback: Bool { d.bool(forKey: copyFallbackKey) }
    static var historyLimit: Int { max(10, d.integer(forKey: historyLimitKey)) }
    static var pauseClipboard: Bool { d.bool(forKey: pauseClipboardKey) }
    static var ankiPort: Int { d.integer(forKey: ankiPortKey) }
    /// New cards are listening cards (audio in front) unless changed per card.
    static var listening: Bool { d.bool(forKey: listeningKey) }
    /// Look words up on en.wiktionary.org.
    static var dictionary: Bool { d.bool(forKey: dictionaryKey) }

    static let languages: [(code: String, name: String)] = [
        ("de", "Deutsch"), ("en", "Englisch"), ("es", "Spanisch"), ("fr", "Französisch"),
        ("it", "Italienisch"), ("pt", "Portugiesisch"), ("nl", "Niederländisch"),
        ("pl", "Polnisch"), ("tr", "Türkisch"), ("ru", "Russisch"),
    ]
}
