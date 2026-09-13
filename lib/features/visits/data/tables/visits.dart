import 'package:drift/drift.dart';

import '../../../../core/sync/sync_status.dart';
import '../../../objects/data/tables/technical_objects.dart';
import '../../../route/data/tables/routes.dart';
import '../../domain/visit_status.dart';

@TableIndex(name: 'visits_object_created', columns: {#objectId, #createdAt})
class Visits extends Table {
  TextColumn get id => text()();
  TextColumn get objectId => text().references(TechnicalObjects, #id)();
  TextColumn get routeId => text().nullable().references(Routes, #id)();
  TextColumn get status =>
      textEnum<VisitStatus>().withDefault(const Constant('completed'))();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  // Drift DSL: CHECK ссылается на колонку, getter переопределяется генератором.
  // ignore: recursive_getters
  RealColumn get accuracy => real().check(accuracy.isBiggerOrEqualValue(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get syncStatus =>
      textEnum<SyncStatus>().withDefault(const Constant('pending'))();
  IntColumn get serverVersion => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
