# Contributing to Clipout

Thanks for helping! Bug reports, ideas and pull requests are welcome.

## Issues

- **Bug:** use the bug report form and fill in the versions. Without them, problems are hard to reproduce.
- **Idea:** describe what you are trying to do, not only the solution.
- **Security problem:** don't open an issue, see [SECURITY.md](SECURITY.md).
- Issues are public: leave out personal text, keys and private screenshots.

## Pull requests

1. For anything bigger than a small fix, **open an issue first** so we can agree on the approach before you spend time on it.
2. Fork the repository and create a branch from `main`.
3. Keep a PR to **one change**. Several unrelated fixes are easier to review as several PRs.
4. Fill in the PR template.

The maintainer reviews every PR and decides about merging. A PR may be closed if it doesn't fit Clipout's principles below.

## Build and test

You need macOS 26 or later and Swift (the Command Line Tools are enough, Xcode is not needed).

```bash
./build.sh --open     # build build/Clipout.app and start it
./test.sh             # run the tests
```

To keep the Accessibility permission across rebuilds, create a signing certificate once with `./make-cert.sh` (see the README).

## Principles

- **Everything stays on the Mac.** No accounts, tracking or analytics. The only network call is the optional Wiktionary lookup, which sends just the word.
- **No third-party dependencies.** Only Apple's frameworks. The one exception is LAME, the MP3 encoder: macOS can't write MP3, and AnkiWeb plays nothing else. It is built from the official, checksum-verified source by `make-lame.sh` and linked in.
- **Privacy first.** Clipboard data is encrypted on disk, and secrets are never stored. Changes to this need a very good reason.
- **Any language pair.** Don't assume German or English; field names and card templates stay language-neutral.

## Code

- Logic without UI goes in `Sources/ClipoutCore` and gets a test in `Tests/ClipoutCoreTests`.
- Match the style of the surrounding code: small types, comments that explain *why*, not *what*.
- UI text goes in `Sources/Clipout/L10n.swift`: the German text is the key, add the English translation.
- Commit messages: a short summary line in English (imperative, e.g. "Fix cut-off audio"), then a blank line and the why.
