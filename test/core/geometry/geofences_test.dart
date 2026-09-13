import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/geometry/geo_point.dart';
import 'package:workingwithmaps/core/geometry/distance.dart';
import 'package:workingwithmaps/core/geometry/circular_geofence.dart';
import 'package:workingwithmaps/core/geometry/polygon.dart';

void main() {
  const square = [
    GeoPoint(0, 0),
    GeoPoint(0, 2),
    GeoPoint(2, 2),
    GeoPoint(2, 0),
  ];
  test('Circular geofence defaults: inside, approaching, outside', () {
    final zone = CircularGeofence(center: const GeoPoint(0, 0));
    GeoPoint meters(double value) =>
        GeoPoint(0, value / 6371008.8 * 180 / 3.141592653589793);
    expect(zone.classify(meters(0)), GeofenceState.inside);
    expect(zone.classify(meters(49.99)), GeofenceState.inside);
    expect(zone.classify(meters(50.01)), GeofenceState.approaching);
    expect(zone.classify(meters(149.99)), GeofenceState.approaching);
    expect(zone.classify(meters(150.01)), GeofenceState.outside);
  });
  test('Exact geofence boundaries are inclusive and configurable', () {
    const center = GeoPoint(0, 0),
        boundary = GeoPoint(0, 0.001),
        outer = GeoPoint(0, 0.003);
    final zone = CircularGeofence(
      center: center,
      radius: calculateDistance(center, boundary),
      approachingRadius: calculateDistance(center, outer),
    );
    expect(zone.classify(boundary), GeofenceState.inside);
    expect(zone.classify(outer), GeofenceState.approaching);
    expect(
      () => CircularGeofence(center: center, radius: -1),
      throwsArgumentError,
    );
    expect(
      () => CircularGeofence(center: center, approachingRadius: 10),
      throwsArgumentError,
    );
    expect(
      () => zone.classify(const GeoPoint(double.nan, 0)),
      throwsArgumentError,
    );
  });
  test('Ray Casting: square inside, outside, each edge and vertex', () {
    expect(isPointInPolygon(const GeoPoint(1, 1), square), isTrue);
    expect(isPointInPolygon(const GeoPoint(1, 3), square), isFalse);
    for (final p in [
      ...square,
      const GeoPoint(0, 1),
      const GeoPoint(2, 1),
      const GeoPoint(1, 0),
      const GeoPoint(1, 2),
    ]) {
      expect(isPointInPolygon(p, square), isTrue);
    }
    expect(isPointInPolygon(const GeoPoint(1, 2.000001), square), isFalse);
  });
  test('Triangle, clockwise orientation, explicitly closed ring', () {
    const triangle = [GeoPoint(0, 0), GeoPoint(0, 4), GeoPoint(4, 0)];
    for (final ring in [
      triangle,
      triangle.reversed.toList(),
      [...triangle, triangle.first],
    ]) {
      expect(isPointInPolygon(const GeoPoint(1, 1), ring), isTrue);
      expect(isPointInPolygon(const GeoPoint(2, 2), ring), isTrue);
      expect(isPointInPolygon(const GeoPoint(3, 3), ring), isFalse);
    }
  });
  test(
    'Concave L shape excludes its notch; shared vertex ray is counted once',
    () {
      const ring = [
        GeoPoint(0, 0),
        GeoPoint(0, 3),
        GeoPoint(1, 3),
        GeoPoint(1, 1),
        GeoPoint(3, 1),
        GeoPoint(3, 0),
      ];
      expect(isPointInPolygon(const GeoPoint(2, 0.5), ring), isTrue);
      expect(isPointInPolygon(const GeoPoint(2, 2), ring), isFalse);
      expect(isPointInPolygon(const GeoPoint(1, 0.5), ring), isTrue);
      expect(isPointInPolygon(const GeoPoint(1, 1), ring), isTrue);
    },
  );
  test('Date-line crossing is local; Greenwich is outside', () {
    const ring = [
      GeoPoint(0, 179),
      GeoPoint(0, -179),
      GeoPoint(2, -179),
      GeoPoint(2, 179),
    ];
    expect(isPointInPolygon(const GeoPoint(1, 180), ring), isTrue);
    expect(isPointInPolygon(const GeoPoint(1, -179.5), ring), isTrue);
    expect(isPointInPolygon(const GeoPoint(1, 0), ring), isFalse);
  });
  test('Invalid and collinear polygons are rejected', () {
    expect(() => GeoPolygon([]), throwsArgumentError);
    expect(
      () => GeoPolygon([
        const GeoPoint(0, 0),
        const GeoPoint(1, 1),
        const GeoPoint(2, 2),
      ]),
      throwsArgumentError,
    );
    expect(
      () => GeoPolygon([
        const GeoPoint(0, 0),
        const GeoPoint(100, 0),
        const GeoPoint(0, 1),
      ]),
      throwsArgumentError,
    );
  });
}
