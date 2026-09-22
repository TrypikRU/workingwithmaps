import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/geometry/distance.dart';
import 'package:workingwithmaps/core/geometry/geo_point.dart';
import 'package:workingwithmaps/core/geometry/polygon.dart';
import 'package:workingwithmaps/core/geometry/circular_geofence.dart';

void main() {
  test('Haversine retains submeter precision at field coordinates', () {
    const start = GeoPoint(61.650478, 50.770391);
    expect(
      calculateDistance(start, const GeoPoint(61.650479, 50.770391)),
      closeTo(0.11119508, 0.000001),
    );
    final east = calculateDistance(start, const GeoPoint(61.650478, 50.770392));
    expect(east, inExclusiveRange(0.05, 0.06));
  });

  test('Small GPS polygon stays valid and independent of input mutation', () {
    final input = [
      const GeoPoint(61.650478, 50.770391),
      const GeoPoint(61.650478, 50.770401),
      const GeoPoint(61.650488, 50.770401),
      const GeoPoint(61.650488, 50.770391),
    ];
    final polygon = GeoPolygon(input);
    input.clear();
    expect(polygon.contains(const GeoPoint(61.650483, 50.770396)), isTrue);
    expect(polygon.contains(const GeoPoint(61.650483, 50.770411)), isFalse);
    expect(polygon.contains(const GeoPoint(61.650478, 50.770396)), isTrue);
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
