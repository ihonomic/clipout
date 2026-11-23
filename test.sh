#!/bin/bash
# The Command Line Tools ship the Swift Testing macros outside the default
# plugin path, so `swift test` alone fails with "plugin for module
# 'TestingMacros' not found".
set -euo pipefail
cd "$(dirname "$0")"
# A key twice in the English table crashes the app as soon as its language
# is English (Swift traps on duplicate dictionary literal keys).
dupes=$(grep -oE '^ *"([^"\\]|\\.)*": ' Sources/Clipout/L10n.swift | sort | uniq -d)
if [[ -n "$dupes" ]]; then echo "Doppelt in L10n.swift: $dupes" >&2; exit 1; fi

swift test -Xswiftc -plugin-path -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing" "$@"
