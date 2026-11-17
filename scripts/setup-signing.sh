#!/bin/zsh
# Creates a project-scoped, reusable development identity. Not for distribution.
set -euo pipefail
export EDITOR=vim VISUAL=vim GIT_EDITOR=vim
cd "${0:A:h:h}"
umask 077
signing_dir="$PWD/.local-signing"
mkdir -p "$signing_dir"
keychain="$signing_dir/SuperShot.keychain-db"
if [[ -f "$keychain" ]]; then
    print 'Local signing keychain already exists; keeping its identity.'
    exit 0
fi
openssl rand -hex 32 > "$signing_dir/password"
password=$(cat "$signing_dir/password")
cat > "$signing_dir/certificate.conf" <<'CONFIG'
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
CN = SuperShot Local Development
[extensions]
basicConstraints = critical,CA:TRUE
keyUsage = critical,digitalSignature,keyCertSign
extendedKeyUsage = critical,codeSigning
CONFIG
openssl req -new -newkey rsa:2048 -nodes -x509 -days 3650 \
    -config "$signing_dir/certificate.conf" \
    -keyout "$signing_dir/private.pem" -out "$signing_dir/certificate.pem" 2>/dev/null
pkcs12_flags=()
if openssl version | /usr/bin/grep -q '^OpenSSL 3'; then
    pkcs12_flags+=(-legacy)
fi
openssl pkcs12 -export "${pkcs12_flags[@]}" -inkey "$signing_dir/private.pem" \
    -in "$signing_dir/certificate.pem" -out "$signing_dir/identity.p12" \
    -passout "file:$signing_dir/password"
security create-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$password" "$keychain"
security import "$signing_dir/identity.p12" -k "$keychain" -P "$password" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
print 'Created SuperShot Local Development in .local-signing/.'
print 'Keep this directory private and preserve it across builds.'
