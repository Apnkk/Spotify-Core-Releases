#!/usr/bin/env python3
"""Ensures CFBundleIcons and CFBundleIcons~ipad in Info.plist include all alternate icons."""
import os
import plistlib
import subprocess
import sys
import tempfile
import zipfile

if len(sys.argv) < 3:
    print(f"Usage: {sys.argv[0]} <ipa> <app_dir>", file=sys.stderr)
    sys.exit(1)

ipa = sys.argv[1]
app_dir = sys.argv[2]
plist_path = f"{app_dir}Info.plist"

with zipfile.ZipFile(ipa, 'r') as z:
    if plist_path not in z.namelist():
        print(f"Error: {plist_path} not found in {ipa}", file=sys.stderr)
        sys.exit(1)
    raw_data = z.read(plist_path)

plist = plistlib.loads(raw_data)

# Ensure CFBundleIcons and CFBundleIcons~ipad exist
for key in ["CFBundleIcons", "CFBundleIcons~ipad"]:
    if key not in plist or not isinstance(plist[key], dict):
        plist[key] = {}
    if "CFBundleAlternateIcons" not in plist[key] or not isinstance(plist[key]["CFBundleAlternateIcons"], dict):
        plist[key]["CFBundleAlternateIcons"] = {}

    alt_dict = plist[key]["CFBundleAlternateIcons"]
    for i in range(1, 18):
        icon_name = f"spotify_logo_{i:02d}"
        alt_dict[icon_name] = {
            "CFBundleIconFiles": [icon_name],
            "UIPrerenderedIcon": True
        }

with tempfile.TemporaryDirectory() as tmp:
    out_plist_dir = os.path.join(tmp, os.path.dirname(plist_path))
    os.makedirs(out_plist_dir, exist_ok=True)
    out_plist_path = os.path.join(tmp, plist_path)
    with open(out_plist_path, "wb") as f:
        plistlib.dump(plist, f)
    subprocess.run(["zip", "-q", os.path.abspath(ipa), plist_path], cwd=tmp, check=True)

print(f"    Injected 17 alternate icons into {plist_path}")
