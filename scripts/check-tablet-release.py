#!/usr/bin/env python3
"""Fail-closed source metadata gate. No device, network or signing-key access."""
import argparse
import json
import re
from pathlib import Path

def inspect(root):
    def read(path):
        return (root / path).read_text(encoding="utf-8")
    def field(text, name):
        m = re.search(r"\b" + name + r"\s+['\"]?([^\s'\"]+)", text)
        return m.group(1) if m else None
    root_pkg = json.loads(read("package.json"))
    server = json.loads(read("server/package.json"))
    lock = json.loads(read("server/package-lock.json"))
    gradle = read("android/app/build.gradle")
    manifest = read("android/app/src/main/AndroidManifest.xml")
    version = re.search(r"\bVERSION\s*=\s*['\"]([^'\"]+)['\"]", read("server/src/version.js"))
    return {
        "root": root_pkg.get("version"),
        "server": server.get("version"),
        "lock": lock.get("version"),
        "lock_root": lock.get("packages", {}).get("", {}).get("version"),
        "runtime": version.group(1) if version else None,
        "android": field(gradle, "versionName"),
        "version_code": field(gradle, "versionCode"),
        "min_sdk": field(gradle, "minSdk"),
        "package": field(gradle, "applicationId"),
        "debug_signing": bool(re.search(r"signingConfig\s+signingConfigs\.debug\b", gradle)),
        "owner_signing_config": ("signingConfig signingConfigs.tabletRelease" in gradle and "CHARLES_RELEASE_KEYSTORE" in gradle and "Release signing is not configured" in gradle),
        "microphone_permission": "android.permission.RECORD_AUDIO" in manifest,
        "cleartext_disabled": 'android:usesCleartextTraffic="false"' in manifest,
    }

def validate(data, expected_version, expected_code, device_api, package, android_version=None):
    errors = []
    for field in ("root", "server", "lock", "lock_root", "runtime", "android"):
        if data.get(field) != (android_version if field == "android" and android_version else expected_version):
            errors.append(field + ": version mismatch")
    if data.get("version_code") != str(expected_code):
        errors.append("version code mismatch")
    try:
        if not 1 <= int(data["min_sdk"]) <= device_api:
            errors.append("SDK incompatible")
    except (KeyError, ValueError, TypeError):
        errors.append("SDK missing or invalid")
    if data.get("package") != package:
        errors.append("package mismatch")
    if data.get("debug_signing") is not False:
        errors.append("debug signing or unknown signing configuration")
    if data.get("owner_signing_config") is not True:
        errors.append("owner release signing configuration missing")
    if data.get("microphone_permission") is not False:
        errors.append("microphone permission present or unknown")
    if data.get("cleartext_disabled") is not True:
        errors.append("cleartext policy missing or unknown")
    return errors

def self_test():
    good = dict.fromkeys(("root", "server", "lock", "lock_root", "runtime", "android"), "0.19.1")
    good.update(version_code="70", min_sdk="30", package="br.charles.phonemcp", debug_signing=False, owner_signing_config=True, microphone_permission=False, cleartext_disabled=True)
    tests = [({}, True)]
    tests += [({k: "bad"}, False) for k in ("root","server","lock","lock_root","runtime","android","version_code","min_sdk","package")]
    tests += [({"min_sdk":"34"},False),({"debug_signing":True},False),({"microphone_permission":True},False),({"cleartext_disabled":False},False),({"debug_signing":None},False),({"owner_signing_config":False},False)]
    for change, expected in tests:
        actual = not validate({**good, **change}, "0.19.1", 70, 33, "br.charles.phonemcp")
        if actual != expected:
            raise RuntimeError("Synthetic test failed: " + str(change))
    print(json.dumps({"self_tests_passed":len(tests),"scope":"synthetic validation only"}))

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--root", type=Path, default=Path("."))
    p.add_argument("--version", default="0.19.1")
    p.add_argument("--android-version", default="0.19.1-tablet.1")
    p.add_argument("--version-code", type=int, default=71)
    p.add_argument("--device-api", type=int, default=33)
    p.add_argument("--package", default="br.charles.phonemcp")
    p.add_argument("--self-test", action="store_true")
    a = p.parse_args()
    if a.self_test:
        self_test()
        return 0
    try:
        data = inspect(a.root)
        errors = validate(data, a.version, a.version_code, a.device_api, a.package, a.android_version)
        print(json.dumps({"source_gate_passed":not errors,"observed":data,"errors":errors,"real_apk_verified":False}))
        return int(bool(errors))
    except (OSError, ValueError, TypeError, KeyError) as e:
        print(json.dumps({"source_gate_passed":False,"error":type(e).__name__}))
        return 2

if __name__ == "__main__":
    raise SystemExit(main())
