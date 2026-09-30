import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/location/location_service.dart';
import 'package:workingwithmaps/features/tracking/domain/location_point_filter.dart';

void main() {
  LocationFix point(double longitude, int milliseconds, {double? speed}) =>
      LocationFix(
        latitude: 0,
        longitude: longitude,
        accuracy: 8,
        speed: speed,
        timestamp: DateTime.utc(2026).add(Duration(milliseconds: milliseconds)),
      );
  test(
    'Subsecond GPS intervals use fractional seconds; missing speed is valid',
    () {
      const filter = LocationPointFilter();
      final previous = point(0, 0);
      // Около 5,56 м за 0,5 с допустимо; такое же перемещение за 0,1 с — нет.
      expect(filter.reject(point(0.00005, 500), previous: previous), isNull);
      expect(
        filter.reject(point(0.00005, 100), previous: previous),
        PointRejection.speed,
      );
    },
  );
  test('Nonfinite reported speed is discarded even for the first point', () {
    for (final speed in [double.nan, double.infinity]) {
      expect(
        const LocationPointFilter().reject(point(0, 0, speed: speed)),
        PointRejection.invalid,
      );
    }
  });
}
