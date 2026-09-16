import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/database/app_database.dart';
import 'package:workingwithmaps/core/sync/sync_status.dart';
import 'package:workingwithmaps/features/objects/data/demo_objects.dart';
import 'package:workingwithmaps/features/objects/data/drift_objects_data_source.dart';
import 'package:workingwithmaps/features/objects/data/objects_repository.dart';
import 'package:workingwithmaps/features/objects/domain/technical_object.dart';
import 'package:workingwithmaps/features/visits/domain/visit_status.dart';

import '../../support/test_database.dart';

void main() {
  test(
    'all eight tables exist; seed creates objects but no pending operations',
    () async {
      final database = createTestDatabase();
      addTearDown(database.close);
      final tables = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      expect(tables.map((row) => row.read<String>('name')).toSet(), {
        'objects',
        'routes',
        'route_objects',
        'visits',
        'location_points',
        'sync_queue',
        'sync_conflicts',
        'app_metadata',
      });
      expect(
        await database.select(database.technicalObjects).get(),
        hasLength(demoObjects.length),
      );
      expect(await database.select(database.syncQueue).get(), isEmpty);
      expect(
        (await database.select(database.appMetadata).getSingle()).key,
        'demo_objects_seeded_at',
      );
    },
  );

  test(
    'file database preserves edits, queue and seed metadata across restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'field_inspector_db_test_',
      );
      final file = File('${directory.path}/database.sqlite');
      var database = AppDatabase.forTesting(NativeDatabase(file));
      try {
        final source = ObjectsRepository(DriftObjectsDataSource(database));
        final objects = await source.watchObjects().first;
        final changed = objects.first.copyWith(
          name: 'Изменено локально',
          status: ObjectStatus.error,
        );
        final seedMetadata = await database
            .select(database.appMetadata)
            .getSingle();
        await source.saveObject(changed);
        await database.close();
        database = AppDatabase.forTesting(NativeDatabase(file));
        final afterRestart = await ObjectsRepository(
          DriftObjectsDataSource(database),
        ).watchObjects().first;
        expect(afterRestart, hasLength(demoObjects.length));
        expect(
          afterRestart.singleWhere((object) => object.id == changed.id),
          changed,
        );
        expect(await database.select(database.syncQueue).get(), hasLength(1));
        expect(
          (await database.select(database.appMetadata).getSingle()).value,
          seedMetadata.value,
        );
      } finally {
        await database.close();
        await file.delete();
        await directory.delete();
      }
    },
  );

  test('foreign keys, route order and enum name converters work', () async {
    final database = createTestDatabase(seedDemoData: false);
    addTearDown(database.close);
    await database
        .into(database.technicalObjects)
        .insert(
          TechnicalObjectsCompanion.insert(
            id: 'object',
            name: 'Объект',
            latitude: 55,
            longitude: 37,
          ),
        );
    await database
        .into(database.routes)
        .insert(RoutesCompanion.insert(id: 'route', name: 'Обход'));
    await database
        .into(database.routeObjects)
        .insert(
          RouteObjectsCompanion.insert(
            routeId: 'route',
            objectId: 'object',
            position: 0,
          ),
        );
    await expectLater(
      database
          .into(database.routeObjects)
          .insert(
            RouteObjectsCompanion.insert(
              routeId: 'route',
              objectId: 'missing',
              position: 1,
            ),
          ),
      throwsA(isA<Exception>()),
    );
    await database
        .into(database.technicalObjects)
        .insert(
          TechnicalObjectsCompanion.insert(
            id: 'other',
            name: 'Другой объект',
            latitude: 55,
            longitude: 37,
          ),
        );
    await expectLater(
      database
          .into(database.routeObjects)
          .insert(
            RouteObjectsCompanion.insert(
              routeId: 'route',
              objectId: 'other',
              position: 0,
            ),
          ),
      throwsA(isA<Exception>()),
    );

    for (final status in SyncStatus.values) {
      await database
          .into(database.visits)
          .insert(
            VisitsCompanion.insert(
              id: 'visit-${status.name}',
              objectId: 'object',
              routeId: const Value('route'),
              status: const Value(VisitStatus.completed),
              latitude: 55,
              longitude: 37,
              accuracy: 8,
              syncStatus: Value(status),
              serverVersion: const Value(3),
            ),
          );
    }
    final visits = await database.select(database.visits).get();
    expect(
      visits.map((visit) => visit.syncStatus).toSet(),
      SyncStatus.values.toSet(),
    );
    final raw = await database
        .customSelect('SELECT sync_status FROM visits')
        .get();
    expect(
      raw.map((row) => row.read<String>('sync_status')).toSet(),
      SyncStatus.values.map((status) => status.name).toSet(),
    );
    expect(visits.every((visit) => visit.serverVersion == 3), isTrue);
    final timestamp = DateTime.utc(2026, 9, 12);
    await database
        .into(database.locationPoints)
        .insert(
          LocationPointsCompanion.insert(
            id: 'point',
            routeId: 'route',
            latitude: 55,
            longitude: 37,
            accuracy: 4,
            timestamp: timestamp,
          ),
        );
    final point = await database.select(database.locationPoints).getSingle();
    expect(point.speed, isNull);
    expect(point.syncStatus, SyncStatus.pending);
    expect(point.timestamp.toUtc(), timestamp);
    // Несинхронизированные зависимые данные не удаляются каскадно.
    await expectLater(
      (database.delete(
        database.routes,
      )..where((route) => route.id.equals('route'))).go(),
      throwsA(isA<Exception>()),
    );
    expect(await database.select(database.locationPoints).get(), hasLength(1));
  });
}
