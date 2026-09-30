import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_status.dart';
import '../../../core/sync/queue_coalescing.dart';
import '../../../core/geometry/circular_geofence.dart';
import '../../../core/geometry/geo_point.dart';
import '../domain/technical_object.dart';

/// Детали SQL и преобразование строк Drift остаются внутри слоя данных.
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
    // visited при ручном обновлении до подтверждения посещения SyncEngine.
    final localVisits = await _database.select(_database.visits).get();
    protectedIds.addAll(
      localVisits
          .where((visit) => visit.syncStatus != SyncStatus.synced)
          .map((visit) => visit.objectId),
    );
    final localVersions = {
      for (final row
          in await _database.select(_database.technicalObjects).get())
        row.id: row.serverVersion,
    };
    await _database.batch((batch) {
      for (final record in records) {
        final object = record.object;
        if (protectedIds.contains(object.id)) continue;
        // GET может завершиться после ACK или более нового GET. Удалённая
        // очередь уже не защищает объект, поэтому версия не должна убывать.
        final version = localVersions[object.id];
        if (version != null &&
            (object.serverVersion == null || object.serverVersion! < version)) {
          continue;
        }
        batch.insertAllOnConflictUpdate(_database.technicalObjects, [
          TechnicalObjectsCompanion.insert(
            id: object.id,
            name: object.name,
            address: Value(object.address),
            latitude: object.latitude,
            longitude: object.longitude,
            status: Value(object.status),
            priority: Value(object.priority),
            serverVersion: Value(object.serverVersion),
            updatedAt: Value(record.updatedAt),
            // API пока не содержит контракта геометрии. При отсутствии значений обновление сохраняет
            // локальные polygon/radius; новые строки получают значения по умолчанию.
          ),
        ]);
      }
    });
    // Загрузка с сервера не создаёт исходящих операций. Отсутствующие в ответе
    // записи не удаляем: контракт ещё не содержит отметок удалённых объектов.
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
              serverVersion: row.serverVersion,
              geofenceRadius: row.geofenceRadius,
              polygon: row.polygon,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<void> saveObject(TechnicalObject object) =>
      _database.transaction(() async {
        CircularGeofence(
          center: GeoPoint(object.latitude, object.longitude),
          radius: object.geofenceRadius,
        );
        final now = DateTime.now().toUtc();
        // Интерфейс может редактировать старый снимок после подтверждения. Версию сервера берём
        // из текущей БД, а не откатываем её значением из формы редактирования.
        final existing = await (_database.select(
          _database.technicalObjects,
        )..where((o) => o.id.equals(object.id))).getSingleOrNull();
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
                serverVersion: Value(
                  existing?.serverVersion ?? object.serverVersion,
                ),
                updatedAt: Value(now),
                geofenceRadius: Value(object.geofenceRadius),
                polygon: Value(object.polygon),
              ),
            );
        // Нет состояния «объект сохранён, но операция синхронизации потеряна».
        // Ошибка любой записи откатывает обе; HTTP в пути локальной записи отсутствует.
        await enqueueObjectUpdate(_database, object.id, now);
      });
}
