import Foundation

/// AnkiConnect's request envelope: {"action", "version": 6, "params"}.
public struct AnkiRequest<P: Encodable>: Encodable {
    public let action: String
    public let version = 6
    public let params: P

    public init(action: String, params: P) {
        self.action = action
        self.params = params
    }
}

public struct AnkiResponse<R: Decodable>: Decodable {
    public let result: R?
    public let error: String?
}

public struct NoParams: Codable, Sendable {
    public init() {}
}

/// Accepts any JSON value, for actions whose result we don't need.
public struct Ignored: Decodable, Sendable {
    public init(from decoder: Decoder) throws {}
}

public struct AnkiError: LocalizedError, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }

    public var isDuplicate: Bool { message.lowercased().contains("duplicate") }

    /// Anki refuses note-type writes while an editor window is open.
    public var isEditorOpen: Bool { message.lowercased().contains("close the affected editor") }

    /// What to show the user, in German.
    public var explanation: String {
        if isDuplicate { return "Diese Karte gibt es schon in Anki." }
        if isEditorOpen { return "In Anki ist ein Bearbeiten-Fenster offen. Schließ es, dann geht es weiter." }
        return message
    }
}

public struct CanAddResult: Decodable, Sendable {
    public let canAdd: Bool
    public let error: String?
}
