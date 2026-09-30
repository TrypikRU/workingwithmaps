import 'distance.dart';
import 'geo_point.dart';

enum GeofenceState { outside, approaching, inside }

/// Только геометрия: разрешение, актуальность и точность GPS проверяет вызывающая сторона.
class CircularGeofence {
  CircularGeofence({
    required this.center,
    this.radius = 50,
    double? approachingRadius,
  }) : approachingRadius = approachingRadius ?? radius * 3 {
    if (!center.isValid ||
        !radius.isFinite ||
        radius <= 0 ||
        !this.approachingRadius.isFinite ||
        this.approachingRadius < radius) {
      throw ArgumentError('Invalid circular geofence');
    }
  }
  final GeoPoint center;
  final double radius;
  final double approachingRadius;
  GeofenceState classify(GeoPoint point) {
    final distance = calculateDistance(center, point);
    if (distance <= radius) return GeofenceState.inside;
    if (distance <= approachingRadius) return GeofenceState.approaching;
    return GeofenceState.outside;
  }
}
