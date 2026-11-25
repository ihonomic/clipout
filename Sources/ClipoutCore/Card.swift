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

    public init(deckName: String, modelName: String, fields: [String: String], tags: [String]) {
        self.deckName = deckName
        self.modelName = modelName
        self.fields = fields
        self.tags = tags
    }

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
    /// Writing corrections: a typed answer per gap (see Corrections).
    public static let correction = "Clipout Correction"
    /// The same corrections as one card per sentence; Settings decides which
    /// of the two is active (the other one is suspended in Anki).
    public static let correctionSentence = "Clipout Correction Sentence"
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

    /// Writing corrections. "Back Extra" holds your original and the tip,
    /// "Sentence" the corrected sentence the audio reads. You type each gap:
    /// recalling the right form is the point, so the original stays on the back.
    public static let correctionFields = ["Text", "Back Extra", "Sentence", "Audio"]
    public static let correctionCSS = css + """

    .extra { color: #666; font-size: 17px; text-align: left; max-width: 640px; margin: 14px auto 0;
      font-style: italic; }
    .nightMode .extra, .night_mode .extra { color: #aaa; }
    #typeans { font-size: 22px; }
    /* Your original in italics above, the tip upright below a line. */
    .tip { display: block; color: #2e7d32; font-style: normal; border-top: 1px solid #ddd;
      margin-top: 8px; padding-top: 8px; }
    .nightMode .tip, .night_mode .tip { color: #81c784; border-top-color: #444; }
    /* Words of your original that the correction changed. */
    .wrong { color: #c62828; }
    .nightMode .wrong, .night_mode .wrong { color: #ff7a7a; }
    /* The front's hint, kept on the back under the revealed answer. */
    .gap-hint { color: #888; font-size: 16px; margin: 4px auto 0; max-width: 640px; }
    """
    public static let correctionSentenceFields = ["Sentence", "Original", "Checklist", "Gaps", "Tip", "Audio"]
    public static let correctionSentenceCSS = css + """

    .task { font-size: 15px; color: #888; }
    .original { font-size: 17px; font-style: italic; color: #777; max-width: 640px; margin: 4px auto 0; }
    .checklist { text-align: left; max-width: 640px; margin: 10px auto 0; font-size: 16px; color: #555; }
    .checklist ul { margin: 4px 0 0; padding-left: 22px; }
    .gaps { font-size: 22px; margin: 14px auto 6px; max-width: 640px; }
    .tip { color: #2e7d32; font-size: 16px; text-align: left; max-width: 640px; margin: 10px auto 0; }
    .nightMode .original, .night_mode .original, .nightMode .checklist, .night_mode .checklist { color: #aaa; }
    .nightMode .tip, .night_mode .tip { color: #81c784; }
    /* Anki's typing box is one line: small type so a whole sentence fits. */
    #typeans { font-size: 14px; width: 100%; box-sizing: border-box; }
    """
    /// `task` and `lookFor` are UI text in the app language.
    public static func correctionSentenceFront(task: String, lookFor: String) -> String {
        """
        <div class="task">\(task)</div>
        <div class="original">{{Original}}</div>
        <hr>
        {{#Checklist}}<div class="checklist">\(lookFor){{Checklist}}</div>{{/Checklist}}
        <div class="gaps">{{Gaps}}</div>
        {{type:Sentence}}
        """
    }
    public static let correctionSentenceBack = """
    <div class="sentence">{{Sentence}}</div>
    {{type:Sentence}}
    <hr id=answer>
    {{#Tip}}<div class="tip">{{Tip}}</div>{{/Tip}}
    {{Audio}}
    """

    public static let correctionFront = """
    <div class="sentence">{{cloze:Text}}</div>
    {{type:cloze:Text}}
    """
    public static let correctionBack = """
    <div class="sentence">{{cloze:Text}}</div>
    <div class="gap-hint" id="clipout-hint" hidden></div>
    {{type:cloze:Text}}
    <hr id=answer>
    {{#Back Extra}}<div class="extra">{{Back Extra}}</div>{{/Back Extra}}
    {{Audio}}
    <div id="clipout-gaps" hidden>{{Text}}</div>
    <div id="clipout-sentence" hidden>{{Sentence}}</div>
    <script>
    \(tipForGapScript)
    \(markOriginalScript)
    (function () {
      var extra = document.querySelector('.extra');
      var fixed = document.getElementById('clipout-sentence');
      if (!extra || !fixed) return;
      var tip = extra.querySelector('.tip');
      var head = document.createElement('div');
      var node = extra.firstChild;
      while (node && node !== tip) { var next = node.nextSibling; head.appendChild(node); node = next; }
      var text = head.textContent.replace(/^\\s*Original:\\s*/i, '');
      var marked = document.createElement('span');
      marked.innerHTML = 'Original: ' + clipoutMarkOriginal(text, fixed.textContent) + (tip ? '<br>' : '');
      extra.insertBefore(marked, tip);
    })();
    (function () {
      var active = document.querySelector('.cloze[data-ordinal]');
      var tip = document.querySelector('.extra .tip');
      var raw = document.getElementById('clipout-gaps');
      var hintBox = document.getElementById('clipout-hint');
      if (active && raw && hintBox) {
        var hint = clipoutHintForGap(active.getAttribute('data-ordinal'), raw.textContent);
        if (hint) { hintBox.textContent = hint; hintBox.hidden = false; }
      }
      if (!active || !tip || !raw) return;
      var picked = clipoutTipForGap(tip.innerHTML, active.getAttribute('data-ordinal'), raw.textContent);
      if (picked === null) tip.remove(); else tip.innerHTML = picked;
    })();
    </script>
    """

    /// Each gap card shows only the tip for its own gap. The AI numbers the
    /// tips after the gaps: "Tipp: (1) … (3) …"; a gap without a number gets
    /// none (it needed no explanation). Older rows have one tip for the whole
    /// sentence: with one gap it stays, with several each card shows the rule
    /// from its own gap's hint ("meaning · rule") instead. Returns the tip's
    /// new HTML, or null to hide it. Pure, so it can be tested on its own.
    /// Your original with the words the correction changed in red: word
    /// diff (longest common subsequence) against the corrected sentence,
    /// ignoring case and punctuation. Returns escaped HTML. Pure.
    public static let markOriginalScript = """
    function clipoutMarkOriginal(original, fixed) {
      function norm(w) { return w.toLowerCase().replace(/[^\\p{L}\\p{N}]/gu, ''); }
      function esc(t) { return t.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
      var a = original.trim().split(/\\s+/), b = fixed.trim().split(/\\s+/).map(norm);
      var n = a.length, m = b.length, an = a.map(norm), L = [], i, j;
      for (i = 0; i <= n; i++) { L.push(new Array(m + 1).fill(0)); }
      for (i = n - 1; i >= 0; i--) for (j = m - 1; j >= 0; j--)
        L[i][j] = an[i] && an[i] === b[j] ? L[i + 1][j + 1] + 1 : Math.max(L[i + 1][j], L[i][j + 1]);
      var out = [];
      for (i = 0, j = 0; i < n;) {
        if (j < m && an[i] && an[i] === b[j]) { out.push(esc(a[i])); i++; j++; }
        else if (j < m && L[i][j + 1] >= L[i + 1][j]) { j++; }
        else { out.push(an[i] ? '<span class="wrong">' + esc(a[i]) + '</span>' : esc(a[i])); i++; }
      }
      return out.join(' ');
    }
    """

    public static let tipForGapScript = """
    function clipoutHintForGap(n, rawText) {
      var m, re = /\\{\\{c(\\d+)::(.*?)(?:::(.*?))?\\}\\}/g;
      while ((m = re.exec(rawText))) {
        if (m[1] === String(n) && m[3]) return m[3].trim();
      }
      return '';
    }
    function clipoutTipForGap(tipHTML, n, rawText) {
      var label = (tipHTML.match(/^\\s*(Tipp?|Tip):\\s*/i) || [''])[0];
      var body = tipHTML.slice(label.length);
      if (/^\\(\\d+\\)/.test(body)) {
        var parts = body.split(/\\s*\\((\\d+)\\)\\s*/);
        for (var i = 1; i < parts.length; i += 2) {
          if (parts[i] === String(n)) return label + parts[i + 1].trim();
        }
        return null;
      }
      var gaps = {}, hint = null, m, re = /\\{\\{c(\\d+)::(.*?)(?:::(.*?))?\\}\\}/g;
      while ((m = re.exec(rawText))) {
        gaps[m[1]] = true;
        if (m[1] === String(n) && hint === null) hint = m[3] || '';
      }
      if (Object.keys(gaps).length <= 1) return tipHTML;
      var rule = (hint || '').split('\u{00B7}').slice(1).join('\u{00B7}').trim();
      if (!rule) return null;
      var esc = rule.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      return (label || 'Tipp: ') + esc;
    }
    """

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
