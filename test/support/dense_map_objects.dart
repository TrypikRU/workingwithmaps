import 'package:workingwithmaps/core/geometry/geo_point.dart';
import 'package:workingwithmaps/features/objects/domain/technical_object.dart';

/// Детерминированный плотный район; данные попадают в карту через SQLite.
List<TechnicalObject> denseMapObjects() => List.generate(500, (index) {
  final lat = 55.75 + (index ~/ 25) * 0.0002;
  final lon = 37.62 + (index % 25) * 0.0002;
  return TechnicalObject(
    id: 'dense-$index',
    name: 'Объект ${index.toString().padLeft(3, '0')}',
    address: 'Тестовый район',
    latitude: lat,
    longitude: lon,
    status: ObjectStatus.values[index % 3],
    priority: ObjectPriority.values[index % 4],
    polygon: [
      GeoPoint(lat - 0.00004, lon - 0.00004),
      GeoPoint(lat - 0.00004, lon + 0.00004),
      GeoPoint(lat + 0.00004, lon),
    ],
  );
});
