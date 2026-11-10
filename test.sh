#!/bin/bash
# The Command Line Tools ship the Swift Testing macros outside the default
# plugin path, so `swift test` alone fails with "plugin for module
# 'TestingMacros' not found".
set -euo pipefail
cd "$(dirname "$0")"
swift test -Xswiftc -plugin-path -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing" "$@"
