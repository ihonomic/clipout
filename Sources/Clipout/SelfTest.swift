import AppKit
import AVFAudio
import ClipoutCore

/// `Clipout --selftest`: checks the parts that need the real system (Anki,
/// translation, voice, text recognition) and prints the result. Sends no card.
@MainActor
enum SelfTest {
    static func run() async {
        Prefs.registerDefaults()
        Paths.ensure()
        let controller = AppController.shared
        var lines: [String] = []

        await controller.anki.poll()
        lines.append("Anki erreichbar: \(controller.anki.isUp)")
        if controller.anki.isUp {
            let note = CardModels.note(for: CardDraft(sentence: "Clipout Selbsttest \(UUID().uuidString)"),
                                       deck: Prefs.deck)
            lines.append("Notiztypen + canAdd: \(await controller.anki.check(note))")
        }

        await controller.translator.refresh()
        lines.append("Übersetzung Status: \(String(describing: controller.translator.status))")
        if let text = await controller.translator.translate("Also wird das noch was mit mir?") {
            lines.append("Übersetzung: \(text)")
        }

        for word in ["schmälert", "Abstimmungen", "keineswegs"] {
            let e = await controller.dictionary.explain(word)
            lines.append("Wörterbuch \(word): \(e.map { "\($0.lemma ?? "-") | \($0.definitions.joined(separator: "; "))" } ?? "nichts")")
        }

        // Several sentences: enhanced voices deliver them in several buffers.
        let audio = Paths.root.appendingPathComponent("selftest.\(Prefs.audioExtension)")
        let spoke = await controller.speech.makeAudio(
            "Jeden Tag von Toledo nach Madrid. Gerade als ich an der Universität angekommen war, erfuhr ich von dem Unfall.",
            language: Prefs.sourceLang, to: audio)
        let seconds = (try? AVAudioFile(forReading: audio)).map { Double($0.length) / $0.fileFormat.sampleRate } ?? 0
        lines.append("Audio (\(audio.pathExtension)): \(spoke), lesbar \(String(format: "%.1f", seconds)) s, Stimme: \(SpeechMaker.voice(for: Prefs.sourceLang)?.name ?? "-")")
        try? FileManager.default.removeItem(at: audio)

        lines.append("Bedienungshilfen erlaubt: \(SelectionReader.isTrusted)")

        let sealed = Vault.seal(Data("geheim".utf8))
        lines.append("Tresor: Schlüssel \(Vault.key != nil), Rundreise \(sealed.flatMap(Vault.open) == Data("geheim".utf8))")
        let history = SealedFile.load([ClipItem].self, from: Paths.history) ?? []
        let images = history.filter { $0.kind == .image }
        let readable = images.filter { controller.clips.image($0) != nil }.count
        lines.append("Verlauf entschlüsselt: \(history.count) Einträge, Bilder lesbar \(readable)/\(images.count)")

        if CommandLine.arguments.contains("--send"), controller.anki.isUp {
            // Real round trip, then the test note is deleted again.
            let sentence = "Der Trabi war laut \(Int.random(in: 1000...9999))."
            let hidden: Set<Int> = [Sentence.tokens(sentence).firstIndex { $0.text == "Trabi" }!]
            let draft = CardDraft(sentence: sentence, translation: "The Trabi was loud.", hiddenWords: hidden,
                                  sourceURL: "https://de.wikipedia.org/wiki/Trabant", sourceTitle: "Wikipedia",
                                  explanations: [WordExplanation(word: "Trabi", definitions: ["Trabant (car)"])],
                                  listening: true)
            let outcome = await controller.send(draft, image: nil, audio: true)
            lines.append("Senden: \(outcome.message)")
            let client = AnkiClient(port: Prefs.ankiPort)
            let found = try? await client.call("findNotes", ["query": "tag:clipout added:1 \"Translation:The Trabi was loud.\""],
                                               as: [Int].self)
            let ids: [Int] = (found ?? nil) ?? []
            struct Info: Decodable { struct F: Decodable { let value: String }; let modelName: String; let fields: [String: F] }
            if let id = ids.last,
               let info = try? await client.call("notesInfo", ["notes": [id]], as: [Info].self)?.first {
                lines.append("In Anki: \(info.modelName) | \(info.fields["Text"]?.value ?? "") | \(info.fields["Audio"]?.value ?? "") | Listening=\(info.fields["Listening"]?.value ?? "?") | \(info.fields["Meaning"]?.value ?? "?")")
                _ = try? await client.call("deleteNotes", ["notes": ids], as: Ignored.self)
                if let audio = info.fields["Audio"]?.value.dropFirst(7).dropLast() {
                    _ = try? await client.call("deleteMediaFile", ["filename": String(audio)], as: Ignored.self)
                }
                lines.append("Testkarte wieder gelöscht")
            }
        }
        let store = controller.patterns
        store.start(clips: controller.clips)
        let before = store.patterns
        store.draft = "clipout-selbsttest-muster"
        store.add()
        let added = store.patterns.contains("clipout-selbsttest-muster") && store.notice != nil
        store.remove("clipout-selbsttest-muster")
        store.draft = "/[kaputt/"
        store.add()
        lines.append("Muster: hinzugefügt \(added), entfernt \(store.patterns == before), kaputtes Regex abgelehnt \(store.error != nil)")
        lines.append("Verlauf-Standard: \(Prefs.historyDays) Tag(e)")

        print(lines.joined(separator: "\n"))
        fflush(stdout)
        exit(0)
    }
}

/// `Clipout --repair-audio`: re-creates the audio of every Clipout note in
/// Anki under its existing file name. For cards made before the audio fix,
/// whose files were cut off by enhanced voices.
@MainActor
enum AudioRepair {
    static func run() async {
        Prefs.registerDefaults()
        Paths.ensure()
        let client = AnkiClient(port: Prefs.ankiPort)
        struct Info: Decodable {
            struct F: Decodable { let value: String }
            let noteId: Int
            let fields: [String: F]
        }
        let ids = ((try? await client.call("findNotes", ["query": "tag:clipout"], as: [Int].self)) ?? nil) ?? []
        let notes = ((try? await client.call("notesInfo", ["notes": ids], as: [Info].self)) ?? nil) ?? []
        var repaired = 0
        for note in notes {
            let audio = note.fields["Audio"]?.value ?? ""
            guard audio.hasPrefix("[sound:"), audio.hasSuffix("]") else { continue }
            let name = String(audio.dropFirst(7).dropLast())
            let html = note.fields["Sentence"]?.value ?? note.fields["Text"]?.value ?? ""
            let text = html
                .replacingOccurrences(of: #"\{\{c\d+::(.*?)(::.*?)?\}\}"#, with: "$1", options: .regularExpression)
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
            let url = Paths.media.appendingPathComponent(name)
            guard !text.isEmpty,
                  await AppController.shared.speech.makeAudio(text, language: Prefs.sourceLang, to: url),
                  let data = try? Data(contentsOf: url) else { continue }
            _ = try? await client.call("storeMediaFile", ["filename": name, "data": data.base64EncodedString()],
                                       as: Ignored.self, timeout: 30)
            try? FileManager.default.removeItem(at: url)
            repaired += 1
        }
        print("Audio neu erzeugt: \(repaired) von \(notes.count) Clipout-Karten")
        fflush(stdout)
        exit(0)
    }
}

/// `Clipout --convert-audio`: makes existing Clipout notes play on AnkiWeb.
/// - .m4a audio becomes MP3 (AnkiWeb plays only MP3). The sound is decoded
///   and re-encoded, not spoken again, so it stays exactly as it was.
/// - File names in the notes are lowercased: AnkiConnect stores media in
///   lowercase, older Clipout versions wrote the name in uppercase, and
///   AnkiWeb, unlike the Mac, doesn't find the file then.
/// Anki's Tools → Check Media removes the old .m4a files afterwards.
@MainActor
enum AudioConvert {
    static func run() async {
        Prefs.registerDefaults()
        Paths.ensure()
        let client = AnkiClient(port: Prefs.ankiPort)
        struct Info: Decodable {
            struct F: Decodable { let value: String }
            let noteId: Int
            let fields: [String: F]
        }
        struct Update: Encodable {
            struct Note: Encodable { let id: Int; let fields: [String: String] }
            let note: Note
        }
        let ids = ((try? await client.call("findNotes", ["query": "tag:clipout"], as: [Int].self)) ?? nil) ?? []
        let notes = ((try? await client.call("notesInfo", ["notes": ids], as: [Info].self)) ?? nil) ?? []
        var converted = 0, renamed = 0, failed = 0
        for note in notes {
            var fields: [String: String] = [:]
            for key in ["Audio", "Image"] {
                guard let value = note.fields[key]?.value, value.contains("clipout-") else { continue }
                // Anki already holds these files under the lowercase name.
                if value != value.lowercased() { fields[key] = value.lowercased() }
            }
            let audio = fields["Audio"] ?? note.fields["Audio"]?.value ?? ""
            if audio.hasPrefix("[sound:"), audio.hasSuffix(".m4a]") {
                let old = String(audio.dropFirst(7).dropLast())
                guard let new = await mp3(from: old, client: client) else { failed += 1; continue }
                fields["Audio"] = "[sound:\(new)]"
                converted += 1
            }
            guard !fields.isEmpty else { continue }
            do {
                _ = try await client.call("updateNoteFields", Update(note: .init(id: note.noteId, fields: fields)),
                                          as: Ignored.self)
                if fields.count > (audio.hasSuffix(".m4a]") ? 1 : 0) { renamed += 1 }
            } catch {
                print("Notiz \(note.noteId): \(error)")
                failed += 1
            }
        }
        print("In MP3 umgewandelt: \(converted), Dateinamen korrigiert: \(renamed), fehlgeschlagen: \(failed), Clipout-Karten insgesamt: \(notes.count)")
        fflush(stdout)
        exit(0)
    }

    /// Fetches `name` from Anki, stores it as MP3 and returns the stored name.
    private static func mp3(from name: String, client: AnkiClient) async -> String? {
        let new = (name as NSString).deletingPathExtension + ".mp3"
        let oldURL = Paths.media.appendingPathComponent(name)
        let newURL = Paths.media.appendingPathComponent(new)
        defer {
            try? FileManager.default.removeItem(at: oldURL)
            try? FileManager.default.removeItem(at: newURL)
        }
        guard let base64 = (try? await client.call("retrieveMediaFile", ["filename": name],
                                                    as: String.self, timeout: 30)) ?? nil,
              let data = Data(base64Encoded: base64),
              (try? data.write(to: oldURL)) != nil,
              let buffers = MP3Encoder.buffers(from: oldURL),
              MP3Encoder.write(buffers, to: newURL),
              let mp3 = try? Data(contentsOf: newURL) else { return nil }
        return (try? await client.call("storeMediaFile", ["filename": new, "data": mp3.base64EncodedString()],
                                       as: String.self, timeout: 30)) ?? nil
    }
}
