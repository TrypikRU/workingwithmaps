import '../../../core/geometry/distance.dart';
import '../../../core/geometry/geo_point.dart';
import '../../../core/location/location_service.dart';

enum PointRejection { invalid, accuracy, timestamp, movement, speed }

/// Сравнение только с последней принятой точкой: отброшенный выброс не меняет базу.
class LocationPointFilter {
  const LocationPointFilter({
    this.maxAccuracy = 50,
    this.minDistance = 5,
    this.maxSpeed = 15,
  });
  final double maxAccuracy;
  final double minDistance;
  final double maxSpeed;

  PointRejection? reject(LocationFix current, {LocationFix? previous}) {
    if (!GeoPoint(current.latitude, current.longitude).isValid ||
        !current.accuracy.isFinite ||
        current.accuracy < 0 ||
        (current.speed != null &&
            (!current.speed!.isFinite || current.speed! < 0))) {
      return PointRejection.invalid;
    }
    if (current.accuracy > maxAccuracy) return PointRejection.accuracy;
    if (previous == null) return null;
    final seconds =
        current.timestamp.difference(previous.timestamp).inMicroseconds /
        1000000;
    if (seconds <= 0) return PointRejection.timestamp;
    final distance = calculateDistance(
      GeoPoint(previous.latitude, previous.longitude),
      GeoPoint(current.latitude, current.longitude),
    );
    if (distance < minDistance) return PointRejection.movement;
    // Проверяем скорость по координатам/времени, а не доверяем GPS speed.
    if (distance / seconds > maxSpeed) return PointRejection.speed;
    return null;
  }
}
