import '../../../core/geometry/distance.dart';
import '../../../core/geometry/geo_point.dart';
import '../../../core/location/location_service.dart';
import 'route_status.dart';

class TrackPoint {
  const TrackPoint(this.fix, this.segmentId);
  final LocationFix fix;
  final String? segmentId;
}

class RouteSnapshot {
  const RouteSnapshot({
    required this.id,
    required this.name,
    required this.status,
    required this.startedAt,
    this.endedAt,
    required this.points,
    required this.visitedNames,
  });
  final String id;
  final String name;
  final RouteStatus status;
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<TrackPoint> points;
  final List<String> visitedNames;
  double get distance {
    var result = 0.0;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      if (a.segmentId != b.segmentId) continue;
      result += calculateDistance(
        GeoPoint(a.fix.latitude, a.fix.longitude),
        GeoPoint(b.fix.latitude, b.fix.longitude),
      );
    }
    return result;
  }

  Duration duration(DateTime now) {
    final value = (endedAt ?? now).difference(startedAt);
    return value.isNegative ? Duration.zero : value;
  }
}
