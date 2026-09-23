#!/bin/sh
# Builds the Audio effects page harness for the simulator: Shared/JamesDSP's page, the Settings/ framework
# and JamesDSPSettings.m as they are in the tweak, stubs.m for the engine.
set -e
SRC=$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)
OUT=$(dirname "$0")/build
rm -rf "$OUT"; mkdir -p "$OUT/JamesDSPHarness.app"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -I"$SRC/Shared/JamesDSP" -isysroot "$SDK" -Wall -Wno-deprecated-declarations \
    "$(dirname "$0")/main.m" "$(dirname "$0")/stubs.m" \
    "$SRC"/Shared/JamesDSP/JamesDSPSettings.m "$SRC"/Shared/JamesDSP/JamesDSPPage.m \
    "$SRC"/Shared/JamesDSP/SGDSPCurveView.m "$SRC"/Shared/JamesDSP/JamesDSPLibraryPage.m \
    "$SRC"/Settings/SGPage.m "$SRC"/Settings/SGPageStyle.m "$SRC"/Settings/SGModPage.m "$SRC"/Settings/SGGlowSwitch.m \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGViewTree.m "$SRC"/Core/SGFlagForce.m "$SRC"/Core/SGUIMode.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework UniformTypeIdentifiers -framework Foundation \
    -o "$OUT/JamesDSPHarness.app/JamesDSPHarness"

cat > "$OUT/JamesDSPHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>JamesDSPHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.jamesdspharness</string>
<key>CFBundleName</key><string>JamesDSPHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
</dict>
</dict></plist>
PLIST
echo "built $OUT/JamesDSPHarness.app"
