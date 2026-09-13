enum LocationAccess { granted, denied, deniedForever }

/// Модель приложения: будущий Kotlin-адаптер не должен экспортировать в UI
/// ни PlatformException, ни тип Position из geolocator.
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
    this.speed,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime timestamp;
  final double? speed;
}

enum LocationFailureKind { permission, serviceDisabled, timeout, unknown }

class LocationFailure implements Exception {
  const LocationFailure(this.kind);
  final LocationFailureKind kind;
}

/// Реальная граница платформы: другой источник foreground-координат подключается
/// заменой locationServiceProvider, без изменений экрана или state controller.
abstract interface class LocationService {
  Future<bool> isServiceEnabled();
  Future<LocationAccess> checkPermission();
  Future<LocationAccess> requestPermission();
  Future<LocationFix> getCurrentPosition();
  Future<LocationFix?> getLastKnownPosition();
  Stream<LocationFix> watchPosition();
  Stream<bool> watchServiceEnabled();
  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}
