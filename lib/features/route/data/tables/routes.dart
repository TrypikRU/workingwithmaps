import 'package:drift/drift.dart';

import '../../../../core/sync/sync_status.dart';
import '../../domain/route_status.dart';

@DataClassName('RouteRow')
class Routes extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get status =>
      textEnum<RouteStatus>().withDefault(const Constant('planned'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get syncStatus =>
      textEnum<SyncStatus>().withDefault(const Constant('pending'))();
  IntColumn get serverVersion => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
