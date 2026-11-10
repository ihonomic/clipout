import ClipoutCore
import Foundation
import os

/// The user's own "never store" patterns. Encrypted like the history: a
/// pattern can itself be private (part of a password, a customer number).
/// Adding and removing are final; there is no undo.
@MainActor
final class PatternStore: ObservableObject {
    /// Counts only, never the patterns: they can be private.
    private let log = Logger(subsystem: "com.ihonomic.clipout", category: "patterns")

    @Published private(set) var patterns: [String] = []
    /// Confirmation after adding, e.g. how many history entries went.
    @Published private(set) var notice: String?
    @Published var draft = ""
    @Published var error: String?

    private let url = Paths.root.appendingPathComponent("patterns.sealed")
    private weak var clips: ClipboardMonitor?

    func start(clips: ClipboardMonitor) {
        self.clips = clips
        patterns = SealedFile.load([String].self, from: url) ?? []
    }

    func add() {
        let pattern = draft.trimmingCharacters(in: .whitespaces)
        if let problem = CustomPattern.problem(pattern) {
            error = L(problem)
            return
        }
        error = nil
        draft = ""
        guard !patterns.contains(pattern) else { return }
        patterns.append(pattern)
        save()
        // Entries already in the history go too, for good.
        let purged = clips?.removeEntries { $0.text.map { CustomPattern.matches($0, pattern) } ?? false } ?? 0
        let added = L("„%@“ hinzugefügt", pattern)
        notice = purged == 0 ? added : added + " · " + L("%d Einträge aus dem Verlauf entfernt", purged)
        log.info("added pattern, now \(self.patterns.count), purged \(purged)")
    }

    func remove(_ pattern: String) {
        guard patterns.contains(pattern) else { return }
        patterns.removeAll { $0 == pattern }
        notice = nil
        save()
        log.info("removed pattern, now \(self.patterns.count)")
    }

    private func save() {
        SealedFile.save(patterns, to: url)
    }
}
