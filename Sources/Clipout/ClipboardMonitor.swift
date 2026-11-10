import AppKit
import ClipoutCore

/// macOS keeps no clipboard history, so Clipout records one: it checks the
/// pasteboard's change counter twice a second and stores new text and images.
@MainActor
final class ClipboardMonitor: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    private let pasteboard = NSPasteboard.general
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?
    /// Set while Clipout itself borrows the clipboard (see SelectionReader).
    var suspended = false

    func start() {
        items = JSONFile.load([ClipItem].self, from: Paths.history) ?? []
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in self.check() }
        }
    }

    /// Forget changes made so far, e.g. after restoring the user's clipboard.
    func skipCurrentChange() {
        lastChange = pasteboard.changeCount
    }

    func imageURL(_ item: ClipItem) -> URL? {
        item.imageFile.map { Paths.clips.appendingPathComponent($0) }
    }

    func remove(_ item: ClipItem) {
        deleteFiles([item])
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        deleteFiles(items)
        items = []
        save()
    }

    /// Puts an old entry back on the clipboard (it then moves to the top).
    func copyBack(_ item: ClipItem) {
        pasteboard.clearContents()
        if let text = item.text {
            pasteboard.setString(text, forType: .string)
        } else if let url = imageURL(item), let image = NSImage(contentsOf: url) {
            pasteboard.writeObjects([image])
        }
    }

    private func check() {
        guard pasteboard.changeCount != lastChange else { return }
        lastChange = pasteboard.changeCount
        guard !suspended, !Prefs.pauseClipboard else { return }

        let app = NSWorkspace.shared.frontmostApplication
        let types = pasteboard.types?.map(\.rawValue) ?? []
        guard !PasteboardRules.shouldIgnore(types: types, appBundleID: app?.bundleIdentifier) else { return }
        // Copied files (Finder) are not something to learn from.
        guard !types.contains(NSPasteboard.PasteboardType.fileURL.rawValue) else { return }

        var item: ClipItem?
        if let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            item = ClipItem(kind: .text, text: text, appName: app?.localizedName)
        } else if let png = Self.pngData(from: pasteboard) {
            let name = "\(UUID().uuidString).png"
            if (try? png.write(to: Paths.clips.appendingPathComponent(name))) != nil {
                item = ClipItem(kind: .image, imageFile: name, appName: app?.localizedName)
            }
        }
        guard let item else { return }
        let (list, dropped) = History.inserting(item, into: items, limit: Prefs.historyLimit)
        deleteFiles(dropped)
        items = list
        save()
    }

    static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func deleteFiles(_ list: [ClipItem]) {
        for item in list {
            if let url = imageURL(item) { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func save() {
        JSONFile.save(items, to: Paths.history)
    }
}
