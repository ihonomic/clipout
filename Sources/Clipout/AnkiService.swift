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
        }
    }

    func send(_ note: AnkiNote, media: [String]) async -> SendOutcome {
        let card = QueuedCard(note: note, media: media)
        queue.append(card)
        save()
        if isUp {
            await flush()
        }
        return outcomes.removeValue(forKey: card.id) ?? .queued(lastError ?? L("Anki ist nicht geöffnet."))
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
                    _ = try await client.call("storeMediaFile",
                                              ["filename": name, "data": data.base64EncodedString()],
                                              as: Ignored.self, timeout: 30)
                }
                _ = try await client.call("addNote", ["note": card.note], as: Int.self)
                finish(card, .sent)
            }
            lastError = nil
        } catch let error as AnkiError {
            lastError = L(error.explanation)
        } catch {
            lastError = L("Anki antwortet nicht: %@", error.localizedDescription)
        }
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
        let wanted: [(name: String, fields: [String], cloze: Bool, front: String, back: String)] = [
            (CardModels.basic, CardModels.basicFields, false, CardModels.basicFront, CardModels.basicBack),
            (clozeModel, CardModels.clozeFields, true, CardModels.clozeFront, CardModels.clozeBack),
        ]
        for m in wanted {
            if !models.contains(m.name) {
                _ = try await client.call("createModel", CreateModel(
                    modelName: m.name, inOrderFields: m.fields, css: CardModels.css, isCloze: m.cloze,
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
            if styling?["css"] != CardModels.css {
                _ = try await client.call("updateModelStyling",
                                          UpdateStyling(model: .init(name: m.name, css: CardModels.css)),
                                          as: Ignored.self)
            }
        }
        let decks = try await client.call("deckNames", NoParams(), as: [String].self) ?? []
        for deck in Set(queue.map(\.note.deckName) + [Prefs.deck]) where !decks.contains(deck) {
            _ = try await client.call("createDeck", ["deck": deck], as: Ignored.self)
        }
    }
}
