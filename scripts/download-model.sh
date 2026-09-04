#!/bin/zsh
set -euo pipefail

MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v2.bin?download=true"
MODEL_SHA256="9a423fe4d40c82774b6af34115b8b935f34152246eb19e80e376071d3f999487"
MODEL_DIR="${SAYO_MODEL_DIR:-$HOME/Library/Application Support/Sayo/Models}"
MODEL_PATH="$MODEL_DIR/ggml-large-v2.bin"
PARTIAL_PATH="$MODEL_PATH.part"

mkdir -p "$MODEL_DIR"

if [[ -f "$MODEL_PATH" ]]; then
    CURRENT_SHA256="$(shasum -a 256 "$MODEL_PATH" | awk '{print $1}')"
    if [[ "$CURRENT_SHA256" == "$MODEL_SHA256" ]]; then
        echo "Модель уже установлена: $MODEL_PATH"
        exit 0
    fi
    echo "Ошибка: существующая модель не прошла проверку SHA-256: $MODEL_PATH" >&2
    echo "Переместите её вручную и повторите команду." >&2
    exit 1
fi

echo "Загружаю Whisper Large v2 (около 3,1 ГБ)…"
curl --fail --location --continue-at - --progress-bar \
    "$MODEL_URL" \
    --output "$PARTIAL_PATH"

DOWNLOADED_SHA256="$(shasum -a 256 "$PARTIAL_PATH" | awk '{print $1}')"
if [[ "$DOWNLOADED_SHA256" != "$MODEL_SHA256" ]]; then
    echo "Ошибка: SHA-256 загруженной модели не совпадает с официальной." >&2
    echo "Ожидалось: $MODEL_SHA256" >&2
    echo "Получено:  $DOWNLOADED_SHA256" >&2
    exit 1
fi

mv "$PARTIAL_PATH" "$MODEL_PATH"
echo "Модель установлена: $MODEL_PATH"
