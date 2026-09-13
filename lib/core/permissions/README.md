# Permissions

Разрешения геолокации обрабатываются в `core/location/LocationController`
через `LocationService`, чтобы проверки доступа и lifecycle потока находились
в одном месте. UI не вызывает Geolocator напрямую.

В AndroidManifest объявлены ACCESS_COARSE_LOCATION и ACCESS_FINE_LOCATION.
Пользователь может выдать approximate location; приложение принимает её и
показывает точность полученных координат. Runtime dialog открывается только по
кнопке «Разрешить». deniedForever требует перехода в настройки приложения.
При возврате из настроек доступ перепроверяется автоматически.

ACCESS_BACKGROUND_LOCATION и foreground service permissions не добавлены:
обновления работают только при foreground lifecycle приложения.
Другие виды разрешений можно добавлять в этот каталог по мере необходимости.
