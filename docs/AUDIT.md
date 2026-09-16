# Аудит и тестирование — 14 сентября 2026

Проверены Flutter domain/data слои, SQLite-транзакции, восстановление очереди,
границы Riverpod/UI и существующие тесты. Архитектура и схема БД сохранены:
`UI → Riverpod → Repository → Drift`; HTTP применяется для синхронизации.

## Исправления, подтверждённые регрессионными тестами

1. **Откат версии устаревшим GET.** После подтверждения изменения очередь уже
   пуста, поэтому её проверки недостаточно. `DriftObjectsDataSource` теперь
   отклоняет записи с меньшей `serverVersion`, а также без версии, если локальная
   версия уже известна. Более новая версия продолжает обновляться через SQLite.
2. **Объединение через границу операции.** `enqueueObjectUpdate` раньше выбирал
   все неотправленные обновления сущности. Теперь объединяется только непрерывный
   хвост после последней замороженной/другой операции. Сохраняется старший ID хвоста;
   порядок, idempotency key и payload уже отправлявшейся операции не меняются.

Четыре новых теста воспроизвели эти ошибки до исправлений и прошли после них.
Миграции, HTTP-контракты и зависимости менять не потребовалось.

## Покрытие

Существующие проверки сохранены; добавлено 18 тестовых сценариев.
Пути в таблице относительны корню репозитория.

| Область | Проверки и ключевые файлы |
| --- | --- |
| Haversine | Нулевая дистанция, известная длина дуги, симметрия, полюса, антиподы, линия смены дат, недопустимые координаты; добавлена субметровая точность. `test/core/geometry/distance_test.dart`, `geometry_precision_test.dart` |
| Polygon / Geofence | Внутри/снаружи/граница, вогнутые формы, направление обхода, закрытое кольцо, точные пороги; добавлены маленький GPS-полигон, независимость от мутации входа, geofence через линию смены дат. `test/core/geometry/geofences_test.dart`, `geometry_precision_test.dart` |
| GPS filter | Точность, минимальное перемещение, выбросы скорости, порядок времени; добавлены дробные секунды, отсутствующая и нечисловая скорость. `test/features/tracking/tracking_test.dart`, `location_point_filter_test.dart` |
| Repositories | Реактивный cache, успешная загрузка, offline/500/timeout, валидация всего ответа, rollback, защита локальных изменений и версий. `test/features/objects/objects_refresh_test.dart`, `remote_version_test.dart`, `objects_repository_test.dart` |
| Check-in | Радиус, точность, last-known fix, повторная проверка объекта в транзакции, атомарные visit + queue + visited, rollback. `test/features/visits/check_in_test.dart` |
| SyncEngine | Последовательность, HTTP 500/409, offline, timeout, retry, перезапуск, duplicate/lost ACK, частичный успех, единый engine UI/worker и lease fencing. `test/core/sync/sync_engine_test.dart`, `background_sync_test.dart` |
| RetryPolicy | Удвоение, монотонность и предел на 1000 попытках, пользовательский предел, начальная попытка. `test/core/sync/retry_policy_test.dart` |
| Конфликты / coalescing | A/B/C, потерянный ACK, immutable visit, сохранение истории, явные стратегии, устаревший диалог, повторный 409, reopen, барьеры очереди. `test/core/sync/sync_conflict_test.dart`, `queue_coalescing_test.dart` |
| Widget: детали / Check-in | Данные объекта, переходы, неизвестный ID, allowed/outside/poor accuracy, offline сохранение; добавлены denied и deniedForever. `test/features/map/map_navigation_test.dart`, `test/features/visits/check_in_screen_test.dart` |
| Widget: синхронизация | Счётчики, ошибка, retry, активный engine, изменения Drift; добавлено пустое состояние. `test/features/sync/sync_diagnostics_screen_test.dart`, `sync_conflict_dialog_test.dart` |
| Widget: network + cache | Добавлены offline и HTTP 500: список остаётся виден, сообщение в SnackBar, нет глобальной ошибки или зависшего loading. `test/features/objects/objects_offline_screen_test.dart` |

## Сквозной offline-first сценарий

`test/integration/offline_lifecycle_test.dart` использует реальный SQLite-файл,
настоящие repositories, DTO/Dio и SyncEngine; подменён только HTTP transport.

1. Запуск без сети: seed читается через локальный repository stream; refresh падает,
   но объекты остаются доступны.
2. Check-in сохраняет visit, queue и visited без HTTP.
3. Закрывается соединение SQLite; создаются новое соединение, repositories и engine.
4. Проверяются сохранённые поля визита, очередь и visited в локальном stream.
5. Сеть восстанавливается: engine отправляет запись, реактивный stream получает
   synced/serverVersion, очередь очищается. Повторный запуск ничего не дублирует.

Сценарий выполняется в двух вариантах: закрытие до первой отправки и после
неудачной offline-отправки. Во втором сохраняются retry-метаданные и тот же ключ
идемпотентности. Это моделирует перезапуск storage/dependencies; убийство процесса
Android и ограничения ОС проверяются отдельно на устройстве.

## Запуск

```sh
flutter analyze
flutter test
```

Обычный запуск не требует backend; три интеграционных HTTP-теста пропускаются.
Для полного запуска используйте **отдельную тестовую БД**, поскольку HTTP-тесты
изменяют серверные объекты:

```sh
dotnet run --project backend/FieldInspector.Api --no-launch-profile -- --urls http://127.0.0.1:5097 --Storage:Path ../.tmp/audit.sqlite
flutter test --dart-define=SYNC_TEST_URL=http://127.0.0.1:5097/
```

Итог аудита: `flutter analyze` — без замечаний; полный набор с изолированным
ASP.NET backend — **152 passed, 0 skipped**. Локальный backend после проверки
остановлен. Подробный локальный лог — `audit-flutter-test.log` (не включается в Git).

Drift предупреждал о нескольких экземплярах класса БД в трёх тестах параллельных
подключений. Они намеренно создают **разные** `NativeDatabase` executors.
Предупреждение отключается только на время соответствующего конструктора теста,
с немедленным восстановлением настройки; production-код не подавляет диагностику.
Уведомления pub о доступных версиях и информационное сообщение flutter_map об OSM
не являются ошибками нашего кода; обновление зависимостей в аудит не включалось.

Android APK, поведение foreground service на реальном устройстве, системное
планирование WorkManager и реальные картографические пакеты в этом аудите не
проверялись. Тесты не являются доказательством отсутствия всех возможных гонок.
