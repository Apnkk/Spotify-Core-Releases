#!/bin/sh
# Builds the JamesDSP harness for the Mac: SGDSPEngine.m as the tweak compiles it, over the Mac build of
# libjamesdsp (vendor/libjamesdsp, made here first), and main.m.
#   ./build.sh            build/jamesdsp
#   ./build.sh thread     build/jamesdsp-thread, the engine and the library under ThreadSanitizer
#   ./build.sh address    build/jamesdsp-address, under AddressSanitizer
set -e
cd "$(dirname "$0")"
VENDOR=../../vendor/libjamesdsp
SANITIZE=$1
make -s -C "$VENDOR" JDSP_PLATFORM=mac ${SANITIZE:+JDSP_SANITIZE=$SANITIZE} -j8
LIB="$VENDOR/build/mac${SANITIZE:+-$SANITIZE}/libjamesdsp.a"
OUT=build/jamesdsp${SANITIZE:+-$SANITIZE}
mkdir -p build
xcrun clang -fobjc-arc -O2 -g -Wall -Werror -target arm64-apple-macos13.0 ${SANITIZE:+-fsanitize=$SANITIZE -O1 -fno-omit-frame-pointer} \
    -I ../../tweak/Sources -isystem "$VENDOR/subtree/Main/libjamesdsp/jni/jamesdsp/jdsp" -isystem "$VENDOR" \
    main.m ../../tweak/Sources/Shared/JamesDSP/SGDSPEngine.m "$LIB" \
    -framework Foundation -framework AudioToolbox -o "$OUT"
echo "built $OUT"
