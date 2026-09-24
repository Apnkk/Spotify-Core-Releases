#!/usr/bin/env python3
"""Patches Spotify's LaunchScreen storyboard and adds custom Ares launch images to the IPA."""
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile
from PIL import Image

if len(sys.argv) < 3:
    print(f"Usage: {sys.argv[0]} <ipa> <app_dir> [logo_path]", file=sys.stderr)
    sys.exit(1)

ipa = sys.argv[1]
app_dir = sys.argv[2]
if not app_dir.endswith("/"):
    app_dir += "/"

script_dir = os.path.dirname(os.path.abspath(__file__))
default_logo = os.path.join(script_dir, "..", "icons", "spotify_logo_01.png")
logo_path = sys.argv[3] if len(sys.argv) > 3 and os.path.exists(sys.argv[3]) else default_logo

if not os.path.exists(logo_path):
    print(f"Error: logo file not found: {logo_path}", file=sys.stderr)
    sys.exit(1)

nib_rel_path = f"{app_dir}LaunchScreen.storyboardc/01J-lp-oVM-view-MkI-aN-x20.nib"

with zipfile.ZipFile(ipa, 'r') as z:
    if nib_rel_path not in z.namelist():
        print(f"Warning: {nib_rel_path} not found in {ipa}, skipping launchscreen patch.")
        sys.exit(0)
    raw_nib = bytearray(z.read(nib_rel_path))

# In 01J-lp-oVM-view-MkI-aN-x20.nib, the image resource name is 'Default'.
# Replacing 'Default' with 'AresLog' keeps the exact same byte length (7 characters).
patched = False
pos = raw_nib.find(b'Default')
if pos != -1:
    raw_nib[pos:pos+7] = b'AresLog'
    patched = True
    print(f"    Replaced 'Default' with 'AresLog' in {nib_rel_path}")

img = Image.open(logo_path).convert("RGBA")

with tempfile.TemporaryDirectory() as tmp:
    files_to_inject = []

    if patched:
        nib_dest = os.path.join(tmp, nib_rel_path)
        os.makedirs(os.path.dirname(nib_dest), exist_ok=True)
        with open(nib_dest, "wb") as f:
            f.write(raw_nib)
        files_to_inject.append(nib_rel_path)

    # Generate AresLog and Default images at 1x (115), 2x (230), and 3x (345)
    image_specs = [
        ("AresLog.png", 115),
        ("AresLog@2x.png", 230),
        ("AresLog@3x.png", 345),
        ("Default.png", 115),
        ("Default@2x.png", 230),
        ("Default@3x.png", 345),
    ]

    for name, sz in image_specs:
        rel_img_path = f"{app_dir}{name}"
        dest_path = os.path.join(tmp, rel_img_path)
        os.makedirs(os.path.dirname(dest_path), exist_ok=True)
        resized = img.resize((sz, sz), Image.Resampling.LANCZOS)
        resized.save(dest_path, "PNG")
        files_to_inject.append(rel_img_path)

    if shutil.which("zip"):
        subprocess.run(["zip", "-q", os.path.abspath(ipa)] + files_to_inject, cwd=tmp, check=True)
    else:
        # Fallback using zipfile if zip executable is not present
        tmp_ipa = ipa + ".tmp.zip"
        with zipfile.ZipFile(ipa, 'r') as zin, zipfile.ZipFile(tmp_ipa, 'w', compression=zipfile.ZIP_DEFLATED) as zout:
            inject_map = {p: os.path.join(tmp, p) for p in files_to_inject}
            for p, local_path in inject_map.items():
                zout.write(local_path, p)
            for item in zin.infolist():
                if item.filename not in inject_map:
                    zout.writestr(item, zin.read(item.filename))
        os.replace(tmp_ipa, ipa)

print(f"    Injected Ares launch screen images and patched storyboard in {ipa}")
