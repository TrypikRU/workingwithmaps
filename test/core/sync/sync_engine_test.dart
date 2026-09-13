import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/database/app_database.dart';
import 'package:workingwithmaps/core/location/location_service.dart';
import 'package:workingwithmaps/features/route/data/route_repository.dart';
import 'package:workingwithmaps/core/sync/retry_policy.dart';
import 'package:workingwithmaps/core/sync/sync_engine.dart';
import 'package:workingwithmaps/core/sync/sync_processor.dart';
import 'package:workingwithmaps/core/sync/sync_status.dart';
import 'package:workingwithmaps/core/utils/app_logger.dart';
import 'package:workingwithmaps/features/sync/data/sync_diagnostics_repository.dart';

import '../../support/test_database.dart';
import '../../support/sync_server.dart';

void main() {
  late AppDatabase db;
  late SyncServer server;
  late Dio dio;
  late DateTime now;
  late List<String> events;
  SyncEngine engine() {
    final logger = AppLogger(sink: (event, fields) => events.add(event));
    return SyncEngine(
      SyncProcessor(db, dio: () => dio, clock: () => now, logger: logger),
      logger: logger,
    );
  }

  setUp(() {
    db = createTestDatabase();
    server = SyncServer();
    dio = Dio(BaseOptions(baseUrl: 'http://test/'))..httpClientAdapter = server;
    now = DateTime.utc(2026, 9, 12, 12);
    events = [];
  });
  tearDown(() async {
    dio.close(force: true);
    await db.close();
  });

  test('Success atomically removes queue and marks entity synced', () async {
    await enqueue(db, 'one');
    final result = await engine().run();
    expect(result.succeeded, 1);
    expect(await db.select(db.syncQueue).get(), isEmpty);
    final visit = await db.select(db.visits).getSingle();
    expect(visit.syncStatus, SyncStatus.synced);
    expect(visit.serverVersion, 1);
    expect(
      events,
      containsAll([
        'sync.run.start',
        'sync.operation.claimed',
        'sync.operation.success',
        'sync.run.complete',
      ]),
    );
  });

  test(
    'Route registration precedes points and dependency retries without HTTP',
    () async {
      final repository = RouteRepository(db);
      final routeId = await repository.start();
      await repository.append(
        routeId,
        'segment',
        LocationFix(
          latitude: 0,
          longitude: 0,
          accuracy: 5,
          timestamp: DateTime.now(),
        ),
      );
      now = DateTime.now().toUtc();
      server.responses.add(500);
      expect((await engine().run()).failed, 2);
      expect(server.requests, hasLength(1));
      final queue = await db.select(db.syncQueue).get();
      expect(queue.last.lastError, contains('dependency'));
      now = now.add(const Duration(seconds: 6));
      expect((await engine().run()).succeeded, 2);
      expect(server.requests[1]['id'], routeId);
      expect(
        (server.requests.last['points'] as List).single['routeId'],
        routeId,
      );
      expect(await db.select(db.syncQueue).get(), isEmpty);
    },
  );

  test(
    'Diagnostics snapshot persists successful count/time and empty run does not advance it',
    () async {
      final repository = SyncDiagnosticsRepository(db);
      expect((await repository.watch().first).synced, 0);
      await enqueue(db, 'one');
      final stream = StreamIterator(repository.watch());
      addTearDown(stream.cancel);
      await stream.moveNext();
      expect(stream.current.operations.single.status, SyncStatus.pending);
      await engine().run();
      final success = await repository.watch().first;
      expect(success.synced, 1);
      expect(success.lastSuccessAt, now);
      expect(success.operations, isEmpty);
      now = now.add(const Duration(hours: 1));
      await engine().run();
      expect(
        (await SyncDiagnosticsRepository(db).watch().first).lastSuccessAt,
        success.lastSuccessAt,
      );
      expect((await repository.watch().first).synced, 1);
    },
  );

  test(
    'Manual failed retry bypasses backoff but preserves payload/key and attempt history',
    () async {
      await enqueue(db, 'one');
      server.responses.addAll([500, 409, 200]);
      await engine().run();
      final original = await db.select(db.syncQueue).getSingle();
      expect(original.nextRetryAt!.isAfter(now), isTrue);
      await engine().run(retryFailed: true);
      final failed = await db.select(db.syncQueue).getSingle();
      expect(failed.syncStatus, SyncStatus.failed);
      expect(failed.attemptCount, 2);
      expect(failed.lastError, contains('conflict'));
      expect(failed.payload, original.payload);
      expect(failed.operationId, original.operationId);
      expect((await SyncDiagnosticsRepository(db).watch().first).synced, 0);
      await engine().run(retryFailed: true);
      expect(await db.select(db.syncQueue).get(), isEmpty);
      expect((await SyncDiagnosticsRepository(db).watch().first).synced, 1);
      expect(server.keys.toSet(), hasLength(1));
    },
  );

  test(
    'Global activity stream reports automatic runs and returns to idle on error',
    () async {
      await enqueue(db, 'one');
      final sync = engine();
      final activity = <bool>[];
      final subscription = sync.watchRunning().listen(activity.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      server.responses.add(500);
      await sync.run();
      await pumpEventQueue();
      expect(activity, [false, true, false]);
    },
  );

  for (final scenario in ['offline', '500', '409', '400', 'timeout']) {
    test('$scenario persists classified failure and retry state', () async {
      await enqueue(db, 'one');
      if (scenario == 'offline' || scenario == 'timeout') {
        server.failure = scenario == 'offline'
            ? DioExceptionType.connectionError
            : DioExceptionType.receiveTimeout;
      } else {
        server.responses.add(int.parse(scenario));
      }
      expect((await engine().run()).failed, 1);
      final row = await db.select(db.syncQueue).getSingle();
      expect(row.syncStatus, SyncStatus.failed);
      expect(row.attemptCount, 1);
      expect(row.payload, isNotNull);
      expect(row.operationId, isNotEmpty);
      expect(row.lastError, isNotEmpty);
      expect(
        (await db.select(db.visits).getSingle()).syncStatus,
        SyncStatus.failed,
      );
      final error = jsonDecode(row.lastError!);
      final retryable = !['409', '400'].contains(scenario);
      expect(error['retryable'], retryable);
      if (scenario == '409') expect(error['kind'], 'conflict');
      if (scenario == '400') expect(error['kind'], 'client');
      expect(
        row.nextRetryAt?.toUtc(),
        retryable ? now.add(const Duration(seconds: 5)) : null,
      );
      expect((await engine().run()).succeeded, 0);
      expect(server.requests, hasLength(1));
    });
  }

  test(
    'First succeeds, second fails, third independent record still succeeds',
    () async {
      await enqueue(db, 'one');
      await enqueue(db, 'two');
      await enqueue(db, 'three');
      server.responses.addAll([200, 500, 200]);
      final result = await engine().run();
      expect(result.succeeded, 2);
      expect(result.failed, 1);
      expect((await db.select(db.syncQueue).getSingle()).entityId, 'two');
      expect(server.requests.map((r) => r['id']), ['one', 'two', 'three']);
      expect(server.maxActive, 1);
    },
  );

  test(
    'Backoff retry waits, keeps identical payload/key and recovers',
    () async {
      await enqueue(db, 'one');
      server.responses.addAll([500, 500, 200]);
      await engine().run();
      now = now.add(const Duration(seconds: 5));
      await engine().run();
      expect(
        (await db.select(db.syncQueue).getSingle()).nextRetryAt!.toUtc(),
        now.add(const Duration(seconds: 10)),
      );
      now = now.add(const Duration(seconds: 10));
      expect((await engine().run()).succeeded, 1);
      expect(server.keys.toSet(), hasLength(1));
      expect(server.requests.map(jsonEncode).toSet(), hasLength(1));
      expect(await db.select(db.syncQueue).get(), isEmpty);
    },
  );

  test(
    'Lost response and duplicate operation do not apply twice on server',
    () async {
      await enqueue(db, 'one');
      server.loseNextAck = true;
      await engine().run();
      expect(server.applied, 1);
      now = now.add(const Duration(seconds: 5));
      await engine().run();
      await db
          .into(db.syncQueue)
          .insert(
            SyncQueueCompanion.insert(
              entityType: 'visit',
              entityId: 'one',
              operation: 'upsert',
            ),
          );
      await engine().run();
      expect(server.applied, 1);
      expect((await db.select(db.visits).getSingle()).serverVersion, 1);
      expect((await engine().run()).succeeded, 0);
      expect(server.requests, hasLength(3));
    },
  );

  test('Two engine instances share one in-flight run', () async {
    await enqueue(db, 'one');
    server.hold = Completer<void>();
    final first = engine().run();
    final second = engine().run();
    expect(identical(first, second), isTrue);
    server.hold!.complete();
    await Future.wait([first, second]);
    expect(server.requests, hasLength(1));
    expect(server.maxActive, 1);
    expect(events, contains('sync.run.joined'));
  });

  test(
    'New local revision is not lost behind frozen retry and uses new serverVersion',
    () async {
      await enqueue(db, 'one');
      server.loseNextAck = true;
      await engine().run();
      await db.transaction(() async {
        await (db.update(db.visits)..where((v) => v.id.equals('one'))).write(
          const VisitsCompanion(accuracy: Value(9)),
        );
        await db
            .into(db.syncQueue)
            .insert(
              SyncQueueCompanion.insert(
                entityType: 'visit',
                entityId: 'one',
                operation: 'upsert',
              ),
            );
      });
      await engine().run();
      expect(server.requests, hasLength(1)); // successor cannot overtake retry
      now = now.add(const Duration(seconds: 5));
      expect((await engine().run()).succeeded, 2);
      expect(server.requests[1]['accuracy'], 8);
      expect(server.requests[2]['accuracy'], 9);
      expect(server.requests[2]['serverVersion'], 1);
      expect((await db.select(db.visits).getSingle()).accuracy, 9);
      expect(server.applied, 2);
    },
  );

  test(
    'Crash after queue creation / interrupted claim resumes from SQLite file',
    () async {
      await db.close();
      final directory = await Directory.systemTemp.createTemp('field-sync-');
      final file = File('${directory.path}/test.sqlite');
      db = AppDatabase.forTesting(NativeDatabase(file));
      await enqueue(db, 'one');
      await db.close(); // no HTTP occurred before process shutdown
      db = AppDatabase.forTesting(NativeDatabase(file));
      expect((await engine().run()).succeeded, 1);
      await enqueue(db, 'two');
      server.loseNextAck = true;
      await engine().run();
      final frozen = await db.select(db.syncQueue).getSingle();
      // Model process death after server commit but before local acknowledgement.
      await db
          .update(db.syncQueue)
          .write(
            const SyncQueueCompanion(syncStatus: Value(SyncStatus.syncing)),
          );
      await db.close();
      db = AppDatabase.forTesting(NativeDatabase(file));
      expect((await engine().run()).succeeded, 1);
      expect(server.keys.last, frozen.operationId);
      expect(server.applied, 2);
      expect((await SyncDiagnosticsRepository(db).watch().first).synced, 2);
      expect(events, contains('sync.recovered'));
      await db.close();
      db = createTestDatabase();
      await directory.delete(recursive: true);
    },
  );

  test(
    'Unsupported legacy operation is retained and cannot block another entity',
    () async {
      await db
          .into(db.syncQueue)
          .insert(
            SyncQueueCompanion.insert(
              entityType: 'object',
              entityId: 'demo-1',
              operation: 'upsert',
            ),
          );
      await enqueue(db, 'one');
      final result = await engine().run();
      expect(result.failed, 1);
      expect(result.succeeded, 1);
      final row = await db.select(db.syncQueue).getSingle();
      expect(jsonDecode(row.lastError!)['kind'], 'unsupported');
      expect(server.requests, hasLength(1));
    },
  );

  test('Location point uses immutable ID via batch endpoint', () async {
    await db
        .into(db.routes)
        .insert(RoutesCompanion.insert(id: 'route', name: 'Route'));
    await db.transaction(() async {
      await db
          .into(db.locationPoints)
          .insert(
            LocationPointsCompanion.insert(
              id: 'point',
              routeId: 'route',
              latitude: 55,
              longitude: 37,
              accuracy: 5,
              timestamp: now,
            ),
          );
      await db
          .into(db.syncQueue)
          .insert(
            SyncQueueCompanion.insert(
              entityType: 'location_point',
              entityId: 'point',
              operation: 'upsert',
            ),
          );
    });
    expect((await engine().run()).succeeded, 1);
    expect(
      (await db.select(db.locationPoints).getSingle()).syncStatus,
      SyncStatus.synced,
    );
    expect(server.requests.single['points'], hasLength(1));
  });

  test(
    'Diagnostic write failure rolls back ACK, count and timestamp together',
    () async {
      await enqueue(db, 'one');
      await db.customStatement(
        "CREATE TEMP TRIGGER reject_diagnostics BEFORE INSERT ON app_metadata WHEN NEW.key = 'sync.last_success_at' BEGIN SELECT RAISE(ABORT, 'diagnostic failure'); END",
      );
      expect((await engine().run()).failed, 1);
      final diagnostics = await SyncDiagnosticsRepository(db).watch().first;
      expect(diagnostics.synced, 0);
      expect(diagnostics.lastSuccessAt, isNull);
      expect(diagnostics.operations.single.status, SyncStatus.failed);
      expect((await db.select(db.visits).getSingle()).serverVersion, isNull);
    },
  );

  test('Backoff has a finite maximum even after many attempts', () {
    const policy = RetryPolicy();
    expect(policy.delay(1), const Duration(seconds: 5));
    expect(policy.delay(2), const Duration(seconds: 10));
    expect(policy.delay(1000000), const Duration(minutes: 15));
  });

  test(
    'Local ACK rollback keeps queue; retry after repair does not reapply remotely',
    () async {
      await enqueue(db, 'one');
      await db.customStatement(
        "CREATE TEMP TRIGGER reject_ack BEFORE UPDATE ON visits WHEN NEW.sync_status = 'synced' BEGIN SELECT RAISE(ABORT, 'ack failure'); END",
      );
      expect((await engine().run()).failed, 1);
      expect(server.applied, 1);
      final failed = await db.select(db.syncQueue).getSingle();
      expect(failed.payload, isNotNull);
      expect(
        (await db.select(db.visits).getSingle()).syncStatus,
        SyncStatus.failed,
      );
      await db.customStatement('DROP TRIGGER reject_ack');
      // Explicit repair: no payload/key regeneration after a possibly committed POST.
      await db
          .update(db.syncQueue)
          .write(
            const SyncQueueCompanion(syncStatus: Value(SyncStatus.pending)),
          );
      expect((await engine().run()).succeeded, 1);
      expect(server.applied, 1);
      expect(server.keys.toSet(), hasLength(1));
    },
  );
}
