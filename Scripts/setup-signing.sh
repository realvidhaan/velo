#!/usr/bin/env bash
#
# One-time setup: create a *persistent* local code-signing identity so
# Velo.app keeps a stable signature across rebuilds.
#
#   Scripts/setup-signing.sh
#
# Why this exists
# ---------------
# macOS ties an app's TCC privacy grants (Accessibility, Input Monitoring,
# Microphone) to its code-signing identity. Ad-hoc signatures (`codesign -s -`)
# are content-hashed, so they change on every rebuild and macOS treats each
# build as a brand-new app — wiping the permissions you granted. A stable
# self-signed certificate fixes that: the signing identity stays constant, so
# the grants stick.
#
# This does NOT require an Apple Developer account. It creates a self-signed
# certificate named "FlowClone Local Dev", imports it into your login keychain,
# and trusts it for code signing. It is idempotent — re-running is a no-op once
# the identity exists. Run it once; you do not need it on later builds.
#
# If you already have an "Apple Development" identity, you don't need this at
# all — build-app.sh prefers that automatically.

set -euo pipefail

CERT_NAME="FlowClone Local Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

# Already have a usable identity? Then there's nothing to do.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
    echo "==> An 'Apple Development' identity already exists — no local cert needed."
    echo "    build-app.sh will use it automatically."
    exit 0
fi
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "==> '$CERT_NAME' identity already present and valid — nothing to do."
    exit 0
fi

echo "==> Creating a persistent local code-signing identity: '$CERT_NAME'"

# Work in a temp dir so the private key never lingers in the repo.
WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# A random password protects the transient .p12 (it's deleted with $WORK).
P12_PASS="$(openssl rand -hex 16)"

cat > "$WORK/sign.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $CERT_NAME
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# Self-signed cert (10 years) carrying the Code Signing extended key usage.
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" \
    -days 3650 -config "$WORK/sign.cnf" >/dev/null 2>&1

# Bundle key + cert into a PKCS#12 for import. OpenSSL 3.x defaults to a MAC
# algorithm the macOS Security framework can't read, so use -legacy there;
# LibreSSL (the system openssl) doesn't know -legacy but is already compatible.
if ! openssl pkcs12 -export -legacy \
        -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
        -out "$WORK/cert.p12" -name "$CERT_NAME" \
        -passout pass:"$P12_PASS" >/dev/null 2>&1; then
    openssl pkcs12 -export \
        -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
        -out "$WORK/cert.p12" -name "$CERT_NAME" \
        -passout pass:"$P12_PASS" >/dev/null 2>&1
fi

# Import into the login keychain, pre-authorizing /usr/bin/codesign to use the
# private key (so signing doesn't pop a keychain prompt on every build).
security import "$WORK/cert.p12" -k "$KEYCHAIN" -P "$P12_PASS" \
    -T /usr/bin/codesign >/dev/null

# Trust the cert for code signing (user domain — no admin/sudo needed). Without
# this the identity exists but shows as CSSMERR_TP_NOT_TRUSTED and codesign
# won't treat it as valid.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem" >/dev/null 2>&1 || {
    echo "warning: could not set trust automatically. If signing fails, open" >&2
    echo "         Keychain Access, find '$CERT_NAME', and set 'Code Signing:" >&2
    echo "         Always Trust'." >&2
}

# Verify the identity is now usable.
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$CERT_NAME"; then
    echo "==> Done. '$CERT_NAME' is ready and will be used by build-app.sh."
    echo "    Your Accessibility / Input Monitoring / Microphone grants will now"
    echo "    survive rebuilds. You only needed to run this once."
else
    echo "error: identity '$CERT_NAME' was created but is not showing as valid." >&2
    echo "       Try opening Keychain Access and trusting it for code signing." >&2
    exit 1
fi
