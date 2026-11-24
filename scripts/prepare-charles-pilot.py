#!/usr/bin/env python3
"""Prepare a side-by-side pilot APK; run from repository root in a clean CI checkout."""
from pathlib import Path
old, new = "fr.phonemcp", "br.charles.phonemcp"
android = Path("android")
for path in android.rglob("*"):
    if not path.is_file() or path.suffix not in {".java",".aidl",".xml",".gradle",".properties",".kt",".json",".pro",".md",".txt"}:
        continue
    if any(part in {".gradle","build"} for part in path.parts): continue
    raw = path.read_text(encoding="utf-8")
    updated = raw.replace(old,new)
    if path.name == "AndroidManifest.xml":
        updated = updated.replace('android:label="Phone MCP"', 'android:label="Charles Phone MCP (Pilot)"').replace('android:scheme="phonemcp"', 'android:scheme="charlesphonemcp"')
    updated = updated.replace("phonemcp://pair", "charlesphonemcp://pair")
    if path.suffix == ".java":
        updated = updated.replace('"phonemcp".equals(', '"charlesphonemcp".equals(')
    if updated != raw: path.write_text(updated,encoding="utf-8")
for path in sorted(android.rglob("phonemcp"),key=lambda p:len(p.parts),reverse=True):
    if path.is_dir() and path.parent.name == "fr":
        dest = path.parent.parent / "br" / "charles" / "phonemcp"
        dest.parent.mkdir(parents=True,exist_ok=True)
        if dest.exists(): raise RuntimeError(f"Destination exists: {dest}")
        path.rename(dest)
for path in Path("server/src").rglob("*.js"):
    raw=path.read_text(encoding="utf-8")
    updated=raw.replace("phonemcp://pair","charlesphonemcp://pair")
    if raw!=updated:path.write_text(updated,encoding="utf-8")
assert "applicationId 'br.charles.phonemcp'" in Path("android/app/build.gradle").read_text()
print("Pilot package identity prepared. Never use this APK to replace the original.")
