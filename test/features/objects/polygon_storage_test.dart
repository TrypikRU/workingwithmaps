import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/database/app_database.dart';
import 'package:workingwithmaps/core/geometry/geo_point.dart';
import 'package:workingwithmaps/features/objects/domain/technical_object.dart';
import 'package:workingwithmaps/features/objects/data/drift_objects_data_source.dart';

void main() {
  test(
    'Polygon JSON, SQLite restart and remote refresh preserve local geometry',
    () async {
      final directory = await Directory.systemTemp.createTemp('geometry-db-');
      final file = File('${directory.path}/geometry.sqlite');
      var db = AppDatabase.forTesting(
        NativeDatabase(file),
        seedDemoData: false,
      );
      var source = DriftObjectsDataSource(db);
      const object = TechnicalObject(
        id: 'polygon',
        name: 'Area',
        latitude: 1,
        longitude: 1,
        geofenceRadius: 75,
        polygon: [
          GeoPoint(0, 0),
          GeoPoint(0, 2),
          GeoPoint(2, 2),
          GeoPoint(2, 0),
        ],
      );
      expect(TechnicalObject.fromJson(object.toJson()), object);
      await source.saveObject(object);
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(file), seedDemoData: false);
      source = DriftObjectsDataSource(db);
      expect((await source.watchObjects().first).single, object);
      await db.delete(db.syncQueue).go(); // Local edit already acknowledged.
      await source.mergeRemoteObjects([
        (
          object: object.copyWith(
            name: 'Server',
            polygon: [],
            geofenceRadius: 50,
          ),
          updatedAt: DateTime.now(),
        ),
      ]);
      final merged = (await source.watchObjects().first).single;
      expect(merged.name, 'Server');
      expect(merged.polygon, object.polygon);
      expect(merged.geofenceRadius, 75);
      await expectLater(
        source.saveObject(object.copyWith(polygon: [const GeoPoint(0, 0)])),
        throwsArgumentError,
      );
      expect(
        (await source.watchObjects().first).single.polygon,
        object.polygon,
      );
      expect(await db.select(db.syncQueue).get(), isEmpty);
      await db.close();
      await directory.delete(recursive: true);
    },
  );
}
