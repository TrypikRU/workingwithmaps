import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/database/app_database.dart';
import 'package:workingwithmaps/core/geometry/geo_point.dart';
import 'package:workingwithmaps/features/objects/data/demo_objects.dart';
import 'package:workingwithmaps/features/objects/domain/technical_object.dart';

void main() {
  Future<void> withDatabase(Future<void> Function(File) test) async {
    final directory = await Directory.systemTemp.createTemp('demo-relocation-');
    try {
      await test(File('${directory.path}/local.sqlite'));
    } finally {
      await directory.delete(recursive: true);
    }
  }

  Future<void> insertLegacy(AppDatabase db) async {
    for (final entry in legacyDemoLocations.entries) {
      await db
          .into(db.technicalObjects)
          .insert(
            TechnicalObjectsCompanion.insert(
              id: entry.key,
              name: 'User name ${entry.key}',
              address: Value(entry.value.address),
              latitude: entry.value.latitude,
              longitude: entry.value.longitude,
              status: const Value(ObjectStatus.visited),
              serverVersion: const Value(4),
              polygon: Value(entry.key == 'demo-1' ? legacyDemoPolygon : []),
            ),
          );
    }
  }

  test(
    'Legacy seed relocates on reopen without losing history and is idempotent',
    () async {
      await withDatabase((file) async {
        var db = AppDatabase.forTesting(
          NativeDatabase(file),
          seedDemoData: false,
        );
        try {
          await insertLegacy(db);
          // Simulate a server refresh before the app upgrade: API updates the
          // coordinates but currently has no polygon field.
          final destination = demoObjects.first;
          await (db.update(
            db.technicalObjects,
          )..where((t) => t.id.equals(destination.id))).write(
            TechnicalObjectsCompanion(
              address: Value(destination.address),
              latitude: Value(destination.latitude),
              longitude: Value(destination.longitude),
            ),
          );
          await db.customStatement(
            "INSERT INTO visits (id, object_id, latitude, longitude, accuracy) VALUES ('visit', 'demo-1', 55.7586, 37.6442, 5)",
          );
          await db
              .into(db.syncQueue)
              .insert(
                SyncQueueCompanion.insert(
                  entityType: 'visit',
                  entityId: 'visit',
                  operation: 'create',
                ),
              );
          await db.close();
          db = AppDatabase.forTesting(NativeDatabase(file));
          final rows = await db.select(db.technicalObjects).get();
          for (final object in demoObjects) {
            final row = rows.singleWhere((r) => r.id == object.id);
            expect(row.address, object.address);
            expect(row.latitude, object.latitude);
            expect(row.longitude, object.longitude);
            expect(row.polygon, object.polygon);
            expect(row.name, 'User name ${object.id}');
            expect(row.status, ObjectStatus.visited);
            expect(row.serverVersion, 4);
          }
          expect((await db.select(db.visits).getSingle()).latitude, 55.7586);
          expect((await db.select(db.syncQueue).getSingle()).entityId, 'visit');
          await db.close();
          db = AppDatabase.forTesting(NativeDatabase(file));
          expect(
            (await db.select(db.technicalObjects).get()).map((r) => r.toJson()),
            rows.map((r) => r.toJson()),
          );
        } finally {
          await db.close();
        }
      });
    },
  );

  test('Relocation preserves pending edits and custom addresses, coordinates and polygons', () async {
    await withDatabase((file) async {
      var db = AppDatabase.forTesting(
        NativeDatabase(file),
        seedDemoData: false,
      );
      try {
        await insertLegacy(db);
        await db
            .into(db.syncQueue)
            .insert(
              SyncQueueCompanion.insert(
                entityType: 'object',
                entityId: 'demo-1',
                operation: 'upsert',
                payload: const Value('{"frozen":true}'),
                operationId: const Value('original'),
              ),
            );
        await (db.update(
          db.technicalObjects,
        )..where((t) => t.id.equals('demo-2'))).write(
          const TechnicalObjectsCompanion(address: Value('User address')),
        );
        await (db.update(db.technicalObjects)
              ..where((t) => t.id.equals('demo-3')))
            .write(const TechnicalObjectsCompanion(latitude: Value(60)));
        await (db.update(
          db.technicalObjects,
        )..where((t) => t.id.equals('demo-4'))).write(
          const TechnicalObjectsCompanion(
            polygon: Value([GeoPoint(1, 1), GeoPoint(1, 2), GeoPoint(2, 1)]),
          ),
        );
        final unchanged = (await db.select(db.technicalObjects).get())
            .where((r) => r.id != 'demo-5')
            .map((r) => r.toJson())
            .toList();
        final queue = await db.select(db.syncQueue).get();
        await db.close();
        db = AppDatabase.forTesting(NativeDatabase(file));
        expect(
          (await db.select(db.technicalObjects).get())
              .where((r) => r.id != 'demo-5')
              .map((r) => r.toJson()),
          unchanged,
        );
        expect(await db.select(db.syncQueue).get(), queue);
      } finally {
        await db.close();
      }
    });
  });
}
