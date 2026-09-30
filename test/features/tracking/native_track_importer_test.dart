import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/location/native_tracking.dart';
import 'package:workingwithmaps/features/route/data/route_repository.dart';
import 'package:workingwithmaps/features/tracking/data/native_track_importer.dart';

import '../../support/fake_native_tracking.dart';
import '../../support/test_database.dart';
import 'tracking_test.dart' show sample;

void main() {
  test('Native backlog -> atomic Drift + queue; lost ACK is safe after remote sync', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = RouteRepository(db);
    final routeId = await repository.start();
    final native = FakeNativeTracking()..failAck = true;
    native.inbox.add(
      RecordedPoint(
        id: 'native-1',
        routeId: routeId,
        segmentId: 's',
        fix: sample(0, 0),
      ),
    );
    final importer = NativeTrackImporter(native, repository);
    await expectLater(importer.drain(), throwsStateError);
    expect(await db.select(db.locationPoints).get(), hasLength(1));
    expect(await db.select(db.syncQueue).get(), hasLength(2));
    await db
        .delete(db.syncQueue)
        .go(); // Имитируем исходящую очередь, уже подтверждённую сервером.
    native.failAck = false;
    await importer.drain();
    expect(native.inbox, isEmpty);
    expect(await db.select(db.locationPoints).get(), hasLength(1));
    expect(await db.select(db.syncQueue).get(), isEmpty);
  });
  test(
    'Drift queue failure rolls back point and never ACKs the native inbox',
    () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = RouteRepository(db);
      final id = await repository.start();
      final native = FakeNativeTracking();
      native.inbox.add(
        RecordedPoint(
          id: 'native-2',
          routeId: id,
          segmentId: 's',
          fix: sample(0, 0),
        ),
      );
      await db.customStatement(
        "CREATE TRIGGER fail_queue BEFORE INSERT ON sync_queue BEGIN SELECT RAISE(ABORT, 'disk'); END",
      );
      await expectLater(
        NativeTrackImporter(native, repository).drain(),
        throwsA(anything),
      );
      expect(await db.select(db.locationPoints).get(), isEmpty);
      expect(native.inbox, hasLength(1));
      await db.customStatement('DROP TRIGGER fail_queue');
      await repository.finish(id); // Поздний импорт после перезапуска интерфейса или завершения обхода допустим.
      await NativeTrackImporter(native, repository).drain();
      expect(native.inbox, isEmpty);
      expect((await repository.watchCurrent().first)!.points, hasLength(1));
    },
  );
}
