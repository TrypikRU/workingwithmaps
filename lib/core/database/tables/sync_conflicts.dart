import 'package:drift/drift.dart';

/// Без FK на очередь: история сохраняется после явного разрешения конфликта.
class SyncConflicts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get queueId => integer().unique()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get requestPayload => text()();
  TextColumn get localPayload => text()();
  TextColumn get serverPayload => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get resolvedAt => dateTime().nullable()();
  TextColumn get resolution => text().nullable()();
}
