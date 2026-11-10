# Security

Clipout can read selected text in other apps (Accessibility permission) and keeps a clipboard history, so security problems matter.

## Reporting a problem

Please **don't open a public issue**. Report it privately instead:

**[Report a vulnerability](https://github.com/ihonomic/clipout/security/advisories/new)** (GitHub → Security → Advisories)

Describe what you found and how to reproduce it. You'll get an answer as soon as possible, and the fix goes into a new release before the details are made public.

## Supported versions

Only the [latest release](https://github.com/ihonomic/clipout/releases/latest) gets security fixes.

## What Clipout does to protect your data

- The clipboard history, its images, the card queue and your patterns are encrypted with AES-256-GCM; the key is in your login keychain.
- Passwords, API keys, tokens, private keys and one-time codes are never stored.
- History entries are deleted after 24 hours by default.
- The app runs with the Hardened Runtime.
- Nothing leaves your Mac except optional Wiktionary lookups (only the word).

Each release lists the SHA-256 checksum of `Clipout.dmg`, so you can check that your download is genuine.
