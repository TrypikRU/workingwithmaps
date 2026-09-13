import 'package:drift/drift.dart';

import '../../domain/technical_object.dart';
import '../../../../core/database/polygon_converter.dart';

@DataClassName('TechnicalObjectRow')
class TechnicalObjects extends Table {
  @override
  String get tableName => 'objects';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get address => text().withDefault(const Constant(''))();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  // textEnum использует EnumNameConverter: перестановка элементов enum
  // не меняет смысл сохранённых значений. Переименование требует миграции.
  TextColumn get status =>
      textEnum<ObjectStatus>().withDefault(const Constant('planned'))();
  TextColumn get priority =>
      textEnum<ObjectPriority>().withDefault(const Constant('normal'))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  RealColumn get geofenceRadius => real().withDefault(const Constant(50))();
  TextColumn get polygon =>
      text().map(const PolygonConverter()).withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}
