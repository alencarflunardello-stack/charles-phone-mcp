#!/usr/bin/env python3
"""Audit installation and isolated-session requirements separately. No device access."""
import argparse
import json
import re
from pathlib import Path

CLASSES = ("SessionEngineManager.java", "VirtualEngine.java")

def guard_min(source):
    matches = re.findall(r"Build\.VERSION\.SDK_INT\s*<\s*(\d+)", source)
    if not matches:
        raise ValueError("Explicit SDK guard not found; source audit required")
    return max(map(int, matches))

def audit(root, api):
    android = root / "android" / "app"
    gradle = (android / "build.gradle").read_text()
    m = re.search(r"\bminSdk\s+(\d+)", gradle)
    if not m:
        raise ValueError("minSdk not found")
    install_min = int(m.group(1))
    guards = {}
    for name in CLASSES:
        files = list((android / "src" / "main" / "java").rglob(name))
        if len(files) != 1:
            raise ValueError("Missing or ambiguous source: " + name)
        guards[name] = guard_min(files[0].read_text())
    minimum = max(guards.values())
    return {
        "device_api": api,
        "installation_min_api": install_min,
        "installation_sdk_eligible": api >= install_min,
        "separate_session_source_guards": guards,
        "separate_session_min_api": minimum,
        "separate_session_sdk_eligible": api >= minimum,
        "real_device_isolation_verified": False,
        "scope": "static lower bounds only; runtime isolation, vendor compatibility, owner permission and cleanup require separate real-device tests",
    }

def self_test():
    assert guard_min("if(Build.VERSION.SDK_INT<34)throw new Exception();") == 34
    assert guard_min("if(Build.VERSION.SDK_INT < 34){} if(Build.VERSION.SDK_INT < 35){}") == 35
    try:
        guard_min("if(true){}")
    except ValueError:
        pass
    else:
        raise AssertionError("Missing guard accepted")
    import tempfile
    with tempfile.TemporaryDirectory() as path:
        root = Path(path)
        a = root / "android/app"
        j = a / "src/main/java/fr/phonemcp"
        j.mkdir(parents=True)
        (a / "build.gradle").write_text("android { defaultConfig { minSdk 30 } }")
        for name in CLASSES:
            (j / name).write_text("if(Build.VERSION.SDK_INT<34)throw new Exception();")
        x = audit(root, 33)
        assert x["installation_sdk_eligible"] and not x["separate_session_sdk_eligible"]
        y = audit(root, 34)
        assert y["separate_session_sdk_eligible"] and not y["real_device_isolation_verified"]
        (j / CLASSES[1]).unlink()
        try:
            audit(root, 34)
        except ValueError:
            pass
        else:
            raise AssertionError("Missing source accepted")
    print("6 static compatibility cases passed")

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--root",type=Path,default=Path("."))
    p.add_argument("--device-api",type=int,default=33)
    p.add_argument("--require-separate",action="store_true")
    p.add_argument("--self-test",action="store_true")
    a=p.parse_args()
    if a.self_test:
        self_test()
        return 0
    try:
        report=audit(a.root,a.device_api)
        print(json.dumps(report,indent=2))
        return 1 if a.require_separate and not report["separate_session_sdk_eligible"] else 0
    except (OSError,ValueError) as e:
        print(json.dumps({"audit_error":str(e),"real_device_isolation_verified":False}))
        return 2

if __name__=="__main__":
    raise SystemExit(main())
