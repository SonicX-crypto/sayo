# Sayo

Sayo — бесплатная локальная диктовка для macOS. Нажмите правый `⌘`, произнесите
текст и нажмите правый `⌘` ещё раз: расшифровка появится в буфере обмена и активном
поле. Аудио и текст не отправляются в интернет.

![macOS](https://img.shields.io/badge/macOS-13%2B-black)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## Установка

Sayo предназначена для Mac с Apple Silicon (M1 и новее) и macOS 13 или новее.

1. Скачайте последний `Sayo-…-macOS-arm64.dmg` на странице
   [Releases](https://github.com/SonicX-crypto/sayo/releases/latest).
2. В образе запустите `Install Sayo Components.command`. Скрипт установит через
   Homebrew `ffmpeg`, `whisper.cpp`, загрузит официальную Whisper Large v2 и проверит
   её SHA-256. Модель занимает около 3,1 ГБ.
3. Перетащите `Sayo.app` в `Applications`.
4. Откройте Sayo и разрешите доступ к микрофону и универсальному доступу.

Публичная preview-сборка пока не нотарифицирована Apple. При первом запуске macOS может
запросить подтверждение: откройте `Системные настройки` → `Конфиденциальность и
безопасность` и нажмите `Всё равно открыть`. Не отключайте Gatekeeper целиком.

Подробная инструкция и решение типичных проблем находятся в [INSTALL.md](INSTALL.md).

## Модель распознавания

Модель не хранится в Git: официальный полный файл больше 3 ГБ. Загрузчик получает
`ggml-large-v2.bin` напрямую из репозитория whisper.cpp на Hugging Face и сверяет
контрольную сумму:

```text
9a423fe4d40c82774b6af34115b8b935f34152246eb19e80e376071d3f999487
```

Основной путь:

```text
~/Library/Application Support/Sayo/Models/ggml-large-v2.bin
```

Если Superwhisper уже установил совместимый `ggml-large.bin`, Sayo найдёт его
автоматически и ничего копировать не потребуется.

Можно использовать другую совместимую GGML-модель whisper.cpp:

```sh
defaults write ru.specit.RightCommandDictation modelPath -string "/полный/путь/model.bin"
```

После изменения перезапустите Sayo. Вернуть автоматический выбор:

```sh
defaults delete ru.specit.RightCommandDictation modelPath
```

Происхождение и лицензии компонентов описаны в
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Возможности

- глобальная клавиша — правый `⌘`;
- полная Whisper Large v2 без квантования;
- Metal-ускорение на Apple Silicon;
- локальный `whisper-server`, слушающий только `127.0.0.1:18080`;
- светлый HUD «живая орбита» и темы `Стандартная`, `Космос`, `Маскот`;
- настройка формы, материала, цветов, размера, движения и контраста HUD;
- автоматическая вставка и локальная история последних 12 фраз;
- `Esc` для отмены записи;
- очередь восстановления неудачных записей;
- повторная расшифровка последней диктовки другим способом декодирования;
- health-check сервера и резервное распознавание через `whisper-cli`.

## Сборка из исходников

Требуются Xcode Command Line Tools. SwiftPM не обязателен: скрипт вызывает `swiftc`
напрямую.

```sh
git clone https://github.com/SonicX-crypto/sayo.git
cd sayo
./scripts/setup-dependencies.sh
SAYO_ALLOW_ADHOC_SIGNING=1 ./build-app.sh
```

Приложение появится в `dist/Sayo.app`. Для стабильной подписи укажите доступную
identity через `SAYO_SIGNING_IDENTITY`; для публичного распространения используйте
Developer ID Application и notarization.

Создать ZIP, DMG и файл контрольных сумм:

```sh
./scripts/package-release.sh
```

Артефакты появятся в `dist/releases`. Тег вида `v0.5.1` автоматически запускает
GitHub Actions и создаёт Release.

## Приватность

- аудио и расшифровки обрабатываются локально;
- внешних API, аккаунтов, телеметрии и аналитики нет;
- аудио последней распознанной диктовки хранится локально до следующей, чтобы её можно
  было расшифровать заново из меню; более ранние успешные записи удаляются;
- после ошибки запись остаётся в
  `~/Library/Application Support/Sayo/Recovery`, пока пользователь не повторит
  распознавание или не удалит её.

## Документация

- [INSTALL.md](INSTALL.md) — установка и устранение проблем;
- [PROJECT.md](PROJECT.md) — состояние продукта и важные решения;
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — устройство приложения;
- [.planning/ROADMAP.md](.planning/ROADMAP.md) — следующие улучшения;
- [CHANGELOG.md](CHANGELOG.md) — история изменений.

Sayo распространяется по лицензии [MIT](LICENSE).
