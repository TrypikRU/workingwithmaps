import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../../features/objects/data/demo_objects.dart';
import '../../features/objects/data/tables/technical_objects.dart';
import '../../features/objects/domain/technical_object.dart';
import '../../features/route/data/tables/routes.dart';
import '../../features/route/data/tables/route_objects.dart';
import '../../features/route/domain/route_status.dart';
import '../../features/visits/data/tables/visits.dart';
import '../../features/visits/domain/visit_status.dart';
import '../../features/tracking/data/tables/location_points.dart';
import '../sync/sync_status.dart';
import 'tables/sync_queue.dart';
import 'tables/sync_conflicts.dart';
import 'tables/app_metadata.dart';
import 'app_database.steps.dart';
import '../geometry/geo_point.dart';
import 'polygon_converter.dart';

part 'app_database.g.dart';

/// Одно постоянное подключение, общие миграции и транзакции всех функциональных модулей.
@DriftDatabase(
  tables: [
    TechnicalObjects,
    Routes,
    RouteObjects,
    Visits,
    LocationPoints,
    SyncQueue,
    SyncConflicts,
    AppMetadata,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase()
    : seedDemoData = true,
      super(driftDatabase(name: 'field_inspector'));

  /// В тестах можно отключить демонстрационные данные для проверки пустой БД и миграций.
  AppDatabase.forTesting(super.executor, {this.seedDemoData = true});

  final bool seedDemoData;
  int? _externalVersion;
  bool _checkingExternal = false;

  /// Независимые движки Flutter не могут надёжно использовать общий IsolateNameServer.
  /// PRAGMA data_version обнаруживает фиксацию в другом подключении SQLite; обновляем
  /// потоки Drift без запросов к удалённому API из интерфейса и без опроса каждой таблицы.
  Future<void> refreshExternalChanges() async {
    if (_checkingExternal) return;
    _checkingExternal = true;
    try {
      final row = await customSelect('PRAGMA data_version').getSingle();
      final version = row.read<int>('data_version');
      if (version != _externalVersion) {
        _externalVersion = version;
        notifyUpdates({
          for (final table in allTables) TableUpdate(table.actualTableName),
        });
      }
    } finally {
      _checkingExternal = false;
    }
  }

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: stepByStep(
      from5To6: (m, schema) => transaction(() async {
        await m.addColumn(schema.objects, schema.objects.serverVersion);
        await m.createTable(schema.syncConflicts);
        // Старые 409 уже блокируют очередь. Переносим их в диагностику, чтобы
        // пользователь мог загрузить current и разрешить их после обновления.
        await customStatement('''
          INSERT INTO sync_conflicts
            (queue_id, entity_type, entity_id, request_payload, local_payload, created_at)
          SELECT id, entity_type, entity_id, COALESCE(payload, '{}'),
            COALESCE(payload, '{}'), created_at FROM sync_queue
          WHERE sync_status = 'failed' AND CASE WHEN json_valid(last_error)
            THEN json_extract(last_error, '\$.kind') = 'conflict' ELSE 0 END
        ''');
      }),
      from4To5: (m, schema) => transaction(() async {
        await m.addColumn(schema.objects, schema.objects.polygon);
        await m.addColumn(schema.objects, schema.objects.geofenceRadius);
        // Дополняем только неизменённый известный демонстрационный объект. Пользовательские и
        // перемещённые учебные объекты сохраняют пустой контур; реальные границы не предполагаются.
        await customStatement(
          '''UPDATE objects SET polygon =
          '[{"latitude":55.7583,"longitude":37.6437},{"latitude":55.7583,"longitude":37.6447},{"latitude":55.7589,"longitude":37.6447},{"latitude":55.7589,"longitude":37.6437}]'
          WHERE id='demo-1' AND latitude=55.7586 AND longitude=37.6442 AND polygon='[]' ''',
        );
      }),
      from3To4: (m, schema) => transaction(() async {
        await m.addColumn(
          schema.locationPoints,
          schema.locationPoints.segmentId,
        );
      }),
      from2To3: (m, schema) => transaction(() async {
        await m.addColumn(schema.syncQueue, schema.syncQueue.operationId);
        await m.addColumn(schema.syncQueue, schema.syncQueue.payload);
        await m.addColumn(schema.syncQueue, schema.syncQueue.syncStatus);
      }),
      from1To2: (m, schema) => transaction(() async {
        // Используем неизменяемый снимок v2, а не текущие определения таблиц:
        // будущая v3 не должна случайно изменить поведение перехода v1 → v2.
        await m.createTable(schema.objects);
        await customStatement('''
        INSERT INTO objects (id, name, latitude, longitude)
        SELECT id, name, latitude, longitude FROM technical_objects
      ''');
        await customStatement('DROP TABLE technical_objects');
        await m.createTable(schema.routes);
        await m.createTable(schema.routeObjects);
        await m.createTable(schema.visits);
        await m.createTable(schema.locationPoints);
        await m.createTable(schema.syncQueue);
        await m.createTable(schema.appMetadata);
        await m.createIndex(schema.visitsObjectCreated);
        await m.createIndex(schema.locationPointsRouteTime);
        await m.createIndex(schema.syncQueueRetryCreated);
      }),
    ),
    beforeOpen: (details) async {
      await customStatement('PRAGMA busy_timeout = 5000');
      // SQLite не включает FK автоматически. Запрещаем потерю зависимых
      // визитов/точек маршрута через случайное удаление родительской записи.
      await customStatement('PRAGMA foreign_keys = ON');
      if (seedDemoData) {
        await _relocateLegacyDemoObjects();
        await _seedObjectsIfEmpty();
      }
    },
  );

  /// Миграция демонстрационных данных без изменения схемы и очистки базы. Точное совпадение
  /// старого адреса и геометрии делает её повторяемой, в том числе между движками.
  /// Очередь и факты визитов/треков не переписываем: их координаты исторические.
  Future<void> _relocateLegacyDemoObjects() => transaction(() async {
    for (final object in demoObjects) {
      final old = legacyDemoLocations[object.id]!;
      final row = await (select(
        technicalObjects,
      )..where((t) => t.id.equals(object.id))).getSingleOrNull();
      if (row == null) continue;
      final hasLegacyPolygon =
          object.id == 'demo-1' &&
          row.polygon.length == legacyDemoPolygon.length &&
          row.polygon.indexed.every(
            (entry) =>
                entry.$2.latitude == legacyDemoPolygon[entry.$1].latitude &&
                entry.$2.longitude == legacyDemoPolygon[entry.$1].longitude,
          );
      final isOldLocation =
          row.address == old.address &&
          row.latitude == old.latitude &&
          row.longitude == old.longitude;
      // API пока не передаёт polygon. Если обновление уже перенесло точку, старую
      // узнаваемую учебную границу также переносим при следующем открытии базы.
      final isNewLocation =
          row.address == object.address &&
          row.latitude == object.latitude &&
          row.longitude == object.longitude;
      if (!isOldLocation && !(isNewLocation && hasLegacyPolygon)) continue;
      if (row.polygon.isNotEmpty && !hasLegacyPolygon) continue;
      final queued =
          await (select(syncQueue)
                ..where(
                  (q) =>
                      q.entityType.equals('object') &
                      q.entityId.equals(object.id),
                )
                ..limit(1))
              .get();
      // Даже ошибочная операция с зафиксированным запросом должна разрешаться обычным SyncEngine,
      // иначе её повтор мог бы молча вернуть старую геометрию на сервер.
      if (queued.isNotEmpty) continue;
      await (update(
        technicalObjects,
      )..where((t) => t.id.equals(object.id))).write(
        TechnicalObjectsCompanion(
          address: Value(object.address),
          latitude: Value(object.latitude),
          longitude: Value(object.longitude),
          polygon: Value(object.polygon),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    }
  });

  Future<void> _seedObjectsIfEmpty() => transaction(() async {
    final existing = await (select(technicalObjects)..limit(1)).get();
    if (existing.isNotEmpty) return;
    // Проверка и вставка одной транзакцией: экран видит готовый набор.
    // Непустую БД никогда не перезаписываем демонстрационными значениями.
    await batch((batch) {
      batch.insertAll(
        technicalObjects,
        demoObjects
            .map(
              (object) => TechnicalObjectsCompanion.insert(
                id: object.id,
                name: object.name,
                address: Value(object.address),
                latitude: object.latitude,
                longitude: object.longitude,
                status: Value(object.status),
                priority: Value(object.priority),
                geofenceRadius: Value(object.geofenceRadius),
                polygon: Value(object.polygon),
              ),
            )
            .toList(),
      );
    });
    await into(appMetadata).insertOnConflictUpdate(
      AppMetadataCompanion.insert(
        key: 'demo_objects_seeded_at',
        value: DateTime.now().toUtc().toIso8601String(),
      ),
    );
  });
}
