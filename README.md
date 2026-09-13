# Field Inspector / Field Route

Android-only Flutter pet-проект для выездных сотрудников. Сохранены package name
`workingwithmaps` и Android applicationId `com.klochkov.workingwithmaps`.

## Что работает

- Карта flutter_map / OpenStreetMap, маркеры статусов, детали объекта и список.
- SQLite — основной источник объектов для карты, списка и деталей.
- Пять демонстрационных объектов добавляются только при пустой таблице objects.
- Foreground-геолокация, accuracy, круг точности, кнопка «Моя позиция», permissions.
- Центрирование выбранного объекта и возврат к общему региону объектов.
- Транзакционное сохранение объекта вместе с операцией в локальной sync_queue.

Начало/завершение обхода, нативный Android foreground location service, статистика и Polyline
работают офлайн. Активный обход восстанавливается из SQLite после перезапуска.
Сервис сохраняет GPS и при свёрнутом Flutter / выключенном экране в пределах ограничений Android.
Автоматическое построение маршрута пока не реализовано. Объекты читаются без интернета;
для загрузки новых тайлов нужна сеть. Офлайн-тайлы не реализованы.

## Архитектура данных

### Check-in

Экран объекта показывает расстояние по Haversine, GPS accuracy и допустимую зону.
По умолчанию CheckInPolicy разрешает Check-in при расстоянии ≤ 50 м и accuracy
от 0 до 50 м включительно. Политика в domain не зависит от Flutter/Geolocator;
радиус и допустимую accuracy можно настроить через checkInPolicyProvider.
Последняя известная позиция, отсутствие permission или выключенная геолокация
не разрешают Check-in. Перед записью controller повторно запрашивает текущую
позицию через общий location layer. При плохой точности нужно дождаться нового fix.

VisitsRepository повторяет проверку зоны по координатам объекта из SQLite и одной
транзакцией создаёт visit (status=completed, syncStatus=pending), операцию
`entityType=visit, operation=upsert` в sync_queue и меняет объект на visited.
Любой сбой откатывает все три записи. ID визита создаётся локально и сохранится
для будущих повторов отправки. UI видит visited через Drift stream сразу после commit.
HTTP при Check-in не вызывается. Ручная загрузка объектов не перезаписывает объекты
с несинхронизированными визитами. Отправку визитов и подтверждение serverVersion
выполняет SyncEngine. Повторный явный Check-in создаёт новый визит;
параллельные нажатия во время сохранения блокируются controller.

Ключевые файлы: `core/geometry/distance.dart`,
`features/visits/domain/check_in_policy.dart`, `features/visits/data/visits_repository.dart`,
`features/visits/presentation/check_in_controller.dart`.
Тесты покрывают геометрию, пороги, запись/rollback, защиту visited от remote refresh
и обновление экрана после Check-in без сети.

```text
MapScreen / ObjectsScreen / ObjectDetailsScreen
                      ↓
        objectsProvider / objectProvider(id)
                      ↓
               ObjectsRepository
                      ↓
            DriftObjectsDataSource
                      ↓
        AppDatabase → field_inspector.sqlite
```

UI не импортирует Drift и получает доменные TechnicalObject через Riverpod.
Repositories не экспортируют строки таблиц или companions. Один AppDatabase
живёт в ProviderScope, открывается лениво и закрывается при освобождении scope.
Файл БД остаётся в постоянном каталоге документов приложения через drift_flutter.

`watchObjects()` использует SQL watch(): карта, список и детали получают
изменения из общей БД после commit. Прежний MockObjectsDataSource удалён.
`demo_objects.dart` используется исключительно для начального заполнения SQLite.
Проверка пустоты, seed и запись metadata выполняются одной транзакцией в beforeOpen.
Непустая таблица не дополняется и не перезаписывается seed-данными. Если таблицу
полностью очистить, при следующем открытии приложения она будет заполнена снова.
Seed не создаёт операции синхронизации.

`ObjectsRepository.saveObject()` обновляет объект с updatedAt и добавляет
`entityType=object`, `operation=upsert` в sync_queue одной транзакцией.
Ошибка любой записи откатывает обе. В этом пути нет HTTP. SyncEngine сохраняет
payload и operationId перед первой отправкой. API пока не принимает изменения
самих объектов, поэтому такие операции остаются failed/unsupported. Отправка
визитов и точек реализована. Кнопки редактирования объектов не добавлялись.

TechnicalObject сохраняет существующий UI-контракт. updatedAt пока является
метаданными хранения и не требуется экрану. SyncStatus — общий enum в core/sync:
`synced`, `pending`, `syncing`, `failed`.

## Схема SQLite v3

| Таблица | Назначение и основные поля |
| --- | --- |
| objects | id, name, address, latitude, longitude, status, priority, updatedAt |
| routes | id, name, status, createdAt, updatedAt, syncStatus, serverVersion |
| route_objects | routeId, objectId, position; составной PK и уникальная позиция внутри обхода |
| visits | id, objectId, nullable routeId, status, latitude, longitude, accuracy, createdAt, updatedAt, syncStatus, serverVersion |
| location_points | id, routeId, latitude, longitude, accuracy, nullable speed, timestamp, syncStatus |
| sync_queue | локальный auto-increment id, entityType, entityId, operation, createdAt, attemptCount, lastError, nextRetryAt, operationId, payload, syncStatus |
| app_metadata | key, value, updatedAt |

Все id сущностей — TEXT и могут назначаться клиентом; id очереди — локальный INTEGER.
`serverVersion` допускает NULL до получения серверной версии. Время хранится
стандартным DateTime Drift (Unix seconds), запись приложения использует UTC.
Отсутствующая скорость — NULL, а не искусственный ноль.

ObjectStatus, ObjectPriority, RouteStatus, VisitStatus и SyncStatus хранятся
строковыми именами через встроенный Drift `textEnum` / EnumNameConverter.
Порядок enum можно менять, переименование сохранённых значений требует миграции.
RouteStatus: planned / active / completed; VisitStatus: completed / failed.

Включён PRAGMA foreign_keys. Связи не удаляют каскадно визиты и точки маршрута.
CHECK ограничивает отрицательные accuracy, position и attemptCount. Добавлены
индексы visits(objectId, createdAt), location_points(routeId, timestamp),
sync_queue(nextRetryAt, createdAt).

## Миграции

v2 → v3 транзакционно добавляет поля durable sync claim, сохраняя очередь.
Снимки v1/v2/v3 и тесты переходов хранятся в репозитории.

Сохранён снимок v1. Переход v1 → v2 создаёт objects, переносит все id, имена
и координаты из technical_objects и добавляет новые таблицы и индексы.
У перенесённых объектов address пустой, status planned, priority normal;
updatedAt устанавливается при миграции. Перенос выполняется транзакционно.
После него непустая objects не заменяется демонстрационными объектами.

Переход использует неизменяемую Schema2 из app_database.steps.dart, поэтому
изменения будущей текущей схемы не должны повлиять на старую миграцию.
При следующем изменении таблиц:

1. Увеличить schemaVersion.
2. Выполнить `dart run build_runner build` и `dart run drift_dev make-migrations`.
3. Дописать новый переход в MigrationStrategy, сохранив старые шаги.
4. Проверить schema validation и сохранность данных в migration tests.

Снимки drift_schemas и сгенерированные schema/steps файлы хранятся в репозитории.
Их не редактируют вручную. Удаление БД вместо миграции недопустимо для локальных
несинхронизированных данных.

## Структура

```text
lib/
  app/                    # MaterialApp.router, навигация, тема
  core/
    database/             # AppDatabase, миграции, seed, служебные таблицы
    network/              # Dio и ошибки remote-загрузки
    location/             # LocationService, адаптер geolocator, Riverpod, lifecycle
    permissions/
    sync/                 # SyncEngine, processor, backoff, foreground lifecycle
    utils/
    widgets/
  features/
    map/{data,domain,presentation}/
    objects/{data,domain,presentation}/
    route/{data,domain,presentation}/
    visits/{data,domain,presentation}/
    tracking/{data,domain,presentation}/
    sync/presentation/
```

Таблицы предметных сущностей находятся в data соответствующих features.
Служебные sync_queue и app_metadata — в core/database/tables.
Геолокация карты и Check-in работает через LocationService. Запись обхода выполняет
Kotlin LocationTrackingService с независимым SQLite inbox; NativeTrackImporter переносит
точки в Drift через RouteRepository. UI не зависит от наличия platform channel events.
[Описание геолокации](lib/core/location/README.md).

## Запуск и проверки

Окружение: Flutter 3.44.5 stable / Dart 3.12.2, Android SDK.

```sh
flutter pub get
dart run build_runner build
dart format lib test
flutter analyze
flutter test
flutter run -d <android-device-id>
```

В pubspec.lock зафиксированы зависимости. drift и drift_dev закреплены на 2.34.0
для совместимости инструментов миграций. Freezed/JSON/Drift настроены в build.yaml.
Dio используется для ручного обновления объектов с backend.

## Тестовый backend

В `backend/FieldInspector.Api` находится отдельный минимальный ASP.NET Core API
с SQLite / EF Core, Swagger и искусственными ошибками синхронизации.
[Запуск, контракты и проверки API](backend/README.md).
На ПК: `http://127.0.0.1:5080/swagger`, в Android Emulator: `http://10.0.2.2:5080`.
Debug-сборка Android разрешает HTTP для `10.0.2.2`.
SyncEngine отправляет очередь при старте/resume и раз в 15 секунд в foreground.
Дополнительно Android WorkManager запускает тот же SyncEngine без UI: periodic work
с NetworkType.connected и достаточным зарядом, интервал от 15 минут. SQLite lease
защищает очередь от одновременных запусков разных Flutter engines.
[Архитектура worker, retry, reboot и команды проверки](lib/core/sync/BACKGROUND_SYNC.md).
Экран «Синхронизация» показывает последнюю успешную синхронизацию, Synced/Pending/Syncing/Failed,
все операции очереди и подробности ошибок. Есть ручной запуск, повтор ошибочных
и индикатор автоматической/ручной синхронизации. Источником UI остаётся Drift.
[Гарантии, идемпотентность, retry и ограничения SyncEngine](lib/core/sync/README.md).

### Ручное обновление объектов

Кнопка обновления в AppBar карты и списка запускает цепочку:
`Dio → ObjectsRemoteDataSource → ObjectDto → ObjectsRepository → Drift → StreamProvider → UI`.
API по умолчанию: `http://10.0.2.2:5080/` (Android Emulator).
Другой адрес: `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5080/`.
Запустите backend по инструкции выше и нажмите «Обновить объекты с сервера».
Автоматической загрузки объектов при открытии нет; исходящая очередь обрабатывается автоматически.

DTO и mapper находятся в `features/objects/data/object_dto.dart` и не заменяют
доменную TechnicalObject. Весь ответ проверяется до записи, затем upsert выполняется
одной транзакцией с серверным updatedAt. Загрузка не создаёт исходящих sync_queue
операций и не удаляет отсутствующие в ответе объекты. Записи с локальными операциями
в очереди сохраняются без изменений до будущего разрешения конфликтов SyncEngine.

ObjectsRefreshController хранит только состояние обновления; список и карта
продолжают читать один локальный stream. При отсутствии сети, timeout или HTTP 500
SnackBar сообщает об ошибке, а сохранённые объекты остаются доступны. Ошибка
конфигурации API также не блокирует чтение SQLite. Повторите обновление вручную
после восстановления связи. Проверки repository используют настоящий Drift в памяти
и подменяют только Dio transport: сеть/500/cache, upsert, rollback, защита локальных
правок и независимость refresh от состояния objectsProvider.

Тесты проверяют:

- создание семи таблиц, seed только пустой БД, связи и строковое хранение enum;
- реактивный repository и атомарность «объект + очередь», включая rollback;
- сохранение изменений и очереди после закрытия/открытия файловой SQLite;
- точную схему v5 после миграции и сохранность данных v1/v2/v3/v4;
- карту и детали через настоящую SQLite в памяти, location state и lifecycle.

Widget-тесты используют тайлы из памяти и fake LocationService. Файловый тест
создаёт отдельную временную БД. Реальный Android GPS требует проверки на устройстве.
Тайлы OSM используют HTTPS, идентификатор приложения и видимую атрибуцию:
[OSM Tile Usage Policy](https://operations.osmfoundation.org/policies/tiles/).

## Запись обхода

На вкладке «Текущий обход» нажмите «Начать обход», разрешите точную геолокацию и уведомления.
Валидные точки сохраняются без сети; Check-in связывает визит с активным обходом.
Экран показывает длительность, число точек, расстояние, GPS accuracy, посещённые
объекты и состояние записи. «Завершить обход» останавливает запись и фиксирует итог.
На карте отображается трек текущего либо последнего завершённого обхода.

[Фильтр, lifecycle, восстановление и ограничения](lib/features/tracking/README.md).

## Геометрия объектов

В `core/geometry` реализованы CircularGeofence (inside/approaching/outside) и
собственный Ray Casting Point in Polygon. Haversine сохранён. Контур и радиус объекта
хранятся в Drift v5, polygon отображается на карте. В зоне approaching появляется
подсказка «Вы находитесь рядом с объектом». Автоматический Check-in не выполняется.
[Правила границы, формат хранения и ограничения](lib/core/geometry/README.md).
