import '../domain/technical_object.dart';
import '../../../core/geometry/geo_point.dart';

/// Только начальные данные для пустой БД. UI не читает этот список.
const demoObjects = [
  TechnicalObject(
    id: 'demo-1',
    name: 'Тепловой пункт № 1',
    address: 'Москва, ул. Покровка, 10',
    latitude: 55.7586,
    longitude: 37.6442,
    // Synthetic demo boundary, not cadastral data.
    polygon: [
      GeoPoint(55.7583, 37.6437),
      GeoPoint(55.7583, 37.6447),
      GeoPoint(55.7589, 37.6447),
      GeoPoint(55.7589, 37.6437),
    ],
    status: ObjectStatus.planned,
    priority: ObjectPriority.high,
  ),
  TechnicalObject(
    id: 'demo-2',
    name: 'Распределительный шкаф № 2',
    address: 'Москва, Чистопрудный бульвар, 12',
    latitude: 55.7618,
    longitude: 37.6425,
    status: ObjectStatus.visited,
    priority: ObjectPriority.normal,
  ),
  TechnicalObject(
    id: 'demo-3',
    name: 'Насосная станция № 3',
    address: 'Москва, ул. Маросейка, 8',
    latitude: 55.7573,
    longitude: 37.6359,
    status: ObjectStatus.error,
    priority: ObjectPriority.critical,
  ),
  TechnicalObject(
    id: 'demo-4',
    name: 'Узел связи № 4',
    address: 'Москва, Архангельский переулок, 7',
    latitude: 55.7602,
    longitude: 37.6363,
    status: ObjectStatus.planned,
    priority: ObjectPriority.low,
  ),
  TechnicalObject(
    id: 'demo-5',
    name: 'Электрощитовая № 5',
    address: 'Москва, ул. Жуковского, 4',
    latitude: 55.7634,
    longitude: 37.6495,
    status: ObjectStatus.visited,
    priority: ObjectPriority.high,
  ),
];
