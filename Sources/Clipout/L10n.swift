import Foundation

/// App language. German texts are the keys; other languages map them.
/// (SwiftPM without Xcode makes .strings bundles awkward; a table is enough
/// for this many strings.)
enum L10n {
    static let key = "appLanguage"
    static let available: [(code: String, name: String)] = [("de", "Deutsch"), ("en", "English")]

    static var language: String {
        if let chosen = UserDefaults.standard.string(forKey: key) { return chosen }
        return Locale.preferredLanguages.first?.hasPrefix("de") == true ? "de" : "en"
    }

    /// "Deutsch"/"German" for a language code, in the app language.
    static func languageName(_ code: String) -> String {
        Locale(identifier: language).localizedString(forLanguageCode: code)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? code
    }

    static let english: [String: String] = [
        // menu
        "Anki verbunden": "Anki connected",
        "Anki ist nicht geöffnet": "Anki is not open",
        "Anki ist nicht geöffnet.": "Anki is not open.",
        "%d Karte(n) in der Warteschlange": "%d card(s) waiting",
        "Erneut senden": "Retry",
        "Verlauf leeren": "Clear history",
        "Einstellungen": "Settings",
        "Beenden": "Quit",
        "Öffnen": "Open",
        "Für das Symbol bei Markierungen braucht Clipout die Berechtigung „Bedienungshilfen“.":
            "Clipout needs the Accessibility permission to show its button next to selected text.",
        "Übersetzung offline: Sprachpaket noch nicht geladen.": "Offline translation: language pack not downloaded yet.",
        "Noch nichts kopiert. Kopiere Text oder ein Bild (⌘C) – es erscheint hier.":
            "Nothing copied yet. Copy text or an image (⌘C) and it shows up here.",
        "Karte daraus erstellen": "Make a card from this",
        "Wieder in die Zwischenablage": "Copy to clipboard again",
        "Aus dem Verlauf löschen": "Remove from history",
        // composer
        "Neue Karte": "New card",
        "Satz (Vorderseite)": "Sentence (front)",
        "Karte": "Card",
        "Lesen": "Reading",
        "Hören": "Listening",
        "Hören: vorne nur Audio, Satz und Übersetzung hinten.": "Listening: only audio in front, sentence and translation on the back.",
        "Wort antippen für": "Tap a word for",
        "Lückentext": "Cloze",
        "Erklärung": "Meaning",
        "Lückentext: Wörter antippen, die verdeckt werden sollen": "Cloze: tap the words to hide",
        "Erklärung: Wörter antippen, um sie nachzuschlagen (Wiktionary)": "Meaning: tap words to look them up (Wiktionary)",
        "Erklärungen (Rückseite)": "Meanings (back)",
        "Nichts gefunden: %@": "Nothing found: %@",
        "Wird nachgeschlagen…": "Looking up…",
        "Übersetzung (Rückseite)": "Translation (back)",
        "Neu übersetzen": "Translate again",
        "Quelle": "Source",
        "Titel": "Title",
        "Audio erzeugen (Systemstimme)": "Create audio (system voice)",
        "Abbrechen": "Cancel",
        "An Anki senden": "Send to Anki",
        "Lückentext senden": "Send cloze",
        "Text im Bild wird erkannt…": "Reading text in the image…",
        "Wird übersetzt…": "Translating…",
        "Wird gesendet…": "Sending…",
        "Übersetzung nicht verfügbar: Sprachpaket in den Einstellungen laden.":
            "Translation unavailable: download the language pack in Settings.",
        // outcomes and messages
        "✓ An Anki gesendet": "✓ Sent to Anki",
        "Diese Karte gibt es schon in Anki.": "This card is already in Anki.",
        "In der Warteschlange: %@": "Waiting: %@",
        "In Anki ist ein Bearbeiten-Fenster offen. Schließ es, dann geht es weiter.":
            "An edit window is open in Anki. Close it and sending continues.",
        "Anki antwortet nicht: %@": "Anki does not answer: %@",
        "Anki lehnt die Karte ab.": "Anki refused the card.",
        "Keine Markierung gefunden": "No selection found",
        "Nichts markiert": "Nothing selected",
        "Karte aus der Markierung erstellen (⌥⌘A)": "Make a card from the selection (⌥⌘A)",
        // settings
        "Clipout – Einstellungen": "Clipout Settings",
        "App-Sprache": "App language",
        "Deck": "Deck",
        "AnkiConnect-Port": "AnkiConnect port",
        "Audio für jede Karte erzeugen": "Create audio for every card",
        "Neue Karten als Hörkarten": "New cards are listening cards",
        "Sprachen": "Languages",
        "Ich lerne": "I'm learning",
        "Übersetzen nach": "Translate into",
        "Sprachpaket laden": "Download language pack",
        "Übersetzung bereit (offline) ✓": "Translation ready (offline) ✓",
        "Sprachpaket muss einmal geladen werden": "The language pack needs to be downloaded once",
        "Dieses Sprachpaar wird nicht unterstützt": "This language pair is not supported",
        "Wird geprüft…": "Checking…",
        "Stimme": "Voice",
        "Audioformat": "Audio format",
        "MP3 – läuft überall, auch auf AnkiWeb": "MP3 – plays everywhere, AnkiWeb included",
        "M4A (AAC) – nicht auf AnkiWeb": "M4A (AAC) – not on AnkiWeb",
        "Automatisch (beste)": "Automatic (best)",
        "Erweitert": "Enhanced",
        "Premium": "Premium",
        "Probe hören": "Listen to a sample",
        "Stimmen verwalten…": "Manage voices…",
        "Bessere Stimmen: Bedienungshilfen → Gesprochene Inhalte → Systemstimme → Stimmen verwalten. Oder in den Systemeinstellungen nach „Stimme“ suchen.":
            "Better voices: Accessibility → Spoken Content → System voice → Manage voices. Or search System Settings for “voice”.",
        "Wörterbuch": "Dictionary",
        "Erklärungen aus dem Wiktionary (online, sendet nur das Wort)": "Meanings from Wiktionary (online, sends only the word)",
        "Bei 1–3 Wörtern automatisch nachschlagen.": "Looked up automatically for 1–3 words.",
        "Markieren überall": "Select anywhere",
        "Symbol neben markiertem Text zeigen": "Show button next to selected text",
        "Notfalls mit ⌘C lesen (für Apps, die die Markierung nicht freigeben)":
            "Fall back to ⌘C (for apps that don't share their selection)",
        "Tastenkürzel ⌥⌘A: Markierung sofort als Karte senden.": "Shortcut ⌥⌘A: send the selection as a card right away.",
        "Bedienungshilfen: erlaubt ✓": "Accessibility: allowed ✓",
        "Bedienungshilfen: nicht erlaubt": "Accessibility: not allowed",
        "Erlauben": "Allow",
        "Zwischenablage": "Clipboard",
        "Verlauf pausieren": "Pause history",
        "Höchstens %d Einträge": "At most %d entries",
        "Automatisch löschen nach": "Delete automatically after",
        "Nie speichern": "Never store",
        "Eingebaute Muster (%d)": "Built-in patterns (%d)",
        "Muster entfernen": "Remove pattern",
        "Eigenes Muster, z. B. Kundennummer": "Your own pattern, e.g. customer number",
        "Hinzufügen": "Add",
        "„%@“ hinzugefügt": "“%@” added",
        "%d Einträge aus dem Verlauf entfernt": "%d entries removed from the history",
        "Text, der irgendwo vorkommt (Groß-/Kleinschreibung egal), oder /regulärer Ausdruck/. Passende Einträge werden sofort und endgültig aus dem Verlauf gelöscht. Deine Muster werden verschlüsselt gespeichert.":
            "Text that appears anywhere (case doesn't matter), or /regular expression/. Matching entries are deleted from the history right away and for good. Your patterns are stored encrypted.",
        "Leeres Muster": "Empty pattern",
        "Ungültiger regulärer Ausdruck": "Invalid regular expression",
        "Zu kurz: mindestens 2 Zeichen": "Too short: at least 2 characters",
        "Private Schlüssel (-----BEGIN … PRIVATE KEY-----)": "Private keys (-----BEGIN … PRIVATE KEY-----)",
        "Stripe-Schlüssel (sk_live_…, pk_test_…)": "Stripe keys (sk_live_…, pk_test_…)",
        "OpenAI-/Anthropic-Schlüssel (sk-…)": "OpenAI/Anthropic keys (sk-…)",
        "GitHub-Tokens (ghp_…, github_pat_…)": "GitHub tokens (ghp_…, github_pat_…)",
        "GitLab-Tokens (glpat-…)": "GitLab tokens (glpat-…)",
        "Slack-Tokens (xoxb-…)": "Slack tokens (xoxb-…)",
        "AWS-Zugangsschlüssel (AKIA…)": "AWS access keys (AKIA…)",
        "Google-API-Schlüssel (AIza…)": "Google API keys (AIza…)",
        "JSON Web Tokens (eyJ….eyJ….)": "JSON Web Tokens (eyJ….eyJ….)",
        "Zuweisungen wie „Passwort: …“, „API_KEY=…“, „token=…“": "Assignments like “password: …”, “API_KEY=…”, “token=…”",
        "Lange Zeichenketten aus Buchstaben und Ziffern ohne Leerzeichen (Passwörter, Tokens)":
            "Long strings of letters and digits without spaces (passwords, tokens)",
        "Zahlen aus 4–8 Ziffern (PINs, Bestätigungscodes)": "Numbers of 4–8 digits (PINs, verification codes)",
        "Alles aus Passwort-Managern (Passwörter, 1Password, Bitwarden, Schlüsselbund)":
            "Everything from password managers (Passwords, 1Password, Bitwarden, Keychain)",
        "1 Tag": "1 day",
        "%d Tagen": "%d days",
        "Nie": "Never",
        "Der Verlauf ist verschlüsselt (Schlüssel im Schlüsselbund). Passwörter, API-Schlüssel, Tokens und Codes werden nie gespeichert. Alles bleibt auf diesem Mac.":
            "The history is encrypted (key in the keychain). Passwords, API keys, tokens and codes are never stored. Everything stays on this Mac.",
        "System": "System",
        "Beim Anmelden starten": "Open at login",
        // onboarding
        "Willkommen bei Clipout": "Welcome to Clipout",
        "Markiere irgendwo einen Satz und mach mit einem Klick eine Anki-Karte daraus.":
            "Select a sentence anywhere and turn it into an Anki card with one click.",
        "Meine Sprache (Übersetzung)": "My language (translation)",
        "Bedienungshilfen erlauben": "Allow Accessibility",
        "Damit Clipout markierten Text in anderen Apps lesen kann.": "So Clipout can read text you select in other apps.",
        "Anki mit AnkiConnect": "Anki with AnkiConnect",
        "Anki öffnen. AnkiConnect-Add-on: Code 2055492159.": "Open Anki. AnkiConnect add-on: code 2055492159.",
        "Verbunden ✓": "Connected ✓",
        "Los geht's": "Get started",
        "Übersetzung": "Translation",
    ]
}

/// Localized text for a German key.
func L(_ german: String) -> String {
    L10n.language == "de" ? german : (L10n.english[german] ?? german)
}

func L(_ german: String, _ args: CVarArg...) -> String {
    String(format: L(german), arguments: args)
}
