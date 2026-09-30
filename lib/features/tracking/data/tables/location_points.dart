import 'package:drift/drift.dart';

import '../../../../core/sync/sync_status.dart';
import '../../../route/data/tables/routes.dart';

@TableIndex(name: 'location_points_route_time', columns: {#routeId, #timestamp})
class LocationPoints extends Table {
  // Новый сеанс записи не соединяется с предыдущим через разрыв в фоне.
  TextColumn get segmentId => text().nullable()();
  TextColumn get id => text()();
  TextColumn get routeId => text().references(Routes, #id)();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  // Drift DSL: CHECK ссылается на столбец, метод чтения свойства переопределяется генератором.
  // ignore: recursive_getters
  RealColumn get accuracy => real().check(accuracy.isBiggerOrEqualValue(0))();
  // GPS может не сообщить скорость. Отсутствие значения не равно нулю.
  RealColumn get speed => real().nullable()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get syncStatus =>
      textEnum<SyncStatus>().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
