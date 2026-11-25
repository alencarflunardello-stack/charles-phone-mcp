#!/usr/bin/env python3
"""Inspect an APK against independently supplied certificate and file digests."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path

def digest(value):
    value = value.replace(":", "").strip().lower()
    if not re.fullmatch(r"[a-f0-9]{64}", value):
        raise ValueError("Invalid SHA-256 digest")
    return value

def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=120).stdout

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--apk", required=True, type=Path)
    p.add_argument("--apk-sha256", required=True)
    p.add_argument("--cert-sha256", required=True)
    p.add_argument("--aapt", required=True)
    p.add_argument("--apksigner", required=True)
    p.add_argument("--package", default="br.charles.phonemcp")
    p.add_argument("--version", default="0.19.1")
    p.add_argument("--version-code", type=int, default=70)
    p.add_argument("--device-api", type=int, default=33)
    a = p.parse_args()
    try:
        with a.apk.open("rb") as f:
            actual_hash = hashlib.file_digest(f, "sha256").hexdigest()
        b = run(a.aapt, "dump", "badging", str(a.apk))
        c = run(a.apksigner, "verify", "--print-certs", "--min-sdk-version", str(a.device_api), str(a.apk))
        pkg = next((line for line in b.splitlines() if line.startswith("package: ")), "")
        def field(k):
            m = re.search(r"(?:^|\s)" + k + r"='([^']*)'", pkg)
            return m.group(1) if m else None
        min_sdk = re.search(r"^sdkVersion:'(\d+)'", b, re.M)
        max_sdk = re.search(r"^maxSdkVersion:'(\d+)'", b, re.M)
        signers = [digest(s) for s in re.findall(r"^Signer #\d+ certificate SHA-256 digest:\s*([a-fA-F0-9:]+)\s*$", c, re.M)]
        checks = {
            "apk_digest": actual_hash == digest(a.apk_sha256),
            "package": field("name") == a.package,
            "version": field("versionName") == a.version,
            "version_code": field("versionCode") == str(a.version_code),
            "min_sdk": min_sdk is not None and 1 <= int(min_sdk.group(1)) <= a.device_api,
            "max_sdk": max_sdk is None or int(max_sdk.group(1)) >= a.device_api,
            "certificate": signers == [digest(a.cert_sha256)],
            "not_debuggable": not bool(re.search(r"^application-debuggable\b", b, re.M)),
            "not_debug_certificate": not bool(re.search(r"^Signer #\d+ certificate DN:.*(?:CN=Android Debug|O=Android Debug)", c, re.M | re.I)),
            "no_audio_permission": "android.permission.RECORD_AUDIO" not in b,
        }
        passed = all(checks.values())
        print(json.dumps({"passed": passed, "checks": checks, "apk_sha256": actual_hash, "certificates": signers, "package": field("name"), "version": field("versionName"), "version_code": field("versionCode"), "min_sdk": int(min_sdk.group(1)) if min_sdk else None, "device_api": a.device_api}))
        return 0 if passed else 1
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        print(json.dumps({"passed": False, "error": type(exc).__name__}))
        return 2

if __name__ == "__main__":
    raise SystemExit(main())
