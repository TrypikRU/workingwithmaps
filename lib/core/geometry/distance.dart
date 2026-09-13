import 'dart:math' as math;

import 'geo_point.dart';

/// Haversine: расстояние по поверхности сферы в метрах, координаты в градусах.
/// Не зависит от платформенного GPS SDK и одинаково работает в domain и тестах.
double calculateDistance(GeoPoint first, GeoPoint second) {
  if (!first.isValid || !second.isValid) {
    throw ArgumentError('Invalid geographic coordinates');
  }
  const earthRadius = 6371008.8;
  const radians = math.pi / 180;
  final latitudeDelta = (second.latitude - first.latitude) * radians;
  final longitudeDelta = (second.longitude - first.longitude) * radians;
  final a =
      math.pow(math.sin(latitudeDelta / 2), 2) +
      math.cos(first.latitude * radians) *
          math.cos(second.latitude * radians) *
          math.pow(math.sin(longitudeDelta / 2), 2);
  // Округление около антиподов может вывести a за [0, 1] и дать NaN.
  final bounded = a.clamp(0.0, 1.0);
  return earthRadius *
      2 *
      math.atan2(math.sqrt(bounded), math.sqrt(1 - bounded));
}
