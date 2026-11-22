#!/bin/bash
# One-time: creates a self-signed code-signing identity in ./signing so macOS keeps
# Kalam's permissions across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p signing && cd signing
[ -f kalam.keychain-db ] && { echo "Signing keychain already exists"; exit 0; }
cat > cert.cnf <<'CNF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Kalam Local Signing
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout key.pem -out cert.pem -days 3650 -config cert.cnf 2>/dev/null
PASS=$(openssl rand -hex 16); echo -n "$PASS" > keychain-password.txt
openssl pkcs12 -export -inkey key.pem -in cert.pem -out id.p12 -passout pass:"$PASS" -legacy 2>/dev/null || \
  openssl pkcs12 -export -inkey key.pem -in cert.pem -out id.p12 -passout pass:"$PASS"
security create-keychain -p "$PASS" "$(pwd)/kalam.keychain-db"
security set-keychain-settings "$(pwd)/kalam.keychain-db"
security unlock-keychain -p "$PASS" "$(pwd)/kalam.keychain-db"
security import id.p12 -k "$(pwd)/kalam.keychain-db" -P "$PASS" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -s -k "$PASS" "$(pwd)/kalam.keychain-db" >/dev/null
rm -f key.pem id.p12
echo "Created Kalam Local Signing identity"
