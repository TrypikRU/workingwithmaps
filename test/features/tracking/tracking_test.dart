import 'dart:io';

import 'package:workingwithmaps/core/location/native_tracking.dart';

import '../../support/fake_native_tracking.dart';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/database/app_database.dart';
import 'package:workingwithmaps/core/database/database_provider.dart';
import 'package:workingwithmaps/core/location/location_controller.dart';
import 'package:workingwithmaps/core/location/location_service.dart';
import 'package:workingwithmaps/features/route/data/route_repository.dart';
import 'package:workingwithmaps/features/route/domain/route_status.dart';
import 'package:workingwithmaps/features/tracking/domain/location_point_filter.dart';
import 'package:workingwithmaps/features/tracking/presentation/tracking_controller.dart';
import 'package:workingwithmaps/features/visits/data/visits_repository.dart';

import '../../support/fake_location_service.dart';
import '../../support/test_database.dart';

LocationFix sample(
  double longitude,
  int second, {
  double accuracy = 8,
  double? speed = 1,
}) => LocationFix(
  latitude: 0,
  longitude: longitude,
  accuracy: accuracy,
  speed: speed,
  timestamp: DateTime.utc(2026, 9, 13, 12, 0, second),
);

void main() {
  const filter = LocationPointFilter();
  test('First valid point accepted; accuracy threshold is inclusive', () {
    expect(filter.reject(sample(0, 0, accuracy: 50)), isNull);
    expect(
      filter.reject(sample(0, 0, accuracy: 50.01)),
      PointRejection.accuracy,
    );
  });
  test('Movement below 5m rejected; realistic movement accepted', () {
    expect(
      filter.reject(sample(0.00001, 10), previous: sample(0, 0)),
      PointRejection.movement,
    );
    expect(filter.reject(sample(0.0001, 10), previous: sample(0, 0)), isNull);
  });
  test('Calculated speed ignores misleading reported speed', () {
    expect(
      filter.reject(sample(1, 1, speed: 0), previous: sample(0, 0)),
      PointRejection.speed,
    );
    expect(
      const LocationPointFilter(maxSpeed: 2)
          .reject(sample(0.0001, 1), previous: sample(0, 0)),
      PointRejection.speed,
    );
  });
  test('Duplicate/out-of-order timestamps and malformed samples discarded', () {
    expect(
      filter.reject(sample(0.0001, 0), previous: sample(0, 0)),
      PointRejection.timestamp,
    );
    expect(
      filter.reject(sample(0.0001, 1), previous: sample(0, 2)),
      PointRejection.timestamp,
    );
    expect(filter.reject(sample(double.nan, 0)), PointRejection.invalid);
    expect(filter.reject(sample(0, 0, accuracy: -1)), PointRejection.invalid);
    expect(filter.reject(sample(0, 0, speed: -1)), PointRejection.invalid);
  });

  test(
    'Start is idempotent; points + queue atomic; end rejects late fixes',
    () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repo = RouteRepository(db);
      final id = await repo.start();
      expect(await repo.start(), id);
      expect(await repo.append(id, 'a', sample(0, 0)), isTrue);
      expect(await repo.append(id, 'a', sample(0.00001, 1)), isFalse);
      expect(await repo.append(id, 'a', sample(1, 2)), isFalse);
      expect(await repo.append(id, 'a', sample(0.0001, 10)), isTrue);
      final route = (await repo.watchCurrent().first)!;
      expect(route.points, hasLength(2));
      expect(route.distance, closeTo(11.1195, 0.01));
      expect(route.points.first.fix.speed, 1);
      expect(
        await db.select(db.syncQueue).get(),
        hasLength(3),
      ); // Регистрация и две точки.
      await repo.finish(id);
      expect(await repo.append(id, 'a', sample(0.0002, 20)), isFalse);
      expect((await repo.watchCurrent().first)!.status, RouteStatus.completed);
      expect(await repo.start(), isNot(id));
    },
  );

  test('Point queue failure rolls back point and distance', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repo = RouteRepository(db);
    final id = await repo.start();
    await db.customStatement(
      "CREATE TEMP TRIGGER reject_point BEFORE INSERT ON sync_queue WHEN NEW.entity_type = 'location_point' BEGIN SELECT RAISE(ABORT, 'test'); END",
    );
    await expectLater(
      repo.append(id, 'a', sample(0, 0)),
      throwsA(isA<Exception>()),
    );
    expect((await repo.watchCurrent().first)!.points, isEmpty);
    expect(await db.select(db.syncQueue).get(), hasLength(1));
  });

  test('Active route and saved segments survive file restart; gaps are not distance', () async {
    final directory = await Directory.systemTemp.createTemp('field-tracking-');
    final file = File('${directory.path}/track.sqlite');
    var db = AppDatabase.forTesting(NativeDatabase(file));
    var repo = RouteRepository(db);
    final id = await repo.start();
    await repo.append(id, 'before-restart', sample(0, 0));
    await repo.append(id, 'before-restart', sample(0.0001, 10));
    await db.close();
    db = AppDatabase.forTesting(NativeDatabase(file));
    repo = RouteRepository(db);
    expect((await repo.watchCurrent().first)!.id, id);
    expect((await repo.watchCurrent().first)!.status, RouteStatus.active);
    expect(await repo.start(), id);
    await repo.append(id, 'after-restart', sample(1, 20));
    expect((await repo.watchCurrent().first)!.points, hasLength(3));
    expect((await repo.watchCurrent().first)!.distance, closeTo(11.1195, 0.01));
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'Check-in attaches to active route and appears in visited list',
    () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repo = RouteRepository(db);
      final id = await repo.start();
      await VisitsRepository(db).checkIn(
        objectId: 'demo-1',
        position: LocationFix(
          latitude: 61.659078,
          longitude: 50.794591,
          accuracy: 5,
          timestamp: DateTime.now(),
        ),
      );
      expect((await db.select(db.visits).getSingle()).routeId, id);
      expect((await repo.watchCurrent().first)!.visitedNames, [
        'Тепловой пункт № 1',
      ]);
    },
  );

  test(
    'Native recorder survives Flutter pause and ProviderContainer disposal',
    () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final service = FakeLocationService()..access = LocationAccess.granted;
      addTearDown(service.dispose);
      final native = FakeNativeTracking();
      ProviderContainer scope() => ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          locationServiceProvider.overrideWithValue(service),
          nativeTrackingProvider.overrideWithValue(native),
        ],
      );
      var container = scope();
      var tracker = container.read(trackingControllerProvider.notifier);
      await tracker.start();
      final id = native.routeId!;
      tracker.setForeground(false);
      container.dispose();
      expect(native.running, isTrue);
      expect(native.stops, 0);
      native.inbox.add(
        RecordedPoint(
          id: 'background-fix',
          routeId: id,
          segmentId: 'native-session',
          fix: sample(0, 0),
        ),
      );
      container = scope();
      addTearDown(container.dispose);
      tracker = container.read(trackingControllerProvider.notifier);
      await tracker.refresh();
      expect(
        (await RouteRepository(db).watchCurrent().first)!.points,
        hasLength(1),
      );
      expect(native.inbox, isEmpty);
      await tracker.finish();
      expect(native.running, isFalse);
      expect(native.stops, 1);
      expect(
        (await RouteRepository(db).watchCurrent().first)!.status,
        RouteStatus.completed,
      );
    },
  );
}
