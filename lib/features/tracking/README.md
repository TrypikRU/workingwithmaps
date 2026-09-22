# Android foreground location tracking

## Сохранение без Flutter

`FusedLocationProviderClient → GpsFilter → TrackingStore (tracking_inbox.sqlite)`.
Сервис — started Foreground Service, type `location`, stopWithTask=false, не bound
к Activity/FlutterEngine. SQLite и HandlerThread принадлежат сервису/applicationContext.
Flutter может быть уничтожен: callback фильтрует и сохраняет точки самостоятельно.
Используется Google Play Services Location 21.3.0; нужен device/emulator с Google APIs.

Когда UI доступен: `NativeTrackImporter → RouteRepository → Drift transaction
(location_points INSERT + sync_queue INSERT) → native ACK → Drift streams → Riverpod → UI`.
Канал `field_inspector/tracking`: `startTracking`, `stopTracking`, `isTracking`,
`readPoints` (до 200 записей), `ackPoints`, `requestNotificationPermission`.
EventChannel не нужен: pull раз в 2 секунды и при resume читает durable inbox.
UI не рисует точки из ответа канала; карта/статистика по-прежнему читают Drift.

Выбран отдельный журнал вместо второго прямого writer в Drift: Kotlin не зависит
от generated Drift schema/migrations и не обходит invalidation reactive streams.
До импорта журнал является durable входящей очередью, после импорта данные приложения
находятся в Drift. Поэтому во время отсутствия Flutter серверная sync_queue ещё не
пополняется; отправка накопленного трека начинается после возвращения в приложение.
Сам сбор GPS не зависит ни от импорта, ни от сети.

Гарантии переноса:
- UUID точки генерируется Kotlin и не меняется при повторной доставке.
- Native SQLite атомарно записывает точку, baseline фильтра и счётчик notification.
- Native ACK удаляет только подтверждённые ID **после** успешного Drift commit.
- Сбой до commit оставляет batch в inbox. Сбой после commit до ACK даёт повтор;
  repository пропускает существующие ID и не создаёт повторную queue operation,
  даже если предыдущая операция уже синхронизирована с сервером.
- Stop ACK — барьер записи: новые callbacks блокируются, предыдущие записи закончены.
  Затем Flutter импортирует остаток и завершает route. При ошибке его можно завершить повторно.
- SQLite ошибки сохраняют необработанный inbox для retry; не выполняется destructive reset.

Существующая Drift v4 не менялась. Native inbox имеет отдельную версию 1;
будущие его миграции должны сохранять pending точки. Все ранее записанные Dart-точки остаются.

## Фильтрация и lifecycle

GpsFilter (чистый Kotlin) повторяет domain LocationPointFilter Dart: accuracy >50 м,
движение <5 м, невалидные значения/время, скорость по Haversine >15 м/с отбрасываются.
Reported speed хранится отдельно. Радиус Земли одинаков: 6371008.8 м.
Последний принятый fix и счётчик переживают native ACK. Время нормализовано до секунды
для совместимости с Drift. Повтор timestamp не принимается даже после restart.
Старые fixes (>30 секунд по elapsedRealtime) не записываются.

Обычный Home, блокировка экрана, пересоздание Activity и навигация Flutter не меняют
segmentId и не останавливают сервис. Новый экземпляр сервиса создаёт новый участок,
чтобы не соединять неизвестный промежуток после завершения процесса. Polyline и
расстояние берутся из сохранённых сегментов. Длительность включает календарные паузы.
Geolocator остаётся источником текущей позиции для UI/Check-in, но больше НЕ пишет трек.

## Permissions и ограничения Android

- Manifest: COARSE/FINE_LOCATION, FOREGROUND_SERVICE, FOREGROUND_SERVICE_LOCATION,
  POST_NOTIFICATIONS. Сервис exported=false, foregroundServiceType=location.
- Запуск из видимой Activity: точное while-in-use permission запрашивает общий location
  layer, Kotlin проверяет его повторно. Approximate разрешение недостаточно для политики 50м:
  выберите «Точное местоположение» в настройках приложения.
- Android 8+: notification channel LOW; immutable PendingIntent открывает приложение.
- Android 12+: не запускаем FGS из фона. Android 14+ повторно проверяет while-in-use access
  при startForeground; отказ возвращается через MethodChannel, без crash-loop.
- Android 13+: запрашивается POST_NOTIFICATIONS. Отказ не запрещает FGS, но Android может
  скрыть уведомление из шторки, оставив сервис в Task Manager. Чтобы видеть счётчик,
  разрешите уведомления в настройках. Обход не требует ACCESS_BACKGROUND_LOCATION:
  он запускается с экрана приложения и продолжается в location foreground service.
- Отзыв разрешения: регистрация/периодическая проверка прекращают подписку; исправьте
  permission и нажмите «Возобновить tracking». Выключенный GPS отображается как ожидание.
- START_STICKY просит Android восстановить сервис с durable routeId, но не гарантирует
  непрерывность после убийства процесса, OEM-ограничений, force-stop или Task Manager Stop.
  При возвращении восстановятся маршрут и inbox; остановленный сервис запускается явно
  кнопкой «Возобновить tracking». Нет автоматического запуска после перезагрузки телефона.
- Выключенный экран поддерживается FGS + Fused updates. Частота (запрос 5с, минимум 2с)
  не гарантирована Android/Doze/OEM. Принудительный wakelock и обход battery restrictions
  не добавлены. Для длительных полевых тестов проверьте режим батареи производителя.

Официальные основания:
[Location FGS](https://developer.android.com/develop/background-work/services/fgs/service-types#location),
[background start restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start),
[notification permission](https://developer.android.com/develop/ui/compose/notifications/notification-permission),
[user Stop](https://developer.android.com/develop/background-work/services/fgs/handle-user-stopping).

## Проверка на Android

```powershell
flutter build apk --debug
flutter analyze
flutter test
# Из android/, JAVA_HOME должен указывать на JDK Android Studio:
.\gradlew.bat :app:testDebugUnitTest
```

В этой Windows-конфигурации incremental Kotlin compilation отключена: Pub cache C:
и checkout F: ломают относительные пути incremental cache. Build warnings legacy KGP
исходят из существующих Flutter plugins; обновление их toolchain не входит в tracking.

Установка и ручной сценарий (если подключено несколько устройств, добавьте `-s <serial>`):

```powershell
adb install -r build/app/outputs/flutter-apk/app-debug.apk
adb shell am start -n com.klochkov.workingwithmaps/.MainActivity
adb logcat -s FieldTracking:I AndroidRuntime:E ActivityManager:I
```

1. Начать обход с точной геолокацией и уведомлениями. На улице пройти 50–100 м:
   проверить notification, счётчик/Polyline и статистику. В помещении accuracy может
   быть >50 м — отсутствие сохранённых точек в таком случае ожидаемо.
2. Home, затем выключить экран на 3–5 минут и продолжить движение. Notification
   count/Logcat должны расти. Открыть приложение — backlog импортируется без разрыва
   сегмента на границе сворачивания. Повторный resume не создаёт дубликаты.
3. Удалить Activity из Recents во время обхода (не нажимать Android Stop). Сервис
   должен продолжить работу, если OEM не завершает процесс. Запустить приложение:
   восстановится тот же route и накопленные точки. «Don't keep activities» в Developer
   options помогает проверить уничтожение Activity отдельно от остановки всего app.
4. Завершить обход: уведомление исчезает, новые точки не сохраняются. Повторить
   старт/стоп, проверить отсутствие двух одновременных подписок.
5. Проверить отказ/постоянный отказ/approximate location, отключение GPS,
   запрет уведомлений, отзыв permission и восстановление через настройки.
6. Отключить интернет: service/inbox/Drift продолжают работать. После возврата сети
   и приложения точки поступают в sync_queue и проходят существующий SyncEngine.

Полезные команды:

```powershell
adb shell dumpsys activity services com.klochkov.workingwithmaps
adb shell dumpsys location
adb shell dumpsys notification
adb shell dumpsys package com.klochkov.workingwithmaps
adb shell input keyevent KEYCODE_HOME
adb shell input keyevent KEYCODE_SLEEP
adb shell input keyevent KEYCODE_WAKEUP
# Осознанный тест остановки всего приложения — GPS после него не обязан продолжаться:
adb shell am force-stop com.klochkov.workingwithmaps
# Android 13+ Task Manager Stop simulation:
adb shell cmd activity stop-app com.klochkov.workingwithmaps
# Debug-only: наличие native inbox; смотреть таблицу points можно в Database Inspector.
adb shell run-as com.klochkov.workingwithmaps ls databases
```

Emulator: образ Google APIs/Google Play, Extended Controls → Location → Routes или
GPX с walking speed. Либо одиночные точки (порядок longitude, latitude):

```powershell
adb emu geo fix 50.794591 61.659078
# Подождите ≥5 секунд, затем переместитесь примерно на 10 м:
adb emu geo fix 50.794751 61.659078
```

Не делайте большие мгновенные телепортации: фильтр скорости корректно их отбрасывает.
Unit tests проверяют Kotlin-фильтр, Drift rollback, lost ACK, replay после удалённой
синхронизации и сохранение recorder при disposal ProviderContainer. Эти tests не
заменяют проверку реального GPS, battery policy и системных диалогов на устройстве.
