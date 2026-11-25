#!/usr/bin/env bash
set -euo pipefail
umask 077
cd /workspaces/charles-phone-mcp
export CHARLES_LOCAL_TLS_SHA256=a39fe7663e39fcbf0e527df5d32594dc7f07949b5859844f625d89c21bcd1a24
apk=$(find /workspaces/charles-owner-private/output -name 'Charles-Phone-MCP-0.19.1-tablet.2.apk' -print -quit)
test -n "$apk"
f=$(mktemp)
trap 'rm -f -- "$f"' EXIT
git show 683296fab768d57e93320d15dc5dee900ba1c67e:scripts/owner-build-api33-probe.sh > "$f"
CHARLES_LOCAL_TLS_PUBLIC_CERT=$(python3 - "$apk" <<'PY'
import zipfile, hashlib, base64, re, os, sys
expected=os.environ['CHARLES_LOCAL_TLS_SHA256']
with zipfile.ZipFile(sys.argv[1]) as z:
    for e in z.infolist():
        if e.is_dir() or not 256 <= e.file_size <= 65536: continue
        b=z.read(e)
        candidates=[b]
        for m in re.finditer(rb'-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----',b,re.S):
            try: candidates.append(base64.b64decode(re.sub(rb'\s+',b'',m[1]),validate=True))
            except ValueError: pass
        for der in candidates:
            if hashlib.sha256(der).hexdigest()==expected:
                print(base64.b64encode(der).decode()); sys.exit(0)
raise SystemExit('Certificado original nao localizado; compilacao cancelada.')
PY
)
test -n "$CHARLES_LOCAL_TLS_PUBLIC_CERT"
export CHARLES_LOCAL_TLS_PUBLIC_CERT
python3 - "$f" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); s=p.read_text()
marker="(p/'build.sh').write_text(s)"
a='read -r -p "Certificado PUBLICO DER em base64 (uma linha): " public_cert'
b='public_cert="${CHARLES_LOCAL_TLS_PUBLIC_CERT:?}"'
assert s.count(marker)==1
p.write_text(s.replace(marker, f'change({a!r},{b!r})\n'+marker))
PY
bash -n "$f"
echo 'Certificado original localizado e conferido.'
bash "$f"
