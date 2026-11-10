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
}

/// The two note types Clipout creates in Anki. Reading card: German sentence
/// in front; translation, audio, explanations and source on the back.
/// Listening card (field "Hören" filled): only the audio in front.
public enum CardModels {
    public static let basic = "Clipout"
    public static let cloze = "Clipout Lücke"
    public static let basicFields = ["Satz", "Übersetzung", "Audio", "Bild", "Quelle", "Erklärung", "Hören"]
    public static let clozeFields = ["Text", "Übersetzung", "Audio", "Bild", "Quelle", "Erklärung", "Hören"]

    public static let css = """
    .card { font-family: -apple-system, "Helvetica Neue", sans-serif; font-size: 24px;
      line-height: 1.4; text-align: center; color: #222; background: #fdfdfd; padding: 0 12px; }
    .nightMode.card, .night_mode .card { color: #eee; background: #1e1e1e; }
    .satz { font-size: 26px; }
    .cloze { font-weight: 700; color: #2f6fd6; }
    .hint { color: #888; font-size: 18px; margin-bottom: 8px; }
    .ue { color: #666; font-size: 20px; margin: 12px 0; }
    .nightMode .ue, .night_mode .ue { color: #aaa; }
    .def { color: #777; font-size: 16px; text-align: left; max-width: 640px; margin: 12px auto 0; }
    .def b { color: inherit; }
    .quelle { color: #999; font-size: 13px; margin-top: 14px; }
    .quelle a { color: inherit; }
    img { max-width: 90%; border-radius: 8px; margin-top: 10px; }
    """

    private static let backExtras = """
    <div class="ue">{{Übersetzung}}</div>
    {{^Hören}}{{Audio}}{{/Hören}}
    {{#Erklärung}}<div class="def">{{Erklärung}}</div>{{/Erklärung}}
    {{#Quelle}}<div class="quelle">{{Quelle}}</div>{{/Quelle}}
    """

    public static let basicFront = """
    {{#Hören}}<div class="hint">🎧 Hör zu</div>{{Audio}}{{/Hören}}
    {{^Hören}}<div class="satz">{{Satz}}</div>{{/Hören}}
    {{#Bild}}<div>{{Bild}}</div>{{/Bild}}
    """
    public static let basicBack = """
    {{FrontSide}}
    <hr id=answer>
    {{#Hören}}<div class="satz">{{Satz}}</div>{{/Hören}}
    """ + "\n" + backExtras

    public static let clozeFront = """
    <div class="satz">{{cloze:Text}}</div>
    {{#Hören}}{{Audio}}{{/Hören}}
    {{#Bild}}<div>{{Bild}}</div>{{/Bild}}
    """
    public static let clozeBack = """
    <div class="satz">{{cloze:Text}}</div>
    {{#Hören}}{{Audio}}{{/Hören}}
    {{#Bild}}<div>{{Bild}}</div>{{/Bild}}
    <hr id=answer>
    """ + "\n" + backExtras

    public static func note(for draft: CardDraft, deck: String) -> AnkiNote {
        let sentence = Sentence.clean(draft.sentence)
        let source: String
        if draft.sourceURL.isEmpty {
            source = HTML.escape(draft.sourceTitle)
        } else {
            let label = draft.sourceTitle.isEmpty ? draft.sourceURL : draft.sourceTitle
            source = "<a href=\"\(HTML.escape(draft.sourceURL))\">\(HTML.escape(label))</a>"
        }
        // A listening card without audio would have an empty front.
        let listening = draft.listening && draft.audioFile != nil
        var fields = [
            "Übersetzung": HTML.escape(draft.translation),
            "Audio": draft.audioFile.map { "[sound:\($0)]" } ?? "",
            "Bild": draft.imageFile.map { "<img src=\"\(HTML.escape($0))\">" } ?? "",
            "Quelle": source,
            "Erklärung": draft.explanations.map(\.html).joined(separator: "<br>"),
            "Hören": listening ? "ja" : "",
        ]
        if draft.isCloze {
            fields["Text"] = Sentence.clozeHTML(sentence, hidden: draft.hiddenWords)
        } else {
            fields["Satz"] = HTML.escape(sentence)
        }
        return AnkiNote(deckName: deck, modelName: draft.isCloze ? cloze : basic,
                        fields: fields, tags: ["clipout"])
    }
}
