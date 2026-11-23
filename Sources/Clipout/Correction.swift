import AppKit
import ClipoutCore
import SwiftUI

/// The writing-correction side of the main window: an AI corrects your text
/// and returns one line per sentence (see `CorrectionPrompt`); pasted here,
/// every correction becomes a card where you type the right form.
@MainActor
final class CorrectionModel: ObservableObject {
    @Published var input = "" {
        didSet { (rows, problems) = Corrections.parse(input) }
    }
    @Published private(set) var rows: [CorrectionRow] = []
    @Published private(set) var problems: [Corrections.Problem] = []
    /// While sending: "Audio 3 of 12…".
    @Published private(set) var progress: String?
    @Published private(set) var result: String?

    var cardCount: Int { rows.map(\.cardCount).reduce(0, +) }

    func send(with controller: AppController) async {
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
            notes.append((Corrections.note(for: row, deck: deck, audioFile: audio), audio.map { [$0] } ?? []))
        }
        progress = L("Wird an Anki gesendet…")
        let outcomes = await controller.anki.send(notes)
        progress = nil
        var sent = 0, duplicates = 0, queued = 0
        for outcome in outcomes {
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

            Spalte 1 (Text): der korrigierte Satz. Jede Korrektur ist eine Cloze: {{c1::korrekte Form::Bedeutung auf \(mine) · Grammatikregel}}. Bei Wortstellungsfehlern umfasst die Cloze den ganzen Satzteil, nicht nur das Verb.
            Spalte 2 (Back Extra): Original: <mein Originalsatz><br>Tipp: <kurze Erklärung auf \(learn)>
            Spalte 3 (Satz): derselbe korrigierte Satz ohne Cloze-Markierungen.
            Spalte 4 (Tags): Fehlerkategorien aus dieser Liste, mit Leerzeichen getrennt: Wortstellung Kasus Modalverb Passiv Reflexiv FalscherFreund Wortschatz Ausdruck TrennbaresVerb Rechtschreibung Verbform – plus das heutige Datum: \(today).

            Regeln:
            - Jede Korrektur bekommt eine eigene Cloze, auch wenn sich ein Fehler wiederholt.
            - Ausnahme: Artikel (der/die/das, ein/eine), Adjektivendungen und Umlaute (ä, ö, ü) korrigierst du im Satz, aber ohne Cloze.
            - Ein Satz = eine Zeile. Mehrere Korrekturen im selben Satz = c1, c2, c3 in derselben Zeile.
            - Prüfe deine Korrekturen vor der Antwort noch einmal auf Rechtschreibung.

            Mein Text:

            """
        }
        return """
        Correct my text below (language: \(learn)). Then output every correction as an Anki line, tab-separated, without a header row, in a code block.

        Column 1 (Text): the corrected sentence. Every correction is a cloze: {{c1::correct form::meaning in \(mine) · grammar rule}}. For word-order mistakes the cloze covers the whole phrase, not just the verb.
        Column 2 (Back Extra): Original: <my original sentence><br>Tip: <short explanation in \(learn)>
        Column 3 (Sentence): the same corrected sentence without cloze markup.
        Column 4 (Tags): error categories from this list, separated by spaces: WordOrder Case ModalVerb Passive Reflexive FalseFriend Vocabulary Expression SeparableVerb Spelling VerbForm – plus today's date: \(today).

        Rules:
        - Every correction gets its own cloze, even if a mistake repeats.
        - Exception: articles, adjective endings and umlauts (ä, ö, ü) are corrected in the sentence, but without a cloze.
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
                Text(L("%d Sätze · %d Karten", model.rows.count, model.cardCount))
                    .font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                            CorrectionRowView(row: row)
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
                .disabled(model.rows.isEmpty || model.progress != nil)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(sentence).font(.system(size: 13))
                Spacer(minLength: 6)
                Text(row.cardCount == 1 ? L("1 Karte") : L("%d Karten", row.cardCount))
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
        while let match = rest.firstMatch(of: #/\{\{c\d+::(.*?)(?:::(.*?))?\}\}/#) {
            result += AttributedString(String(rest[..<match.range.lowerBound]))
            var gap = AttributedString(String(match.1))
            gap.foregroundColor = .accentColor
            gap.font = .system(size: 13, weight: .semibold)
            result += gap
            if let hint = match.2 {
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
