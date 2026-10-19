#!/bin/bash
# Sign Nomi with one certificate stored in the login keychain. The designated
# requirement is the certificate, so microphone permission survives rebuilds.
# An ad-hoc signature changes on every build and macOS treats it as a new app.
set -euo pipefail

identity="Nomi Local Development"
root="$(cd "$(dirname "$0")/.." && pwd)"
keychain="$HOME/Library/Keychains/login.keychain-db"

ensure_local_identity() {
    if security find-certificate -c "$identity" "$keychain" >/dev/null 2>&1; then
        return
    fi
    local dir pass
    dir="$(mktemp -d)"
    pass="$(uuidgen)"
    cat > "$dir/cert.conf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $identity
O = Nomi Local
[ ext ]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
    openssl req -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
        -keyout "$dir/key.pem" -out "$dir/cert.pem" \
        -config "$dir/cert.conf" >/dev/null 2>&1
    openssl pkcs12 -export -inkey "$dir/key.pem" -in "$dir/cert.pem" \
        -out "$dir/cert.p12" -name "$identity" -passout "pass:$pass" >/dev/null
    security import "$dir/cert.p12" -k "$keychain" -P "$pass" -A \
        -T /usr/bin/codesign -T /usr/bin/security >/dev/null
    rm -rf "$dir"
    security find-certificate -c "$identity" "$keychain" >/dev/null
}

sign_app() {
    local app="$1"
    if [[ ! -d "$app/Contents/MacOS" ]]; then
        echo "还没有 $app，先打包再签名。" >&2
        exit 1
    fi
    ensure_local_identity
    local bin name
    for bin in "$app/Contents/MacOS"/*; do
        [[ -f "$bin" ]] || continue
        name="$(basename "$bin")"
        # Signing the main executable signs the bundle, so helpers go first.
        [[ "$name" == "Nomi" ]] && continue
        codesign --force --sign "$identity" --timestamp=none "$bin"
    done
    codesign --force --sign "$identity" --timestamp=none "$app"
    codesign --verify --strict --verbose=2 "$app" >/dev/null
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    sign_app "${1:-$root/build/Nomi.app}"
fi
