import Foundation

/// A word and its meanings, for the back of the card.
public struct WordExplanation: Codable, Equatable, Sendable {
    /// The word as it appeared in the sentence.
    public var word: String
    /// The dictionary form, when it differs ("Abstimmungen" → "Abstimmung").
    public var lemma: String?
    public var definitions: [String]

    public init(word: String, lemma: String? = nil, definitions: [String]) {
        self.word = word
        self.lemma = lemma
        self.definitions = definitions
    }

    /// "Abstimmungen (Abstimmung): vote; co-ordination", as card HTML.
    public var html: String {
        let head = lemma.map { "\(HTML.escape(word)) (\(HTML.escape($0)))" } ?? HTML.escape(word)
        return "<b>\(head)</b>: " + definitions.map(HTML.escape).joined(separator: "; ")
    }
}

/// Reads the English Wiktionary REST API
/// (en.wiktionary.org/api/rest_v1/page/definition/<word>).
public enum Wiktionary {
    public struct Parsed: Equatable {
        public var definitions: [String]
        /// Set when the entry is only an inflected form ("plural of Abstimmung").
        public var lemma: String?
    }

    private struct Entry: Decodable {
        struct Definition: Decodable {
            let definition: String
        }
        let partOfSpeech: String?
        let definitions: [Definition]
    }

    public static func url(for word: String) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove("/")
        guard let path = word.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://en.wiktionary.org/api/rest_v1/page/definition/\(path)")
    }

    /// Meanings in `language` (e.g. "de"). Inflected forms carry no meaning of
    /// their own, only a link to the lemma, which the caller then looks up.
    public static func parse(_ data: Data, language: String, limit: Int = 3) -> Parsed? {
        guard let all = try? JSONDecoder().decode([String: [Entry]].self, from: data),
              let entries = all[language] else { return nil }
        var definitions: [String] = []
        var lemma: String?
        for entry in entries {
            for item in entry.definitions {
                let raw = item.definition
                if raw.contains("form-of-definition") {
                    if lemma == nil { lemma = lemmaLink(in: raw) }
                    continue
                }
                let text = plainText(raw)
                if !text.isEmpty && !definitions.contains(text) {
                    definitions.append(text)
                }
            }
        }
        if definitions.isEmpty && lemma == nil { return nil }
        return Parsed(definitions: Array(definitions.prefix(limit)), lemma: lemma)
    }

    static func lemmaLink(in html: String) -> String? {
        let pattern = #"form-of-definition-link.*?<a [^>]*title="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return decodeEntities(String(html[range]))
    }

    static func plainText(_ html: String) -> String {
        let noTags = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeEntities(noTags)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
