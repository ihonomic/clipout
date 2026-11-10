import AppKit
import ClipoutCore

/// macOS keeps no clipboard history, so Clipout records one: it checks the
/// pasteboard's change counter twice a second and stores new text and images.
///
/// Everything is encrypted on disk (Vault), secrets are never stored
/// (SecretDetector), and entries expire after `Prefs.historyDays`.
@MainActor
final class ClipboardMonitor: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    private let pasteboard = NSPasteboard.general
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?
    private var lastPrune = Date.distantPast
    private var thumbnails: [UUID: NSImage] = [:]
    /// Set while Clipout itself borrows the clipboard (see SelectionReader).
    var suspended = false

    func start() {
        items = SealedFile.load([ClipItem].self, from: Paths.history) ?? migrateLegacyHistory()
        prune()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in self.check() }
        }
    }

    /// Forget changes made so far, e.g. after restoring the user's clipboard.
    func skipCurrentChange() {
        lastChange = pasteboard.changeCount
    }

    /// The decrypted image of a history entry.
    func image(_ item: ClipItem) -> NSImage? {
        if let cached = thumbnails[item.id] { return cached }
        guard let data = imageData(item), let image = NSImage(data: data) else { return nil }
        thumbnails[item.id] = image
        return image
    }

    /// A plain copy of the image for the composer, deleted when it closes.
    func temporaryImageFile(_ item: ClipItem) -> URL? {
        guard let data = imageData(item) else { return nil }
        let url = Paths.media.appendingPathComponent("preview-\(UUID().uuidString).png")
        guard (try? data.write(to: url)) != nil else { return nil }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return url
    }

    /// Deletes text entries matching `predicate` for good. Returns how many.
    func removeEntries(where predicate: (ClipItem) -> Bool) -> Int {
        let before = items.count
        items.removeAll { $0.kind == .text && predicate($0) }
        let removed = before - items.count
        if removed > 0 { save() }
        return removed
    }

    private func customPatterns() -> [String] {
        AppController.shared.patterns.patterns
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
        } else if let image = image(item) {
            pasteboard.writeObjects([image])
        }
    }

    private func check() {
        if Date().timeIntervalSince(lastPrune) > 3600 { prune() }
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
            guard !SecretDetector.looksSecret(text, custom: customPatterns()) else { return }
            item = ClipItem(kind: .text, text: text, appName: app?.localizedName)
        } else if let png = Self.pngData(from: pasteboard), let sealed = Vault.seal(png) {
            let name = "\(UUID().uuidString).sealed"
            let url = Paths.clips.appendingPathComponent(name)
            if (try? sealed.write(to: url)) != nil {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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

    private func imageData(_ item: ClipItem) -> Data? {
        guard let name = item.imageFile,
              let sealed = try? Data(contentsOf: Paths.clips.appendingPathComponent(name)) else { return nil }
        return Vault.open(sealed)
    }

    private func prune() {
        lastPrune = Date()
        let (kept, dropped) = History.pruned(items, keepingDays: Prefs.historyDays)
        guard !dropped.isEmpty else { return }
        deleteFiles(dropped)
        items = kept
        save()
    }

    /// Clipout 0.1.0 stored the history and images unencrypted: encrypt them
    /// once, delete the plain files and drop secrets that slipped in.
    private func migrateLegacyHistory() -> [ClipItem] {
        guard let old = JSONFile.load([ClipItem].self, from: Paths.legacyHistory) else { return [] }
        // Without a key nothing can be encrypted: leave the old files alone.
        guard Vault.key != nil else { return old }
        var migrated: [ClipItem] = []
        for var item in old {
            if let text = item.text, SecretDetector.looksSecret(text) { continue }
            if let name = item.imageFile {
                let plain = Paths.clips.appendingPathComponent(name)
                let sealedName = (name as NSString).deletingPathExtension + ".sealed"
                let target = Paths.clips.appendingPathComponent(sealedName)
                if let data = try? Data(contentsOf: plain), let sealed = Vault.seal(data),
                   (try? sealed.write(to: target)) != nil {
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                    item.imageFile = sealedName
                    migrated.append(item)
                }
                try? FileManager.default.removeItem(at: plain)
                continue
            }
            migrated.append(item)
        }
        items = migrated
        save()
        try? FileManager.default.removeItem(at: Paths.legacyHistory)
        return migrated
    }

    private func deleteFiles(_ list: [ClipItem]) {
        for item in list {
            thumbnails[item.id] = nil
            if let name = item.imageFile {
                try? FileManager.default.removeItem(at: Paths.clips.appendingPathComponent(name))
            }
        }
    }

    private func save() {
        SealedFile.save(items, to: Paths.history)
    }
}
