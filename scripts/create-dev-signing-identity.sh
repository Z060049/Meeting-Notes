#!/usr/bin/env bash
set -euo pipefail

# Creates a STABLE self-signed code-signing identity for local development.
#
# Why this exists:
#   Ad-hoc signing (`codesign --sign -`) gives the app a designated requirement
#   based on its cdhash, which changes on every rebuild. macOS TCC (Microphone,
#   Screen Recording, etc.) binds granted permissions to that requirement, so
#   every rebuild invalidates previously granted access and re-triggers the
#   onboarding permission loop.
#
#   Signing with a stable self-signed certificate makes the designated
#   requirement identity-based (certificate leaf hash). The cdhash can then
#   change freely across rebuilds while TCC keeps recognizing the app, so
#   granted permissions persist.
#
# This is a ONE-TIME setup. You will be prompted once for your login password
# to trust the certificate for code signing.

IDENTITY_NAME="${MEETINGNOTES_SIGNING_IDENTITY:-MeetingNotes Dev Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning "$KEYCHAIN" | grep -Fq "$IDENTITY_NAME"; then
    echo "Signing identity '$IDENTITY_NAME' already exists and is valid. Nothing to do."
    exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
    echo "Error: openssl is required (install via 'brew install openssl')." >&2
    exit 1
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

KEY="$WORKDIR/key.pem"
CERT="$WORKDIR/cert.pem"
P12="$WORKDIR/identity.p12"
P12_PASS="meetingnotes-dev"

echo "Creating self-signed code-signing certificate '$IDENTITY_NAME'..."
openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$KEY" -out "$CERT" -days 3650 \
    -subj "/CN=$IDENTITY_NAME" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature" \
    -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

# `-legacy` produces a PKCS#12 MAC/encryption scheme that macOS `security` can
# import. OpenSSL 3's default scheme fails with "MAC verification failed".
openssl pkcs12 -export -legacy \
    -out "$P12" -inkey "$KEY" -in "$CERT" \
    -name "$IDENTITY_NAME" -passout pass:"$P12_PASS" >/dev/null 2>&1

echo "Importing certificate and private key into the login keychain..."
# -A lets codesign use the key without a per-signing prompt.
security import "$P12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign -A >/dev/null

echo
echo "Trusting the certificate for code signing."
echo "macOS will prompt for your login password now — this is expected."
# User-domain trust for the code-signing policy so codesign treats it as valid.
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$CERT"

echo
if security find-identity -v -p codesigning "$KEYCHAIN" | grep -Fq "$IDENTITY_NAME"; then
    echo "Success. '$IDENTITY_NAME' is now a valid code-signing identity."
    echo "Rebuild the app with ./scripts/build-dev-app.sh and it will be signed with this identity."
else
    echo "Warning: '$IDENTITY_NAME' is not listed as valid yet." >&2
    echo "Open Keychain Access, find '$IDENTITY_NAME', and set its trust for" >&2
    echo "'Code Signing' to 'Always Trust', then re-run this script." >&2
    exit 1
fi
