#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"

FORMULAE=()
[[ -x /opt/homebrew/bin/ffmpeg || -x /usr/local/bin/ffmpeg ]] || FORMULAE+=(ffmpeg)
[[ -x /opt/homebrew/bin/whisper-server || -x /usr/local/bin/whisper-server ]] \
    || FORMULAE+=(whisper-cpp)

if (( ${#FORMULAE[@]} > 0 )); then
    if ! command -v brew >/dev/null 2>&1; then
        echo "Для автоматической установки нужен Homebrew: https://brew.sh/ru/" >&2
        echo "Установите Homebrew и запустите этот скрипт ещё раз." >&2
        exit 1
    fi
    echo "Устанавливаю: ${FORMULAE[*]}"
    brew install "${FORMULAE[@]}"
else
    echo "ffmpeg и whisper.cpp уже установлены."
fi

SAYO_MODEL="$HOME/Library/Application Support/Sayo/Models/ggml-large-v2.bin"
SUPERWHISPER_MODEL="$HOME/Library/Application Support/superwhisper/ggml-large.bin"
if [[ -f "$SAYO_MODEL" ]]; then
    "$SCRIPT_DIR/download-model.sh"
elif [[ -f "$SUPERWHISPER_MODEL" ]]; then
    echo "Найдена совместимая модель Superwhisper: $SUPERWHISPER_MODEL"
    echo "Sayo будет использовать её без копирования."
else
    "$SCRIPT_DIR/download-model.sh"
fi

echo
echo "Компоненты Sayo готовы. Перенесите Sayo.app в /Applications и запустите её."
