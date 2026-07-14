#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"

SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
CACHE="/private/tmp/right-command-dictation-module-cache"
mkdir -p "$SCRIPT_DIR/.build/release" "$CACHE"

# Compile directly so the app also builds in restricted shells where SwiftPM's
# nested sandbox cannot start. The 15.4 SDK is intentionally selected because
# it is compatible with the Command Line Tools currently installed on this Mac.
CLANG_MODULE_CACHE_PATH="$CACHE" swiftc \
    "$SCRIPT_DIR/Sources/main.swift" \
    -o "$SCRIPT_DIR/.build/release/RightCommandDictation" \
    -O \
    -sdk "$SDK" \
    -target arm64-apple-macosx13.0 \
    -module-cache-path "$CACHE" \
    -framework AppKit \
    -framework ApplicationServices \
    -framework AVFoundation

APP_DIR="$SCRIPT_DIR/dist/Локальная диктовка.app"
CONTENTS="$APP_DIR/Contents"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$SCRIPT_DIR/.build/release/RightCommandDictation" "$CONTENTS/MacOS/RightCommandDictation"
cp "$SCRIPT_DIR/Info.plist" "$CONTENTS/Info.plist"
cp "$SCRIPT_DIR/Assets/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
