import AppKit
import ClipoutCore
import ServiceManagement
import SwiftUI
import Translation

/// The window under the menu bar icon: Anki status and clipboard history.
struct MenuView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var anki: AnkiService
    @ObservedObject var clips: ClipboardMonitor
    @ObservedObject var translator: Translator
    @AppStorage(L10n.key) private var appLanguage = L10n.language

    init(controller: AppController) {
        self.controller = controller
        anki = controller.anki
        clips = controller.clips
        translator = controller.translator
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            status.padding(12)
            if !controller.accessibilityTrusted {
                banner(L("Für das Symbol bei Markierungen braucht Clipout die Berechtigung „Bedienungshilfen“."),
                       button: L("Öffnen")) { SelectionReader.requestAccess() }
            }
            if !translator.isReady {
                banner(L("Übersetzung offline: Sprachpaket noch nicht geladen."), button: L("Einstellungen")) {
                    controller.openSettings()
                }
            }
            Divider()
            if clips.items.isEmpty {
                Text(L("Noch nichts kopiert. Kopiere Text oder ein Bild (⌘C) – es erscheint hier."))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(clips.items) { item in
                            ClipRow(item: item, controller: controller)
                            Divider()
                        }
                    }
                }
                .frame(height: 380)
            }
            Divider()
            footer.padding(10)
        }
        .frame(width: 380)
        .id(appLanguage)   // rebuild every text when the app language changes
    }

    private var status: some View {
        HStack(spacing: 8) {
            Circle().fill(anki.isUp ? Color.green : Color.red).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(anki.isUp ? L("Anki verbunden") : L("Anki ist nicht geöffnet")).font(.headline)
                if !anki.queue.isEmpty {
                    Text(L("%d Karte(n) in der Warteschlange", anki.queue.count))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = anki.lastError, !anki.queue.isEmpty {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if !anki.queue.isEmpty {
                Button(L("Erneut senden")) { anki.retry() }.controlSize(.small)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(L("Verlauf leeren")) { clips.clear() }
                .disabled(clips.items.isEmpty)
            Spacer()
            Button { controller.openSettings() } label: { Image(systemName: "gearshape") }
                .help(L("Einstellungen"))
            Button(L("Beenden")) { NSApp.terminate(nil) }
        }
        .controlSize(.small)
    }

    private func banner(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(text).font(.caption)
            Spacer()
            Button(button, action: action).controlSize(.small)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }
}

struct ClipRow: View {
    let item: ClipItem
    let controller: AppController

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            content
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                Button {
                    controller.openComposer(for: item)
                } label: {
                    Label("Anki", systemImage: "plus")
                }
                .controlSize(.small)
                .help(L("Karte daraus erstellen"))
                HStack(spacing: 6) {
                    Button { controller.clips.copyBack(item) } label: { Image(systemName: "doc.on.doc") }
                        .help(L("Wieder in die Zwischenablage"))
                    Button { controller.clips.remove(item) } label: { Image(systemName: "trash") }
                        .help(L("Aus dem Verlauf löschen"))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let text = item.text {
                Text(Sentence.clean(text)).lineLimit(3).font(.system(size: 13))
            } else if let image = controller.clips.image(item) {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 90, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            Text([item.appName, item.date.formatted(date: .omitted, time: .shortened)]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// State the settings and welcome windows keep. In an object because @State
/// is a macro whose plugin the Command Line Tools don't ship.
@MainActor
final class SettingsState: ObservableObject {
    @Published var download: TranslationSession.Configuration?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
}

/// Language pickers and the language pack status, shared by the settings
/// and the welcome window.
struct LanguageSection: View {
    @ObservedObject var translator: Translator
    @ObservedObject var state: SettingsState
    var compact = false

    @AppStorage(L10n.key) private var appLanguage = L10n.language
    @AppStorage(Prefs.sourceLangKey) private var sourceLang = "de"
    @AppStorage(Prefs.targetLangKey) private var targetLang = "en"

    var body: some View {
        Picker(L("App-Sprache"), selection: $appLanguage) {
            ForEach(L10n.available, id: \.code) { Text($0.name).tag($0.code) }
        }
        Picker(L("Ich lerne"), selection: $sourceLang) {
            ForEach(Prefs.languages, id: \.code) { Text(L10n.languageName($0.code)).tag($0.code) }
        }
        Picker(compact ? L("Meine Sprache (Übersetzung)") : L("Übersetzen nach"), selection: $targetLang) {
            ForEach(Prefs.languages, id: \.code) { Text(L10n.languageName($0.code)).tag($0.code) }
        }
        HStack {
            Text(status).foregroundStyle(translator.isReady ? .green : .secondary)
            Spacer()
            if !translator.isReady && translator.status == .supported {
                Button(L("Sprachpaket laden")) {
                    state.download = .init(source: Locale.Language(identifier: sourceLang),
                                           target: Locale.Language(identifier: targetLang))
                }
            }
        }
        .onChange(of: sourceLang) { Task { await translator.refresh() } }
        .onChange(of: targetLang) { Task { await translator.refresh() } }
        .translationTask(state.download) { session in
            try? await session.prepareTranslation()
            await translator.refresh()
        }
    }

    private var status: String {
        switch translator.status {
        case .installed: return L("Übersetzung bereit (offline) ✓")
        case .supported: return L("Sprachpaket muss einmal geladen werden")
        case .unsupported: return L("Dieses Sprachpaar wird nicht unterstützt")
        default: return L("Wird geprüft…")
        }
    }
}

struct SettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var translator: Translator
    @ObservedObject var patterns: PatternStore
    @ObservedObject private var state = SettingsState()

    @AppStorage(L10n.key) private var appLanguage = L10n.language
    @AppStorage(Prefs.deckKey) private var deck = "Clipout"
    @AppStorage(Prefs.sourceLangKey) private var sourceLang = "de"
    @AppStorage(Prefs.makeAudioKey) private var makeAudio = true
    @AppStorage(Prefs.listeningKey) private var listening = false
    @AppStorage(Prefs.dictionaryKey) private var dictionary = true
    @AppStorage(Prefs.voiceKey) private var voice = ""
    @AppStorage(Prefs.showIconKey) private var showIcon = true
    @AppStorage(Prefs.copyFallbackKey) private var copyFallback = true
    @AppStorage(Prefs.historyLimitKey) private var historyLimit = 200
    @AppStorage(Prefs.historyDaysKey) private var historyDays = 1
    @AppStorage(Prefs.pauseClipboardKey) private var pauseClipboard = false
    @AppStorage(Prefs.ankiPortKey) private var ankiPort = 8765

    init(controller: AppController) {
        self.controller = controller
        translator = controller.translator
        patterns = controller.patterns
    }

    var body: some View {
        Form {
            Section(L("Sprachen")) {
                LanguageSection(translator: translator, state: state)
                HStack {
                    Picker(L("Stimme"), selection: $voice) {
                        Text(L("Automatisch (beste)")).tag("")
                        ForEach(SpeechMaker.voices(for: sourceLang), id: \.identifier) { v in
                            Text(SpeechMaker.label(v)).tag(v.identifier)
                        }
                    }
                    Button {
                        VoicePreview.play(language: sourceLang)
                    } label: {
                        Image(systemName: "play.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(L("Probe hören"))
                }
                Button(L("Stimmen verwalten…")) { VoiceSettings.open() }
                Text(L("Bessere Stimmen: Bedienungshilfen → Gesprochene Inhalte → Systemstimme → Stimmen verwalten. Oder in den Systemeinstellungen nach „Stimme“ suchen."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Anki") {
                TextField(L("Deck"), text: $deck)
                TextField(L("AnkiConnect-Port"), value: $ankiPort, format: .number.grouping(.never))
                Toggle(L("Audio für jede Karte erzeugen"), isOn: $makeAudio)
                Toggle("🎧 " + L("Neue Karten als Hörkarten"), isOn: $listening)
            }
            Section(L("Wörterbuch")) {
                Toggle(L("Erklärungen aus dem Wiktionary (online, sendet nur das Wort)"), isOn: $dictionary)
                Text(L("Bei 1–3 Wörtern automatisch nachschlagen."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section(L("Markieren überall")) {
                Toggle(L("Symbol neben markiertem Text zeigen"), isOn: $showIcon)
                Toggle(L("Notfalls mit ⌘C lesen (für Apps, die die Markierung nicht freigeben)"), isOn: $copyFallback)
                Text(L("Tastenkürzel ⌥⌘A: Markierung sofort als Karte senden."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text(controller.accessibilityTrusted ? L("Bedienungshilfen: erlaubt ✓") : L("Bedienungshilfen: nicht erlaubt"))
                        .foregroundStyle(controller.accessibilityTrusted ? .green : .orange)
                    Spacer()
                    if !controller.accessibilityTrusted {
                        Button(L("Erlauben")) { SelectionReader.requestAccess() }
                    }
                }
            }
            Section(L("Zwischenablage")) {
                Toggle(L("Verlauf pausieren"), isOn: $pauseClipboard)
                Stepper(L("Höchstens %d Einträge", historyLimit), value: $historyLimit, in: 20...1000, step: 20)
                Picker(L("Automatisch löschen nach"), selection: $historyDays) {
                    Text(L("1 Tag")).tag(1)
                    Text(L("%d Tagen", 7)).tag(7)
                    Text(L("%d Tagen", 30)).tag(30)
                    Text(L("Nie")).tag(0)
                }
                Text(L("Der Verlauf ist verschlüsselt (Schlüssel im Schlüsselbund). Passwörter, API-Schlüssel, Tokens und Codes werden nie gespeichert. Alles bleibt auf diesem Mac."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            neverStore
            Section(L("System")) {
                Toggle(L("Beim Anmelden starten"), isOn: $state.launchAtLogin)
                    .onChange(of: state.launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            state.launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 560)
        .id(appLanguage)
        .onChange(of: appLanguage) { controller.updateSettingsTitle() }
    }
}

extension SettingsView {
    /// Built-in rules (locked) and the user's own patterns.
    var neverStore: some View {
        Section(L("Nie speichern")) {
            DisclosureGroup(L("Eingebaute Muster (%d)", SecretDetector.builtInRules.count
                              + SecretDetector.heuristicLabels.count + 1)) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SecretDetector.builtInRules.map(\.label) + SecretDetector.heuristicLabels
                            + ["Alles aus Passwort-Managern (Passwörter, 1Password, Bitwarden, Schlüsselbund)"],
                            id: \.self) { label in
                        Label(L(label), systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            ForEach(patterns.patterns, id: \.self) { pattern in
                // LabeledContent is how a grouped Form expects a row with a
                // trailing control; a plain HStack row swallowed the click.
                LabeledContent {
                    Button(role: .destructive) { patterns.remove(pattern) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help(L("Muster entfernen"))
                } label: {
                    Text(pattern).font(.system(.body, design: .monospaced))
                }
                .contextMenu {
                    Button(L("Muster entfernen"), role: .destructive) { patterns.remove(pattern) }
                }
            }
            HStack {
                // In a grouped Form a titled TextField turns the title into a
                // label and the field itself has no border: nobody saw where to type.
                TextField("", text: $patterns.draft, prompt: Text(L("Eigenes Muster, z. B. Kundennummer")))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    .onSubmit { patterns.add() }
                Button(L("Hinzufügen")) { patterns.add() }
                    .disabled(patterns.draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let error = patterns.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if let notice = patterns.notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
            Text(L("Text, der irgendwo vorkommt (Groß-/Kleinschreibung egal), oder /regulärer Ausdruck/. Passende Einträge werden sofort und endgültig aus dem Verlauf gelöscht. Deine Muster werden verschlüsselt gespeichert."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// First start: languages, Accessibility, Anki. Shown once.
struct WelcomeView: View {
    @ObservedObject var controller: AppController
    @ObservedObject var translator: Translator
    @ObservedObject var anki: AnkiService
    @ObservedObject private var state = SettingsState()
    let done: () -> Void

    @AppStorage(L10n.key) private var appLanguage = L10n.language

    init(controller: AppController, done: @escaping () -> Void) {
        self.controller = controller
        translator = controller.translator
        anki = controller.anki
        self.done = done
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                Text(L("Willkommen bei Clipout")).font(.title2).bold()
                Text(L("Markiere irgendwo einen Satz und mach mit einem Klick eine Anki-Karte daraus."))
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(.top, 20).padding(.horizontal, 24)

            Form {
                Section(L("Sprachen")) {
                    LanguageSection(translator: translator, state: state, compact: true)
                }
                Section {
                    step(done: controller.accessibilityTrusted, title: L("Bedienungshilfen erlauben"),
                         detail: L("Damit Clipout markierten Text in anderen Apps lesen kann."),
                         button: L("Erlauben")) { SelectionReader.requestAccess() }
                    step(done: anki.isUp, title: L("Anki mit AnkiConnect"),
                         detail: anki.isUp ? L("Verbunden ✓") : L("Anki öffnen. AnkiConnect-Add-on: Code 2055492159."),
                         button: nil) {}
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button(L("Los geht's"), action: done).keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 500, height: 600)
        .id(appLanguage)
    }

    private func step(done: Bool, title: String, detail: String, button: String?,
                      action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).bold()
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let button, !done {
                Button(button, action: action)
            }
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var anki: AnkiService

    var body: some View {
        Image(systemName: anki.isUp ? "rectangle.and.text.magnifyingglass" : "rectangle.dashed")
    }
}
