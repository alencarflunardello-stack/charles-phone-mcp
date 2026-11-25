#!/usr/bin/env bash
# Owner-only Codespaces build. No device access, deployment or secret upload.
set -euo pipefail
umask 077
MODE="${1:---check}"
COMMIT=a0733689e4e5e6d2925096a56e100d0f81394ed0
REPO=https://github.com/alencarflunardello-stack/charles-phone-mcp.git
SDK_HASH=4e4c464f145a7512b57d088ac6c278c03c9eea610886b35a5e0804e74eedf583
SDK_URL=https://dl.google.com/android/repository/commandlinetools-linux-15859902_latest.zip
PRIVATE=/workspaces/charles-owner-private
die(){ printf '%s\n' "$*" >&2; exit 1; }
[[ "$MODE" == --check || "$MODE" == --build ]] || die "Uso: --check ou --build"
[[ "${CODESPACES:-}" == true && "$(uname -s)" == Linux && "$(uname -m)" == x86_64 && -d /workspaces ]] || die "Execute somente em GitHub Codespaces Linux x86_64 do proprietário."
for tool in git curl unzip sha256sum python3; do command -v "$tool" >/dev/null || die "Ferramenta ausente: $tool"; done
python3 -c 'import sys; sys.exit(sys.version_info < (3,11))' || die "Python 3.11+ necessário."
[[ ! -L "$PRIVATE" ]] || die "Diretório privado não pode ser link simbólico."
if [[ -e "$PRIVATE" ]]; then
  [[ -d "$PRIVATE" && -O "$PRIVATE" ]] || die "Diretório privado inválido."
fi
printf '%s\n' "Pré-verificação de ambiente aprovada. Fonte fixada: $COMMIT"
df -h /workspaces
[[ "$MODE" == --build ]] || exit 0
[[ -t 0 ]] || die "Abra o terminal interativo do Codespaces."
printf '%s\n' "Confirme que o uso está dentro da franquia gratuita e que gastos excedentes estão bloqueados."
read -r -p "Franquia verificada e execução autorizada? Digite SIM: " approved
[[ "$approved" == SIM ]] || die "Cancelado sem criar chave."
mkdir -p "$PRIVATE"; chmod 700 "$PRIVATE"
for d in sdk backup output; do
  [[ ! -L "$PRIVATE/$d" ]] || die "Caminho privado inválido."
  mkdir -p "$PRIVATE/$d"; chmod 700 "$PRIVATE/$d"
done
# Prefer a preinstalled JDK 17; install into the cloud VM only if absent.
java17(){ "$1/bin/java" -version 2>&1 | grep -Eq 'version "17([."]|$)'; }
JDK=""
for candidate in "${JAVA_HOME:-/nonexistent}" /usr/lib/jvm/java-17-openjdk-amd64 /usr/local/sdkman/candidates/java/17*; do
  if [[ -x "$candidate/bin/java" ]] && java17 "$candidate"; then JDK="$candidate"; break; fi
done
if [[ -z "$JDK" ]]; then
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends openjdk-17-jdk-headless
  JDK=/usr/lib/jvm/java-17-openjdk-amd64
fi
java17 "$JDK" || die "JDK 17 indisponível."
export JAVA_HOME="$JDK" PATH="$JDK/bin:$PATH"
work="$(mktemp -d)"
cleanup(){ unset CHARLES_RELEASE_STORE_PASSWORD CHARLES_RELEASE_KEY_PASSWORD CHARLES_RELEASE_KEYSTORE CHARLES_RELEASE_KEY_ALIAS || true; rm -rf -- "$work"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export ANDROID_HOME="$PRIVATE/sdk" ANDROID_SDK_ROOT="$PRIVATE/sdk"
manager="$ANDROID_HOME/cmdline-tools/pinned/bin/sdkmanager"
if [[ ! -x "$manager" ]]; then
  curl --fail --location --proto '=https' --tlsv1.2 --retry 2 "$SDK_URL" -o "$work/sdk.zip"
  printf '%s  %s\n' "$SDK_HASH" "$work/sdk.zip" | sha256sum -c -
  unzip -q "$work/sdk.zip" -d "$work/sdk"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  [[ ! -e "$ANDROID_HOME/cmdline-tools/pinned" ]] || die "Instalação SDK parcial; revisar antes de continuar."
  mv "$work/sdk/cmdline-tools" "$ANDROID_HOME/cmdline-tools/pinned"
fi
[[ -x "$manager" ]] || die "SDK manager indisponível."
if [[ ! -f "$ANDROID_HOME/platforms/android-36/android.jar" || ! -x "$ANDROID_HOME/build-tools/36.0.0/apksigner" || ! -x "$ANDROID_HOME/build-tools/36.0.0/aapt" ]]; then
  printf '%s\n' "Leia e aceite os termos oficiais do SDK caso concorde."
  "$manager" --sdk_root="$ANDROID_HOME" --licenses
  "$manager" --sdk_root="$ANDROID_HOME" "platforms;android-36" "build-tools;36.0.0"
fi
git clone --no-checkout --single-branch --branch charles-tablet-release "$REPO" "$work/source"
git -C "$work/source" checkout --detach "$COMMIT"
[[ "$(git -C "$work/source" rev-parse HEAD)" == "$COMMIT" ]] || die "Commit inesperado."
(cd "$work/source" && python3 scripts/prepare-charles-pilot.py && python3 scripts/check-tablet-release.py --root . --device-api 33)
export CHARLES_RELEASE_KEYSTORE="$PRIVATE/backup/charles-release.p12"
export CHARLES_RELEASE_KEY_ALIAS=charles-release
fingerprint="$PRIVATE/backup/certificate.sha256"
[[ ! -L "$CHARLES_RELEASE_KEYSTORE" && ! -L "$fingerprint" ]] || die "Arquivos de assinatura inválidos."
if [[ -e "$fingerprint" && ! -f "$CHARLES_RELEASE_KEYSTORE" ]]; then die "Restaure a chave original; não crie uma substituta."; fi
read -r -s -p "Senha privada do keystore (não enviar ao chat): " CHARLES_RELEASE_STORE_PASSWORD; printf '\n'
[[ "${#CHARLES_RELEASE_STORE_PASSWORD}" -ge 16 ]] || die "Use pelo menos 16 caracteres."
export CHARLES_RELEASE_STORE_PASSWORD CHARLES_RELEASE_KEY_PASSWORD="$CHARLES_RELEASE_STORE_PASSWORD"
if [[ ! -e "$CHARLES_RELEASE_KEYSTORE" ]]; then
  read -r -s -p "Repita a senha: " repeat; printf '\n'
  [[ "$repeat" == "$CHARLES_RELEASE_STORE_PASSWORD" ]] || die "Senhas diferentes."
  unset repeat
  keytool -genkeypair -storetype PKCS12 -keystore "$CHARLES_RELEASE_KEYSTORE" -storepass:env CHARLES_RELEASE_STORE_PASSWORD -keypass:env CHARLES_RELEASE_KEY_PASSWORD -alias "$CHARLES_RELEASE_KEY_ALIAS" -keyalg RSA -keysize 3072 -validity 10000 -dname 'CN=Charles Owner Release'
fi
chmod 600 "$CHARLES_RELEASE_KEYSTORE"
keytool -exportcert -keystore "$CHARLES_RELEASE_KEYSTORE" -storepass:env CHARLES_RELEASE_STORE_PASSWORD -alias "$CHARLES_RELEASE_KEY_ALIAS" -file "$work/owner.der"
cert="$(sha256sum "$work/owner.der" | cut -d' ' -f1)"
if [[ -f "$fingerprint" ]]; then
  [[ "$(cat "$fingerprint")" == "$cert" ]] || die "Certificado diferente do original."
else
  printf '%s\n' "$cert" > "$fingerprint"
fi
printf '%s\n' "Certificado público: $cert" "No Explorer, baixe os dois arquivos da pasta $PRIVATE/backup para o tablet e guarde em local seguro. O .p12 é cifrado; mantenha a senha separada. Nunca envie ao chat nem faça commit."
read -r -p "Backup concluído e conferido? Digite SIM: " confirmed
[[ "$confirmed" == SIM ]] || die "Chave preservada; compilação não iniciada."
(cd "$work/source/android" && bash gradlew --no-daemon assembleRelease)
unset CHARLES_RELEASE_STORE_PASSWORD CHARLES_RELEASE_KEY_PASSWORD
apk="$work/source/android/app/build/outputs/apk/release/app-release.apk"
sha="$(sha256sum "$apk" | cut -d' ' -f1)"
python3 "$work/source/scripts/verify-tablet-apk.py" --apk "$apk" --apk-sha256 "$sha" --cert-sha256 "$cert" --aapt "$ANDROID_HOME/build-tools/36.0.0/aapt" --apksigner "$ANDROID_HOME/build-tools/36.0.0/apksigner" > "$work/verification.json"
out="$(mktemp -d "$PRIVATE/output/release.XXXXXX")"
cp "$apk" "$out/Charles-Phone-MCP-0.19.1.apk"
cp "$work/verification.json" "$out/verification.json"
printf '%s  %s\n' "$sha" Charles-Phone-MCP-0.19.1.apk > "$out/SHA256SUMS.txt"
printf '%s\n' "$COMMIT" > "$out/SOURCE_COMMIT.txt"
printf '%s\n' "APK validado: $out" "Baixe somente o APK e os metadados públicos. Não instale antes da validação do relay e da revogação das credenciais antigas." "Depois de confirmar backup e downloads, pare/exclua o Codespace para evitar consumo de quota."
