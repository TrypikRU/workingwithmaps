import 'package:drift/drift.dart';

import '../../sync/sync_status.dart';

@TableIndex(
  name: 'sync_queue_retry_created',
  columns: {#nextRetryAt, #createdAt},
)
class SyncQueue extends Table {
  // Заполняются атомарно перед первой отправкой и переживают потерю ответа.
  TextColumn get operationId => text().nullable()();
  TextColumn get payload => text().nullable()();
  TextColumn get syncStatus =>
      textEnum<SyncStatus>().withDefault(const Constant('pending'))();
  // Локальный номер операции; глобальные идентификаторы сущностей хранятся отдельно.
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // Drift DSL: CHECK ссылается на столбец, метод чтения свойства переопределяется генератором.
  IntColumn get attemptCount => integer()
      .withDefault(const Constant(0))
      // ignore: recursive_getters
      .check(attemptCount.isBiggerOrEqualValue(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
}
