import AppKit
import ClipoutCore
import SwiftUI

/// State of one "Neue Karte" window.
@MainActor
final class ComposerModel: ObservableObject {
    enum TapMode: Hashable {
        case cloze, explain
    }

    @Published var sentence: String {
        didSet { if Sentence.tokens(sentence) != tokens { tokens = Sentence.tokens(sentence); hidden = [] } }
    }
    @Published var translation = ""
    @Published var hidden: Set<Int> = []
    @Published var explanations: [WordExplanation] = []
    @Published var lookingUp: Set<String> = []
    @Published var tapMode: TapMode = .cloze
    @Published var listening = Prefs.listening
    @Published var sourceURL: String
    @Published var sourceTitle: String
    @Published var makeAudio = Prefs.makeAudio
    @Published var busy: String?
    @Published var result: String?
    @Published private(set) var tokens: [Token]
    let imageURL: URL?

    init(text: String, source: (url: String, title: String), imageURL: URL? = nil) {
        let clean = Sentence.clean(text)
        sentence = clean
        tokens = Sentence.tokens(clean)
        sourceURL = source.url
        sourceTitle = source.title
        self.imageURL = imageURL
        if Prefs.dictionary && tokens.filter(\.isWord).count <= 3 { tapMode = .explain }
    }

    var draft: CardDraft {
        CardDraft(sentence: sentence, translation: translation, hiddenWords: hidden,
                  sourceURL: sourceURL, sourceTitle: sourceTitle,
                  explanations: explanations, listening: listening)
    }

    func prepare(controller: AppController) async {
        if sentence.isEmpty, let imageURL {
            busy = L("Text im Bild wird erkannt…")
            sentence = Sentence.clean(await TextRecognizer.text(in: imageURL, language: Prefs.sourceLang))
        }
        // A word or short phrase: its meaning matters more than a translation.
        let words = tokens.filter(\.isWord).map(\.text)
        if Prefs.dictionary && words.count <= 3 {
            for word in words { Task { await explain(word, controller: controller) } }
        }
        await translate(controller: controller)
    }

    func translate(controller: AppController) async {
        guard !sentence.isEmpty else { busy = nil; return }
        busy = L("Wird übersetzt…")
        if let text = await controller.translator.translate(Sentence.clean(sentence)) {
            translation = text
        } else if translation.isEmpty {
            result = L("Übersetzung nicht verfügbar: Sprachpaket in den Einstellungen laden.")
        }
        busy = nil
    }

    func tap(_ index: Int, controller: AppController) {
        switch tapMode {
        case .cloze:
            if hidden.contains(index) { hidden.remove(index) } else { hidden.insert(index) }
        case .explain:
            let word = tokens[index].text
            if let i = explanations.firstIndex(where: { $0.word == word }) {
                explanations.remove(at: i)
            } else {
                Task { await explain(word, controller: controller) }
            }
        }
    }

    func isMarked(_ index: Int) -> Bool {
        switch tapMode {
        case .cloze: return hidden.contains(index)
        case .explain: return explanations.contains { $0.word == tokens[index].text }
        }
    }

    private func explain(_ word: String, controller: AppController) async {
        guard !lookingUp.contains(word), !explanations.contains(where: { $0.word == word }) else { return }
        lookingUp.insert(word)
        defer { lookingUp.remove(word) }
        if let found = await controller.dictionary.explain(word) {
            explanations.append(found)
        } else {
            result = L("Nichts gefunden: %@", word)
        }
    }
}

struct ComposerView: View {
    @ObservedObject var model: ComposerModel
    let controller: AppController
    let close: () -> Void
    @AppStorage(L10n.key) private var appLanguage = L10n.language

    var body: some View {
        // Reading the setting makes SwiftUI redraw on a language change; no
        // .id() here, it would restart the translation.
        let _ = appLanguage
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let url = model.imageURL, let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                section(L("Satz (Vorderseite)")) {
                    editor($model.sentence, size: 15, minHeight: 56)
                }

                HStack {
                    Picker(L("Karte"), selection: $model.listening) {
                        Text(L("Lesen")).tag(false)
                        Text("🎧 " + L("Hören")).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    Spacer()
                }
                if model.listening {
                    Text(L("Hören: vorne nur Audio, Satz und Übersetzung hinten."))
                        .font(.caption).foregroundStyle(.secondary)
                }

                if model.tokens.contains(where: \.isWord) { wordChips }

                if !model.explanations.isEmpty || !model.lookingUp.isEmpty {
                    section(L("Erklärungen (Rückseite)")) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(model.explanations, id: \.word) { e in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(e.lemma.map { "\(e.word) (\($0))" } ?? e.word).bold()
                                        Text(e.definitions.joined(separator: "; "))
                                            .foregroundStyle(.secondary)
                                    }
                                    .font(.system(size: 13))
                                    Spacer()
                                    Button { model.explanations.removeAll { $0.word == e.word } } label: {
                                        Image(systemName: "xmark.circle.fill")
                                    }
                                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                                }
                            }
                            if !model.lookingUp.isEmpty {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    Text(L("Wird nachgeschlagen…")).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                section(L("Übersetzung (Rückseite)")) {
                    HStack(alignment: .top) {
                        editor($model.translation, size: 14, minHeight: 40)
                        Button {
                            Task { await model.translate(controller: controller) }
                        } label: { Image(systemName: "arrow.clockwise") }
                            .help(L("Neu übersetzen"))
                    }
                }

                section(L("Quelle")) {
                    TextField(L("Titel"), text: $model.sourceTitle)
                    TextField("URL", text: $model.sourceURL)
                }

                Toggle(L("Audio erzeugen (Systemstimme)"), isOn: $model.makeAudio)

                footer
            }
            .padding(16)
        }
        .frame(minWidth: 480, minHeight: 440)
        .task { await model.prepare(controller: controller) }
    }

    private var wordChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            if Prefs.dictionary {
                HStack {
                    Text(L("Wort antippen für")).font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $model.tapMode) {
                        Text(L("Lückentext")).tag(ComposerModel.TapMode.cloze)
                        Text(L("Erklärung")).tag(ComposerModel.TapMode.explain)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            Text(model.tapMode == .cloze ? L("Lückentext: Wörter antippen, die verdeckt werden sollen")
                                         : L("Erklärung: Wörter antippen, um sie nachzuschlagen (Wiktionary)"))
                .font(.caption).foregroundStyle(.secondary)
            FlowLayout(spacing: 5) {
                ForEach(Array(model.tokens.enumerated()), id: \.offset) { index, token in
                    if token.isWord {
                        let on = model.isMarked(index)
                        let tint = model.tapMode == .cloze ? Color.accentColor : Color.orange
                        Button(token.text) { model.tap(index, controller: controller) }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 5)
                                .fill(on ? tint : Color.secondary.opacity(0.15)))
                            .foregroundStyle(on ? Color.white : Color.primary)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if let busy = model.busy {
                ProgressView().controlSize(.small)
                Text(busy).foregroundStyle(.secondary)
            } else if let result = model.result {
                Text(result).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            Button(L("Abbrechen"), action: close)
                .keyboardShortcut(.cancelAction)
            Button(model.hidden.isEmpty ? L("An Anki senden") : L("Lückentext senden")) {
                Task {
                    model.busy = L("Wird gesendet…")
                    let outcome = await controller.send(model.draft, image: model.imageURL,
                                                        audio: model.makeAudio || model.listening)
                    model.busy = nil
                    model.result = outcome.message
                    if case .sent = outcome {
                        try? await Task.sleep(for: .milliseconds(700))
                        close()
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || model.busy != nil || !model.lookingUp.isEmpty)
        }
    }

    private func editor(_ text: Binding<String>, size: CGFloat, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.system(size: size))
            .frame(minHeight: minHeight)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
    }

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}

/// Wraps its children onto new lines, like words in a paragraph.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: min(width, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
