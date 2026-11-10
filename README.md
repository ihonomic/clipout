# Clipout

Select a sentence anywhere on your Mac (in Chrome, Safari, a PDF or any other app) and turn it into an Anki card with one click.

- **Front:** the sentence
- **Back:** translation, audio and source

## Download

**[⬇︎ Download Clipout for Mac (.dmg)](https://github.com/ihonomic/clipout/releases/latest/download/Clipout.dmg)**

Needs macOS 26 or later (Apple Silicon or Intel) and [Anki](https://apps.ankiweb.net) with the [AnkiConnect](https://ankiweb.net/shared/info/2055492159) add-on.

1. Open the .dmg and drag **Clipout** onto **Applications**.
2. Open Clipout. macOS blocks the first launch because Clipout isn't from an identified developer (it isn't notarized by Apple). Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to Clipout. You only do this once.
3. The welcome window guides you through the rest: languages, the Accessibility permission and the Anki connection.

## Screenshots

<p align="center">
  <img src="pics/menu.png" width="360" alt="Menu bar: Anki status and clipboard history with a “+ Anki” button on every entry">
</p>
<p align="center"><em>Menu bar: Anki status and clipboard history, every entry with “+ Anki”</em></p>

<p align="center">
  <img src="pics/welcome-de.png" width="360" alt="Welcome window in German">
  &nbsp;
  <img src="pics/welcome-en.png" width="360" alt="Welcome window in English">
</p>
<p align="center"><em>First start: choose the app language, the language you learn and your own language, then check Accessibility and Anki (German and English)</em></p>

<p align="center">
  <img src="pics/settings.png" width="400" alt="Settings: Anki, dictionary, select anywhere, clipboard">
</p>
<p align="center"><em>Settings: deck, listening cards, dictionary, select anywhere, clipboard</em></p>

## Features

- **Button next to a selection:** after you select text, a small “+ Anki” appears next to it. Clicking it opens the “New card” window.
- **⌥⌘A:** sends the selection as a card right away, without a window.
- **Clipboard history:** the menu bar icon lists everything you copied, text and images. Every row has a “+ Anki” button.
- **Translation:** Apple's on-device translation, offline and free.
- **Audio:** the system voice reads the sentence. The recording goes on the back as .m4a.
- **Cloze:** tap words in the window to hide them, and the card becomes a cloze card.
- **Dictionary:** in “Meaning” mode, tap a word and its meaning from the English Wiktionary goes on the back. Inflected forms are resolved (“Abstimmungen” → “Abstimmung”). For 1–3 selected words this happens automatically. Online, only the word is sent. Can be switched off.
- **Listening cards:** “🎧 Listening” in the card window (or as the default in Settings). Only audio in front; sentence, translation and meanings on the back.
- **App language:** German or English. On first start, a welcome window asks for the app language, the language you learn and your own language.
- **Images:**
  - A screenshot (⌘⇧⌃4 copies it) becomes a card with the image.
  - The text in the image is recognized automatically.
- **Source:** in Chrome, Safari, Arc, Brave and Edge the page URL goes on the card. In other apps it's the window title.
- **Queue:** when Anki is closed, Clipout keeps the cards and sends them as soon as Anki is open. Errors (for example an open edit window in Anki) are shown in the menu.
- **Privacy:**
  - Entries from password managers are never stored.
  - Everything stays local in `~/Library/Application Support/Clipout`.

## Requirements

- macOS 26 or later
- Anki with the [AnkiConnect](https://ankiweb.net/shared/info/2055492159) add-on
- Swift (the Command Line Tools are enough, Xcode is not needed)

## Build and run

```bash
./build.sh --open     # builds build/Clipout.app and starts it
./test.sh             # tests
```

On first start:

1. **Allow Accessibility:** System Settings → Privacy & Security → Accessibility → switch Clipout on. Without it, only the clipboard history works.
2. **Download the language pack:** Clipout menu → ⚙︎ → “Download language pack”, once.
3. **Allow Automation:** the first time in Chrome or Safari, macOS asks whether Clipout may control the browser. Clipout only needs this for the URL.

### Once: a fixed certificate, so the permission survives rebuilds

macOS ties the Accessibility permission to the app's signature. Without a certificate the signature changes with every `./build.sh` and the permission stops working (the list still shows Clipout as switched on).

1. `./make-cert.sh` creates the certificate `Clipout Dev` in the login keychain. Recent macOS versions no longer offer Keychain Access's certificate assistant, so the script does it from the command line.
2. `./build.sh --open`. The script finds the certificate. If macOS asks for your login password, choose **“Always Allow”**.
3. In Accessibility, remove the old Clipout entry with `−`, add `build/Clipout.app` with `+` and switch it on. You never need to do this again.

### Share as .dmg

```bash
./make-dmg.sh         # → build/Clipout.dmg
```

Clipout is signed with its own certificate, not with an Apple Developer ID, and not notarized. On another Mac, macOS therefore blocks the first launch; the user allows it once under System Settings → Privacy & Security → **Open Anyway** (right-click → Open no longer skips this since macOS 15).

To publish a new version, attach the file as `Clipout.dmg` to a GitHub release, so the download link above keeps working:

```bash
gh release create v0.1.0 build/Clipout.dmg --title "Clipout 0.1.0" --notes "First release"
```

Optional, to check that everything works:

```bash
build/Clipout.app/Contents/MacOS/Clipout --selftest          # Anki, translation, dictionary, voice
build/Clipout.app/Contents/MacOS/Clipout --selftest --send   # + one real test card, deleted again afterwards
```

## Anki

Clipout creates:

- the deck **Clipout**
- the note types **Clipout** (sentence → translation) and **Clipout Lücke** (cloze). Their fields are German: Satz/Text (sentence), Übersetzung (translation), Audio, Bild (image), Quelle (source), Erklärung (meaning) and Hören (listening). Missing fields are added to older note types automatically.

All cards have the tag `clipout`.

## Structure

| Folder | Contents |
|---|---|
| `Sources/ClipoutCore` | Logic without UI: building cards, cloze, history, Wiktionary parsing, AnkiConnect messages. Tested in `Tests/`. |
| `Sources/Clipout` | The app: menu bar, reading the selection, floating button, windows, translation, audio, Anki queue. |
