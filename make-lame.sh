#!/bin/bash
# Builds LAME (the MP3 encoder) as a universal static libmp3lame.a, which
# Clipout links in. Usage: ./make-lame.sh   (build.sh runs it when missing)
#
# macOS can't encode MP3, and AnkiWeb plays nothing else. Static, because the
# Hardened Runtime only loads libraries signed by the same team, and a
# self-signed certificate has none; switching that check off would let a
# swapped library run with Clipout's Accessibility permission. LAME is LGPL:
# Clipout's source and this script let anyone relink it with their own LAME.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=3.100
SHA256=ddfe36cab873794038ae2c1210557ad34857a4b6bdc515785d1da9e175b1da1e
# SourceForge breaks off downloads now and then; Debian keeps the same file.
URLS=("https://downloads.sourceforge.net/project/lame/lame/$VERSION/lame-$VERSION.tar.gz"
      "https://deb.debian.org/debian/pool/main/l/lame/lame_$VERSION.orig.tar.gz")
WORK=.build/lame
OUT=$WORK/libmp3lame.a

mkdir -p "$WORK"
TARBALL="$WORK/lame-$VERSION.tar.gz"
for URL in "${URLS[@]}"; do
    [[ -f "$TARBALL" ]] && break
    curl -fsSL --retry 3 -o "$TARBALL.part" "$URL" && mv "$TARBALL.part" "$TARBALL"
done
rm -f "$TARBALL.part"
echo "$SHA256  $TARBALL" | shasum -a 256 -c - >/dev/null || {
    echo "Prüfsumme von lame-$VERSION.tar.gz stimmt nicht – Abbruch." >&2
    rm -f "$TARBALL"; exit 1
}

SLICES=()
for ARCH in arm64 x86_64; do
    SRC="$WORK/src-$ARCH"
    rm -rf "$SRC" && mkdir -p "$SRC"
    tar -xzf "$TARBALL" -C "$SRC" --strip-components 1
    HOST=$([[ $ARCH == arm64 ]] && echo aarch64-apple-darwin || echo x86_64-apple-darwin)
    (
        cd "$SRC"
        # -w: LAME's code is old and warns a lot; nothing of it matters here
        CFLAGS="-arch $ARCH -O2 -w -mmacosx-version-min=26.0" \
        LDFLAGS="-arch $ARCH -mmacosx-version-min=26.0" \
        ./configure --host="$HOST" --enable-static --disable-shared \
            --disable-frontend --disable-gtktest >/dev/null 2>&1
        make -j"$(sysctl -n hw.ncpu)" >/dev/null
    )
    SLICES+=("$SRC/libmp3lame/.libs/libmp3lame.a")
done

lipo -create "${SLICES[@]}" -output "$OUT"
# The LGPL travels with the library (build.sh puts it into the app).
cp "$WORK/src-arm64/COPYING" "$WORK/LAME-COPYING.txt"
echo "Fertig: $OUT"
