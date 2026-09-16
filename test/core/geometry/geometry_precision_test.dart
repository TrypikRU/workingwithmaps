import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/geometry/distance.dart';
import 'package:workingwithmaps/core/geometry/geo_point.dart';
import 'package:workingwithmaps/core/geometry/polygon.dart';
import 'package:workingwithmaps/core/geometry/circular_geofence.dart';

void main() {
  test('Haversine retains submeter precision at field coordinates', () {
    const start = GeoPoint(55.75, 37.62);
    expect(
      calculateDistance(start, const GeoPoint(55.750001, 37.62)),
      closeTo(0.11119508, 0.000001),
    );
    final east = calculateDistance(start, const GeoPoint(55.75, 37.620001));
    expect(east, inExclusiveRange(0.06, 0.07));
  });

  test('Small GPS polygon stays valid and independent of input mutation', () {
    final input = [
      const GeoPoint(55.75, 37.62),
      const GeoPoint(55.75, 37.62001),
      const GeoPoint(55.75001, 37.62001),
      const GeoPoint(55.75001, 37.62),
    ];
    final polygon = GeoPolygon(input);
    input.clear();
    expect(polygon.contains(const GeoPoint(55.750005, 37.620005)), isTrue);
    expect(polygon.contains(const GeoPoint(55.750005, 37.62002)), isFalse);
    expect(polygon.contains(const GeoPoint(55.75, 37.620005)), isTrue);
  });

  test('Geofence works across the date line and rejects nonfinite radii', () {
    final fence = CircularGeofence(center: const GeoPoint(0, 179.9999));
    expect(fence.classify(const GeoPoint(0, -179.9999)), GeofenceState.inside);
    expect(
      fence.classify(const GeoPoint(0, -179.999)),
      GeofenceState.approaching,
    );
    expect(fence.classify(const GeoPoint(0, -179.99)), GeofenceState.outside);
    for (final radius in [double.nan, double.infinity]) {
      expect(
        () => CircularGeofence(center: const GeoPoint(0, 0), radius: radius),
        throwsArgumentError,
      );
    }
  });
}
