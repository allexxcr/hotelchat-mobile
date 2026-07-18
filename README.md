# HotelChat Mobile 1.1.3 — compileSdk 36

Исправляет ошибку сборки:

```text
Dependency 'androidx.core:core:1.18.0' requires compileSdk 36 or later.
:app is currently compiled against android-35.
```

## Изменения

- `compileSdk = 36`;
- `targetSdk = 35` оставлен без изменения;
- `minSdk = 23` оставлен без изменения;
- GitHub Actions явно устанавливает:
  - `platforms;android-36`;
  - `build-tools;36.0.0`;
  - `platform-tools`;
- сохранены Firebase, push-диагностика и исправление фотографий.

## Установка

Загрузите всё содержимое папки в корень существующего GitHub-репозитория,
подтвердите замену файлов и запустите:

```text
Actions → Build HotelChat Android APK
```

В журнале должна появиться строка:

```text
Android API 36 installed successfully
```
