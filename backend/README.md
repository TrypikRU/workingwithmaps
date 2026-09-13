# Field Inspector — тестовый API

Небольшой ASP.NET Core Web API (.NET 10) для проверки мобильной offline-first
синхронизации. EF Core хранит Objects, Routes, Visits и LocationPoints в отдельной
SQLite. Authentication отсутствует; мобильный SyncEngine отправляет визиты и точки,
а UI продолжает читать Drift.
Ручное обновление объектов из API уже доступно на карте и в списке Flutter.

## Запуск

Установите .NET 10 SDK. Из корня репозитория:

```powershell
dotnet restore backend/FieldInspector.Api
dotnet run --project backend/FieldInspector.Api --launch-profile http
```

В текущем рабочем окружении SDK также установлен в игнорируемый `backend/.tools/dotnet`.
Если `dotnet` отсутствует в PATH, используйте вместо него
`& './backend/.tools/dotnet/dotnet.exe'`. Этот SDK не входит в исходники.

Swagger: http://127.0.0.1:5080/swagger (Try it out).
OpenAPI: http://127.0.0.1:5080/swagger/v1/swagger.json.
Профиль `http` включает Development, поэтому доступны debug-сбои.

SQLite автоматически создаётся в `backend/FieldInspector.Api/Data/field-inspector.sqlite`.
Пять объектов с такими же `demo-*` ID, как в Flutter, добавляются только при пустой
таблице. При запуске создаётся тестовый обход на текущий день **UTC**, если его нет.
После смены дня перезапустите API для создания нового обхода.
Повторный запуск сохраняет визиты и точки. `Storage:Path` позволяет выбрать другую БД:

```powershell
dotnet run --project backend/FieldInspector.Api --launch-profile http -- --Storage:Path ../.tmp/test.sqlite
```

Для минимального стенда используется `EnsureCreated`, без EF migrations.
После изменения схемы задайте новый путь к тестовой БД или сохраните её копию перед
пересозданием. Это не затрагивает SQLite мобильного приложения.

## Android Emulator

Базовый URL: **http://10.0.2.2:5080/**. `10.0.2.2` — адрес loopback хоста
из стандартного [Android Emulator](https://developer.android.com/studio/run/emulator-networking).
На самом ПК используйте `127.0.0.1`. Сервер слушает только loopback.

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5080/
```

В debug Android Manifest подключено разрешение cleartext HTTP только для `10.0.2.2`.
Release-конфигурация не менялась. Кнопка обновления объектов вызывает GET /objects
через Dio и repository, сохраняет ответ в Drift. UI обновляется через stream БД.
SyncEngine отправляет очередь через POST /visits и POST /location/batch.
Новый локальный обход сначала регистрируется через POST /routes.
GET /sync и загрузка обходов пока автоматически не вызываются.
Для физического телефона этот адрес не подходит.

## Контракты и ручная проверка

JSON использует camelCase, enum — строки. Время передаётся ISO 8601 с UTC/offset.

| Endpoint | Ответ / назначение |
| --- | --- |
| `GET /objects` | Массив объектов: id, name, address, latitude, longitude, status, priority, updatedAt |
| `GET /routes/today` | Массив обходов на день UTC: id, name, date, status, objectIds, updatedAt |
| `POST /routes` | `{id, name, date: "2026-09-13"}`; 201 создание, 200 идентичный повтор, 409 тот же ID с другими данными |
| `POST /visits` | 201 при создании, 200 при повторе/обновлении; актуальные updatedAt и serverVersion |
| `POST /location/batch` | `{inserted, existing, accepted}`; от 1 до 500 точек, атомарно |
| `GET /sync?since=<timestamp>` | `{cursor, serverTime, objects, routes, visits, locationPoints}` |

Примеры PowerShell:

Регистрация локального обхода неизменяема и идемпотентна по client-generated ID.
Она не меняет active/completed на сервере: завершение сейчас сохраняется в Drift.
Debug-заголовки работают для POST /routes так же, как для остальных endpoints.

```powershell
$api = 'http://127.0.0.1:5080'
Invoke-RestMethod "$api/objects"
$routes = Invoke-RestMethod "$api/routes/today"
$visit = @{
  id = [guid]::NewGuid().ToString(); objectId = 'demo-1'; routeId = $routes[0].id
  status = 'completed'; latitude = 55.7586; longitude = 37.6442; accuracy = 8
  createdAt = [DateTimeOffset]::UtcNow.ToString('o'); serverVersion = $null
}
Invoke-RestMethod "$api/visits" -Method Post -ContentType application/json -Body ($visit | ConvertTo-Json)
$batch = @{ points = @(@{
  id = [guid]::NewGuid().ToString(); routeId = $routes[0].id
  latitude = 55.7586; longitude = 37.6442; accuracy = 8; speed = $null
  timestamp = [DateTimeOffset]::UtcNow.ToString('o')
}) }
Invoke-RestMethod "$api/location/batch" -Method Post -ContentType application/json -Body ($batch | ConvertTo-Json -Depth 5)
# PowerShell 7.5+: preserve the timestamp string, including fractional seconds.
$sync = curl.exe --silent "$api/sync" | ConvertFrom-Json -DateKind String
Invoke-RestMethod ("$api/sync?since=" + [uri]::EscapeDataString($sync.cursor))
```

Visit status: `completed` / `failed`. Object status: `planned` / `visited` / `error`;
priority: `low` / `normal` / `high` / `critical`. Route status: `planned` / `active` / `completed`.
POST визита со status=completed атомарно меняет статус объекта на visited.

Клиент назначает стабильные ID до отправки. Повтор того же визита возвращает
существующую запись без новой версии. Для изменения payload передайте последнюю
`serverVersion`: несовпадение даёт 409 с текущей записью в `current`.
Точки неизменяемы: повтор идентичной точки допустим, другой payload с тем же ID
даёт 409 и откатывает весь пакет. Неизвестные связи и некорректные поля дают 400.

Для первой синхронизации пропустите `since`. После успешного применения ответа
сохраните **cursor**, передавайте его в следующий запрос без округления. Время
клиента и `serverTime` не являются курсором. Курсор имеет микросекундную точность,
совместимую с Dart DateTime. Сервер отдаёт текущие состояния изменённых записей,
не журнал каждого события; удалений и пагинации пока нет.

## Искусственные ошибки

Механизм включается только когда одновременно установлены Environment=Development
и `DebugFaults:Enabled=true` (настроено в appsettings.Development.json).
Каждый сбой относится только к одному запросу и выполняется **до записи данных**.

| Query | Эквивалентный header | Поведение |
| --- | --- | --- |
| `?debug=500` | `X-Debug-Fault: 500` | HTTP 500 Problem JSON |
| `?debug=409` | `X-Debug-Fault: 409` | HTTP 409 Problem JSON |
| `?debug=timeout` | `X-Debug-Fault: timeout` | Ожидание отмены клиентом; это не HTTP 408 |
| `?debug=delay&delayMs=2000` | `X-Debug-Fault: delay`, `X-Debug-Delay-Ms: 2000` | Задержка, затем обычный endpoint |

Header имеет приоритет над query. Delay по умолчанию 2000 мс, диапазон 0–30000 мс.
Неизвестный режим или неправильная задержка дают 400. Для timeout задавайте
конечный receiveTimeout в Dio или `--max-time` в curl:

```powershell
curl.exe -i "$api/objects?debug=500"
curl.exe -i -H 'X-Debug-Fault: 409' "$api/objects"
curl.exe -i --max-time 2 "$api/objects?debug=timeout"
curl.exe -i "$api/objects?debug=delay&delayMs=1500"
```

Те же параметры работают на POST. Симуляция потери ответа **после commit** пока
не предусмотрена; безопасный повтор можно проверить двойной отправкой POST.

## Проверки и структура

При запущенном Development API, PowerShell **7.5+**:

```powershell
pwsh -File backend/scripts/Smoke-Test.ps1
# Другой порт:
pwsh -File backend/scripts/Smoke-Test.ps1 -BaseUrl http://127.0.0.1:5081
```

Скрипт создаёт тестовые визиты/точки с уникальными ID. Используйте отдельный
`Storage:Path`. Проверяет seed, идемпотентность, реальные конфликты версий,
атомарность batch, delta/cursor, валидацию, Swagger и четыре искусственных сбоя.

- `Program.cs` — DI, SQLite, Swagger и запуск seed.
- `Data/` — четыре EF-сущности, связи/индексы, начальные данные.
- `Contracts.cs` — HTTP DTO отдельно от сущностей хранения.
- `ApiEndpoints.cs` — пять endpoint-ов, валидация и транзакционная запись.
- `SyncGate.cs` — согласованный курсор и сериализация записи/sync snapshot в одном процессе.
- `DebugFaultMiddleware.cs` — запросные искусственные сбои, отключённые вне Development.

API рассчитан на один локальный процесс. Не запускайте несколько экземпляров
с одним файлом SQLite и не меняйте БД внешним редактором во время работы:
единый gate защищает границу cursor/commit только внутри этого процесса.
