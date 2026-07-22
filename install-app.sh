#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP_NAME="Sayo.app"
SOURCE_APP="$SCRIPT_DIR/dist/$APP_NAME"
TARGET_APP="/Applications/$APP_NAME"
LEGACY_APP="/Applications/Локальная диктовка.app"

"$SCRIPT_DIR/build-app.sh"

pkill -f RightCommandDictation 2>/dev/null || true
pkill -f 'whisper-server.*18080' 2>/dev/null || true

ditto "$SOURCE_APP" "$TARGET_APP"
codesign --verify --deep --strict "$TARGET_APP"
if [[ -d "$LEGACY_APP" ]]; then
    rm -rf "$LEGACY_APP"
fi
open "$TARGET_APP"

echo "Установлено: $TARGET_APP"
