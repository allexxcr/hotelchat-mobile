# HotelChat Mobile 1.0.2

Полный исправленный Flutter-проект для автоматической сборки Android APK через GitHub Actions.

## Что исправлено

- исправлена синтаксическая ошибка в `HomeScreen.load`;
- стандартный Flutter-тест больше не мешает анализу;
- workflow использует актуальные версии GitHub Actions;
- Android-проект создаётся автоматически;
- package ID принудительно устанавливается в `online.ognispb.hotelchat`;
- название приложения устанавливается в `HotelChat`;
- минимальная версия Android устанавливается в SDK 23;
- разрешение доступа в интернет проверяется автоматически;
- перед сборкой выполняется статический анализ;
- готовый APK, SHA-256 и информация о сборке публикуются в Artifacts.

## Как загрузить

Распакуйте архив и загрузите **содержимое этой папки** в корень репозитория GitHub.

В корне GitHub должны быть видны:

```text
.github
lib
tool
pubspec.yaml
analysis_options.yaml
README.md
VERSION
```

После Commit changes сборка запустится автоматически.

## Как скачать APK

```text
Actions
→ Build HotelChat Android APK
→ зелёный запуск
→ Artifacts
→ HotelChat-Mobile-APK-N
```

## Сервер

Перед входом приложение ожидает API:

```text
https://ognispb.online/api/mobile/v1/index.php?route=health
```

## Подпись APK

Первая версия подходит для тестовой ручной установки. Автоматические обновления поверх уже установленной версии потребуют постоянного закрытого ключа подписи в GitHub Secrets.
