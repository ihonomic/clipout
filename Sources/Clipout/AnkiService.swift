import ClipoutCore
import Foundation

/// Thin AnkiConnect client: POST JSON to localhost.
struct AnkiClient {
    var port: Int

    func call<P: Encodable, R: Decodable>(_ action: String, _ params: P, as: R.Type = R.self,
                                          timeout: TimeInterval = 10) async throws -> R? {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(AnkiRequest(action: action, params: params))
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(AnkiResponse<R>.self, from: data)
        if let error = response.error { throw AnkiError(error) }
        return response.result
    }
}

struct QueuedCard: Codable, Identifiable {
    var id = UUID()
    var note: AnkiNote
    /// Files in Paths.media to upload before the note.
    var media: [String]
}

enum SendOutcome {
    case sent
    case duplicate
    case queued(String)

    var message: String {
        switch self {
        case .sent: return L("✓ An Anki gesendet")
        case .duplicate: return L("Diese Karte gibt es schon in Anki.")
        case .queued(let why): return L("In der Warteschlange: %@", why)
        }
    }
}

/// Watches whether Anki is open and delivers cards. Every card goes through the
/// same queue, so a card made while Anki is closed is sent when it opens.
@MainActor
final class AnkiService: ObservableObject {
    @Published private(set) var isUp = false
    @Published private(set) var queue: [QueuedCard] = []
    /// Why the queue is stuck, in German. LinguaMiner hid this and the user only saw "sending 2".
    @Published private(set) var lastError: String?

    private var client: AnkiClient { AnkiClient(port: Prefs.ankiPort) }
    private var flushing = false
    /// The cloze note type in use: "Clipout Cloze", or "Clipout Lücke" when an
    /// older version already created that one.
    private(set) var clozeModel = CardModels.cloze
    private var outcomes: [UUID: SendOutcome] = [:]
    private var timer: Timer?

    func start() {
        queue = SealedFile.load([QueuedCard].self, from: Paths.queue)
            ?? SealedFile.migrate([QueuedCard].self, from: Paths.legacyQueue, to: Paths.queue) ?? []
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in await self.poll() }
        }
        Task { await poll() }
    }

    func poll() async {
        let up = (try? await client.call("version", NoParams(), as: Int.self, timeout: 2)) != nil
        if up != isUp { isUp = up }
        if !up {
            lastError = queue.isEmpty ? nil : L("Anki ist nicht geöffnet.")
        } else if !queue.isEmpty {
            await flush()
        } else if Prefs.correctionMode != UserDefaults.standard.string(forKey: Prefs.appliedCorrectionModeKey) {
            // Switched in Settings while Anki was closed.
            await applyCorrectionMode()
        } else if !templatesChecked, !flushing {
            // A new Clipout may bring new card templates; without this they
            // only reached Anki with the next card you sent.
            flushing = true
            defer { flushing = false }
            templatesChecked = (try? await prepareAnki()) != nil
        }
    }

    /// Set once the note types match this version (see poll).
    private var templatesChecked = false

    func send(_ note: AnkiNote, media: [String]) async -> SendOutcome {
        await send([(note, media)])[0]
    }

    /// Many notes at once (a whole writing correction): queued together,
    /// so Anki is prepared once and not for every note.
    func send(_ notes: [(note: AnkiNote, media: [String])]) async -> [SendOutcome] {
        let cards = notes.map { QueuedCard(note: $0.note, media: $0.media) }
        queue.append(contentsOf: cards)
        save()
        if isUp {
            await flush()
        }
        return cards.map { outcomes.removeValue(forKey: $0.id) ?? .queued(lastError ?? L("Anki ist nicht geöffnet.")) }
    }

    // MARK: - Writing corrections: gaps or whole sentence

    /// Every corrected sentence has a gap note and a sentence note; the kind
    /// not chosen in Settings is suspended, so switching keeps the progress of
    /// both. Switching to "sentence" the first time makes the sentence notes
    /// for corrections sent before there was such a thing.
    func applyCorrectionMode() async {
        guard isUp, !flushing else { return }
        flushing = true
        defer { flushing = false }
        do {
            try await prepareAnki()
            if Prefs.correctionMode == "sentence" { try await syncSentenceNotes() }
            let (active, inactive) = Prefs.correctionMode == "sentence"
                ? (CardModels.correctionSentence, CardModels.correction)
                : (CardModels.correction, CardModels.correctionSentence)
            try await suspendCards(of: inactive, true)
            try await suspendCards(of: active, false)
            UserDefaults.standard.set(Prefs.correctionMode, forKey: Prefs.appliedCorrectionModeKey)
            lastError = nil
        } catch let error as AnkiError {
            lastError = L(error.explanation)
        } catch {
            lastError = L("Anki antwortet nicht: %@", error.localizedDescription)
        }
    }

    /// After sending corrections: their cards of the kind not in use wait suspended.
    func suspendInactiveCorrections() async {
        guard isUp else { return }
        let inactive = Prefs.correctionMode == "sentence" ? CardModels.correction : CardModels.correctionSentence
        try? await suspendCards(of: inactive, true)
    }

    private func suspendCards(of model: String, _ suspend: Bool) async throws {
        let query = "note:\"\(model)\" " + (suspend ? "-is:suspended" : "is:suspended")
        let cards = try await client.call("findCards", ["query": query], as: [Int].self) ?? []
        guard !cards.isEmpty else { return }
        _ = try await client.call(suspend ? "suspend" : "unsuspend", ["cards": cards], as: Ignored.self)
    }

    /// Makes the sentence note for every gap note, and brings existing ones
    /// up to date when the way they are built changed (the checklist, say).
    private func syncSentenceNotes() async throws {
        struct Field: Decodable { let value: String }
        struct NoteInfo: Decodable { let noteId: Int; let tags: [String]; let fields: [String: Field] }
        struct CardInfo: Decodable { let note: Int; let deckName: String }
        let cardIDs = try await client.call("findCards", ["query": "note:\"\(CardModels.correction)\""],
                                            as: [Int].self) ?? []
        guard !cardIDs.isEmpty else { return }
        let cards = try await client.call("cardsInfo", ["cards": cardIDs], as: [CardInfo].self) ?? []
        let decks = Dictionary(cards.map { ($0.note, $0.deckName) }, uniquingKeysWith: { first, _ in first })
        let infos = try await client.call("notesInfo", ["notes": Array(decks.keys)], as: [NoteInfo].self) ?? []
        let notes = infos.compactMap { info -> AnkiNote? in
            guard let deck = decks[info.noteId] else { return nil }
            return Corrections.sentenceNote(from: AnkiNote(deckName: deck, modelName: CardModels.correction,
                                                           fields: info.fields.mapValues(\.value), tags: info.tags))
        }
        struct Update: Encodable {
            struct Note: Encodable { let id: Int; let fields: [String: String] }
            let note: Note
        }
        let existingIDs = try await client.call("findNotes", ["query": "note:\"\(CardModels.correctionSentence)\""],
                                                as: [Int].self) ?? []
        let existing = try await client.call("notesInfo", ["notes": existingIDs], as: [NoteInfo].self) ?? []
        let bySentence = Dictionary(existing.map { ($0.fields["Sentence"]?.value ?? "", $0) },
                                    uniquingKeysWith: { first, _ in first })
        var missing: [AnkiNote] = []
        for note in notes {
            guard let old = bySentence[note.fields["Sentence"] ?? ""] else { missing.append(note); continue }
            let changed = note.fields.filter { old.fields[$0.key]?.value != $0.value }
            if !changed.isEmpty {
                // An editor open on this note refuses the write; the next switch catches up.
                _ = try? await client.call("updateNoteFields", Update(note: .init(id: old.noteId, fields: changed)),
                                           as: Ignored.self)
            }
        }
        guard !missing.isEmpty else { return }
        let addable = try await client.call("canAddNotes", ["notes": missing], as: [Bool].self) ?? []
        let add = zip(missing, addable).filter(\.1).map(\.0)
        guard !add.isEmpty else { return }
        _ = try await client.call("addNotes", ["notes": add], as: [Int?].self)
    }

    /// For --selftest: set up note types, then ask Anki (without writing a
    /// note) whether this note could be added.
    func check(_ note: AnkiNote) async -> String {
        do {
            try await prepareAnki()
            let result = try await client.call("canAddNotesWithErrorDetail", ["notes": [note]],
                                               as: [CanAddResult].self)?.first
            return result?.canAdd == true ? "ok" : (result?.error ?? "?")
        } catch {
            return "Fehler: \(error.localizedDescription)"
        }
    }

    func retry() {
        Task { await poll() }
    }

    private func flush() async {
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }
        var sentCorrections = false
        do {
            try await prepareAnki()
            while var card = queue.first {
                card.note = card.note.migrated(clozeModel: clozeModel)
                let check = try await client.call("canAddNotesWithErrorDetail",
                                                  ["notes": [card.note]], as: [CanAddResult].self)
                if let result = check?.first, !result.canAdd {
                    let error = AnkiError(result.error ?? L("Anki lehnt die Karte ab."))
                    guard error.isDuplicate else { throw error }
                    finish(card, .duplicate)
                    continue
                }
                for name in card.media {
                    let url = Paths.media.appendingPathComponent(name)
                    guard let data = try? Data(contentsOf: url) else { continue }
                    // AnkiConnect stores the name in lowercase and says so. The
                    // Mac doesn't mind the difference, but AnkiWeb then finds
                    // no file and shows no play button.
                    let stored = try await client.call("storeMediaFile",
                                                       ["filename": name, "data": data.base64EncodedString()],
                                                       as: String.self, timeout: 30)
                    if let stored, stored != name { card.note = card.note.renamingMedia(name, to: stored) }
                }
                _ = try await client.call("addNote", ["note": card.note], as: Int.self)
                if card.note.modelName == CardModels.correction || card.note.modelName == CardModels.correctionSentence {
                    sentCorrections = true
                }
                finish(card, .sent)
            }
            lastError = nil
        } catch let error as AnkiError {
            lastError = L(error.explanation)
        } catch {
            lastError = L("Anki antwortet nicht: %@", error.localizedDescription)
        }
        // Corrections arrive as both kinds of card, also those queued while
        // Anki was closed; the one not in use waits suspended.
        if sentCorrections { await suspendInactiveCorrections() }
    }

    private func finish(_ card: QueuedCard, _ outcome: SendOutcome) {
        outcomes[card.id] = outcome
        queue.removeAll { $0.id == card.id }
        save()
        for name in card.media {
            try? FileManager.default.removeItem(at: Paths.media.appendingPathComponent(name))
        }
    }

    private func save() {
        SealedFile.save(queue, to: Paths.queue)
    }

    // MARK: - Note types and decks

    private struct Template: Codable, Equatable {
        var Front: String
        var Back: String
    }

    private struct CreateModel: Encodable {
        struct CardTemplate: Encodable {
            let Name: String
            let Front: String
            let Back: String
        }
        let modelName: String
        let inOrderFields: [String]
        let css: String
        let isCloze: Bool
        let cardTemplates: [CardTemplate]
    }

    private struct UpdateTemplates: Encodable {
        struct Model: Encodable {
            let name: String
            let templates: [String: Template]
        }
        let model: Model
    }

    private struct FieldRename: Encodable {
        let modelName: String
        let oldFieldName: String
        let newFieldName: String
    }

    private struct FieldAdd: Encodable {
        let modelName: String
        let fieldName: String
        let index: Int
    }

    private struct UpdateStyling: Encodable {
        struct Model: Encodable {
            let name: String
            let css: String
        }
        let model: Model
    }

    /// Creates the note types and decks the queue needs. Existing note types
    /// are only rewritten when they differ: with an editor open in Anki, any
    /// write fails ("Close the affected editor…").
    private func prepareAnki() async throws {
        let models = try await client.call("modelNames", NoParams(), as: [String].self) ?? []
        clozeModel = !models.contains(CardModels.cloze) && models.contains(CardModels.legacyCloze)
            ? CardModels.legacyCloze : CardModels.cloze
        var wanted: [(name: String, fields: [String], cloze: Bool, front: String, back: String, css: String)] = [
            (CardModels.basic, CardModels.basicFields, false, CardModels.basicFront, CardModels.basicBack,
             CardModels.css),
            (clozeModel, CardModels.clozeFields, true, CardModels.clozeFront, CardModels.clozeBack, CardModels.css),
        ]
        // Only for people who use writing corrections.
        if models.contains(CardModels.correction) || queue.contains(where: { $0.note.modelName == CardModels.correction }) {
            wanted.append((CardModels.correction, CardModels.correctionFields, true, CardModels.correctionFront,
                           CardModels.correctionBack, CardModels.correctionCSS))
            wanted.append((CardModels.correctionSentence, CardModels.correctionSentenceFields, false,
                           CardModels.correctionSentenceFront(task: L("Korrigiere diesen Satz:"),
                                                              lookFor: L("Achte auf:")),
                           CardModels.correctionSentenceBack, CardModels.correctionSentenceCSS))
        }
        for m in wanted {
            if !models.contains(m.name) {
                _ = try await client.call("createModel", CreateModel(
                    modelName: m.name, inOrderFields: m.fields, css: m.css, isCloze: m.cloze,
                    cardTemplates: [.init(Name: "Card 1", Front: m.front, Back: m.back)]), as: Ignored.self)
                continue
            }
            var have = try await client.call("modelFieldNames", ["modelName": m.name], as: [String].self) ?? []
            // 0.1.x used German field names; renaming keeps every card's content
            // (Anki updates the templates' references itself).
            for (old, new) in CardModels.legacyFieldNames where have.contains(old) && !have.contains(new) {
                _ = try await client.call("modelFieldRename", FieldRename(modelName: m.name, oldFieldName: old,
                                                                          newFieldName: new), as: Ignored.self)
                have = have.map { $0 == old ? new : $0 }
            }
            // Fields added in later versions go to the end.
            for field in m.fields where !have.contains(field) {
                _ = try await client.call("modelFieldAdd", FieldAdd(modelName: m.name, fieldName: field,
                                                                    index: have.count), as: Ignored.self)
                have.append(field)
            }
            let templates = try await client.call("modelTemplates", ["modelName": m.name],
                                                  as: [String: Template].self) ?? [:]
            if let (cardName, current) = templates.first,
               current != Template(Front: m.front, Back: m.back) {
                _ = try await client.call("updateModelTemplates", UpdateTemplates(model: .init(
                    name: m.name, templates: [cardName: Template(Front: m.front, Back: m.back)])),
                    as: Ignored.self)
            }
            let styling = try await client.call("modelStyling", ["modelName": m.name],
                                                as: [String: String].self)
            if styling?["css"] != m.css {
                _ = try await client.call("updateModelStyling",
                                          UpdateStyling(model: .init(name: m.name, css: m.css)),
                                          as: Ignored.self)
            }
        }
        let decks = try await client.call("deckNames", NoParams(), as: [String].self) ?? []
        for deck in Set(queue.map(\.note.deckName) + [Prefs.deck]) where !decks.contains(deck) {
            _ = try await client.call("createDeck", ["deck": deck], as: Ignored.self)
        }
    }
}
