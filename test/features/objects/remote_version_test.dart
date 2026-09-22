import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/features/objects/data/drift_objects_data_source.dart';
import 'package:workingwithmaps/features/objects/domain/technical_object.dart';

import '../../support/test_database.dart';

void main() {
  for (final staleVersion in <int?>[4, null]) {
    test(
      'Delayed GET version $staleVersion cannot replace acknowledged version 5',
      () async {
        final db = createTestDatabase(seedDemoData: false);
        addTearDown(db.close);
        final source = DriftObjectsDataSource(db);
        const current = TechnicalObject(
          id: 'target',
          name: 'Acknowledged',
          latitude: 0,
          longitude: 0,
          serverVersion: 5,
        );
        final now = DateTime.utc(2026);
        await source.mergeRemoteObjects([(object: current, updatedAt: now)]);
        await source.mergeRemoteObjects([
          (
            object: current.copyWith(
              name: 'Stale',
              serverVersion: staleVersion,
            ),
            updatedAt: now.subtract(const Duration(seconds: 1)),
          ),
        ]);
        expect((await source.watchObjects().first).single, current);
        await source.mergeRemoteObjects([
          (
            object: current.copyWith(name: 'New', serverVersion: 6),
            updatedAt: now.add(const Duration(seconds: 1)),
          ),
        ]);
        expect((await source.watchObjects().first).single.serverVersion, 6);
        expect(await db.select(db.syncQueue).get(), isEmpty);
      },
    );
  }
}
