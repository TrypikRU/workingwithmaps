import '../../../core/geometry/distance.dart';
import '../../../core/geometry/geo_point.dart';
import '../../../core/location/location_service.dart';

enum CheckInBlock { locationUnavailable, poorAccuracy, outsideRadius }

class CheckInEligibility {
  const CheckInEligibility({this.distance, this.block});
  final double? distance;
  final CheckInBlock? block;
  bool get allowed => block == null;
}

/// Одна политика для UI-подсказки и обязательной проверки перед записью в БД.
class CheckInPolicy {
  const CheckInPolicy({this.radius = 50, this.maxAccuracy = 50})
    : assert(radius > 0),
      assert(maxAccuracy > 0);
  final double radius;
  final double maxAccuracy;

  CheckInEligibility evaluate(
    GeoPoint target,
    LocationFix? position, {
    bool isCurrent = true,
  }) {
    if (!isCurrent ||
        position == null ||
        !target.isValid ||
        !GeoPoint(position.latitude, position.longitude).isValid) {
      return const CheckInEligibility(block: CheckInBlock.locationUnavailable);
    }
    final distance = calculateDistance(
      target,
      GeoPoint(position.latitude, position.longitude),
    );
    if (!position.accuracy.isFinite ||
        position.accuracy < 0 ||
        position.accuracy > maxAccuracy) {
      return CheckInEligibility(
        distance: distance,
        block: CheckInBlock.poorAccuracy,
      );
    }
    return CheckInEligibility(
      distance: distance,
      block: distance <= radius ? null : CheckInBlock.outsideRadius,
    );
  }
}

class CheckInRejected implements Exception {
  const CheckInRejected(this.reason);
  final CheckInBlock reason;
}
