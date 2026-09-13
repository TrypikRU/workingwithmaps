import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_status.dart';
import '../../../core/geometry/circular_geofence.dart';
import '../../../core/geometry/geo_point.dart';
import '../domain/technical_object.dart';

/// Детали SQL и преобразование Drift rows остаются внутри data-слоя.
class DriftObjectsDataSource {
  DriftObjectsDataSource(this._database);

  final AppDatabase _database;

  Future<void> mergeRemoteObjects(
    List<({TechnicalObject object, DateTime updatedAt})> records,
  ) => _database.transaction(() async {
    // Проверяем очередь внутри той же транзакции: локальная правка,
    // сделанная во время HTTP-запроса, также защищена от перезаписи.
    final pending = await (_database.select(
      _database.syncQueue,
    )..where((row) => row.entityType.equals('object'))).get();
    final protectedIds = pending.map((row) => row.entityId).toSet();
    // До отправки визита сервер ещё может вернуть planned. Не теряем локальный
    // visited при ручном refresh до подтверждения визита SyncEngine.
    final localVisits = await _database.select(_database.visits).get();
    protectedIds.addAll(
      localVisits
          .where((visit) => visit.syncStatus != SyncStatus.synced)
          .map((visit) => visit.objectId),
    );
    await _database.batch((batch) {
      for (final record in records) {
        final object = record.object;
        if (protectedIds.contains(object.id)) continue;
        batch.insertAllOnConflictUpdate(_database.technicalObjects, [
          TechnicalObjectsCompanion.insert(
            id: object.id,
            name: object.name,
            address: Value(object.address),
            latitude: object.latitude,
            longitude: object.longitude,
            status: Value(object.status),
            priority: Value(object.priority),
            updatedAt: Value(record.updatedAt),
            // API has no geometry contract yet. Absent values preserve locally
            // stored polygon/radius during refresh (new rows receive defaults).
          ),
        ]);
      }
    });
    // Загрузка с сервера не создаёт исходящих операций. Отсутствующие в ответе
    // записи не удаляем: контракт ещё не содержит tombstones удалённых объектов.
  });

  Stream<List<TechnicalObject>> watchObjects() {
    final query = _database.select(_database.technicalObjects)
      ..orderBy([
        (table) => OrderingTerm.asc(table.name),
        (table) => OrderingTerm.asc(table.id),
      ]);
    return query.watch().map(
      (rows) => rows
          .map(
            (row) => TechnicalObject(
              id: row.id,
              name: row.name,
              address: row.address,
              latitude: row.latitude,
              longitude: row.longitude,
              status: row.status,
              priority: row.priority,
              geofenceRadius: row.geofenceRadius,
              polygon: row.polygon,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<void> saveObject(
    TechnicalObject object,
  ) => _database.transaction(() async {
    CircularGeofence(
      center: GeoPoint(object.latitude, object.longitude),
      radius: object.geofenceRadius,
    );
    final now = DateTime.now().toUtc();
    await _database
        .into(_database.technicalObjects)
        .insertOnConflictUpdate(
          TechnicalObjectsCompanion.insert(
            id: object.id,
            name: object.name,
            address: Value(object.address),
            latitude: object.latitude,
            longitude: object.longitude,
            status: Value(object.status),
            priority: Value(object.priority),
            updatedAt: Value(now),
            geofenceRadius: Value(object.geofenceRadius),
            polygon: Value(object.polygon),
          ),
        );
    // Нет состояния «объект сохранён, но операция синхронизации потеряна».
    // Ошибка любой записи откатывает обе; HTTP в пути локальной записи отсутствует.
    await _database
        .into(_database.syncQueue)
        .insert(
          SyncQueueCompanion.insert(
            entityType: 'object',
            entityId: object.id,
            operation: 'upsert',
            createdAt: Value(now),
          ),
        );
  });
}
