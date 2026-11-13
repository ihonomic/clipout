#!/bin/bash
# Fetches sherpa-onnx, which speaks with Piper voices, as universal static
# libraries for build.sh. Usage: ./make-sherpa.sh   (build.sh runs it when missing)
#
# 1.13.8 is the last version with espeak-ng built in; Piper voices need it to
# turn text into sounds, and 2.0 dropped it. espeak-ng is GPL-3, so the built
# app is distributed under the GPL-3 (Clipout's own source stays MIT).
# Static for the same reason as LAME: the Hardened Runtime only loads
# libraries signed by the same team.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=1.13.8
SHA256=5c8fd6490eafed66374e3b0cd6f7ef8e1bc87a64550d38bedde57775cf914d7e
NAME="sherpa-onnx-v$VERSION-osx-universal2-static-lib"
WORK=.build/sherpa

rm -rf "$WORK" && mkdir -p "$WORK/licenses"
TARBALL="$WORK/$NAME.tar.bz2"
curl -fsSL --retry 3 -o "$TARBALL" \
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/v$VERSION/$NAME.tar.bz2"
echo "$SHA256  $TARBALL" | shasum -a 256 -c - >/dev/null || {
    echo "Prüfsumme von $NAME stimmt nicht – Abbruch." >&2
    rm -f "$TARBALL"; exit 1
}
tar -xjf "$TARBALL" -C "$WORK" --strip-components 1
rm "$TARBALL"
# Speakers and microphones aren't needed, only the speech synthesis.
rm -f "$WORK/lib/libsherpa-onnx-portaudio_static.a"

# Licenses of everything linked in, for Contents/Resources (see build.sh).
fetch() { curl -fsSL --retry 3 -o "$WORK/licenses/$1" "$2"; }
fetch sherpa-onnx-LICENSE.txt "https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/v$VERSION/LICENSE"
fetch espeak-ng-COPYING.txt "https://raw.githubusercontent.com/espeak-ng/espeak-ng/1.52.0/COPYING"
fetch piper-phonemize-LICENSE.txt "https://raw.githubusercontent.com/rhasspy/piper-phonemize/master/LICENSE.md"
fetch onnxruntime-LICENSE.txt "https://raw.githubusercontent.com/microsoft/onnxruntime/main/LICENSE"
echo "Fertig: $WORK/lib"
