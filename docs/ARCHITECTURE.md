# Архитектура VoxCommand

## Поток данных

```text
правый ⌘
   ↓
CGEventTap → AVAudioEngine → временный CAF
   ↓
ffmpeg → WAV 16 кГц mono
   ↓
whisper-server (127.0.0.1:18080, Metal GPU, Whisper Large)
   ↓
очистка текста → NSPasteboard → синтетический ⌘V
   ↓
локальная история в UserDefaults
```

## Основные компоненты

`Sources/main.swift` пока содержит приложение целиком:

- `DictationController` — жизненный цикл, меню, разрешения и orchestration;
- `RecordingHUD` — плавающий статус записи и распознавания;
- `CGEventTap` — правый Command и `Esc` во время записи;
- `AVAudioEngine` — запись исходного аудио;
- `whisper-server` — постоянная загрузка 3,1-ГБ модели и локальный HTTP inference;
- fallback на `whisper-cli`, если сервер недоступен.

## Хранение данных

- временные записи: системная temporary directory, удаляются после обработки;
- история: `UserDefaults`, ключ `transcriptHistory`, максимум 12 элементов;
- автovставка: `UserDefaults`, ключ `autoPaste`;
- положение HUD: `hudOriginX` и `hudOriginY`;
- модель: внешняя, только чтение.

## Безопасность и приватность

- сервер привязан к loopback-интерфейсу;
- внешних API и аналитики нет;
- исходное аудио удаляется и не сохраняется в историю;
- текст хранится только локально в UserDefaults и системном clipboard.

## Известные ограничения

- первая загрузка модели занимает память и короткое время после старта;
- ad-hoc подпись может потребовать повторного разрешения TCC после сборки;
- исходник монолитный; при росте проекта его следует разделить на App, Audio,
  Transcription, HUD, Preferences и History;
- порт 18080 фиксирован, при конфликте происходит fallback на CLI.

