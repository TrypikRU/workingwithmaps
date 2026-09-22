import '../domain/technical_object.dart';
import '../../../core/geometry/geo_point.dart';

/// Синтетические учебные объекты возле ЖД вокзала Сыктывкара, не реальные сооружения.
/// Только начальные данные для пустой БД. UI не читает этот список.
const demoObjects = [
  TechnicalObject(
    id: 'demo-1',
    name: 'Тепловой пункт № 1',
    address: 'Сыктывкар, ул. Коммунистическая, 88 (учебный объект)',
    latitude: 61.659078,
    longitude: 50.794591,
    // Synthetic demo boundary, not cadastral data.
    polygon: [
      GeoPoint(61.658778, 50.794091),
      GeoPoint(61.658778, 50.795091),
      GeoPoint(61.659378, 50.795091),
      GeoPoint(61.659378, 50.794091),
    ],
    status: ObjectStatus.planned,
    priority: ObjectPriority.high,
  ),
  TechnicalObject(
    id: 'demo-2',
    name: 'Распределительный шкаф № 2',
    address: 'Сыктывкар, район ЖД вокзала, учебный участок № 2',
    latitude: 61.662278,
    longitude: 50.792891,
    status: ObjectStatus.visited,
    priority: ObjectPriority.normal,
  ),
  TechnicalObject(
    id: 'demo-3',
    name: 'Насосная станция № 3',
    address: 'Сыктывкар, район ЖД вокзала, учебный участок № 3',
    latitude: 61.657778,
    longitude: 50.786291,
    status: ObjectStatus.error,
    priority: ObjectPriority.critical,
  ),
  TechnicalObject(
    id: 'demo-4',
    name: 'Узел связи № 4',
    address: 'Сыктывкар, район ЖД вокзала, учебный участок № 4',
    latitude: 61.660678,
    longitude: 50.786691,
    status: ObjectStatus.planned,
    priority: ObjectPriority.low,
  ),
  TechnicalObject(
    id: 'demo-5',
    name: 'Электрощитовая № 5',
    address: 'Сыктывкар, район ЖД вокзала, учебный участок № 5',
    latitude: 61.663878,
    longitude: 50.799891,
    status: ObjectStatus.visited,
    priority: ObjectPriority.high,
  ),
];

/// Отпечатки прежнего seed: нужны только для безопасного переноса старых БД.
/// Нельзя определять demo-объект по одному id и затирать пользовательские правки.
const legacyDemoLocations = {
  'demo-1': (
    address: 'Москва, ул. Покровка, 10',
    latitude: 55.7586,
    longitude: 37.6442,
  ),
  'demo-2': (
    address: 'Москва, Чистопрудный бульвар, 12',
    latitude: 55.7618,
    longitude: 37.6425,
  ),
  'demo-3': (
    address: 'Москва, ул. Маросейка, 8',
    latitude: 55.7573,
    longitude: 37.6359,
  ),
  'demo-4': (
    address: 'Москва, Архангельский переулок, 7',
    latitude: 55.7602,
    longitude: 37.6363,
  ),
  'demo-5': (
    address: 'Москва, ул. Жуковского, 4',
    latitude: 55.7634,
    longitude: 37.6495,
  ),
};

const legacyDemoPolygon = [
  GeoPoint(55.7583, 37.6437),
  GeoPoint(55.7583, 37.6447),
  GeoPoint(55.7589, 37.6447),
  GeoPoint(55.7589, 37.6437),
];
