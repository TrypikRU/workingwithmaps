import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/database/app_database.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;
import 'generated/schema_v5.dart' as v5;

void main() {
  final verifier = SchemaVerifier(GeneratedHelper());

  test(
    'v4 objects survive v5 geometry migration; known demo gets a boundary',
    () async {
      await verifier.testWithDataIntegrity(
        oldVersion: 4,
        newVersion: 5,
        createOld: v4.DatabaseAtV4.new,
        createNew: v5.DatabaseAtV5.new,
        openTestedDatabase: (c) =>
            AppDatabase.forTesting(c, seedDemoData: false),
        createItems: (batch, db) {
          batch.insert(
            db.objects,
            v4.ObjectsCompanion.insert(
              id: 'legacy',
              name: 'Saved',
              latitude: 1,
              longitude: 2,
            ),
          );
          batch.insert(
            db.objects,
            v4.ObjectsCompanion.insert(
              id: 'demo-1',
              name: 'Demo',
              latitude: 55.7586,
              longitude: 37.6442,
            ),
          );
        },
        validateItems: (db) async {
          final rows = await db.select(db.objects).get();
          final old = rows.singleWhere((r) => r.id == 'legacy');
          expect(old.name, 'Saved');
          expect(old.polygon, '[]');
          expect(old.geofenceRadius, 50);
          expect(
            rows.singleWhere((r) => r.id == 'demo-1').polygon,
            contains('55.7583'),
          );
          expect(await db.select(db.syncQueue).get(), isEmpty);
        },
      );
    },
  );

  test('v3 route and points survive v4 segment migration', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 3,
      newVersion: 5,
      createOld: v3.DatabaseAtV3.new,
      createNew: v5.DatabaseAtV5.new,
      openTestedDatabase: (c) => AppDatabase.forTesting(c, seedDemoData: false),
      createItems: (batch, db) {
        batch.insert(
          db.routes,
          v3.RoutesCompanion.insert(id: 'legacy-route', name: 'Legacy'),
        );
        batch.insert(
          db.locationPoints,
          v3.LocationPointsCompanion.insert(
            id: 'legacy-point',
            routeId: 'legacy-route',
            latitude: 1,
            longitude: 2,
            accuracy: 5,
            timestamp: 1000,
          ),
        );
      },
      validateItems: (db) async {
        final point = await db.select(db.locationPoints).getSingle();
        expect(point.id, 'legacy-point');
        expect(point.latitude, 1);
        expect(point.segmentId, isNull);
        expect((await db.select(db.routes).getSingle()).id, 'legacy-route');
      },
    );
  });

  test('v2 queue survives migration with pending status', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 2,
      newVersion: 5,
      createOld: v2.DatabaseAtV2.new,
      createNew: v5.DatabaseAtV5.new,
      openTestedDatabase: (connection) =>
          AppDatabase.forTesting(connection, seedDemoData: false),
      createItems: (batch, db) => batch.insert(
        db.syncQueue,
        v2.SyncQueueCompanion.insert(
          entityType: 'visit',
          entityId: 'old-visit',
          operation: 'upsert',
        ),
      ),
      validateItems: (db) async {
        final row = await db.select(db.syncQueue).getSingle();
        expect(row.entityId, 'old-visit');
        expect(row.syncStatus, 'pending');
        expect(row.payload, isNull);
        expect(row.operationId, isNull);
      },
    );
  });

  test(
    'v1 upgrades to exact v5 schema including indexes and foreign keys',
    () async {
      final schema = await verifier.schemaAt(1);
      final database = AppDatabase.forTesting(
        schema.newConnection(),
        seedDemoData: false,
      );
      addTearDown(database.close);
      await verifier.migrateAndValidate(database, 5);
    },
  );

  test('v1 rows survive migration; non-empty database is not seeded', () async {
    await verifier.testWithDataIntegrity(
      oldVersion: 1,
      newVersion: 5,
      createOld: v1.DatabaseAtV1.new,
      createNew: v5.DatabaseAtV5.new,
      openTestedDatabase: (connection) => AppDatabase.forTesting(connection),
      createItems: (batch, oldDb) {
        batch.insert(
          oldDb.technicalObjects,
          v1.TechnicalObjectsCompanion.insert(
            id: 'legacy-object',
            name: 'Сохранённый объект',
            latitude: 59.93,
            longitude: 30.31,
          ),
        );
      },
      validateItems: (newDb) async {
        final rows = await newDb.select(newDb.objects).get();
        expect(rows, hasLength(1));
        final object = rows.single;
        expect(object.id, 'legacy-object');
        expect(object.name, 'Сохранённый объект');
        expect(object.latitude, 59.93);
        expect(object.longitude, 30.31);
        expect(object.address, '');
        expect(object.status, 'planned');
        expect(object.priority, 'normal');
        expect(object.updatedAt, greaterThan(0));
        expect(await newDb.select(newDb.syncQueue).get(), isEmpty);
      },
    );
  });
}
