import Foundation

/// One corrected sentence from a writing correction, as an AI returns it:
/// one tab-separated line per sentence, one cloze per correction.
///
///     Text ⇥ Back Extra ⇥ Sentence ⇥ Tags
///     {{c1::In dieser Sendung geht es::…}} um Heiko. ⇥ Original: …<br>Tipp: … ⇥ In dieser … ⇥ Ausdruck 2026-11-22
public struct CorrectionRow: Equatable, Sendable {
    /// The corrected sentence with {{c1::answer::hint}} gaps.
    public var text: String
    /// Your original sentence and the tip, shown on the back.
    public var backExtra: String
    /// The corrected sentence without gaps: read aloud for the audio.
    public var sentence: String
    public var tags: [String]

    /// Each cloze number becomes its own card in Anki.
    public var cardCount: Int { Set(Corrections.gaps(in: text).map(\.number)).count }

    /// The row with these gaps switched off: they stay corrected in the
    /// sentence but get no card, and their numbered tips ("(3) …") go too.
    public func withoutGaps(_ off: Set<Int>) -> CorrectionRow {
        guard !off.isEmpty else { return self }
        var row = self
        row.text = text.replacing(Corrections.gapPattern) { m in
            off.contains(Int(m.1) ?? 1) ? String(m.2) : String(m.0)
        }
        row.backExtra = Corrections.droppingTips(off, from: backExtra)
        return row
    }
}

public enum Corrections {
    public struct Gap: Equatable, Sendable {
        public var number: Int
        public var answer: String
        public var hint: String?
    }

    /// A line that couldn't be read, with its number in the pasted text.
    public struct Problem: Equatable, Sendable {
        public var line: Int
        public var reason: Reason
        public var text: String
    }

    public enum Reason: Equatable, Sendable {
        /// Fewer than three tab-separated columns; copying often turns tabs into spaces.
        case missingColumns
        /// No {{c1::…}} in the first column.
        case noGap
        /// {{ and }} don't pair up.
        case brokenGap
    }

    static let gapPattern = #/\{\{c(\d+)::(.*?)(?:::(.*?))?\}\}/#

    public static func gaps(in text: String) -> [Gap] {
        text.matches(of: gapPattern).map { m in
            Gap(number: Int(m.1) ?? 1, answer: String(m.2), hint: m.3.map(String.init))
        }
    }

    /// The sentence with every gap filled in.
    public static func plain(_ text: String) -> String {
        text.replacing(gapPattern) { String($0.2) }
    }

    /// Reads what the AI returned. Lines starting with # (Anki's import
    /// header) and ``` (the code block around the rows) are skipped.
    public static func parse(_ input: String) -> (rows: [CorrectionRow], problems: [Problem]) {
        var rows: [CorrectionRow] = []
        var problems: [Problem] = []
        for (index, raw) in input.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("```") else { continue }
            let columns = raw.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }
            func problem(_ reason: Reason) { problems.append(Problem(line: index + 1, reason: reason, text: line)) }
            guard columns.count >= 2 else { problem(.missingColumns); continue }
            let text = columns[0]
            guard text.components(separatedBy: "{{").count == text.components(separatedBy: "}}").count else {
                problem(.brokenGap); continue
            }
            guard !gaps(in: text).isEmpty else { problem(.noGap); continue }
            let sentence = columns.count > 2 && !columns[2].isEmpty ? columns[2] : plain(text)
            let tags = columns.count > 3 ? columns[3].split(whereSeparator: \.isWhitespace).map(String.init) : []
            rows.append(CorrectionRow(text: text, backExtra: columns[1], sentence: sentence, tags: tags))
        }
        return (rows, problems)
    }

    /// The note for one row. Anki runs card HTML with JavaScript, so
    /// everything is escaped; only line breaks and bold/italic/underline
    /// from the back stay HTML.
    public static func note(for row: CorrectionRow, deck: String, audioFile: String?) -> AnkiNote {
        AnkiNote(deckName: deck, modelName: CardModels.correction,
                 fields: [
                     "Text": HTML.escape(row.text),
                     "Back Extra": highlightingTip(keepingSimpleTags(HTML.escape(row.backExtra))),
                     "Sentence": HTML.escape(row.sentence),
                     "Audio": audioFile.map { "[sound:\($0)]" } ?? "",
                 ],
                 tags: ["clipout"] + row.tags)
    }

    /// The whole-sentence card for a gap note (its fields as stored in Anki):
    /// your original, what to look out for, the sentence with blanks of one
    /// length (no hints, nothing given away), and you type the whole sentence.
    /// It shares the gap note's audio, deck and tags.
    public static func sentenceNote(from gapNote: AnkiNote) -> AnkiNote {
        let text = gapNote.fields["Text"] ?? ""
        let back = gapNote.fields["Back Extra"] ?? ""
        let withoutSpan = back.replacing(#/<span class="tip">|<\/span>/#, with: "")
        let tipStart = withoutSpan.firstMatch(of: #/(?i)\b(tipp?|tip):/#)?.range.lowerBound
        let tip = numberedOnLines(tipStart.map { String(withoutSpan[$0...]) } ?? "")
        let original = String(withoutSpan[..<(tipStart ?? withoutSpan.endIndex)])
            .replacing(#/^\s*Original:\s*/#, with: "")
            .replacing(#/(\s|<br>)+$/#, with: "")
        let sentence = gapNote.fields["Sentence"] ?? plain(text)
        let points = checklist(gaps: gaps(in: text))
        return AnkiNote(deckName: gapNote.deckName, modelName: CardModels.correctionSentence,
                        fields: [
                            "Sentence": sentence,
                            "Original": original,
                            "Checklist": points.isEmpty ? "" : "<ol>" + points.map { "<li>\($0)</li>" }.joined() + "</ol>",
                            "Gaps": text.replacing(gapPattern) { _ in "_____" },
                            "Tip": tip,
                            "Audio": gapNote.fields["Audio"] ?? "",
                        ],
                        tags: gapNote.tags)
    }

    /// Removes the numbered tips of these gaps; without any left, the whole
    /// "<br>Tipp: …". Unnumbered tips belong to the sentence and stay.
    static func droppingTips(_ off: Set<Int>, from back: String) -> String {
        guard let label = back.firstMatch(of: #/(?i)(<br\s*\/?>)?\s*\b(tipp?|tip):\s*(?=\(\d+\))/#) else { return back }
        let body = back[label.range.upperBound...]
        let kept = body.matches(of: #/\((\d+)\)\s*(.*?)\s*(?=\(\d+\)|$)/#)
            .filter { !off.contains(Int($0.1) ?? 0) }
            .map { "(\($0.1)) \($0.2)" }
        let head = String(back[..<label.range.lowerBound])
        return kept.isEmpty ? head : head + label.output.0 + kept.joined(separator: " ")
    }

    /// "Tipp: (1) … (3) …" → each numbered tip on its own line, for the
    /// sentence card, which shows all of them. Unnumbered tips stay as they are.
    public static func numberedOnLines(_ tip: String) -> String {
        guard tip.firstMatch(of: #/(?i)^\s*(tipp?|tip):\s*\(\d+\)/#) != nil else { return tip }
        return tip.replacing(#/\s*(\(\d+\))\s*/#) { "<br>\($0.1) " }
    }

    /// What to look out for when correcting the whole sentence: the hint of
    /// each gap, word for word as on the gap cards, in the order of the blanks.
    public static func checklist(gaps: [Gap]) -> [String] {
        gaps.map { $0.hint?.trimmingCharacters(in: .whitespaces) ?? "" }.filter { !$0.isEmpty }
    }

    /// "Original: …<br>Tipp: …" → the tip in a span the card shows in red.
    public static func highlightingTip(_ html: String) -> String {
        guard !html.contains("class=\"tip\""),
              let start = html.firstMatch(of: #/(?i)\b(tipp?|tip):/#)?.range.lowerBound else { return html }
        return html[..<start] + "<span class=\"tip\">" + html[start...] + "</span>"
    }

    private static func keepingSimpleTags(_ escaped: String) -> String {
        escaped.replacing(#/(?i)&lt;(\/?)(br|b|i|u)\s*\/?&gt;/#) { "<\($0.1)\($0.2.lowercased())>" }
    }
}
