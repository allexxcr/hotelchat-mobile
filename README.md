# HotelChat Mobile 1.1.2 — Firebase Self-Copy

Исправляет ошибку:

```text
ERROR: android/app/google-services.json is missing
```

## Причина

В репозитории обновился `tool/configure_android.py`, но скрытый workflow
`.github/workflows/build-apk.yml` остался от старой версии и не скопировал
Firebase-конфигурацию в Android-проект.

## Исправление

Версия 1.1.2 хранит Firebase-конфигурацию сразу в двух местах:

- `firebase/google-services.json`;
- `google-services.json`.

Скрипт `tool/configure_android.py` сам находит конфигурацию и копирует её в:

```text
android/app/google-services.json
```

Поэтому сборка больше не зависит от команды копирования внутри workflow.

## Загрузка

Загрузите всё содержимое архива в корень репозитория с заменой файлов.
Особенно важны:

- `tool/configure_android.py`;
- `firebase/google-services.json`;
- `google-services.json`;
- `.github/workflows/build-apk.yml`.
