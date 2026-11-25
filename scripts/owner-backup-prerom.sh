#!/usr/bin/env bash
set -euo pipefail
umask 077
mode=$1
case "$mode" in
 codespace) repo=/workspaces/charles-phone-mcp; private=/workspaces/charles-owner-private; dest="$private/output";;
 tablet) repo="$HOME/charles-hub/phone-mcp"; dest="$HOME/storage/downloads";;
 *) exit 2;;
esac
[[ -t 0 && -d "$repo/.git" && -d "$dest" && -w "$dest" ]] || { echo 'Terminal interativo, repositorio ou pasta de destino indisponivel.' >&2; exit 1; }
for cmd in git tar gpg sha256sum; do command -v "$cmd" >/dev/null || { echo "Ferramenta ausente: $cmd" >&2; exit 1; }; done
export GPG_TTY=$(tty)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
p="$tmp/payload"
mkdir "$p"
if [[ "$mode" == codespace ]]; then
 git -C "$repo" fetch origin --tags '+refs/heads/*:refs/remotes/origin/*'
 [[ -s "$private/backup/charles-release.p12" && -s "$private/backup/certificate.sha256" ]] || { echo 'Chave original ou fingerprint nao localizada.' >&2; exit 1; }
 mkdir "$p/signing" "$p/apks"
 cp -p "$private/backup/charles-release.p12" "$private/backup/certificate.sha256" "$p/signing/"
 for v in 2 4; do
  apk=$(find "$private/output" -type f -name "Charles-Phone-MCP-0.19.1-tablet.$v.apk" -print -quit)
  [[ -n "$apk" && -s "$apk" ]] || { echo "APK tablet.$v ausente." >&2; exit 1; }
  d=$(dirname "$apk"); mkdir "$p/apks/tablet.$v"
  cp -p "$apk" "$p/apks/tablet.$v/"
  for f in SHA256SUMS.txt verification.json SOURCE_COMMIT.txt LOCAL_TLS_CERT_SHA256.txt; do
   if [[ -f "$d/$f" ]]; then cp -p "$d/$f" "$p/apks/tablet.$v/"; fi
  done
  [[ -s "$p/apks/tablet.$v/SHA256SUMS.txt" ]] || { echo 'Manifesto de checksum do APK ausente.' >&2; exit 1; }
  (cd "$p/apks/tablet.$v" && sha256sum -c SHA256SUMS.txt)
 done
else
 mkdir "$p/local" "$p/tls"
 for f in local.crt local.key; do
  [[ -s "$HOME/charles-hub/tls/$f" ]] || { echo "TLS ausente: $f" >&2; exit 1; }
  cp -p "$HOME/charles-hub/tls/$f" "$p/tls/"
 done
 for f in "$repo/server/hub-read-renew.mjs" "$HOME/charles-hub/tunnel/recover-tunnel.sh"; do
  if [[ -f "$f" ]]; then cp -p "$f" "$p/local/"; fi
 done
 if command -v pkg >/dev/null; then pkg list-installed > "$p/termux-packages.txt" 2>/dev/null || true; fi
 if command -v getprop >/dev/null; then
  for prop in ro.product.model ro.product.device ro.build.version.release ro.build.version.sdk ro.build.display.id ro.build.version.security_patch ro.bootloader; do printf '%s=' "$prop"; getprop "$prop"; done > "$p/device.txt"
 fi
fi
git -C "$repo" bundle create "$p/phone-mcp.bundle" --all
git -C "$repo" bundle verify "$p/phone-mcp.bundle"
git -C "$repo" rev-parse HEAD > "$p/HEAD.txt"
git -C "$repo" diff --binary HEAD > "$p/tracked-changes.patch"
git -C "$repo" ls-files --others --exclude-standard > "$p/untracked-names.txt"
printf '%s\n' 'Backup seletivo. Nao restaure tokens antigos nem arquivos .env. Gere novas credenciais e revalide o pareamento. Chave de assinatura e TLS sao privadas; nao envie ao chat.' > "$p/RESTORE.txt"
(cd "$p" && find . -type f ! -name SHA256SUMS.backup -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS.backup)
tar -czf "$tmp/payload.tar.gz" -C "$p" .
out="$dest/Charles-PreROM-$mode-$(date +%Y%m%d-%H%M%S).tar.gz.gpg"
[[ ! -e "$out" ]]
printf '\nDefina uma senha forte para o backup. Guarde fora do tablet; nao use o chat.\n'
gpg --pinentry-mode loopback --symmetric --cipher-algo AES256 --output "$out" "$tmp/payload.tar.gz"
mkdir "$tmp/verify"
gpg --pinentry-mode loopback --decrypt "$out" | tar -xzf - -C "$tmp/verify"
(cd "$tmp/verify" && sha256sum -c SHA256SUMS.backup)
git -C "$repo" bundle verify "$tmp/verify/phone-mcp.bundle"
(cd "$dest" && sha256sum "$(basename "$out")" > "$(basename "$out").sha256")
printf '\nBACKUP LOCAL VALIDADO: %s\n' "$out"
printf '%s\n' 'Copie .gpg e .sha256 para dois destinos fora do tablet. Confira o SHA-256. Ainda nao formate.'
