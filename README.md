# Clipout

<p align="center">
  <img src="pics/cover.png" width="800" alt="The Clipout app icon next to its welcome window">
</p>

Select a sentence anywhere on your Mac (in Chrome, Safari, a PDF or any other app) and turn it into an Anki card with one click.

- **Front:** the sentence
- **Back:** translation, audio and source

## Download

**[⬇︎ Download Clipout for Mac (.dmg)](https://github.com/ihonomic/clipout/releases/latest/download/Clipout.dmg)**

Needs macOS 26 or later (Apple Silicon or Intel) and [Anki](https://apps.ankiweb.net) with the [AnkiConnect](https://ankiweb.net/shared/info/2055492159) add-on.

1. Open the .dmg and drag **Clipout** onto **Applications**.
2. Open Clipout. macOS blocks the first launch because Clipout isn't from an identified developer (it isn't notarized by Apple). Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway** next to Clipout. You only do this once.
3. The welcome window guides you through the rest: languages, the Accessibility permission and the Anki connection.

## How it works

<p align="center">
  <img src="pics/step1-select.png" width="420" alt="Text selected on tagesschau.de with the blue “+ Anki” button next to it">
</p>
<p align="center"><em>1. Select a word or sentence anywhere; a “+ Anki” button appears next to it.</em></p>

<p align="center">
  <img src="pics/step2-new-card.png" width="420" alt="New card window: sentence, listening card, Wiktionary meaning, translation and source">
</p>
<p align="center"><em>2. Check the card: translation, Wiktionary meaning, source and audio are filled in for you.</em></p>

<p align="center">
  <img src="pics/step3-anki-card.png" width="600" alt="The finished listening card in Anki: audio, sentence, translation, meaning and source">
</p>
<p align="center"><em>3. The card is in Anki: here a listening card with audio in front; sentence, translation, meaning and source on the back.</em></p>

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
  <img src="pics/settings.png" width="380" alt="Settings: Anki, dictionary, select anywhere, clipboard">
  &nbsp;
  <img src="pics/settings-2.png" width="380" alt="Settings: automatic deletion, built-in never-store patterns, your own patterns">
</p>
<p align="center"><em>Settings: deck, listening cards, dictionary, select anywhere (left); history deleted after 24 hours, built-in and your own “never store” patterns (right)</em></p>

## Features

- **Button next to a selection:** after you select text, a small “+ Anki” appears next to it. Clicking it opens the “New card” window.
- **⌥⌘A:** sends the selection as a card right away, without a window.
- **Clipboard history:** the menu bar icon lists everything you copied, text and images. Every row has a “+ Anki” button.
- **Translation:** Apple's on-device translation, offline and free.
- **Audio:** a voice reads the sentence (choose it in Settings, ▶ plays a sample): one of the macOS system voices, or a natural-sounding **Piper voice** such as “Thorsten” for German. Piper voices run offline too; Settings → Neural voices downloads one (27–116 MB, checksum verified). The recording goes on the back as MP3, which plays everywhere: Anki on Mac, AnkiDroid, AnkiMobile and AnkiWeb. M4A is still available in Settings, but AnkiWeb doesn't play it.
- **Cloze:** tap words in the window to hide them, and the card becomes a cloze card.
- **Dictionary:** in “Meaning” mode, tap a word and its meaning from the English Wiktionary goes on the back. Inflected forms are resolved (“Abstimmungen” → “Abstimmung”). For 1–3 selected words this happens automatically. Online, only the word is sent. Can be switched off.
- **Listening cards:** “🎧 Listening” in the card window (or as the default in Settings). Only audio in front; sentence, translation and meanings on the back.
- **App language:** German or English. On first start, a welcome window asks for the app language, the language you learn and your own language.
- **Images:**
  - A screenshot (⌘⇧⌃4 copies it) becomes a card with the image.
  - The text in the image is recognized automatically.
- **Source:** in Chrome, Safari, Arc, Brave and Edge the page URL goes on the card. In other apps it's the window title.
- **Queue:** when Anki is closed, Clipout keeps the cards and sends them as soon as Anki is open. Errors (for example an open edit window in Anki) are shown in the menu.
- **Privacy and security:**
  - The clipboard history, its images and the card queue are **encrypted** (AES-256-GCM). The key is in your login keychain, so the files are useless to other programs and in backups.
  - Passwords, API keys, tokens, private keys and one-time codes are **never stored**: entries from password managers and anything that looks like a secret are skipped.
  - Entries are deleted automatically after 24 hours by default (or after 7 days, 30 days or never; see Settings).
  - **Never store:** Settings list the built-in patterns (locked) and let you add your own: plain text such as a customer number, or a `/regular expression/`. Adding a pattern also deletes matching entries already in the history, for good; there is no undo. Your patterns are stored encrypted.
  - Everything stays on your Mac. Only dictionary lookups go online (just the word, to Wiktionary) and can be switched off.
  - The app runs with the Hardened Runtime, so no other program can inject code into it and misuse its Accessibility permission.

## Requirements

- macOS 26 or later
- Anki with the [AnkiConnect](https://ankiweb.net/shared/info/2055492159) add-on
- Swift (the Command Line Tools are enough, Xcode is not needed)
- For building: an internet connection the first time. `build.sh` downloads and builds [LAME](https://lame.sourceforge.io) 3.100, the MP3 encoder, and downloads [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) 1.13.8, which runs the Piper voices (both checksum verified).

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


## Anki

Clipout creates:

- the deck **Clipout**
- the note types **Clipout** (sentence → translation) and **Clipout Cloze**, with these fields:

| Field | Contents |
|---|---|
| `Sentence` (`Text` in Clipout Cloze) | the sentence in your target language, the language you learn |
| `Translation` | the translation into your own language |
| `Audio` | the sentence read by the system voice |
| `Image` | the image, for cards made from screenshots |
| `Source` | the page or app the text came from |
| `Meaning` | Wiktionary meanings of the words you tapped |
| `Listening` | filled for listening cards: then only the audio is on the front |

Clipout works for any language pair Apple's translation supports; set “I'm learning” and “Translate into” in Settings.

Cards made with 0.1.x: Clipout renames their German fields (Satz, Übersetzung, …) to the names above when it starts, and the content stays. The cloze note type keeps its old name “Clipout Lücke”, because AnkiConnect can't rename note types; you can rename it to “Clipout Cloze” in Anki under Tools → Manage Note Types.

All cards have the tag `clipout`.

## Your data

Everything Clipout keeps lives in `~/Library/Application Support/Clipout` (readable only by you) and is encrypted with a key from your login keychain:

| File | Contents |
|---|---|
| `history.sealed` | clipboard history |
| `clips/*.sealed` | copied images |
| `queue.sealed` | cards waiting for Anki |
| `patterns.sealed` | your own “never store” patterns |
| `media/` | audio and images briefly, until Anki has them |
| `voices/` | Piper voices you downloaded (not encrypted: they are public models) |

## Structure

How the parts work together, with diagrams: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

| Folder | Contents |
|---|---|
| `Sources/ClipoutCore` | Logic without UI: building cards, cloze, history and expiry, secret detection and custom patterns, Wiktionary parsing, AnkiConnect messages. Tested in `Tests/`. |
| `Sources/Clipout` | The app: menu bar, reading the selection, floating button, windows, translation, audio, Anki queue, encrypted storage. |
| `Resources` | `Info.plist`, entitlements and `make-icon.swift`, which draws the app icon. |
| `Sources/CSherpaOnnx` | The C interface of sherpa-onnx (Apache-2.0), for the Piper voices. |
| `build.sh`, `make-dmg.sh`, `make-cert.sh`, `make-lame.sh`, `make-sherpa.sh`, `test.sh` | Build the app, build the .dmg, create the signing certificate, build the MP3 encoder, fetch the speech engine, run the tests. |

## Changelog

**Unreleased**
- Natural-sounding Piper voices (e.g. “Thorsten” for German), offline: Settings → Neural voices. The built app is now distributed under the GPL-3, see License.
- Choose the voice in Settings → Languages, with a sample to listen to (before, Clipout always used the best installed voice).
- Audio is saved as MP3, so it plays on AnkiWeb too (AnkiWeb plays only MP3).
- Fixed: cards named their audio in uppercase while Anki stores it in lowercase. The Mac didn't mind, but AnkiWeb found no file and showed no play button.
- Existing cards: `build/Clipout.app/Contents/MacOS/Clipout --convert-audio` (Anki open) fixes both: it turns .m4a into MP3 without changing the sound and corrects the file names. Then sync; Anki's Tools → Check Media removes the old files.

**0.1.1**
- Note types use English, language-neutral field names (Sentence, Translation, Audio, Image, Source, Meaning, Listening); existing fields are renamed, content stays.
- Clipboard history, images, queue and patterns are encrypted (AES-256-GCM, key in the keychain).
- Passwords, API keys, tokens, private keys and one-time codes are never stored.
- “Never store”: built-in patterns shown in Settings, plus your own (text or `/regex/`).
- History entries are deleted after 24 hours by default.
- Hardened Runtime; only `http(s)` links on cards; private file permissions.
- Fixed: audio from enhanced system voices was cut off or could not be played.

**0.1.0**
- First release (universal binary: Apple Silicon and Intel).

## License

[MIT](LICENSE) © 2026 Ihonosetale Oseghale. Contributions are welcome under the same license, see [CONTRIBUTING.md](CONTRIBUTING.md).

**The built app (Clipout.app, Clipout.dmg) is distributed under the [GPL-3](https://www.gnu.org/licenses/gpl-3.0.html)**, because it contains espeak-ng, which the Piper voices need to turn text into sounds. Clipout's own source code stays MIT. The app contains:

| Component | License |
|---|---|
| [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx) 1.13.8 | Apache-2.0 |
| [espeak-ng](https://github.com/espeak-ng/espeak-ng) (inside sherpa-onnx) | GPL-3.0 or later |
| [piper-phonemize](https://github.com/rhasspy/piper-phonemize) | MIT |
| [ONNX Runtime](https://github.com/microsoft/onnxruntime) | MIT |
| [LAME](https://lame.sourceforge.io) 3.100 | LGPL-2.0 or later |

Their license texts are in `Clipout.app/Contents/Resources`. Piper voices are not part of Clipout: you download them yourself, and each has its own license (see `MODEL_CARD` in `~/Library/Application Support/Clipout/voices/<voice>`).

Clipout includes [LAME](https://lame.sourceforge.io) 3.100 (LGPL 2.0 or later) to write MP3, built unmodified from the official, checksum-verified source by `make-lame.sh` and linked into the app. Its license is in `Clipout.app/Contents/Resources/LAME-COPYING.txt`. To use your own build of LAME, put your `libmp3lame.a` into `.build/lame/` and run `./build.sh`.
