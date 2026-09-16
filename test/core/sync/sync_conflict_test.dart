import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/database/app_database.dart'
    hide SyncConflict;
import 'package:workingwithmaps/core/sync/sync_conflict.dart';
import 'package:workingwithmaps/core/sync/sync_conflict_repository.dart';
import 'package:workingwithmaps/core/sync/sync_conflict_remote_data_source.dart';
import 'package:workingwithmaps/core/sync/sync_engine.dart';
import 'package:workingwithmaps/core/sync/sync_processor.dart';
import 'package:workingwithmaps/core/sync/sync_snapshot.dart';
import 'package:workingwithmaps/core/sync/sync_lease.dart';
import 'package:workingwithmaps/features/objects/domain/technical_object.dart';
import 'package:workingwithmaps/features/objects/data/drift_objects_data_source.dart';
import 'package:workingwithmaps/features/objects/data/objects_repository.dart';
import '../../support/test_database.dart';
import '../../support/sync_server.dart';

void main() {
  late AppDatabase db;
  late SyncServer server;
  late Dio dio;
  late DateTime now;
  const original = TechnicalObject(
    id: 'edit',
    name: 'Base',
    address: 'Address',
    latitude: 55,
    longitude: 37,
    serverVersion: 4,
  );
  ObjectsRepository repository() =>
      ObjectsRepository(DriftObjectsDataSource(db));
  SyncConflictRepository conflicts() => SyncConflictRepository(db);
  SyncEngine engine() =>
      SyncEngine(SyncProcessor(db, dio: () => dio, clock: () => now));
  Future<void> edit(String name) =>
      repository().saveObject(original.copyWith(name: name));
  void remote(int version, String name) {
    server.records['edit'] = {
      'business': syncRequest(original.copyWith(name: name).toJson())
        ..remove('serverVersion'),
      'version': version,
    };
  }

  Future<SyncConflict> conflict() async =>
      (await conflicts().watch().first).first;
  Future<void> createConflict() async {
    remote(5, 'Server');
    await edit('Local');
    expect((await engine().run()).failed, 1);
  }

  setUp(() async {
    db = createTestDatabase();
    server = SyncServer();
    dio = Dio(BaseOptions(baseUrl: 'http://test/'))..httpClientAdapter = server;
    now = DateTime.now().toUtc();
    await DriftObjectsDataSource(
      db,
    ).mergeRemoteObjects([(object: original, updatedAt: now)]);
    remote(4, 'Base');
  });
  tearDown(() async {
    dio.close(force: true);
    await db.close();
  });

  test(
    'Unsent A B C coalesce; stale UI version cannot roll back ACK version',
    () async {
      await edit('A');
      await edit('B');
      await edit('C');
      expect(await db.select(db.syncQueue).get(), hasLength(1));
      expect((await engine().run()).succeeded, 1);
      expect(server.requests.single['name'], 'C');
      expect(server.requests.single['serverVersion'], 4);
      await edit('D'); // same old form with v4; repository must preserve ACK v5
      expect((await engine().run()).succeeded, 1);
      expect(server.requests.last['serverVersion'], 5);
      expect(server.applied, 2);
    },
  );

  test(
    'Claim rereads state when B coalesces after engine selected A',
    () async {
      await edit('A');
      final selected = await db.select(db.syncQueue).getSingle();
      await edit('B');
      expect(await SyncProcessor(db, dio: () => dio).process(selected), isTrue);
      expect(server.requests.single['name'], 'B');
    },
  );

  test(
    'Edit during HTTP keeps newer local state; B C share unsent tail and ACK rebases it',
    () async {
      await edit('A');
      server.hold = Completer<void>();
      final run = engine().run();
      while (server.requests.isEmpty) {
        await pumpEventQueue();
      }
      await edit('B');
      await edit('C');
      expect(await db.select(db.syncQueue).get(), hasLength(2));
      server.hold!.complete();
      expect((await run).succeeded, 1);
      final latest = (await repository().watchObjects().first).firstWhere(
        (o) => o.id == 'edit',
      );
      expect(latest.name, 'C');
      expect(latest.serverVersion, 5);
      expect((await engine().run()).succeeded, 1);
      expect(server.requests.map((r) => r['name']), ['A', 'C']);
      expect(server.requests.last['serverVersion'], 5);
      expect(server.keys.toSet(), hasLength(2));
    },
  );

  test(
    'Lost ACK keeps frozen key; later server edit creates conflict for newer B',
    () async {
      await edit('A');
      server.loseNextAck = true;
      await engine().run();
      await edit('B');
      final frozen = (await db.select(db.syncQueue).get()).first;
      remote(6, 'Other device');
      now = now.add(const Duration(seconds: 6));
      final result = await engine().run();
      expect(result.succeeded, 1);
      expect(result.failed, 1);
      expect(server.requests.map((r) => r['name']), ['A', 'A', 'B']);
      expect(server.keys[1], frozen.operationId);
      expect((await conflict()).serverVersion, 6);
      expect((await conflict()).localVersion, 5);
      expect(server.applied, 1); // replay did not overwrite external state
    },
  );

  test(
    '409 blocks retries and successors but not other entities; keepLocal uses new key/version',
    () async {
      await createConflict();
      final first = await conflict();
      expect(first.localVersion, 4);
      expect(first.serverVersion, 5);
      final oldKey = server.keys.single;
      await edit('Latest local');
      await enqueue(db, 'independent');
      expect((await engine().run(retryFailed: true)).succeeded, 1);
      expect(server.requests, hasLength(2));
      final review = await conflict();
      expect(review.currentLocalPayload, contains('Latest local'));
      await conflicts().resolve(review, ConflictResolution.keepLocal);
      expect(await db.select(db.syncQueue).get(), hasLength(1));
      expect((await engine().run()).succeeded, 1);
      expect(server.requests.last['serverVersion'], 5);
      expect(server.requests.last['name'], 'Latest local');
      expect(server.keys.last, isNot(oldKey));
      expect((await conflict()).resolvedAt, isNotNull);
    },
  );

  test(
    'Server changes again after explicit rebase: new 409, no force write',
    () async {
      await createConflict();
      await conflicts().resolve(await conflict(), ConflictResolution.keepLocal);
      remote(6, 'Even newer');
      expect((await engine().run()).failed, 1);
      final history = await conflicts().watch().first;
      expect(history, hasLength(2));
      expect(history.first.serverVersion, 6);
      expect(history.last.resolvedAt, isNotNull);
      expect(server.applied, 0);
    },
  );

  test(
    'acceptServer cancels unsent tail atomically and keeps local audit',
    () async {
      await createConflict();
      await edit('Another local edit');
      await conflicts().resolve(
        await conflict(),
        ConflictResolution.acceptServer,
      );
      expect(await db.select(db.syncQueue).get(), isEmpty);
      final entity = (await repository().watchObjects().first).firstWhere(
        (o) => o.id == 'edit',
      );
      expect(entity.name, 'Server');
      expect(entity.serverVersion, 5);
      expect((await conflict()).localPayload, contains('Another local edit'));
      expect(server.applied, 0);
    },
  );

  test(
    'Stale dialog and duplicate resolution cannot discard subsequent edits',
    () async {
      await createConflict();
      final review = await conflict();
      await edit('New');
      await expectLater(
        conflicts().resolve(review, ConflictResolution.acceptServer),
        throwsStateError,
      );
      expect(await db.select(db.syncQueue).get(), hasLength(2));
      final current = await conflict();
      await conflicts().resolve(current, ConflictResolution.acceptServer);
      await expectLater(
        conflicts().resolve(current, ConflictResolution.keepLocal),
        throwsStateError,
      );
    },
  );

  test(
    'Worker lease blocks resolution; SQL failure rolls back entity/queue/history together',
    () async {
      await createConflict();
      final review = await conflict();
      final lease = SyncLease(db);
      expect(await lease.acquire(), isTrue);
      await expectLater(
        conflicts().resolve(review, ConflictResolution.acceptServer),
        throwsStateError,
      );
      await lease.release();
      await db.customStatement(
        "CREATE TEMP TRIGGER reject_resolution BEFORE UPDATE ON sync_conflicts BEGIN SELECT RAISE(ABORT, 'test'); END",
      );
      await expectLater(
        conflicts().resolve(review, ConflictResolution.acceptServer),
        throwsA(isA<Exception>()),
      );
      expect(await db.select(db.syncQueue).get(), hasLength(1));
      expect((await conflict()).resolvedAt, isNull);
      expect((await conflict()).currentLocalPayload, contains('Local'));
    },
  );

  test(
    'Visit conflict never overwrites server; accepting archives local event',
    () async {
      await enqueue(db, 'visit-fact');
      await engine().run();
      await (db.update(db.visits)..where((v) => v.id.equals('visit-fact')))
          .write(const VisitsCompanion(accuracy: Value(12)));
      await db
          .into(db.syncQueue)
          .insert(
            SyncQueueCompanion.insert(
              entityType: 'visit',
              entityId: 'visit-fact',
              operation: 'upsert',
            ),
          );
      expect((await engine().run()).failed, 1);
      final review = await conflict();
      expect(review.canKeepLocal, isFalse);
      await expectLater(
        conflicts().resolve(review, ConflictResolution.keepLocal),
        throwsStateError,
      );
      await engine().run(retryFailed: true);
      expect(server.requests, hasLength(2));
      await conflicts().resolve(review, ConflictResolution.acceptServer);
      expect((await db.select(db.visits).getSingle()).accuracy, 8);
      expect(jsonDecode((await conflict()).localPayload)['accuracy'], 12);
      expect(server.applied, 1);
    },
  );

  test(
    'Missing or malformed current leaves diagnosable conflict, never auto-retried',
    () async {
      await edit('Local');
      server.responses.add(409);
      await engine().run();
      final review = await conflict();
      expect(review.serverPayload, isNull);
      await expectLater(
        conflicts().resolve(review, ConflictResolution.keepLocal),
        throwsStateError,
      );
      await engine().run(retryFailed: true);
      expect(server.requests, hasLength(1));
      expect(
        validatedServerSnapshot('object', 'edit', {
          'id': 'other',
          'serverVersion': 5,
        }),
        isNull,
      );
    },
  );

  test('Conflict and unsent successor survive database reopen', () async {
    await db.close();
    final directory = await Directory.systemTemp.createTemp('field-conflicts-');
    addTearDown(() async {
      await db.close();
      db = createTestDatabase();
      await directory.delete(recursive: true);
    });
    db = AppDatabase.forTesting(
      NativeDatabase(File('${directory.path}/test.sqlite')),
    );
    await DriftObjectsDataSource(
      db,
    ).mergeRemoteObjects([(object: original, updatedAt: now)]);
    await createConflict();
    await edit('After conflict');
    await db.close();
    db = AppDatabase.forTesting(
      NativeDatabase(File('${directory.path}/test.sqlite')),
    );
    expect((await engine().run(retryFailed: true)).succeeded, 0);
    expect((await conflict()).serverVersion, 5);
    await conflicts().resolve(await conflict(), ConflictResolution.keepLocal);
    expect((await engine().run()).succeeded, 1);
    expect(server.requests.last['name'], 'After conflict');
  });

  test(
    'Debug 409 can recover snapshot through repository; failed fetch preserves conflict',
    () async {
      await edit('Local');
      server.responses.add(409);
      await engine().run();
      final review = await conflict();
      final repo = SyncConflictRepository(
        db,
        remote: () => SyncConflictRemoteDataSource(dio),
      );
      server.failure = DioExceptionType.connectionError;
      await expectLater(
        repo.refreshServer(review),
        throwsA(isA<DioException>()),
      );
      expect((await conflict()).serverPayload, isNull);
      server.failure = null;
      await repo.refreshServer(review);
      expect((await conflict()).serverVersion, 4);
      await expectLater(
        repo.resolve(review, ConflictResolution.keepLocal),
        throwsStateError,
      );
      await repo.resolve(await conflict(), ConflictResolution.keepLocal);
      expect((await engine().run()).succeeded, 1);
    },
  );
}
