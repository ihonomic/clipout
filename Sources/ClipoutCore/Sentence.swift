import Foundation

/// A piece of a sentence: a word, or the spaces and punctuation between words.
/// Joining all tokens gives back the original sentence.
public struct Token: Equatable, Sendable {
    public let text: String
    public let isWord: Bool

    public init(text: String, isWord: Bool) {
        self.text = text
        self.isWord = isWord
    }
}

public enum Sentence {
    /// Text copied from web pages and PDFs is full of hard line breaks and
    /// double spaces; a card wants one clean line.
    public static func clean(_ raw: String) -> String {
        raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Words keep inner hyphens and apostrophes ("Ost-West", "geht's").
    public static func tokens(_ sentence: String) -> [Token] {
        var out: [Token] = []
        var current = ""
        var currentIsWord = false
        for ch in sentence {
            let joiner = ch == "-" || ch == "'" || ch == "’"
            let isWordChar = ch.isLetter || ch.isNumber || (joiner && currentIsWord && !current.isEmpty)
            if !current.isEmpty && isWordChar != currentIsWord {
                out.append(Token(text: current, isWord: currentIsWord))
                current = ""
            }
            currentIsWord = isWordChar
            current.append(ch)
        }
        if !current.isEmpty {
            out.append(Token(text: current, isWord: currentIsWord))
        }
        return out
    }

    /// HTML for the card field, with the chosen words as one cloze ({{c1::…}}).
    public static func clozeHTML(_ sentence: String, hidden: Set<Int>) -> String {
        tokens(sentence).enumerated().map { index, token in
            let text = HTML.escape(token.text)
            return token.isWord && hidden.contains(index) ? "{{c1::\(text)}}" : text
        }.joined()
    }
}

public enum HTML {
    public static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
