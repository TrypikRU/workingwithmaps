import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/geometry/distance.dart';
import 'package:workingwithmaps/core/geometry/geo_point.dart';

void main() {
  test('Same point is zero', () {
    expect(
      calculateDistance(const GeoPoint(55, 37), const GeoPoint(55, 37)),
      0,
    );
  });
  test('One degree on equator matches known great-circle length in meters', () {
    expect(
      calculateDistance(const GeoPoint(0, 0), const GeoPoint(0, 1)),
      closeTo(111195.08, 0.01),
    );
  });
  test('Distance is symmetric and handles date line', () {
    const a = GeoPoint(0, 179.9);
    const b = GeoPoint(0, -179.9);
    expect(calculateDistance(a, b), closeTo(22239.016, 0.01));
    expect(calculateDistance(a, b), calculateDistance(b, a));
  });
  test('Antipodes stay finite and poles converge', () {
    expect(
      calculateDistance(const GeoPoint(0, 0), const GeoPoint(0, 180)),
      closeTo(math.pi * 6371008.8, 0.001),
    );
    expect(
      calculateDistance(const GeoPoint(90, 0), const GeoPoint(90, 120)),
      closeTo(0, 0.001),
    );
  });
  test('Invalid coordinates are rejected', () {
    for (final point in [
      const GeoPoint(91, 0),
      const GeoPoint(0, 181),
      const GeoPoint(double.nan, 0),
    ]) {
      expect(
        () => calculateDistance(point, const GeoPoint(0, 0)),
        throwsArgumentError,
      );
    }
  });
}
