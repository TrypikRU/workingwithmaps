# Полевой инспектор — тестовый API

Небольшой ASP.NET Core Web API (.NET 10) для проверки синхронизации мобильного
приложения с поддержкой работы без интернета. EF Core хранит Objects, Routes,
Visits и LocationPoints в отдельной SQLite. Аутентификации нет.
SyncEngine отправляет изменения, а интерфейс продолжает читать Drift.
Ручное обновление объектов доступно на карте и в списке.

## Запуск

Установите .NET 10 SDK. Из корня репозитория:

```powershell
dotnet restore backend/FieldInspector.Api
dotnet run --project backend/FieldInspector.Api --launch-profile http
```

В рабочем окружении SDK может также находиться в игнорируемом
backend/.tools/dotnet. Если dotnet отсутствует в PATH, используйте
& './backend/.tools/dotnet/dotnet.exe'. Этот SDK не входит в исходники.

[Swagger](http://127.0.0.1:5080/swagger) позволяет выполнить запрос кнопкой Try it out.
[OpenAPI](http://127.0.0.1:5080/swagger/v1/swagger.json).
Профиль http включает Development и отладочные сбои.

SQLite создаётся в backend/FieldInspector.Api/Data/field-inspector.sqlite.
Пять объектов с теми же идентификаторами demo-*, что во Flutter, добавляются только
в пустую таблицу. При запуске создаётся тестовый обход на текущий день UTC,
если его ещё нет. После смены дня перезапустите API для нового обхода.
Посещения и точки сохраняются. Storage:Path задаёт другую БД:

```powershell
dotnet run --project backend/FieldInspector.Api --launch-profile http -- --Storage:Path ../.tmp/test.sqlite
```

Для локального стенда используются EnsureCreated и дополняющее обновление схемы:
при запуске добавляются Objects.ServerVersion и OperationReceipts без удаления
данных. База мобильного приложения мигрирует отдельно через Drift v6.

## Эмулятор Android

Базовый адрес — http://10.0.2.2:5080/. Адрес 10.0.2.2 даёт доступ к локальному
интерфейсу компьютера из стандартного
[Android Emulator](https://developer.android.com/studio/run/emulator-networking).
На ПК используйте 127.0.0.1. Сервер слушает только локальный интерфейс.

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5080/
```

Отладочный Android Manifest разрешает незашифрованный HTTP для 10.0.2.2,
127.0.0.1 и localhost; последние два подходят для adb reverse на устройстве.
Выпускная конфигурация не меняется.
Кнопка обновления получает GET /objects через Dio и репозиторий, сохраняет
результат в Drift. Интерфейс обновляет поток БД.
SyncEngine отправляет PATCH /objects/{id}, POST /routes, POST /visits
и POST /location/batch. Новый обход сначала регистрируется через POST /routes.
GET /sync и загрузка обходов автоматически не вызываются.
Адрес 10.0.2.2 для физического телефона не подходит.

## Контракты и ручная проверка

JSON использует camelCase, перечисления — строки.
Время передаётся в ISO 8601 с UTC или явным смещением.

| Метод API | Ответ или назначение |
| --- | --- |
| GET /objects | Объекты: id, name, address, latitude, longitude, status, priority, updatedAt, serverVersion |
| GET /routes/today | Обходы на день UTC: id, name, date, status, objectIds, updatedAt |
| POST /routes | id, name, date; 201 — создание, 200 — идентичный повтор, 409 — тот же идентификатор с другими данными |
| POST /visits | 201 — создание, 200 — идентичный повтор; другие данные дают 409; актуальные updatedAt и serverVersion |
| POST /location/batch | inserted, existing, accepted; от 1 до 500 точек, атомарно |
| GET /sync?since=… | cursor, serverTime, objects, routes, visits, locationPoints |

Регистрация обхода неизменяема и идемпотентна по идентификатору, созданному
клиентом. Она не меняет серверные active/completed: завершение пока сохраняется
в Drift. Отладочные заголовки работают и для POST /routes.

Примеры PowerShell:

```powershell
$api = 'http://127.0.0.1:5080'
Invoke-RestMethod "$api/objects"
$routes = Invoke-RestMethod "$api/routes/today"
$visit = @{
  id = [guid]::NewGuid().ToString(); objectId = 'demo-1'; routeId = $routes[0].id
  status = 'completed'; latitude = 61.659078; longitude = 50.794591; accuracy = 8
  createdAt = [DateTimeOffset]::UtcNow.ToString('o'); serverVersion = $null
}
Invoke-RestMethod "$api/visits" -Method Post -ContentType application/json -Body ($visit | ConvertTo-Json)
$batch = @{ points = @(@{
  id = [guid]::NewGuid().ToString(); routeId = $routes[0].id
  latitude = 61.659078; longitude = 50.794591; accuracy = 8; speed = $null
  timestamp = [DateTimeOffset]::UtcNow.ToString('o')
}) }
Invoke-RestMethod "$api/location/batch" -Method Post -ContentType application/json -Body ($batch | ConvertTo-Json -Depth 5)
# PowerShell 7.5+: сохраняем строку времени, включая доли секунды.
$sync = curl.exe --silent "$api/sync" | ConvertFrom-Json -DateKind String
Invoke-RestMethod ("$api/sync?since=" + [uri]::EscapeDataString($sync.cursor))
```

Статусы посещения: completed / failed. Объекта: planned / visited / error.
Приоритеты: low / normal / high / critical. Обхода: planned / active / completed.
POST посещения со status=completed атомарно меняет объект на visited.

Клиент назначает постоянные идентификаторы до отправки. Идентичный повтор посещения
возвращает запись без новой версии. Посещения неизменяемы: другие данные дают 409
с текущей записью в current, даже при совпадении serverVersion.
Точки также неизменяемы: другой набор данных с прежним идентификатором даёт 409
и откатывает весь пакет. Неизвестные связи и некорректные поля дают 400.

При первой синхронизации пропустите since. После применения ответа сохраните
cursor и передавайте его без округления. Время клиента и serverTime курсором
не являются. Микросекундная точность совместима с Dart DateTime.
Сервер отдаёт текущие состояния изменённых записей, а не журнал каждого события.
Удалений и постраничной выдачи пока нет.

## Искусственные ошибки

Механизм работает только при Environment=Development и DebugFaults:Enabled=true
(настроено в appsettings.Development.json). Сбой относится к одному запросу
и возникает **до записи данных**.

| Параметр запроса | Эквивалентный заголовок | Поведение |
| --- | --- | --- |
| ?debug=500 | X-Debug-Fault: 500 | HTTP 500 с JSON ошибки |
| ?debug=409 | X-Debug-Fault: 409 | HTTP 409 с JSON ошибки |
| ?debug=timeout | X-Debug-Fault: timeout | Ожидание отмены клиентом, не ответ HTTP 408 |
| ?debug=delay&delayMs=2000 | X-Debug-Fault: delay; X-Debug-Delay-Ms: 2000 | Задержка, затем обычная обработка |

Заголовок имеет приоритет. Задержка по умолчанию 2000 мс, диапазон 0–30000 мс.
Неверный режим или задержка дают 400. Для проверки ожидания задайте конечный
receiveTimeout в Dio или --max-time в curl:

```powershell
curl.exe -i "$api/objects?debug=500"
curl.exe -i -H 'X-Debug-Fault: 409' "$api/objects"
curl.exe -i --max-time 2 "$api/objects?debug=timeout"
curl.exe -i "$api/objects?debug=delay&delayMs=1500"
```

Параметры работают и на POST. Искусственная потеря ответа после фиксации пока
не реализована; безопасный повтор можно проверить двойной отправкой POST.

## Проверки и структура

При запущенном API в Development, PowerShell 7.5+:

```powershell
pwsh -File backend/scripts/Smoke-Test.ps1
# Другой порт:
pwsh -File backend/scripts/Smoke-Test.ps1 -BaseUrl http://127.0.0.1:5081
```

Скрипт создаёт тестовые посещения и точки с уникальными идентификаторами.
Используйте отдельный Storage:Path. Проверяются начальные данные, идемпотентность,
конфликты версий, атомарность пакета, изменения и курсор, проверка данных,
Swagger и четыре искусственных сбоя.

- Program.cs — DI, SQLite, Swagger и запуск начального заполнения.
- Data/ — четыре сущности EF, связи, индексы и начальные данные.
- Contracts.cs — HTTP DTO отдельно от сущностей хранения.
- ApiEndpoints.cs — методы API, проверка и транзакционная запись.
- SyncGate.cs — согласованный курсор, упорядоченная запись и чтение снимка изменений.
- DebugFaultMiddleware.cs — искусственные сбои запросов, отключённые вне Development.

API рассчитан на один локальный процесс. Не запускайте несколько экземпляров
с одной SQLite и не меняйте её внешним редактором во время работы:
общая блокировка защищает границу курсора и фиксации только внутри процесса.

## Версии объектов и конфликты

GET /objects и GET /objects/{id} возвращают serverVersion начиная с 1.
GET /visits/{id} позволяет вручную обновить снимок конфликта.
PATCH /objects/{id} принимает id, name, address, latitude, longitude, status,
priority, serverVersion и обязательный заголовок Idempotency-Key — уникальную
строку до 100 символов. Объект должен существовать; создание через PATCH не
поддерживается. Это замена перечисленных полей, а не JSON Patch RFC 6902.
Поля polygon/geofenceRadius локальные и не отправляются.

Версия клиента 4 при серверной 5 даёт 409 с current — полным ObjectDto.
Успех увеличивает версию на один. Отметка о посещении также увеличивает версию
изменённого объекта. POST посещений не перезаписывает существующий факт с другими данными.

Успешный PATCH и OperationReceipt сохраняются одной транзакцией EF/SQLite.
После потери подтверждения прежний ключ и запрос возвращают исходный ответ,
даже после последующих изменений объекта. Другие данные с тем же ключом дают 409.
Явное разрешение конфликта создаёт новую операцию и снова проверяет версию.
Подтверждения переживают перезапуск; автоматического срока удаления пока нет.

```powershell
$api = 'http://127.0.0.1:5080'
$o = Invoke-RestMethod "$api/objects/demo-1"
$edit = @{ id=$o.id; name='Изменённое имя'; address=$o.address;
  latitude=$o.latitude; longitude=$o.longitude; status=$o.status;
  priority=$o.priority; serverVersion=$o.serverVersion }
Invoke-RestMethod "$api/objects/$($o.id)" -Method Patch -ContentType application/json `
  -Headers @{ 'Idempotency-Key'=[guid]::NewGuid().ToString('N') } -Body ($edit | ConvertTo-Json)
# Другой ключ со старой версией → реальный 409 с current.
Invoke-WebRequest "$api/objects/$($o.id)" -Method Patch -ContentType application/json `
  -Headers @{ 'Idempotency-Key'=[guid]::NewGuid().ToString('N') } -Body ($edit | ConvertTo-Json) -SkipHttpErrorCheck
```

Smoke-Test.ps1 проверяет PATCH, актуальный снимок, неизменяемость посещений
и повтор исходного PATCH после новой записи. Используйте отдельный Storage:Path:
тест намеренно меняет начальные объекты.
