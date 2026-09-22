import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/geometry/geo_point.dart';
import 'package:workingwithmaps/core/sync/sync_status.dart';
import 'package:workingwithmaps/features/objects/data/drift_objects_data_source.dart';
import 'package:workingwithmaps/features/objects/domain/technical_object.dart';
import 'package:workingwithmaps/features/visits/data/visits_repository.dart';
import 'package:workingwithmaps/features/visits/domain/check_in_policy.dart';
import 'package:workingwithmaps/features/visits/domain/visit_status.dart';

import '../../support/fake_location_service.dart';
import '../../support/test_database.dart';

void main() {
  const policy = CheckInPolicy();
  const target = GeoPoint(0, 0);
  const object = TechnicalObject(
    id: 'target',
    name: 'Объект',
    latitude: 0,
    longitude: 0,
  );
  test('Inside radius and accuracy at limit allow check-in', () {
    final result = policy.evaluate(
      target,
      fix(latitude: 0, longitude: 0.0004, accuracy: 50),
    );
    expect(result.allowed, isTrue);
    expect(result.distance, closeTo(44.478, 0.01));
  });
  test('Outside radius blocks check-in', () {
    expect(
      policy.evaluate(target, fix(latitude: 0, longitude: 0.0005)).block,
      CheckInBlock.outsideRadius,
    );
  });
  test('Poor, negative and non-finite accuracy block even at the object', () {
    for (final accuracy in [50.01, -1.0, double.nan, double.infinity]) {
      expect(
        policy
            .evaluate(
              target,
              fix(latitude: 0, longitude: 0, accuracy: accuracy),
            )
            .block,
        CheckInBlock.poorAccuracy,
      );
    }
  });
  test('Cached or unavailable position cannot authorize check-in', () {
    expect(policy.evaluate(target, null).allowed, isFalse);
    expect(
      policy
          .evaluate(target, fix(latitude: 0, longitude: 0), isCurrent: false)
          .allowed,
      isFalse,
    );
  });
  test('Policy radius is configurable', () {
    expect(
      const CheckInPolicy(radius: 100)
          .evaluate(target, fix(latitude: 0, longitude: 0.0005))
          .allowed,
      isTrue,
    );
  });

  test(
    'Visit and queue are persisted and reactive object becomes visited offline',
    () async {
      final db = createTestDatabase(seedDemoData: false);
      addTearDown(db.close);
      final objects = DriftObjectsDataSource(db);
      await objects.mergeRemoteObjects([
        (object: object, updatedAt: DateTime.utc(2026)),
      ]);
      final stream = StreamIterator(objects.watchObjects());
      addTearDown(stream.cancel);
      await stream.moveNext();
      final before = DateTime.now().toUtc().subtract(
        const Duration(seconds: 1),
      );
      final id = await VisitsRepository(db).checkIn(
        objectId: object.id,
        position: fix(latitude: 0, longitude: 0.0001, accuracy: 8),
      );
      await stream.moveNext();
      expect(stream.current.single.status, ObjectStatus.visited);
      final visit = await db.select(db.visits).getSingle();
      expect(visit.id, id);
      expect(visit.objectId, object.id);
      expect(visit.latitude, 0);
      expect(visit.longitude, 0.0001);
      expect(visit.accuracy, 8);
      expect(visit.status, VisitStatus.completed);
      expect(visit.syncStatus, SyncStatus.pending);
      expect(visit.serverVersion, isNull);
      expect(visit.createdAt.toUtc().isAfter(before), isTrue);
      final operation = await db.select(db.syncQueue).getSingle();
      expect(operation.entityType, 'visit');
      expect(operation.entityId, id);
      expect(operation.operation, 'upsert');
      expect(operation.createdAt, visit.createdAt);
      // Сервер ещё не знает о визите: повторный download не отменяет local visited.
      await objects.mergeRemoteObjects([
        (object: object, updatedAt: DateTime.utc(2027)),
      ]);
      expect(
        (await objects.watchObjects().first).single.status,
        ObjectStatus.visited,
      );
    },
  );

  for (final queueFailure in [true, false]) {
    test(
      'Transaction rolls back visit, queue and status when ${queueFailure ? 'queue' : 'object update'} fails',
      () async {
        final db = createTestDatabase(seedDemoData: false);
        addTearDown(db.close);
        final objects = DriftObjectsDataSource(db);
        await objects.mergeRemoteObjects([
          (object: object, updatedAt: DateTime.utc(2026)),
        ]);
        await db.customStatement(
          queueFailure
              ? "CREATE TEMP TRIGGER reject_check_in BEFORE INSERT ON sync_queue BEGIN SELECT RAISE(ABORT, 'queue failure'); END"
              : "CREATE TEMP TRIGGER reject_check_in BEFORE UPDATE ON objects BEGIN SELECT RAISE(ABORT, 'object failure'); END",
        );
        await expectLater(
          VisitsRepository(db).checkIn(
            objectId: object.id,
            position: fix(latitude: 0, longitude: 0),
          ),
          throwsA(isA<Exception>()),
        );
        expect(await db.select(db.visits).get(), isEmpty);
        expect(await db.select(db.syncQueue).get(), isEmpty);
        expect(
          (await objects.watchObjects().first).single.status,
          ObjectStatus.planned,
        );
      },
    );
  }
  test('Repository enforces radius and accuracy without trusting UI', () async {
    final db = createTestDatabase(seedDemoData: false);
    addTearDown(db.close);
    await DriftObjectsDataSource(db)
        .mergeRemoteObjects([(object: object, updatedAt: DateTime.utc(2026))]);
    for (final position in [
      fix(latitude: 1, longitude: 0),
      fix(latitude: 0, longitude: 0, accuracy: 51),
    ]) {
      await expectLater(
        VisitsRepository(db).checkIn(objectId: object.id, position: position),
        throwsA(isA<CheckInRejected>()),
      );
    }
    expect(await db.select(db.visits).get(), isEmpty);
    expect(await db.select(db.syncQueue).get(), isEmpty);
  });
}
