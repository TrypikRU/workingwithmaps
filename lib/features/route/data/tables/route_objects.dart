import 'package:drift/drift.dart';

import '../../../objects/data/tables/technical_objects.dart';
import 'routes.dart';

class RouteObjects extends Table {
  TextColumn get routeId => text().references(Routes, #id)();
  TextColumn get objectId => text().references(TechnicalObjects, #id)();
  // Drift DSL: CHECK ссылается на колонку, getter переопределяется генератором.
  // ignore: recursive_getters
  IntColumn get position => integer().check(position.isBiggerOrEqualValue(0))();

  @override
  Set<Column> get primaryKey => {routeId, objectId};

  @override
  List<Set<Column>> get uniqueKeys => [
    {routeId, position},
  ];
}
