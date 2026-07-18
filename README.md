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


## Версия 1.0.3 — Kotlin compatibility

- Flutter зафиксирован на 3.44.0;
- flutter_secure_storage зафиксирован на 9.2.4;
- зависимости больше не обновляются автоматически;
- перед сборкой удаляются старые Gradle/Kotlin-кэши;
- полный журнал `build-apk.log` загружается в Artifacts даже при ошибке.


## Версия 1.0.4 — исправление MainActivity.kt

Причина предыдущей ошибки Kotlin устранена. Старый скрипт мог удалить перевод
строки после объявления package и соединить его с import. Теперь MainActivity.kt
не редактируется, а полностью создаётся заново:

```kotlin
package online.ognispb.hotelchat

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()
```

Workflow проверяет все три строки до запуска Gradle.
