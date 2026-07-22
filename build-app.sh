#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"

SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
CACHE="/private/tmp/right-command-dictation-module-cache"
mkdir -p "$SCRIPT_DIR/.build/release" "$CACHE"

SIGNING_IDENTITY="${SAYO_SIGNING_IDENTITY:-${VOXCOMMAND_SIGNING_IDENTITY:-VoxCommand Local Development}}"
HAS_STABLE_SIGNING_IDENTITY=0
if security find-identity -v -p codesigning 2>/dev/null | /usr/bin/grep -Fq "\"$SIGNING_IDENTITY\""; then
    HAS_STABLE_SIGNING_IDENTITY=1
elif [[ "${SAYO_ALLOW_ADHOC_SIGNING:-0}" != "1" ]]; then
    echo "Ошибка: code-signing identity '$SIGNING_IDENTITY' не найдена." >&2
    echo "Сборка остановлена, чтобы не заменить стабильную подпись Sayo и не сбросить разрешения macOS." >&2
    echo "Для отдельной тестовой сборки можно явно указать SAYO_ALLOW_ADHOC_SIGNING=1." >&2
    exit 1
fi

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

APP_DIR="$SCRIPT_DIR/dist/Sayo.app"
LEGACY_APP_DIR="$SCRIPT_DIR/dist/Локальная диктовка.app"
CONTENTS="$APP_DIR/Contents"
rm -rf "$APP_DIR"
rm -rf "$LEGACY_APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$SCRIPT_DIR/.build/release/RightCommandDictation" "$CONTENTS/MacOS/RightCommandDictation"
cp "$SCRIPT_DIR/Info.plist" "$CONTENTS/Info.plist"
cp "$SCRIPT_DIR/Assets/SayoAppIcon.icns" "$CONTENTS/Resources/SayoAppIcon.icns"
cp "$SCRIPT_DIR/Assets/Themes/cosmos-orb-512.png" "$CONTENTS/Resources/cosmos-orb-512.png"
cp "$SCRIPT_DIR/Assets/Themes/mascot-orb-512.png" "$CONTENTS/Resources/mascot-orb-512.png"

if [[ "$HAS_STABLE_SIGNING_IDENTITY" == "1" ]]; then
    codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_DIR"
    echo "Подпись: $SIGNING_IDENTITY"
else
    codesign --force --deep --sign - "$APP_DIR"
    echo "Предупреждение: создана только тестовая ad-hoc сборка. Устанавливать её поверх Sayo нельзя."
fi
echo "$APP_DIR"
