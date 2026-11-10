#!/bin/bash
# Creates the self-signed code-signing certificate "Clipout Dev" in the login
# keychain, once. build.sh then signs with it, so the signature (and with it
# the Accessibility permission) stays the same across rebuilds.
#
# Since macOS 26 the certificate assistant of Keychain Access is gone (the app
# opens "Passwords"), so this does the same from the command line.
# Remove again with: security delete-identity -c "Clipout Dev"
set -euo pipefail

if security find-identity -p codesigning | grep -q '"Clipout Dev"'; then
    echo "Zertifikat \"Clipout Dev\" gibt es schon."
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Clipout Dev
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASS=$(openssl rand -hex 12)
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "Clipout Dev" \
    -out "$TMP/id.p12" -passout "pass:$PASS" 2>/dev/null
# -T: codesign may use the key without asking each time
security import "$TMP/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$PASS" -T /usr/bin/codesign

security find-identity -p codesigning | grep '"Clipout Dev"'
echo "Fertig. Jetzt: ./build.sh --open"
