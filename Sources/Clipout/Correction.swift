import AppKit
import ClipoutCore
import SwiftUI

/// The writing-correction side of the main window: an AI corrects your text
/// and returns one line per sentence (see `CorrectionPrompt`); pasted here,
/// every correction becomes a card where you type the right form.
@MainActor
final class CorrectionModel: ObservableObject {
    @Published var input = "" {
        didSet {
            (rows, problems) = Corrections.parse(input)
            off = [:]
        }
    }
    /// As pasted, for the preview.
    @Published private(set) var rows: [CorrectionRow] = []
    /// Gaps you switched off, by row: they stay corrected but get no card.
    @Published private(set) var off: [Int: Set<Int>] = [:]
    @Published private(set) var problems: [Corrections.Problem] = []
    /// While sending: "Audio 3 of 12…".
    @Published private(set) var progress: String?
    @Published private(set) var result: String?

    /// What is sent: without the switched-off gaps; a sentence with none
    /// left is not sent at all.
    var rowsToSend: [CorrectionRow] {
        rows.enumerated().map { $1.withoutGaps(off[$0] ?? []) }.filter { $0.cardCount > 0 }
    }
    var cardCount: Int { rowsToSend.map(\.cardCount).reduce(0, +) }

    func toggle(row: Int, gap: Int) {
        off[row, default: []].formSymmetricDifference([gap])
    }

    func send(with controller: AppController) async {
        let rows = rowsToSend
        guard !rows.isEmpty, progress == nil else { return }
        result = nil
        let deck = Prefs.correctionDeck
        var notes: [(note: AnkiNote, media: [String])] = []
        for (i, row) in rows.enumerated() {
            var audio: String?
            if Prefs.makeAudio {
                progress = L("Audio %d von %d…", i + 1, rows.count)
                let name = "clipout-\(UUID().uuidString.lowercased()).\(Prefs.audioExtension)"
                if await controller.speech.makeAudio(row.sentence, language: Prefs.sourceLang,
                                                     to: Paths.media.appendingPathComponent(name)) {
                    audio = name
                }
            }
            // Both kinds of card, gaps and whole sentence; Settings decides
            // which one is active, the other is suspended after sending.
            let gapNote = Corrections.note(for: row, deck: deck, audioFile: audio)
            notes.append((gapNote, audio.map { [$0] } ?? []))
            notes.append((Corrections.sentenceNote(from: gapNote), audio.map { [$0] } ?? []))
        }
        progress = L("Wird an Anki gesendet…")
        let outcomes = await controller.anki.send(notes)
        progress = nil
        var sent = 0, duplicates = 0, queued = 0
        // Counted per sentence: the gap notes are every other one.
        for outcome in outcomes.enumerated().filter({ $0.offset.isMultiple(of: 2) }).map(\.element) {
            switch outcome {
            case .sent: sent += 1
            case .duplicate: duplicates += 1
            case .queued: queued += 1
            }
        }
        result = L("%d gesendet · %d gab es schon · %d in der Warteschlange", sent, duplicates, queued)
        if queued == 0 { input = "" }
    }
}

/// The instructions to give the AI together with your text. They follow the
/// columns `Corrections.parse` reads.
enum CorrectionPrompt {
    static var text: String {
        let learn = L10n.languageName(Prefs.sourceLang)
        let mine = L10n.languageName(Prefs.targetLang)
        let today = Date().formatted(.iso8601.year().month().day())
        if L10n.language == "de" {
            return """
            Korrigiere meinen Text unten (Sprache: \(learn)). Gib danach jede Korrektur als Anki-Zeile aus, tabulatorgetrennt, ohne Kopfzeile, in einem Codeblock.

            Spalte 1 (Text): der korrigierte Satz. Jede Korrektur ist eine Cloze: {{c1::korrekte Form::Bedeutung auf \(mine) · Grammatikregel}}. Die Cloze ist so klein wie möglich, höchstens 3 Wörter: nur die Wörter, die falsch waren oder ihren Platz geändert haben; was schon richtig war, bleibt sichtbar. Ist der Fehler größer, kommt nur sein Kern in die Lücke (das Verb, die Präposition), der Rest steht korrigiert im Satz. Bei Wortstellungsfehlern nennt der Hinweis zusätzlich die Wörter der Lücke in der Grundform, alphabetisch: {{c1::Was heißt::what does … mean · heißen, was · W-Frage: Verb an Position 2}}.
            Spalte 2 (Back Extra): Original: <mein Originalsatz><br>Tipp: (1) <Erklärung zu c1> (3) <Erklärung zu c3> – auf \(learn). Einfache, klare Begründung in ganzen Sätzen, nur für Lücken, bei denen der Hinweis in der Cloze nicht reicht; die Nummer ist die der Lücke. Braucht keine Lücke einen Tipp, entfällt „<br>Tipp: …“.
            Spalte 3 (Satz): derselbe korrigierte Satz ohne Cloze-Markierungen.
            Spalte 4 (Tags): Fehlerkategorien aus dieser Liste, mit Leerzeichen getrennt: Wortstellung Kasus Modalverb Passiv Reflexiv FalscherFreund Wortschatz Ausdruck TrennbaresVerb Rechtschreibung Verbform – plus das heutige Datum: \(today).

            Regeln:
            - Höchstens 2 Clozes pro Satz: nur die Fehler, bei denen ich am meisten lerne (Grammatik, Wortschatz, Ausdruck). Alle anderen Fehler korrigierst du im Satz, aber ohne Cloze.
            - Nie eine Cloze für Kleinigkeiten: Groß- und Kleinschreibung, Tippfehler, ein vergessenes kleines Wort wie „und“.
            - Ausnahme: Artikel (der/die/das, ein/eine), Adjektivendungen, Deklination und Umlaute (ä, ö, ü) korrigierst du im Satz, aber ohne Cloze.
            - Ein Satz = eine Zeile. Mehrere Korrekturen im selben Satz = c1, c2, c3 in derselben Zeile.
            - Prüfe deine Korrekturen vor der Antwort noch einmal auf Rechtschreibung.

            Mein Text:

            """
        }
        return """
        Correct my text below (language: \(learn)). Then output every correction as an Anki line, tab-separated, without a header row, in a code block.

        Column 1 (Text): the corrected sentence. Every correction is a cloze: {{c1::correct form::meaning in \(mine) · grammar rule}}. The cloze is as small as possible, 3 words at most: only the words that were wrong or moved; what was already right stays visible. If the mistake is bigger, only its core goes into the gap (the verb, the preposition); the rest stands corrected in the sentence. For word-order mistakes the hint also lists the words of the gap in their base form, alphabetically: {{c1::Was heißt::what does … mean · heißen, was · W-question: verb in position 2}}.
        Column 2 (Back Extra): Original: <my original sentence><br>Tip: (1) <explanation for c1> (3) <explanation for c3> – in \(learn). A simple, clear reason in full sentences, only for gaps whose cloze hint isn't enough; the number is the gap's. If no gap needs a tip, leave out "<br>Tip: …".
        Column 3 (Sentence): the same corrected sentence without cloze markup.
        Column 4 (Tags): error categories from this list, separated by spaces: WordOrder Case ModalVerb Passive Reflexive FalseFriend Vocabulary Expression SeparableVerb Spelling VerbForm – plus today's date: \(today).

        Rules:
        - At most 2 clozes per sentence: only the mistakes I learn the most from (grammar, vocabulary, expressions). Correct all other mistakes in the sentence, but without a cloze.
        - Never a cloze for small things: capitalization, typos, a forgotten small word like "und".
        - Exception: articles, adjective endings, declension and umlauts (ä, ö, ü) are corrected in the sentence, but without a cloze.
        - One sentence = one line. Several corrections in the same sentence = c1, c2, c3 in the same line.
        - Check your corrections for spelling once more before answering.

        My text:

        """
    }
}

/// Main window: what you copy (left) and your writing corrections (right).
struct MainView: View {
    @ObservedObject var controller: AppController
    @AppStorage(L10n.key) private var appLanguage = L10n.language

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                PanelTitle(title: L("Kopieren → Anki"),
                           subtitle: L("Was du kopierst oder markierst, mit „+ Anki“ als Karte."))
                Divider()
                MenuView(controller: controller, embedded: true)
            }
            .frame(minWidth: 320, idealWidth: 380, maxWidth: 520)
            VStack(alignment: .leading, spacing: 0) {
                PanelTitle(title: L("Textkorrektur → Anki"),
                           subtitle: L("Jede Korrektur deines Textes wird eine Karte, bei der du die richtige Form eintippst."))
                Divider()
                CorrectionView(controller: controller, model: controller.corrections, anki: controller.anki)
            }
            .frame(minWidth: 460)
        }
        .frame(minHeight: 520)
        .id(appLanguage)
    }
}

struct PanelTitle: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title3.weight(.semibold))
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct CorrectionView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var model: CorrectionModel
    @ObservedObject var anki: AnkiService

    @AppStorage(Prefs.correctionDeckKey) private var deck = ""
    @AppStorage(Prefs.makeAudioKey) private var makeAudio = true
    @AppStorage(Prefs.sourceLangKey) private var sourceLang = "de"
    @ObservedObject private var copied = Flag()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("1. Prompt kopieren, deinen Text darunter einfügen und einer KI geben.\n2. Die Antwort der KI (den Codeblock) hier einfügen.\n3. Prüfen und an Anki senden."))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(CorrectionPrompt.text, forType: .string)
                    copied.flash()
                } label: {
                    Label(L("Prompt kopieren"), systemImage: "doc.on.doc")
                }
                if copied.on {
                    Text(L("✓ Kopiert")).foregroundStyle(.green).font(.callout)
                }
                Spacer()
                if !model.input.isEmpty {
                    Button(L("Leeren")) { model.input = "" }.controlSize(.small)
                }
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.input)
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                if model.input.isEmpty {
                    Text(L("Antwort der KI hier einfügen (⌘V)…"))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .allowsHitTesting(false)
                }
            }
            .padding(6)
            .frame(height: 130)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))

            if !model.problems.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(model.problems.prefix(4), id: \.line) { p in
                        Text(L("Zeile %d: %@", p.line, reason(p.reason)))
                    }
                    if model.problems.count > 4 {
                        Text(L("… und %d weitere", model.problems.count - 4))
                    }
                }
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if model.rows.isEmpty {
                Spacer()
            } else {
                Text(L("%d Sätze · %d Karten", model.rowsToSend.count,
                       Prefs.correctionMode == "sentence" ? model.rowsToSend.count : model.cardCount))
                    .font(.headline)
                Text(L("Klick auf eine Lücke: keine Karte dafür (noch mal klicken: wieder an)."))
                    .font(.caption).foregroundStyle(.secondary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.rows.enumerated()), id: \.offset) { index, row in
                            CorrectionRowView(row: row, off: model.off[index] ?? []) { gap in
                                model.toggle(row: index, gap: gap)
                            }
                            Divider()
                        }
                    }
                }
            }

            Divider()
            HStack(spacing: 10) {
                TextField(L("Deck"), text: $deck, prompt: Text(Prefs.defaultCorrectionDeck))
                    .frame(maxWidth: 220)
                    .help(L("Deck für die Korrekturkarten"))
                Toggle(L("Audio"), isOn: $makeAudio)
                Spacer()
                if let progress = model.progress {
                    ProgressView().controlSize(.small)
                    Text(progress).font(.caption).foregroundStyle(.secondary)
                } else if let result = model.result {
                    Text(result).font(.caption).foregroundStyle(.secondary)
                }
                Button(L("An Anki senden")) {
                    Task { await model.send(with: controller) }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(model.rowsToSend.isEmpty || model.progress != nil)
            }
            if !anki.isUp, !model.rows.isEmpty {
                Text(L("Anki ist nicht geöffnet: Die Karten warten in der Warteschlange, bis Anki läuft."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .id(sourceLang)
    }

    private func reason(_ reason: Corrections.Reason) -> String {
        switch reason {
        case .missingColumns: return L("keine Tabulatoren – füge den Codeblock der KI unverändert ein")
        case .noGap: return L("keine Lücke {{c1::…}}")
        case .brokenGap: return L("Lücke nicht geschlossen ({{ ohne }})")
        }
    }
}

/// A short-lived "copied" mark. An object because @State's macro plugin is
/// missing from the Command Line Tools.
@MainActor
final class Flag: ObservableObject {
    @Published private(set) var on = false

    func flash() {
        on = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            on = false
        }
    }
}

/// One sentence in the preview: the gaps in color with their hints, then
/// the back (original and tip) and the tags.
struct CorrectionRowView: View {
    let row: CorrectionRow
    /// Switched-off gap numbers: shown struck through.
    var off: Set<Int> = []
    var toggle: (Int) -> Void = { _ in }

    private var cardCount: Int { row.withoutGaps(off).cardCount }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                // Each gap is a link: clicking it switches its card off or on.
                Text(sentence).font(.system(size: 13))
                    .environment(\.openURL, OpenURLAction { url in
                        if url.scheme == "clipout-gap", let n = Int(url.host() ?? "") { toggle(n) }
                        return .handled
                    })
                Spacer(minLength: 6)
                Text(cardCount == 1 ? L("1 Karte") : L("%d Karten", cardCount))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if !row.backExtra.isEmpty {
                Text(back).font(.caption).foregroundStyle(.secondary)
            }
            if !row.tags.isEmpty {
                Text(row.tags.joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sentence: AttributedString {
        var result = AttributedString()
        var rest = row.text[...]
        while let match = rest.firstMatch(of: #/\{\{c(\d+)::(.*?)(?:::(.*?))?\}\}/#) {
            result += AttributedString(String(rest[..<match.range.lowerBound]))
            let number = Int(match.1) ?? 1
            let isOff = off.contains(number)
            var gap = AttributedString(String(match.2))
            gap.foregroundColor = isOff ? .secondary : .accentColor
            gap.font = .system(size: 13, weight: isOff ? .regular : .semibold)
            gap.strikethroughStyle = isOff ? .single : nil
            gap.link = URL(string: "clipout-gap://\(number)")
            result += gap
            if let hint = match.3, !isOff {
                var h = AttributedString(" [\(hint)]")
                h.foregroundColor = .secondary
                h.font = .system(size: 11)
                result += h
            }
            rest = rest[match.range.upperBound...]
        }
        result += AttributedString(String(rest))
        return result
    }

    /// "Original: …<br>Tipp: …" as plain lines.
    private var back: String {
        row.backExtra
            .replacing(#/(?i)<br\s*\/?>/#, with: "\n")
            .replacing(#/<[^>]+>/#, with: "")
    }
}
