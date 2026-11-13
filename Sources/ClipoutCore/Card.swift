import Foundation

/// What the user is about to send: filled in by the composer or the hotkey.
public struct CardDraft: Codable, Equatable, Sendable {
    public var sentence: String
    public var translation: String
    /// Token indices (see `Sentence.tokens`) to hide. Empty means a plain card.
    public var hiddenWords: Set<Int>
    public var sourceURL: String
    public var sourceTitle: String
    public var audioFile: String?
    public var imageFile: String?
    public var explanations: [WordExplanation]
    /// Listening card: the front plays the audio instead of showing the sentence.
    public var listening: Bool

    public init(sentence: String, translation: String = "", hiddenWords: Set<Int> = [],
                sourceURL: String = "", sourceTitle: String = "",
                audioFile: String? = nil, imageFile: String? = nil,
                explanations: [WordExplanation] = [], listening: Bool = false) {
        self.sentence = sentence
        self.translation = translation
        self.hiddenWords = hiddenWords
        self.sourceURL = sourceURL
        self.sourceTitle = sourceTitle
        self.audioFile = audioFile
        self.imageFile = imageFile
        self.explanations = explanations
        self.listening = listening
    }

    public var isCloze: Bool { !hiddenWords.isEmpty }
}

/// The note shape AnkiConnect's addNote expects.
public struct AnkiNote: Codable, Equatable, Sendable {
    public struct Options: Codable, Equatable, Sendable {
        public var allowDuplicate = false
        public var duplicateScope = "deck"
    }

    public var deckName: String
    public var modelName: String
    public var fields: [String: String]
    public var options = Options()
    public var tags: [String]

    /// The note with a media file name replaced, for when Anki stores the
    /// file under another name than the one asked for.
    public func renamingMedia(_ old: String, to new: String) -> AnkiNote {
        var note = self
        note.fields = fields.mapValues { $0.replacingOccurrences(of: old, with: new) }
        return note
    }
}

/// The two note types Clipout creates in Anki. Field names are English so
/// they make sense whatever language you learn: "Sentence" holds text in the
/// language you learn (the target language), "Translation" your language.
/// Reading card: sentence in front; translation, audio, meanings and source
/// on the back. Listening card (field "Listening" filled): only audio in front.
public enum CardModels {
    public static let basic = "Clipout"
    public static let cloze = "Clipout Cloze"
    /// Name used by 0.1.x; Anki can't rename note types over AnkiConnect,
    /// so an existing one keeps being used.
    public static let legacyCloze = "Clipout Lücke"
    public static let basicFields = ["Sentence", "Translation", "Audio", "Image", "Source", "Meaning", "Listening"]
    public static let clozeFields = ["Text", "Translation", "Audio", "Image", "Source", "Meaning", "Listening"]
    /// 0.1.x field name → current one, for renaming fields of existing note types.
    public static let legacyFieldNames = [
        "Satz": "Sentence", "Übersetzung": "Translation", "Bild": "Image",
        "Quelle": "Source", "Erklärung": "Meaning", "Hören": "Listening",
    ]

    public static let css = """
    .card { font-family: -apple-system, "Helvetica Neue", sans-serif; font-size: 24px;
      line-height: 1.4; text-align: center; color: #222; background: #fdfdfd; padding: 0 12px; }
    .nightMode.card, .night_mode .card { color: #eee; background: #1e1e1e; }
    .sentence { font-size: 26px; }
    .cloze { font-weight: 700; color: #2f6fd6; }
    .hint { font-size: 30px; margin-bottom: 8px; }
    .translation { color: #666; font-size: 20px; margin: 12px 0; }
    .nightMode .translation, .night_mode .translation { color: #aaa; }
    .meaning { color: #777; font-size: 16px; text-align: left; max-width: 640px; margin: 12px auto 0; }
    .source { color: #999; font-size: 13px; margin-top: 14px; }
    .source a { color: inherit; }
    img { max-width: 90%; border-radius: 8px; margin-top: 10px; }
    """

    private static let backExtras = """
    <div class="translation">{{Translation}}</div>
    {{^Listening}}{{Audio}}{{/Listening}}
    {{#Meaning}}<div class="meaning">{{Meaning}}</div>{{/Meaning}}
    {{#Source}}<div class="source">{{Source}}</div>{{/Source}}
    """

    public static let basicFront = """
    {{#Listening}}<div class="hint">🎧</div>{{Audio}}{{/Listening}}
    {{^Listening}}<div class="sentence">{{Sentence}}</div>{{/Listening}}
    {{#Image}}<div>{{Image}}</div>{{/Image}}
    """
    public static let basicBack = """
    {{FrontSide}}
    <hr id=answer>
    {{#Listening}}<div class="sentence">{{Sentence}}</div>{{/Listening}}
    """ + "\n" + backExtras

    public static let clozeFront = """
    <div class="sentence">{{cloze:Text}}</div>
    {{#Listening}}{{Audio}}{{/Listening}}
    {{#Image}}<div>{{Image}}</div>{{/Image}}
    """
    public static let clozeBack = """
    <div class="sentence">{{cloze:Text}}</div>
    {{#Listening}}{{Audio}}{{/Listening}}
    {{#Image}}<div>{{Image}}</div>{{/Image}}
    <hr id=answer>
    """ + "\n" + backExtras

    static func isWebLink(_ url: String) -> Bool {
        guard let scheme = URL(string: url)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// `clozeModel`: the cloze note type in use (see `legacyCloze`).
    public static func note(for draft: CardDraft, deck: String, clozeModel: String = cloze) -> AnkiNote {
        let sentence = Sentence.clean(draft.sentence)
        let source: String
        // Anki runs card HTML with JavaScript, so only web links become links;
        // a "javascript:" URL typed into the source field stays plain text.
        if !isWebLink(draft.sourceURL) {
            source = HTML.escape([draft.sourceTitle, draft.sourceURL]
                .filter { !$0.isEmpty }.joined(separator: " – "))
        } else {
            let label = draft.sourceTitle.isEmpty ? draft.sourceURL : draft.sourceTitle
            source = "<a href=\"\(HTML.escape(draft.sourceURL))\">\(HTML.escape(label))</a>"
        }
        // A listening card without audio would have an empty front.
        let listening = draft.listening && draft.audioFile != nil
        var fields = [
            "Translation": HTML.escape(draft.translation),
            "Audio": draft.audioFile.map { "[sound:\($0)]" } ?? "",
            "Image": draft.imageFile.map { "<img src=\"\(HTML.escape($0))\">" } ?? "",
            "Source": source,
            "Meaning": draft.explanations.map(\.html).joined(separator: "<br>"),
            "Listening": listening ? "yes" : "",
        ]
        if draft.isCloze {
            fields["Text"] = Sentence.clozeHTML(sentence, hidden: draft.hiddenWords)
        } else {
            fields["Sentence"] = HTML.escape(sentence)
        }
        return AnkiNote(deckName: deck, modelName: draft.isCloze ? clozeModel : basic,
                        fields: fields, tags: ["clipout"])
    }
}

extension AnkiNote {
    /// A note queued by 0.1.x (German field names) in today's shape.
    public func migrated(clozeModel: String) -> AnkiNote {
        var note = self
        note.fields = Dictionary(uniqueKeysWithValues: fields.map { key, value in
            (CardModels.legacyFieldNames[key] ?? key, key == "Hören" && !value.isEmpty ? "yes" : value)
        })
        if note.modelName == CardModels.legacyCloze || note.modelName == CardModels.cloze {
            note.modelName = clozeModel
        }
        return note
    }
}
