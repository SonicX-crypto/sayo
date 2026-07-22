#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP_NAME="Sayo.app"
SOURCE_APP="$SCRIPT_DIR/dist/$APP_NAME"
TARGET_APP="/Applications/$APP_NAME"
LEGACY_APP="/Applications/Локальная диктовка.app"
STABLE_SIGNING_HASH="B8E2488B2F71C744DB0490CAC7BD009ED540BADC"
SIGNING_IDENTITY="${SAYO_SIGNING_IDENTITY:-${VOXCOMMAND_SIGNING_IDENTITY:-$STABLE_SIGNING_HASH}}"

if ! security find-identity -v -p codesigning 2>/dev/null | /usr/bin/grep -Fq "$SIGNING_IDENTITY"; then
    echo "Ошибка: code-signing identity '$SIGNING_IDENTITY' не найдена." >&2
    echo "Установка отменена до изменения работающей Sayo, чтобы сохранить разрешения macOS." >&2
    exit 1
fi

"$SCRIPT_DIR/build-app.sh"
codesign --verify --deep --strict --verbose=2 "$SOURCE_APP"

pkill -f RightCommandDictation 2>/dev/null || true
pkill -f 'whisper-server.*18080' 2>/dev/null || true

ditto "$SOURCE_APP" "$TARGET_APP"
codesign --verify --deep --strict "$TARGET_APP"
if [[ -d "$LEGACY_APP" ]]; then
    rm -rf "$LEGACY_APP"
fi
open "$TARGET_APP"

echo "Установлено: $TARGET_APP"
