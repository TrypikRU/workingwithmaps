import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../utils/app_logger.dart';
import 'sync_status.dart';

/// Вызывается внутри транзакции изменения объекта. Только неотправленный tail
/// можно заменить: timeout/claim означает, что сервер уже мог принять запрос.
Future<void> enqueueObjectUpdate(
  AppDatabase db,
  String id,
  DateTime now,
) async {
  final queued =
      await (db.select(db.syncQueue)
            ..where(
              (q) => q.entityType.equals('object') & q.entityId.equals(id),
            )
            ..orderBy([(q) => OrderingTerm.desc(q.id)]))
          .get();
  // Объединяем только непрерывный хвост этой сущности. Иначе новая правка
  // могла бы переместиться перед delete или уже замороженным запросом.
  final unsent = queued
      .takeWhile(
        (q) =>
            ['upsert', 'patch', 'update'].contains(q.operation) &&
            q.syncStatus == SyncStatus.pending &&
            q.payload == null &&
            q.operationId == null &&
            q.attemptCount == 0,
      )
      .toList()
      .reversed
      .toList();
  if (unsent.isNotEmpty) {
    // Сохраняем старший queue id: watermark уже запущенного engine не теряет
    // выбранную операцию. Актуальное состояние будет заморожено при claim.
    for (final duplicate in unsent.skip(1)) {
      await (db.delete(
        db.syncQueue,
      )..where((q) => q.id.equals(duplicate.id))).go();
    }
    const AppLogger().log('sync.queue.coalesced', {'queueId': unsent.first.id});
    return;
  }
  await db
      .into(db.syncQueue)
      .insert(
        SyncQueueCompanion.insert(
          entityType: 'object',
          entityId: id,
          operation: 'patch',
          createdAt: Value(now),
        ),
      );
}
