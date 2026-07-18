# HotelChat Mobile 1.0

Полноценное Flutter-приложение для Android. Это не WebView.

## Уже реализовано

- авторизация сотрудников через Bearer-токен;
- безопасное хранение токена;
- активные и закрытые обращения;
- счётчики непрочитанных сообщений;
- чат с автообновлением;
- отправка текста и фотографий;
- быстрые ответы;
- назначение обращения на себя;
- статусы «В работе», «Ожидает», «Закрыто»;
- просмотр изображений гостей;
- светлая и тёмная системные темы.

## Требования для сборки

- Flutter stable;
- Android Studio с Android SDK;
- JDK 17;
- Android 6.0 или новее.

## Подготовка проекта

Поскольку архив не содержит бинарный Gradle Wrapper JAR, безопаснее всего создать платформенные файлы своей установленной версией Flutter:

```bash
cd HotelChat-Mobile-1.0-Flutter
flutter create --platforms=android --org online.ognispb --project-name hotelchat_mobile .
```

Команда сохраняет `lib/main.dart` и `pubspec.yaml`, но перед выполнением рекомендуется сделать их копию.

Затем:

```bash
flutter pub get
flutter analyze
flutter build apk --release
```

Готовый APK:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Сервер

Сначала установите `HotelChat-Mobile-API-v1.zip` на VPS.

Проверка API:

```text
https://ognispb.online/api/mobile/v1/index.php?route=health
```

## Домен

Домен указан в начале `lib/main.dart`:

```dart
const apiBase = 'https://ognispb.online/api/mobile/v1/index.php';
```

## Push-уведомления

В 1.0 используется автообновление при открытом приложении. Для фоновых push-уведомлений потребуется Firebase-проект и `google-services.json`.


## Автоматическая сборка через GitHub Actions

Проект содержит готовый workflow `.github/workflows/build-apk.yml`.
Подробная инструкция находится в `GITHUB-ACTIONS-INSTRUCTION-RU.md`.
