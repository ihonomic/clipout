import CryptoKit
import Foundation
import Security

/// ~/Library/Application Support/Clipout
enum Paths {
    static let root = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Clipout", isDirectory: true)
    /// Images from the clipboard history.
    static let clips = root.appendingPathComponent("clips", isDirectory: true)
    /// Audio and images waiting to be uploaded to Anki.
    static let media = root.appendingPathComponent("media", isDirectory: true)
    /// Encrypted (see Vault). The .json names are 0.1.0's plain files, migrated once.
    static let history = root.appendingPathComponent("history.sealed")
    static let queue = root.appendingPathComponent("queue.sealed")
    static let legacyHistory = root.appendingPathComponent("history.json")
    static let legacyQueue = root.appendingPathComponent("queue.json")

    /// Only the user can read the folder: the history holds everything copied.
    static func ensure() {
        let fm = FileManager.default
        for dir in [root, clips, media] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }
        let clipFiles = (try? fm.contentsOfDirectory(at: clips, includingPropertiesForKeys: nil)) ?? []
        for file in [history, queue] + clipFiles where fm.fileExists(atPath: file.path) {
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
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
        // atomic writes create a new file each time, so set the mode again
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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
    static let historyDaysKey = "historyDays"
    static let pauseClipboardKey = "pauseClipboard"
    static let ankiPortKey = "ankiPort"
    static let listeningKey = "listening"
    static let dictionaryKey = "dictionary"
    static let voiceKey = "voice"
    static let audioFormatKey = "audioFormat"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            deckKey: "Clipout",
            sourceLangKey: "de",
            targetLangKey: "en",
            makeAudioKey: true,
            showIconKey: true,
            copyFallbackKey: true,
            historyLimitKey: 200,
            historyDaysKey: 1,
            pauseClipboardKey: false,
            ankiPortKey: 8765,
            listeningKey: false,
            dictionaryKey: true,
            audioFormatKey: "mp3",
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
    /// Entries older than this are deleted; 0 keeps them.
    static var historyDays: Int { d.integer(forKey: historyDaysKey) }
    static var pauseClipboard: Bool { d.bool(forKey: pauseClipboardKey) }
    static var ankiPort: Int { d.integer(forKey: ankiPortKey) }
    /// New cards are listening cards (audio in front) unless changed per card.
    static var listening: Bool { d.bool(forKey: listeningKey) }
    /// Look words up on en.wiktionary.org.
    static var dictionary: Bool { d.bool(forKey: dictionaryKey) }
    /// Identifier of the chosen system voice; empty picks the best one.
    static var voice: String { d.string(forKey: voiceKey) ?? "" }
    /// "mp3" plays everywhere, AnkiWeb included; "m4a" is Apple's AAC.
    static var audioExtension: String { d.string(forKey: audioFormatKey) == "m4a" ? "m4a" : "mp3" }

    static let languages: [(code: String, name: String)] = [
        ("de", "Deutsch"), ("en", "Englisch"), ("es", "Spanisch"), ("fr", "Französisch"),
        ("it", "Italienisch"), ("pt", "Portugiesisch"), ("nl", "Niederländisch"),
        ("pl", "Polnisch"), ("tr", "Türkisch"), ("ru", "Russisch"),
    ]
}

/// Encrypts what Clipout keeps on disk (history, clipboard images, queue)
/// with AES-256-GCM. The key lives in the login keychain, readable only by
/// this app on this Mac, so the files alone are useless to other programs
/// and in backups.
enum Vault {
    private static let service = "com.ihonomic.clipout"
    private static let account = "storage-key"

    /// nil if the keychain refused: then nothing is written to disk at all.
    static let key: SymmetricKey? = loadOrCreateKey()

    static func seal(_ data: Data) -> Data? {
        guard let key else { return nil }
        return try? AES.GCM.seal(data, using: key).combined
    }

    static func open(_ data: Data) -> Data? {
        guard let key, let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    private static func loadOrCreateKey() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var found: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess,
           let data = found as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Clipout storage key",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: key.withUnsafeBytes { Data($0) },
        ]
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess ? key : nil
    }
}

/// JSON files encrypted with the Vault.
enum SealedFile {
    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let sealed = try? Data(contentsOf: url), let data = Vault.open(sealed) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value), let sealed = Vault.seal(data) else { return }
        try? sealed.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Reads an unencrypted file from Clipout 0.1.0 once, then deletes it.
    static func migrate<T: Codable>(_ type: T.Type, from legacy: URL, to url: URL) -> T? {
        guard let old = JSONFile.load(type, from: legacy) else { return nil }
        save(old, to: url)
        try? FileManager.default.removeItem(at: legacy)
        return old
    }
}
