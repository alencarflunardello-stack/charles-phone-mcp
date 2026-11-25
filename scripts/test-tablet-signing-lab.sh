#!/usr/bin/env bash
# Disposable CI-only signing exercise. No key or APK is uploaded or retained.
set -euo pipefail
test -n "$ANDROID_HOME"
test -n "$RUNNER_TEMP"
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "$RUNNER_TEMP/charles-signing-lab.XXXXXX")"
apk="$root/android/app/build/outputs/apk/release/app-release.apk"
trap 'rm -rf "$work"; rm -f "$apk"' EXIT
export CHARLES_RELEASE_KEYSTORE="$work/lab.p12"
export CHARLES_RELEASE_KEY_ALIAS="charles-lab"
export CHARLES_RELEASE_STORE_PASSWORD="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
export CHARLES_RELEASE_KEY_PASSWORD="$CHARLES_RELEASE_STORE_PASSWORD"
keytool -genkeypair -storetype PKCS12 -keystore "$CHARLES_RELEASE_KEYSTORE" \
  -storepass:env CHARLES_RELEASE_STORE_PASSWORD -keypass:env CHARLES_RELEASE_KEY_PASSWORD \
  -alias "$CHARLES_RELEASE_KEY_ALIAS" -keyalg RSA -keysize 2048 -validity 1 \
  -dname "CN=Charles Disposable Lab"
keytool -exportcert -keystore "$CHARLES_RELEASE_KEYSTORE" \
  -storepass:env CHARLES_RELEASE_STORE_PASSWORD -alias "$CHARLES_RELEASE_KEY_ALIAS" -file "$work/lab.der"
expected_cert="$(sha256sum "$work/lab.der" | cut -d' ' -f1)"
(cd "$root/android" && bash gradlew --no-daemon assembleRelease)
expected_apk="$(sha256sum "$apk" | cut -d' ' -f1)"
verify() {
  python3 "$root/scripts/verify-tablet-apk.py" --apk "$apk" --apk-sha256 "$expected_apk" \
  --aapt "$ANDROID_HOME/build-tools/36.0.0/aapt" --apksigner "$ANDROID_HOME/build-tools/36.0.0/apksigner" --cert-sha256 "$1"
}
verify "$expected_cert"
wrong_cert="$(printf '0%.0s' {1..64})"
if verify "$wrong_cert" > "$work/negative.json"; then
  echo "ERROR: wrong certificate accepted"
  exit 1
fi
python3 - "$work/negative.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    result = json.load(f)
assert result["passed"] is False
assert result["checks"]["certificate"] is False
assert all(v for k,v in result["checks"].items() if k != "certificate")
print("Wrong certificate correctly rejected")
PY
echo "Disposable signed APK validation passed; no distribution artifact retained."
