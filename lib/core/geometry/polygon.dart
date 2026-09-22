import 'dart:math' as math;

import 'geo_point.dart';

/// Simple local ring, without holes. Edges are straight in longitude/latitude.
/// Boundary (including a vertex) counts as inside. Ring may be closed or open;
/// orientation is irrelevant. Date-line crossing is unwrapped about the first point.
class GeoPolygon {
  GeoPolygon(List<GeoPoint> vertices) : vertices = List.unmodifiable(vertices) {
    if (vertices.length < 3 || vertices.any((p) => !p.isValid)) {
      throw ArgumentError('Polygon requires at least three valid vertices');
    }
    final anchor = vertices.first.longitude;
    _ring = vertices
        .map((p) => (_longitude(p.longitude, anchor), p.latitude))
        .toList();
    final xs = _ring.map((p) => p.$1);
    if (xs.reduce(math.max) - xs.reduce(math.min) >= 180) {
      throw ArgumentError('Polygon must span less than 180 degrees');
    }
    // Translating to the first vertex avoids cancellation for small GPS polygons.
    var area = 0.0;
    for (var i = 0; i < _ring.length; i++) {
      final a = _ring[i];
      final b = _ring[(i + 1) % _ring.length];
      area +=
          (a.$1 - _ring.first.$1) * (b.$2 - _ring.first.$2) -
          (b.$1 - _ring.first.$1) * (a.$2 - _ring.first.$2);
    }
    if (area.abs() < 1e-18) throw ArgumentError('Degenerate polygon');
  }
  final List<GeoPoint> vertices;
  late final List<(double, double)> _ring;
  static double _longitude(double longitude, double anchor) =>
      anchor + (longitude - anchor + 180) % 360 - 180;

  bool contains(GeoPoint point) {
    if (!point.isValid) throw ArgumentError('Invalid point');
    final x = _longitude(point.longitude, vertices.first.longitude);
    final y = point.latitude;
    const epsilon =
        1e-10; // Degrees; floating-point boundary tolerance, not GPS accuracy.
    var inside = false;
    for (var i = 0; i < _ring.length; i++) {
      final (ax, ay) = _ring[i];
      final (bx, by) = _ring[(i + 1) % _ring.length];
      final dx = bx - ax;
      final dy = by - ay;
      final length = math.sqrt(dx * dx + dy * dy);
      if (x >= math.min(ax, bx) - epsilon &&
          x <= math.max(ax, bx) + epsilon &&
          y >= math.min(ay, by) - epsilon &&
          y <= math.max(ay, by) + epsilon &&
          ((x - ax) * dy - (y - ay) * dx).abs() <= epsilon * length) {
        return true;
      }
      // Half-open Y interval counts a shared vertex once. Horizontal edges never
      // divide by zero. Each crossing of the ray to +X toggles even/odd parity.
      if ((ay > y) != (by > y) && x < ax + (y - ay) * dx / dy) inside = !inside;
    }
    return inside;
  }
}

bool isPointInPolygon(GeoPoint point, List<GeoPoint> polygon) =>
    GeoPolygon(polygon).contains(point);
