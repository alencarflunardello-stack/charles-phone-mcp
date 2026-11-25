#!/usr/bin/env bash
# Update only the owner's existing APK. Never creates/exports a new signing key.
set -euo pipefail
umask 077
COMMIT=6b30c6ad205f733ac2dce27d8095361f07d82550
PRIVATE=/workspaces/charles-owner-private
VERSION=0.19.1-tablet.1
CODE=71
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
printf '%s\n' "APK assinado e validado: $out/$name" "Atualize sem desinstalar. Pare a sessao antes de instalar. Teste foreground e pare novamente. Nao altere servidor ou OAuth."
