import AppKit
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

        let audio = Paths.root.appendingPathComponent("selftest.m4a")
        let spoke = await controller.speech.makeAudio("Das ist ein Test.", language: Prefs.sourceLang, to: audio)
        let size = (try? FileManager.default.attributesOfItem(atPath: audio.path)[.size] as? Int) ?? 0
        lines.append("Audio: \(spoke), \(size) Bytes, Stimme: \(SpeechMaker.bestVoice(for: Prefs.sourceLang)?.name ?? "-")")
        try? FileManager.default.removeItem(at: audio)

        lines.append("Bedienungshilfen erlaubt: \(SelectionReader.isTrusted)")

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
            let found = try? await client.call("findNotes", ["query": "tag:clipout added:1 \"Übersetzung:The Trabi was loud.\""],
                                               as: [Int].self)
            let ids: [Int] = (found ?? nil) ?? []
            struct Info: Decodable { struct F: Decodable { let value: String }; let modelName: String; let fields: [String: F] }
            if let id = ids.last,
               let info = try? await client.call("notesInfo", ["notes": [id]], as: [Info].self)?.first {
                lines.append("In Anki: \(info.modelName) | \(info.fields["Text"]?.value ?? "") | \(info.fields["Audio"]?.value ?? "") | Hören=\(info.fields["Hören"]?.value ?? "?") | \(info.fields["Erklärung"]?.value ?? "?")")
                _ = try? await client.call("deleteNotes", ["notes": ids], as: Ignored.self)
                if let audio = info.fields["Audio"]?.value.dropFirst(7).dropLast() {
                    _ = try? await client.call("deleteMediaFile", ["filename": String(audio)], as: Ignored.self)
                }
                lines.append("Testkarte wieder gelöscht")
            }
        }
        print(lines.joined(separator: "\n"))
        fflush(stdout)
        exit(0)
    }
}
