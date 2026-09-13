import 'dart:convert';
import 'package:drift/drift.dart';
import '../geometry/geo_point.dart';
import '../geometry/polygon.dart';

/// Empty ring means no polygon; actual rings are validated on persistence.
class PolygonConverter extends TypeConverter<List<GeoPoint>, String> {
  const PolygonConverter();
  @override
  List<GeoPoint> fromSql(String fromDb) {
    final points = (jsonDecode(fromDb) as List)
        .map((p) => GeoPoint.fromJson(p as Map<String, dynamic>))
        .toList();
    if (points.isNotEmpty) GeoPolygon(points);
    return List.unmodifiable(points);
  }

  @override
  String toSql(List<GeoPoint> value) {
    if (value.isNotEmpty) GeoPolygon(value);
    return jsonEncode(value.map((p) => p.toJson()).toList());
  }
}
