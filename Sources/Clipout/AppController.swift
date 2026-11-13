import AppKit
import ClipoutCore
import SwiftUI

/// Wires the pieces together: selection → icon → composer → Anki.
@MainActor
final class AppController: ObservableObject {
    static let shared = AppController()

    let anki = AnkiService()
    let clips = ClipboardMonitor()
    let translator = Translator()
    let speech = SpeechMaker()
    let dictionary = DictionaryLookup()
    let patterns = PatternStore()
    private let watcher = SelectionWatcher()
    private var hotKey: HotKey?

    @Published private(set) var accessibilityTrusted = SelectionReader.isTrusted

    private var icon: FloatingPanel?
    private var iconHideTask: Task<Void, Never>?
    private var pendingText: String?
    private var pendingApp: NSRunningApplication?
    private var toast: FloatingPanel?
    private var windows: [NSWindow] = []
    private var settingsWindow: NSWindow?
    private var welcomeWindow: NSWindow?
    private static let welcomedKey = "welcomed"

    func start() {
        Prefs.registerDefaults()
        Paths.ensure()
        anki.start()
        patterns.start(clips: clips)
        clips.start()
        Task { await translator.refresh() }

        watcher.onSelection = { [weak self] point, text, app in self?.showIcon(at: point, text: text, app: app) }
        watcher.onMouseDown = { [weak self] point in
            guard let self, let icon = self.icon, icon.isVisible, !icon.frame.contains(point) else { return }
            self.hideIcon()
        }
        watcher.start()
        hotKey = HotKey { [weak self] in Task { await self?.quickSend() } }
        if !UserDefaults.standard.bool(forKey: Self.welcomedKey) { openWelcome() }

        // The permission can be granted while the app runs.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            Task { @MainActor in
                let trusted = SelectionReader.isTrusted
                if trusted != AppController.shared.accessibilityTrusted {
                    AppController.shared.accessibilityTrusted = trusted
                }
            }
        }
    }

    // MARK: - Icon next to a selection

    private func showIcon(at point: NSPoint, text: String?, app: NSRunningApplication?) {
        pendingText = text
        pendingApp = app
        if icon == nil {
            icon = FloatingPanel(size: NSSize(width: 84, height: 34),
                                 content: SelectionIcon { [weak self] in
                                     Task { await self?.iconClicked() }
                                 })
        }
        icon?.show(near: point)
        iconHideTask?.cancel()
        iconHideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { hideIcon() }
        }
    }

    private func hideIcon() {
        iconHideTask?.cancel()
        icon?.orderOut(nil)
    }

    private func iconClicked() async {
        hideIcon()
        let app = pendingApp
        var text = pendingText
        if text == nil {
            text = await SelectionReader.copySelection(using: clips)
        }
        guard let text else {
            showToast(L("Keine Markierung gefunden"))
            return
        }
        openComposer(text: text, source: SourceDetector.detect(app))
    }

    // MARK: - ⌥⌘A: send the selection without the composer

    private func quickSend() async {
        guard SelectionReader.isTrusted else {
            SelectionReader.askForPermission()
            return
        }
        let app = NSWorkspace.shared.frontmostApplication
        SelectionReader.wakeAccessibility(of: app)
        var text = SelectionReader.selectedText()
        if text == nil { text = await SelectionReader.copySelection(using: clips) }
        guard let text else {
            showToast(L("Nichts markiert"))
            return
        }
        let source = SourceDetector.detect(app)
        showToast(L("Wird übersetzt…"))
        let sentence = Sentence.clean(text)
        let translation = await translator.translate(sentence) ?? ""
        var explanations: [WordExplanation] = []
        let words = Sentence.tokens(sentence).filter(\.isWord).map(\.text)
        if Prefs.dictionary && words.count <= 3 {
            for word in words {
                if let found = await dictionary.explain(word) { explanations.append(found) }
            }
        }
        let draft = CardDraft(sentence: sentence, translation: translation,
                              sourceURL: source.url, sourceTitle: source.title,
                              explanations: explanations, listening: Prefs.listening)
        let outcome = await send(draft, image: nil, audio: Prefs.makeAudio || Prefs.listening)
        showToast(outcome.message)
    }

    // MARK: - Cards

    /// `temporaryImage`: a decrypted copy that is deleted when the window closes.
    func openComposer(text: String, source: (url: String, title: String), imageURL: URL? = nil,
                      temporaryImage: Bool = false) {
        let model = ComposerModel(text: text, source: source, imageURL: imageURL)
        var window: NSWindow?
        let view = ComposerView(model: model, controller: self) { window?.close() }
        window = makeWindow(title: L("Neue Karte"), size: NSSize(width: 540, height: 600), content: view)
        windows.append(window!)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                               queue: .main) { [weak self] note in
            Task { @MainActor in self?.windows.removeAll { $0 === note.object as? NSWindow } }
            if temporaryImage, let imageURL { try? FileManager.default.removeItem(at: imageURL) }
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func openComposer(for item: ClipItem) {
        let source = (url: "", title: item.appName ?? "")
        if let text = item.text {
            openComposer(text: text, source: source)
        } else if let url = clips.temporaryImageFile(item) {
            openComposer(text: "", source: source, imageURL: url, temporaryImage: true)
        }
    }

    /// Adds audio and image files, then hands the note to the queue.
    func send(_ draft: CardDraft, image: URL?, audio: Bool) async -> SendOutcome {
        var draft = draft
        var media: [String] = []
        if audio {
            // Lowercase: the name Anki will store it under anyway.
            let name = "clipout-\(UUID().uuidString.lowercased()).\(Prefs.audioExtension)"
            if await speech.makeAudio(Sentence.clean(draft.sentence), language: Prefs.sourceLang,
                                      to: Paths.media.appendingPathComponent(name)) {
                draft.audioFile = name
                media.append(name)
            }
        }
        if let image {
            let name = "clipout-\(UUID().uuidString.lowercased()).png"
            if (try? FileManager.default.copyItem(at: image, to: Paths.media.appendingPathComponent(name))) != nil {
                draft.imageFile = name
                media.append(name)
            }
        }
        return await anki.send(CardModels.note(for: draft, deck: Prefs.deck, clozeModel: anki.clozeModel),
                               media: media)
    }

    // MARK: - Windows and messages

    func openSettings() {
        if settingsWindow == nil {
            settingsWindow = makeWindow(title: L("Clipout – Einstellungen"), size: NSSize(width: 500, height: 640),
                                        content: SettingsView(controller: self))
        }
        updateSettingsTitle()
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func updateSettingsTitle() {
        settingsWindow?.title = L("Clipout – Einstellungen")
    }

    func openWelcome() {
        if welcomeWindow == nil {
            welcomeWindow = makeWindow(title: "Clipout", size: NSSize(width: 500, height: 600),
                                       content: WelcomeView(controller: self) { [weak self] in
                                           UserDefaults.standard.set(true, forKey: Self.welcomedKey)
                                           self?.welcomeWindow?.close()
                                       })
            welcomeWindow?.styleMask.remove(.resizable)
        }
        NSApp.activate()
        welcomeWindow?.makeKeyAndOrderFront(nil)
    }

    func showToast(_ text: String) {
        toast?.orderOut(nil)
        let panel = FloatingPanel(size: NSSize(width: 360, height: 44), content: ToastView(text: text))
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 360, height: 44))
        toast = panel
        panel.show(near: NSEvent.mouseLocation, offset: NSPoint(x: 12, y: -50))
        Task {
            try? await Task.sleep(for: .seconds(2.2))
            if toast === panel { panel.orderOut(nil) }
        }
    }
}
