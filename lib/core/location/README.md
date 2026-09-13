# Location layer

`LocationService` — платформонезависимый контракт: service enabled, проверка и
запрос permission, текущая и последняя известная позиция, поток координат,
события включения GPS, открытие системных настроек.

`GeolocatorLocationService` — единственное место импорта geolocator. Он переводит
Position, LocationPermission и исключения плагина в собственные типы приложения.
Будущий Kotlin foreground tracking адаптер реализует тот же контракт и подключится
через `locationServiceProvider`. UI и LocationController менять не потребуется.

`LocationController` (Riverpod Notifier) управляет loading, permissionGranted,
permissionDenied, permissionDeniedForever, serviceDisabled, available, error,
paused. Автоматическая проверка не открывает диалог. `requestPermission: true`
передаётся только по пользовательской кнопке. При постоянном отказе предлагаются
настройки приложения; при выключенном GPS — настройки геолокации.

Последняя известная позиция помечается `isLastKnown`, показывается серым и не
разрешает центрирование как на свежий fix. У свежих координат отображаются accuracy
в метрах и круг точности. При неточной Android location разрешение остаётся
валидным: UI показывает фактическую accuracy, а не требует FINE любой ценой.

Поток запускается только при разрешённом доступе и включённом сервисе.
Одиночный запрос ограничен 20 секундами; его timeout не портит состояние, если
поток уже выдал координаты. Ошибка кэша не блокирует получение свежей позиции.
Поколения запросов не позволяют запоздалому Future обновить состояние после pause,
отключения GPS или нового запроса. Более старый fix не затирает новый.

`LocationLifecycle` наблюдает lifecycle приложения (а не вкладок IndexedStack).
При hidden/paused/detached обе подписки отменяются; при resumed заново проверяются
service и permission, включая изменения в настройках. Inactive не прерывает
permission dialog. Результаты уже запущенных platform Future после pause
игнорируются. При уничтожении ProviderScope подписки также освобождаются.

Этот LocationService обслуживает карту и Check-in. Независимый Kotlin foreground
service записывает обход, в том числе при отсутствии FlutterEngine; см.
[native tracking](../../features/tracking/README.md). Пауза этого UI-источника не останавливает сервис.
AndroidSettings потока: high accuracy, distanceFilter 5 м, intervalDuration 5 с;
это параметры запроса к провайдеру, а не гарантия периода или точности.

Тесты подменяют весь LocationService. Они проверяют доступ, recovery, отмену
подписок, гонки запросов, запоздалый кэш, lifecycle и отображение на карте.
Реальную работу датчиков/системных диалогов нужно проверять на Android:

1. Отказать в разрешении, затем выдать его кнопкой «Разрешить».
2. Проверить постоянный отказ и возврат из настроек после выдачи разрешения.
3. Выключить/включить геолокацию через шторку.
4. Свернуть/вернуть приложение и проверить возобновление координат.
5. Выбрать approximate location и проверить отображение accuracy.

API плагина: [Geolocator](https://pub.dev/documentation/geolocator/latest/geolocator/Geolocator-class.html).
