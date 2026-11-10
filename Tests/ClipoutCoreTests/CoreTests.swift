import Foundation
import Testing
@testable import ClipoutCore

@Test func cleanJoinsLinesFromWebPagesAndPDFs() {
    #expect(Sentence.clean("  Also wird das\nnoch   was\r\nmit mir? ") == "Also wird das noch was mit mir?")
}

@Test func tokensRoundTripAndKeepCompoundWords() {
    let s = "Ost-West: geht's gut?"
    let tokens = Sentence.tokens(s)
    #expect(tokens.map(\.text).joined() == s)
    #expect(tokens.filter(\.isWord).map(\.text) == ["Ost-West", "geht's", "gut"])
}

@Test func clozeHidesOnlyTheChosenWords() {
    let s = "Der Trabi war laut."
    let trabi = Sentence.tokens(s).firstIndex { $0.text == "Trabi" }!
    #expect(Sentence.clozeHTML(s, hidden: [trabi]) == "Der {{c1::Trabi}} war laut.")
}

@Test func clozeIgnoresIndicesOfSpacesAndPunctuation() {
    #expect(Sentence.clozeHTML("Ja, gut.", hidden: [1, 3]) == "Ja, gut.")
}

@Test func basicNoteHasSentenceTranslationAudioAndSource() {
    let draft = CardDraft(sentence: "Das ist <neu>", translation: "That is new",
                          sourceURL: "https://zdf.de/a?b=1&c=2", sourceTitle: "ZDF",
                          audioFile: "clipout-1.m4a")
    let note = CardModels.note(for: draft, deck: "Clipout")
    #expect(note.modelName == CardModels.basic)
    #expect(note.deckName == "Clipout")
    #expect(note.fields["Satz"] == "Das ist &lt;neu&gt;")
    #expect(note.fields["Übersetzung"] == "That is new")
    #expect(note.fields["Audio"] == "[sound:clipout-1.m4a]")
    #expect(note.fields["Quelle"] == "<a href=\"https://zdf.de/a?b=1&amp;c=2\">ZDF</a>")
    #expect(note.fields["Text"] == nil)
    #expect(note.tags == ["clipout"])
    #expect(Set(note.fields.keys) == Set(CardModels.basicFields))
}

@Test func hiddenWordsMakeAClozeNote() {
    let s = "Der Trabi war laut."
    let trabi = Sentence.tokens(s).firstIndex { $0.text == "Trabi" }!
    let note = CardModels.note(for: CardDraft(sentence: s, hiddenWords: [trabi]), deck: "D")
    #expect(note.modelName == CardModels.cloze)
    #expect(note.fields["Text"] == "Der {{c1::Trabi}} war laut.")
    #expect(Set(note.fields.keys) == Set(CardModels.clozeFields))
}

@Test func translationAndAudioAreOnTheBackOnly() {
    // audio in front only inside the listening block
    for front in [CardModels.basicFront, CardModels.clozeFront] {
        let reading = front.replacingOccurrences(of: #"\{\{#Hören\}\}.*?\{\{/Hören\}\}"#,
                                                 with: "", options: .regularExpression)
        #expect(!front.contains("{{Übersetzung}}") && !reading.contains("{{Audio}}"))
    }
    for back in [CardModels.basicBack, CardModels.clozeBack] {
        #expect(back.contains("{{Übersetzung}}") && back.contains("{{Audio}}"))
    }
}

@Test func sourceWithoutURLIsPlainText() {
    let note = CardModels.note(for: CardDraft(sentence: "x", sourceTitle: "Vorschau – Buch.pdf"), deck: "D")
    #expect(note.fields["Quelle"] == "Vorschau – Buch.pdf")
}

@Test func historyMovesRepeatedTextToTheTop() {
    let a = ClipItem(kind: .text, text: "eins")
    let b = ClipItem(kind: .text, text: "zwei")
    let again = ClipItem(kind: .text, text: " eins ")
    let (list, dropped) = History.inserting(again, into: [b, a], limit: 10)
    #expect(list.map(\.id) == [again.id, b.id])
    #expect(dropped.map(\.id) == [a.id])
}

@Test func historyRespectsTheLimit() {
    let old = (0..<3).map { ClipItem(kind: .text, text: "\($0)") }
    let new = ClipItem(kind: .image, imageFile: "x.png")
    let (list, dropped) = History.inserting(new, into: old, limit: 3)
    #expect(list.count == 3 && list.first == new)
    #expect(dropped == [old[2]])
}

@Test func passwordsAreNeverStored() {
    #expect(PasteboardRules.shouldIgnore(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"], appBundleID: nil))
    #expect(PasteboardRules.shouldIgnore(types: ["public.utf8-plain-text"], appBundleID: "com.apple.Passwords"))
    #expect(!PasteboardRules.shouldIgnore(types: ["public.utf8-plain-text"], appBundleID: "com.google.Chrome"))
}

@Test func requestEnvelopeMatchesAnkiConnect() throws {
    struct P: Encodable { let deck: String }
    let data = try JSONEncoder().encode(AnkiRequest(action: "createDeck", params: P(deck: "Clipout")))
    let object = try JSONSerialization.jsonObject(with: data)
    let json = try #require(object as? [String: Any])
    #expect(json["action"] as? String == "createDeck")
    #expect(json["version"] as? Int == 6)
    #expect((json["params"] as? [String: String])?["deck"] == "Clipout")
}

@Test func responsesAndErrorsDecode() throws {
    let ok = try JSONDecoder().decode(AnkiResponse<Int>.self, from: Data(#"{"result": 6, "error": null}"#.utf8))
    #expect(ok.result == 6 && ok.error == nil)
    let ignored = try JSONDecoder().decode(AnkiResponse<Ignored>.self, from: Data(#"{"result": {"a": [1]}, "error": null}"#.utf8))
    #expect(ignored.error == nil)
    #expect(AnkiError("cannot create note because it is a duplicate").isDuplicate)
    #expect(AnkiError("Close the affected editor before this API write").isEditorOpen)
}

// MARK: - Wiktionary

private let abstimmungen = #"""
{"de":[{"partOfSpeech":"Noun","language":"German","definitions":[{"definition":"<span class=\"form-of-definition use-with-mention\" about=\"#mwt4\" typeof=\"mw:Transclusion\"><a rel=\"mw:WikiLink\" href=\"/wiki/Appendix:Glossary#plural_number\" title=\"Appendix:Glossary\">plural</a> of <span class=\"form-of-definition-link\"><i class=\"Latn mention\" lang=\"de\"><a rel=\"mw:WikiLink\" href=\"/wiki/Abstimmung#German\" title=\"Abstimmung\">Abstimmung</a></i></span></span>"}]}]}
"""#

private let abstimmung = #"""
{"en":[{"partOfSpeech":"Noun","language":"English","definitions":[{"definition":"not this"}]}],
 "de":[{"partOfSpeech":"Noun","language":"German","definitions":[
   {"definition":"<a rel=\"mw:WikiLink\" href=\"/wiki/vote\" title=\"vote\">vote</a>"},
   {"definition":"<a href=\"/wiki/co-ordination\">co-ordination</a>, <a href=\"/wiki/agreement\">agreement</a> &amp; more"},
   {"definition":""},
   {"definition":"<a>vote</a>"},
   {"definition":"third"},{"definition":"fourth"}]}]}
"""#

@Test func inflectedFormPointsToItsLemma() throws {
    let parsed = try #require(Wiktionary.parse(Data(abstimmungen.utf8), language: "de"))
    #expect(parsed.definitions.isEmpty)
    #expect(parsed.lemma == "Abstimmung")
}

@Test func definitionsArePlainTextInTheStudiedLanguage() throws {
    let parsed = try #require(Wiktionary.parse(Data(abstimmung.utf8), language: "de"))
    #expect(parsed.definitions == ["vote", "co-ordination, agreement & more", "third"])
    #expect(parsed.lemma == nil)
    #expect(Wiktionary.parse(Data(abstimmung.utf8), language: "fr") == nil)
}

@Test func wiktionaryURLEncodesUmlautsAndSlashes() {
    #expect(Wiktionary.url(for: "schmälert")?.absoluteString
            == "https://en.wiktionary.org/api/rest_v1/page/definition/schm%C3%A4lert")
    #expect(Wiktionary.url(for: "a/b")?.absoluteString.hasSuffix("/a%2Fb") == true)
}

@Test func explanationsGoOnTheBackAsHTML() {
    let e = WordExplanation(word: "Abstimmungen", lemma: "Abstimmung", definitions: ["vote", "<agreement>"])
    #expect(e.html == "<b>Abstimmungen (Abstimmung)</b>: vote; &lt;agreement&gt;")
    let note = CardModels.note(for: CardDraft(sentence: "x", explanations: [e, WordExplanation(word: "keineswegs", definitions: ["in no way"])]), deck: "D")
    #expect(note.fields["Erklärung"] == e.html + "<br><b>keineswegs</b>: in no way")
    #expect(CardModels.basicBack.contains("{{Erklärung}}") && !CardModels.basicFront.contains("{{Erklärung}}"))
}

// MARK: - Listening cards

@Test func listeningCardHidesTheSentenceInFront() {
    let note = CardModels.note(for: CardDraft(sentence: "Hallo", audioFile: "a.m4a", listening: true), deck: "D")
    #expect(note.fields["Hören"] == "ja")
    #expect(CardModels.basicFront.contains("{{^Hören}}<div class=\"satz\">{{Satz}}</div>{{/Hören}}"))
    #expect(CardModels.basicFront.contains("{{#Hören}}<div class=\"hint\">🎧 Hör zu</div>{{Audio}}{{/Hören}}"))
    #expect(CardModels.basicBack.contains("{{#Hören}}<div class=\"satz\">{{Satz}}</div>{{/Hören}}"))
}

@Test func listeningWithoutAudioFallsBackToReading() {
    // otherwise the front would be empty and Anki would refuse the note
    let note = CardModels.note(for: CardDraft(sentence: "Hallo", listening: true), deck: "D")
    #expect(note.fields["Hören"] == "")
}

@Test func everyFieldIsFilledForBothNoteTypes() {
    let basic = CardModels.note(for: CardDraft(sentence: "a"), deck: "D")
    let cloze = CardModels.note(for: CardDraft(sentence: "a b", hiddenWords: [0]), deck: "D")
    #expect(Set(basic.fields.keys) == Set(CardModels.basicFields))
    #expect(Set(cloze.fields.keys) == Set(CardModels.clozeFields))
}
