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
import 'tables/app_metadata.dart';
import 'app_database.steps.dart';
import '../geometry/geo_point.dart';
import 'polygon_converter.dart';

part 'app_database.g.dart';

/// Одно постоянное подключение, общие миграции и транзакции всех features.
@DriftDatabase(
  tables: [
    TechnicalObjects,
    Routes,
    RouteObjects,
    Visits,
    LocationPoints,
    SyncQueue,
    AppMetadata,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase()
    : seedDemoData = true,
      super(driftDatabase(name: 'field_inspector'));

  /// В тестах можно отключить demo seed для проверки пустой БД и миграций.
  AppDatabase.forTesting(super.executor, {this.seedDemoData = true});

  final bool seedDemoData;
  int? _externalVersion;
  bool _checkingExternal = false;

  /// Independent Flutter engines cannot share an IsolateNameServer reliably.
  /// PRAGMA data_version detects commits on another SQLite connection; invalidate
  /// Drift streams without making UI read the remote API or polling every table.
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
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: stepByStep(
      from4To5: (m, schema) => transaction(() async {
        await m.addColumn(schema.objects, schema.objects.polygon);
        await m.addColumn(schema.objects, schema.objects.geofenceRadius);
        // Backfill only the untouched, known demo location. User objects and
        // relocated demo objects retain an empty polygon; no real boundaries inferred.
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
        // Используем неизменяемый snapshot v2, а не текущие определения таблиц:
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
      if (seedDemoData) await _seedObjectsIfEmpty();
    },
  );

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
