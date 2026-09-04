# Сторонние компоненты

Sayo не включает перечисленные ниже компоненты в Git-репозиторий или приложение.
Скрипт настройки устанавливает или загружает их из официальных источников.

## Whisper и модель Large v2

- исходный проект и веса: [OpenAI Whisper](https://github.com/openai/whisper), MIT;
- формат GGML и официальный файл `ggml-large-v2.bin`:
  [whisper.cpp](https://github.com/ggerganov/whisper.cpp), MIT;
- источник файла:
  [ggerganov/whisper.cpp на Hugging Face](https://huggingface.co/ggerganov/whisper.cpp/blob/main/ggml-large-v2.bin);
- SHA-256: `9a423fe4d40c82774b6af34115b8b935f34152246eb19e80e376071d3f999487`.

## ffmpeg

Sayo вызывает установленный отдельно `ffmpeg` для локального преобразования аудио.
Условия зависят от конкретной сборки и включённых библиотек. Подробности:
[ffmpeg.org/legal.html](https://ffmpeg.org/legal.html).
