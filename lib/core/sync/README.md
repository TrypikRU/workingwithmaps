# Offline-first SyncEngine

Local DB — источник состояния UI. Engine отправляет только durable `sync_queue`.
Локальная бизнес-операция и вставка очереди остаются одной транзакцией repository.

## Компоненты

- `SyncEngine.run()` — последовательный проход по due-операциям, SyncResult со
  счётчиками успехов/ошибок. Не зависит от UI, Flutter и Riverpod.
- `SyncProcessor` — SQLite claim, сериализация HTTP payload, Dio, ACK и ошибки.
- `SyncException` — network/timeout/server/client/conflict/unsupported/invalidResponse/local.
- `RetryPolicy` — 5, 10, 20, 40… секунд, максимум 15 минут без лимита попыток.
- `SyncLifecycle` — glue-код точки входа `main`: запуск при старте/resume и каждые
  15 секунд в foreground. При pause таймер выключается; начатый run может завершиться.
- `sync_providers.dart` — сборка зависимостей; экран отображает сводку из SQLite
  и позволяет вручную запустить run, сохраняя ограничения nextRetryAt.

## Экран диагностики

Вкладка «Синхронизация» открывает отдельный экран диагностики. Он получает единый
SQLite snapshot через SyncDiagnosticsRepository и Riverpod StreamProvider:
последнее подтверждение, счётчики и список всех текущих queue operations.
Для каждой строки показаны entityType, entityId, operation, createdAt, attemptCount,
lastError, nextRetryAt и статус. У failed доступен диалог полного JSON ошибки
с operationId; старые ошибки в текстовом формате также отображаются.

`Synced` — накопительное количество подтверждённых операций с включения диагностики,
не число серверных сущностей. `Pending/Syncing/Failed` — количество строк в текущей
очереди. Исторические успехи до добавления счётчика не восстанавливаются задним числом.
Время последней успешной синхронизации означает время последнего ACK, включая
частично успешный проход. Пустой запуск или ошибка его не обновляют.
Счётчик `sync.acknowledged_count` и `sync.last_success_at` сохраняются в app_metadata
в той же транзакции, что удаление queue item и подтверждение сущности.
Новая миграция для них не нужна. Значения переживают перезапуск.

«Синхронизировать сейчас» запускает обычный due-проход.
«Повторить ошибочные» вызывает `run(retryFailed: true)`: внутри общей блокировки
engine переводит failed в pending и снимает nextRetryAt, сохраняя attemptCount,
lastError, operationId и payload. Включает явный повтор 4xx/409/unsupported;
конфликты не разрешаются автоматически и при той же причине снова станут failed.
Если другой run активен, ручной retry ждёт его завершения. Ошибочные записи
не удаляются по кнопке, сроку хранения или при просмотре — только после успешного ACK.

Индикатор активности подписан на process-wide stream engine, поэтому показывает
также foreground-запуск и пустой проход, а не только нажатие кнопки на экране.
Пока идёт run, обе кнопки заблокированы. UI не импортирует Drift/Dio и не отправляет HTTP.

## Состояния и порядок

`pending → syncing → synced` (при успехе строка очереди удаляется).
При ошибке очередь и сущность получают `failed`, attemptCount увеличивается,
lastError содержит безопасный JSON `{kind,message,statusCode,retryable}`.
Network, timeout и 5xx получают nextRetryAt. 409 — conflict, остальные 4xx — client;
они не повторяются автоматически. 429 также относится к 4xx на этом этапе.
Неподдерживаемые операции, ошибки данных и некорректные ACK сохраняются для разбора.
UI разрешения конфликтов пока не реализован; engine не выбирает server-wins/local-wins.

Порядок — локальный auto-increment id. Операции одной сущности не обгоняют retry
или conflict предшественника. Ошибка одного объекта не блокирует другие.
Один проход ограничен максимальным id на момент старта, поэтому поступающие записи
не делают его бесконечным. Они будут обработаны следующим запуском.
Одна операция выполняется максимум один раз за проход.

`SyncEngine` использует static single-flight внутри isolate и SQLite lease между
UI/WorkManager engines. До recover движок атомарно получает lease; каждая транзакция
проверяет владельца. Подробности: [Android background sync](BACKGROUND_SYNC.md).

## Транзакции и восстановление

Schema v3 добавляет sync_queue.operationId, payload и syncStatus. Миграция сохраняет
v2 очередь, ссылки и retry-поля. Новые строки по умолчанию pending.
Перед первым HTTP-запросом processor одной транзакцией читает сущность,
сохраняет неизменяемый JSON payload, случайный 128-bit operationId и syncing.
Пока операция ни разу не отправлялась, используется актуальное состояние сущности;
это синхронизация состояний, а не журнал каждого промежуточного изменения.
После первого claim содержимое запросов при retry никогда не меняется.

HTTP выполняется вне SQLite transaction. Успешный ACK проверяется по entityId
и serverVersion визита; затем удаление очереди и изменение syncStatus/serverVersion
коммитятся вместе. Если есть более новая операция той же сущности, статус остаётся
pending; ACK не копирует старые бизнес-поля поверх локальных правок.
Следующая операция получает последнюю подтверждённую serverVersion.

После остановки процесса durable syncing восстанавливается в pending, а payload
и operationId сохраняются. Сетевые failed сохраняют backoff между перезапусками.
Если SQLite недоступна даже для записи ошибки, run прерывается; незавершённый claim
можно восстановить следующим запуском. Подтверждения не теряют очередь частично.

## Идемпотентность и поддержка API

Поддержаны `entityType=visit, operation=upsert → POST /visits` и
`entityType=location_point, operation=upsert → POST /location/batch` (по одной точке).
ID сущностей назначаются клиентом и передаются без изменения. Backend дедуплицирует
их по ID и бизнес-payload: идентичный повтор визита возвращает прежнюю версию,
другой payload проверяет optimistic serverVersion; точки неизменяемы.
Сохранённый operationId отправляется как `Idempotency-Key` и используется в логах.
Backend сейчас не хранит отдельный журнал этого header: гарантия опирается именно
на сохраняемую в серверной SQLite сущность, её ID, payload и serverVersion.

Это at-least-once доставка с идемпотентным применением, а не обещание exactly-once
сетевого запроса. Потерянный после серверного commit ответ приводит к повторному
POST, который не создаёт второй визит и не увеличивает версию повторно.

API поддерживает регистрацию `route/create` через POST /routes. До её ACK связанные
точки/визиты остаются в очереди с retryable dependency, без HTTP с неизвестным routeId.
Регистрация содержит неизменяемые id/name/date; повтор после потери ACK безопасен.
Завершение обхода пока сохраняется только локально.
API не имеет writers для objects, изменения routes и delete. Их очередь остаётся failed с
unsupported; данные не удаляются и не считаются подтверждёнными. Backend должен
содержать objectId/routeId перед отправкой связанных визитов/точек.
GET /sync и автоматическая загрузка обходов пока не включены: загрузка объектов
остаётся отдельной ручной операцией существующего ObjectsRepository.

## Диагностика и проверки

Общий `core/utils/AppLogger` пишет структурированные события в `dart:developer`
с именем FieldInspector: старт/присоединение/итог run, claim, success, failure,
восстановление, attemptCount, elapsedMs и nextRetryAt. Логи доступны в DevTools.
Координаты, payload, HTTP headers и сырой DioException в них не попадают.
Logger имеет внедряемый sink; исключение sink не ломает синхронизацию.

```powershell
flutter analyze
flutter test
# Backend должен быть запущен на отдельной тестовой SQLite:
flutter test test/integration/sync_backend_test.dart --dart-define=SYNC_TEST_URL=http://127.0.0.1:5081/
```

Unit/integration-тесты используют настоящую Drift SQLite и Dio transport fake:
успех, offline/500/409/400/timeout, partial success, backoff, restart файловой БД,
прерванный claim, duplicate operation, потерянный ACK и параллельные engine.
Отдельный opt-in тест проходит через настоящий backend, теряет ACK после commit
и проверяет единственный серверный визит с serverVersion=1 после повторов.
