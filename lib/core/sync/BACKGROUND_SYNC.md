# Android WorkManager synchronization

## Две разные задачи

| Механизм | Назначение | Владелец работы |
| --- | --- | --- |
| Kotlin Foreground Service | Непрерывный сбор GPS, в том числе при выключенном экране; постоянное уведомление | LocationTrackingService + FusedLocationProviderClient + native SQLite inbox |
| Flutter WorkManager | Отложенная отправка существующих pending/retry операций при подходящих условиях | Headless Flutter engine → Drift → тот же SyncEngine |

WorkManager **не** запускает GPS, не подписывается на location updates и не вызывает
tracking MethodChannel. Нет второго алгоритма синхронизации. UI и worker создают
SyncProcessor/SyncEngine с общей Dio-конфигурацией `createApiDio()`.
Точки native inbox пока импортирует существующий NativeTrackImporter при доступном
Flutter UI. Worker отправляет уже попавшие в Drift sync_queue операции; он не переносит
ещё не импортированный native inbox. Это граница текущей архитектуры записи трека.

## Регистрация и выполнение

`main()` неблокирующе вызывает `initializeBackgroundSync()`. Планируется одна задача
`field-inspector-periodic-sync`, taskName `field_inspector.sync.v1`, tag `field-inspector-sync`.
ExistingPeriodicWorkPolicy.keep сохраняет существующее расписание при каждом запуске app:
перезапуск приложения не отменяет выполняющийся worker и не сбрасывает его backoff.

Constraints: `NetworkType.connected`, `requiresBatteryNotLow: true`.
Wi-Fi не обязателен: подходит и мобильная сеть. Подключение не гарантирует доступность
API — Dio/SyncEngine по-прежнему обрабатывают offline, timeout и HTTP ошибки.
Период 15 минут — минимальный интервал, **не обещание запуска ровно каждые 15 минут**.
Android учитывает Doze, ограничения батареи, сеть и собственное планирование.
Ни expedited work, ни foreground dataSync service, ни GPS permissions worker не нужны.

Top-level `syncCallbackDispatcher`, сохранённый через `@pragma('vm:entry-point')`,
инициализирует Flutter binding и обработчик Workmanager. Android FlutterEngine регистрирует
плагины автоматически. Worker не использует ProviderScope/Activity и сам создаёт:
1. AppDatabase — тот же `field_inspector.sqlite` в application documents directory.
2. Dio — тот же `API_BASE_URL` из dart-define (по умолчанию emulator host 10.0.2.2:5080).
3. SyncProcessor и SyncEngine; открытие БД/миграции происходит при первом запросе.

После `run()` worker возвращает true, если нет работы для автоматического повтора;
false означает Android Result.retry(). Dio закрывается и DB connection закрывается
в finally, включая ошибки. Есть callback onTaskStopped, отменяющий текущий Dio-запрос.
Android может уничтожить engine до завершения finally — тогда работают durable claims
и истечение lease, а не предположение о гарантированном cleanup.

## Retry и ограничение времени

На уровне операции остаётся RetryPolicy SyncEngine: 5, 10, 20… секунд, максимум 15 минут.
attemptCount/lastError/nextRetryAt сохраняются в SQLite. Worker **не сбрасывает** nextRetryAt
и не использует `retryFailed: true`. Его false применяется также к pending очереди с будущим
retryAt, занятости lease или прерыванию прохода. WorkManager использует свой exponential
backoff от 30 секунд (Android ограничивает его 5 часами), повторно проверяя constraints.
Фактический запуск должен удовлетворить обоим уровням backoff; при открытом приложении
foreground timer может обработать due-очередь раньше фонового расписания.

409 и остальные permanent 4xx остаются failed и видны в диагностике. Если только такие
операции остались, worker возвращает true: он не повторяет конфликт бесконечно. Последующие
ревизии той же сущности не обгоняют её конфликт. Ручная кнопка повтора сохраняет прежнее поведение.

Один проход SyncEngine ограничен watermark очереди и четырьмя минутами; deadline
отменяет HTTP, оставляет claim/payload для следующего запуска и возвращает deferred.
Большой backlog отправляется несколькими проходами. Нормальные Dio connect/send/receive
timeouts сохранены. При потере сети/OS остановке можно не получить ответ после server commit:
повтор использует тот же operationId, payload и idempotency key.

## Одновременный UI и worker

Static single-flight работает только внутри одного Dart isolate. Между engines действует
`SyncLease`: атомарный SQLite UPSERT строки `app_metadata['sync.engine_lease']` с UUID владельца
и expiresAt. Пока lease занят, второй engine возвращает deferred **до recover и HTTP**.
Транзакции recovery, manual retry, claim, ACK и failure проверяют владельца и продлевают lease
на две минуты. Release удаляет только собственную строку. Schema v4 не меняется.

Если worker погиб/заморожен, lease истекает. Новый owner восстанавливает syncing claim с
тем же замороженным запросом. Старый worker после истечения не сможет ACK/reset/fail чужую
очередь: fencing проверяется в той же транзакции, что изменение. При экстремально долгом
сетевом запросе возможен повтор HTTP после передачи lease; от повторного применения на
сервере защищает уже реализованная серверная идемпотентность. Lease не заменяет её.

У каждого engine своё SQLite connection. `shareAcrossIsolates` не решает обнаружение
другого независимого FlutterEngine. UI при resume и каждые 2 секунды пока открыт проверяет
`PRAGMA data_version`: чужой commit инвалидирует Drift streams. Так карта, список,
счётчики и индикатор активной синхронизации обновляются после работы worker без HTTP из UI.
SQLite busy_timeout=5с сглаживает краткие блокировки локальных транзакций. Ошибки открытия/
SQLite-инфраструктуры приводят к retry worker, сохранённые данные не удаляются.

## Перезапуск и ограничения

WorkManager хранит расписание в собственной SQLite и восстанавливает его после перезагрузки
устройства. Manifest включает ACCESS_NETWORK_STATE и RECEIVE_BOOT_COMPLETED, служебные
receiver/service/initializer приходят из WorkManager manifest merge. Собственного boot receiver
и запуска LocationTrackingService при boot нет. Регистрация выполняется при первом открытии app.

После обычного закрытия UI работа может выполняться без Activity. Force-stop, Android Stop,
ограничения OEM или отозванные фоновые возможности могут остановить/отложить её. Для проверки
после force-stop сначала снова откройте app. KEEP предотвращает размножение расписаний.
Удаление приложения/очистка данных удаляют и очередь, и расписание.

Основания:
[Android persistent work](https://developer.android.com/develop/background-work/background-tasks/persistent),
[constraints и backoff](https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work),
[Drift engines и streams](https://drift.simonbinder.eu/isolates/),
[Workmanager task results](https://docs.page/fluttercommunity/flutter_workmanager/task-status).

## Логи и проверка

Общий AppLogger получает события worker.start, worker.complete, worker.error,
worker.stopped, worker.disposed и события самого SyncEngine, включая sync.run.deferred.
В worker logger выводит структурированный JSON с префиксом FieldSyncWorker в Flutter Logcat.
Есть elapsedMs, succeeded/failed/retry и причина остановки. Payload, координаты и headers не логируются.

```powershell
flutter analyze
flutter test
flutter build apk --debug
adb logcat -s flutter:I WM-WorkerWrapper:D WM-SystemJobService:D
adb shell dumpsys jobscheduler com.klochkov.workingwithmaps
adb shell dumpsys package com.klochkov.workingwithmaps
```

Полевой сценарий: открыть приложение один раз для регистрации; отключить сеть, сделать
Check-in, свернуть приложение. Включить сеть, дождаться worker (или запустить конкретный
JobScheduler job для debug), проверить worker.complete в Logcat. Открыть UI: очередь уменьшилась,
visit synced. Повторить с backend debug HTTP500/409 и при одновременно открытой диагностике.

```powershell
# Найдите реальный JOB_ID компонента androidx.work.impl.background.systemjob.SystemJobService
# в dumpsys jobscheduler. -f применяется только для отладки, обходя constraints:
adb shell cmd jobscheduler run -f com.klochkov.workingwithmaps <JOB_ID>
```

На emulator backend должен быть доступен через 10.0.2.2; физическому устройству нужен
доступный адрес сервера в API_BASE_URL. Для reboot-теста перезагрузите тестовое устройство
после регистрации и проверьте восстановленную задачу при подходящих constraints.
Unit/integration tests используют настоящую файловую SQLite, отдельный Dart isolate,
подменённый Dio transport: успех, offline/500/409/timeout, fencing, cancellation,
восстановление claim и обновление streams при внешней записи.
