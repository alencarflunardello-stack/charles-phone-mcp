#!/usr/bin/env bash
# Build a private localhost TLS candidate. Reuses the owner's existing APK signing key.
# The public TLS certificate is provided interactively and never committed.
set -euo pipefail
umask 077
COMMIT=6b30c6ad205f733ac2dce27d8095361f07d82550
PRIVATE=/workspaces/charles-owner-private
VERSION=0.19.1-tablet.2
CODE=72
REPO=https://github.com/alencarflunardello-stack/charles-phone-mcp.git
die(){ printf '%s\n' "$*" >&2; exit 1; }
[[ "${CODESPACES:-}" == true && "$(uname -s)" == Linux && "$(uname -m)" == x86_64 && -t 0 ]] || die "Execute no terminal interativo do Codespace original."
[[ -d "$PRIVATE" && -O "$PRIVATE" && ! -L "$PRIVATE" ]] || die "Diretorio privado original indisponivel."
for d in sdk backup output; do [[ -d "$PRIVATE/$d" && ! -L "$PRIVATE/$d" && -O "$PRIVATE/$d" ]] || die "Pasta original indisponivel: $d"; done
export ANDROID_HOME="$PRIVATE/sdk" ANDROID_SDK_ROOT="$PRIVATE/sdk"
[[ -f "$ANDROID_HOME/platforms/android-36/android.jar" && -x "$ANDROID_HOME/build-tools/36.0.0/apksigner" && -x "$ANDROID_HOME/build-tools/36.0.0/aapt" ]] || die "SDK original incompleto; nao instalar dependencias automaticamente."
export CHARLES_RELEASE_KEYSTORE="$PRIVATE/backup/charles-release.p12"
export CHARLES_RELEASE_KEY_ALIAS=charles-release
fingerprint="$PRIVATE/backup/certificate.sha256"
[[ -f "$CHARLES_RELEASE_KEYSTORE" && ! -L "$CHARLES_RELEASE_KEYSTORE" && -O "$CHARLES_RELEASE_KEYSTORE" && -f "$fingerprint" && ! -L "$fingerprint" && -O "$fingerprint" ]] || die "Restaurar chave e certificado originais; nunca criar outra chave."
cert="$(cat "$fingerprint")"
[[ "$cert" =~ ^[0-9a-f]{64}$ ]] || die "Fingerprint original invalida."
JDK=""
for candidate in "${JAVA_HOME:-/nonexistent}" /usr/lib/jvm/java-17-openjdk-amd64 /usr/local/sdkman/candidates/java/17*; do
  if [[ -x "$candidate/bin/java" ]] && "$candidate/bin/java" -version 2>&1 | grep -Eq 'version "17([."]|$)'; then JDK="$candidate"; break; fi
done
[[ -n "$JDK" ]] || die "JDK 17 original indisponivel."
export JAVA_HOME="$JDK" PATH="$JDK/bin:$PATH"
work="$(mktemp -d)"
cleanup(){ unset CHARLES_RELEASE_STORE_PASSWORD CHARLES_RELEASE_KEY_PASSWORD CHARLES_RELEASE_KEYSTORE CHARLES_RELEASE_KEY_ALIAS || true; rm -rf -- "$work"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
git clone --no-checkout --single-branch --branch charles-tablet-release "$REPO" "$work/source"
git -C "$work/source" checkout --detach "$COMMIT"
[[ "$(git -C "$work/source" rev-parse HEAD)" == "$COMMIT" ]] || die "Commit inesperado."
# Accept only the exact public certificate generated on the tablet.
expected_tls="${CHARLES_LOCAL_TLS_SHA256:-}"
if [[ -z "$expected_tls" ]]; then read -r -p "SHA-256 do certificado TLS local: " expected_tls; fi
expected_tls="$(printf '%s' "$expected_tls" | tr -d ':' | tr '[:upper:]' '[:lower:]')"
[[ "$expected_tls" =~ ^[0-9a-f]{64}$ ]] || die "Fingerprint TLS invalida."
read -r -p "Certificado PUBLICO DER em base64 (uma linha): " public_cert
printf '%s' "$public_cert" | base64 -d > "$work/local.der"
unset public_cert
openssl x509 -inform DER -in "$work/local.der" -out "$work/local.pem"
openssl x509 -in "$work/local.pem" -outform DER -out "$work/normalized.der"
[[ "$(sha256sum "$work/normalized.der" | cut -d' ' -f1)" == "$expected_tls" ]] || die "Certificado TLS diferente do tablet."
openssl x509 -in "$work/local.pem" -checkend 0 -noout
openssl x509 -in "$work/local.pem" -noout -ext subjectAltName | grep -Eq 'DNS:localhost([,[:space:]]|$)' || die "SAN localhost ausente."
openssl verify -CAfile "$work/local.pem" "$work/local.pem"
python3 - "$work/source" "$work/local.pem" <<'PY'
from pathlib import Path
import sys
root, cert = map(Path, sys.argv[1:])
main = root / "android/app/src/main"
manifest = main / "AndroidManifest.xml"
gradle = root / "android/app/build.gradle"
text = manifest.read_text()
assert text.count('android:usesCleartextTraffic="false"') == 1
assert "android:networkSecurityConfig" not in text
manifest.write_text(text.replace('android:usesCleartextTraffic="false"', 'android:usesCleartextTraffic="false" android:networkSecurityConfig="@xml/charles_local_network"'))
text = gradle.read_text()
assert text.count("versionCode 71") == 1 and text.count("versionName '0.19.1-tablet.1'") == 1
gradle.write_text(text.replace("versionCode 71", "versionCode 72").replace("versionName '0.19.1-tablet.1'", "versionName '0.19.1-tablet.2'"))
raw, xml = main / "res/raw", main / "res/xml"
raw.mkdir(parents=True, exist_ok=True)
xml.mkdir(parents=True, exist_ok=True)
(raw / "charles_local_tls.pem").write_bytes(cert.read_bytes())
(xml / "charles_local_network.xml").write_text("""<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="false">
        <trust-anchors><certificates src="system" /></trust-anchors>
    </base-config>
    <domain-config cleartextTrafficPermitted="false">
        <domain includeSubdomains="false">localhost</domain>
        <trust-anchors><certificates src="@raw/charles_local_tls" /></trust-anchors>
    </domain-config>
</network-security-config>
""")
PY

(cd "$work/source" && python3 scripts/prepare-charles-pilot.py && python3 scripts/check-tablet-release.py --root . --device-api 33 --android-version "$VERSION" --version-code "$CODE")
# This is a foreground-only candidate, not an API 33 parallel-mode release.
(cd "$work/source/android" && bash gradlew --no-daemon compileReleaseJavaWithJavac lintRelease)
read -r -s -p "Senha da chave original (nao enviar ao chat): " CHARLES_RELEASE_STORE_PASSWORD; printf '\n'
export CHARLES_RELEASE_STORE_PASSWORD CHARLES_RELEASE_KEY_PASSWORD="$CHARLES_RELEASE_STORE_PASSWORD"
keytool -exportcert -keystore "$CHARLES_RELEASE_KEYSTORE" -storepass:env CHARLES_RELEASE_STORE_PASSWORD -alias "$CHARLES_RELEASE_KEY_ALIAS" -file "$work/owner.der"
[[ "$(sha256sum "$work/owner.der" | cut -d' ' -f1)" == "$cert" ]] || die "Certificado diferente do original."
(cd "$work/source/android" && bash gradlew --no-daemon assembleRelease)
unset CHARLES_RELEASE_STORE_PASSWORD CHARLES_RELEASE_KEY_PASSWORD
apk="$work/source/android/app/build/outputs/apk/release/app-release.apk"
sha="$(sha256sum "$apk" | cut -d' ' -f1)"
python3 "$work/source/scripts/verify-tablet-apk.py" --apk "$apk" --apk-sha256 "$sha" --cert-sha256 "$cert" --aapt "$ANDROID_HOME/build-tools/36.0.0/aapt" --apksigner "$ANDROID_HOME/build-tools/36.0.0/apksigner" --version "$VERSION" --version-code "$CODE" > "$work/verification.json"
out="$(mktemp -d "$PRIVATE/output/update.XXXXXX")"
name="Charles-Phone-MCP-$VERSION.apk"
cp "$apk" "$out/$name"
cp "$work/verification.json" "$out/verification.json"
printf '%s  %s\n' "$sha" "$name" > "$out/SHA256SUMS.txt"
printf '%s\n' "$COMMIT" > "$out/SOURCE_COMMIT.txt"
printf '%s\n' "$expected_tls" > "$out/LOCAL_TLS_CERT_SHA256.txt"
printf '%s\n' "APK assinado e validado: $out/$name" "Atualize sem desinstalar. Pare a sessao antes de instalar. Endpoint local: https://localhost:8443. Teste somente depois do pareamento local. Nao altere servidor ou OAuth."
