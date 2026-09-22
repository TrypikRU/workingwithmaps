import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/database/app_database.dart';
import 'package:workingwithmaps/core/sync/background_sync.dart';
import 'package:workingwithmaps/core/sync/sync_engine.dart';
import 'package:workingwithmaps/core/sync/sync_lease.dart';
import 'package:workingwithmaps/core/sync/sync_processor.dart';
import 'package:workingwithmaps/core/sync/sync_run_control.dart';
import 'package:workingwithmaps/core/sync/sync_status.dart';
import 'package:workingwithmaps/core/utils/app_logger.dart';

import '../../support/sync_server.dart';

AppDatabase openFile(String path, {bool concurrent = false}) {
  final previous = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  try {
    // These tests deliberately emulate separate UI/worker connections in one
    // isolate. Each owns a NEW executor; no QueryExecutor is shared. Silence
    // Drift's class-instance heuristic only while constructing that connection.
    if (concurrent) driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    return AppDatabase.forTesting(
      NativeDatabase(File(path)),
      seedDemoData: false,
    );
  } finally {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous;
  }
}

Future<bool> competingWorker(String path) => Isolate.run(() async {
  final db = openFile(path);
  try {
    final result = await SyncEngine(
      SyncProcessor(db, dio: () => throw StateError('Must not send HTTP')),
    ).run();
    return result.deferred;
  } finally {
    await db.close();
  }
});

void main() {
  late Directory directory;
  late String path;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('field-worker-');
    path = '${directory.path}/app.sqlite';
    final db = AppDatabase.forTesting(NativeDatabase(File(path)));
    await enqueue(db, 'visit');
    await db.close();
  });
  tearDown(() => directory.delete(recursive: true));

  for (final scenario in ['success', 'offline', '500', '409', 'timeout']) {
    test('Worker lifecycle and persisted queue: $scenario', () async {
      final server = SyncServer();
      if (scenario == 'offline') {
        server.failure = DioExceptionType.connectionError;
      }
      if (scenario == 'timeout') {
        server.failure = DioExceptionType.receiveTimeout;
      }
      if (scenario == '500' || scenario == '409') {
        server.responses.add(int.parse(scenario));
      }
      final events = <String>[];
      final completed = await executeBackgroundSync(
        openDatabase: () => openFile(path),
        createDio: () =>
            Dio(BaseOptions(baseUrl: 'http://test/'))
              ..httpClientAdapter = server,
        logger: AppLogger(sink: (event, _) => events.add(event)),
      );
      expect(completed, scenario == 'success' || scenario == '409');
      expect(
        events,
        containsAll(['worker.start', 'worker.complete', 'worker.disposed']),
      );
      final db = openFile(path);
      try {
        final queue = await db.select(db.syncQueue).get();
        if (scenario == 'success') {
          expect(queue, isEmpty);
          expect(
            (await db.select(db.visits).getSingle()).syncStatus,
            SyncStatus.synced,
          );
        } else {
          expect(queue.single.attemptCount, 1);
          expect(queue.single.lastError, isNotNull);
          expect(queue.single.nextRetryAt == null, scenario == '409');
        }
        expect(
          await (db.select(
            db.appMetadata,
          )..where((m) => m.key.equals(SyncLease.key))).get(),
          isEmpty,
        );
      } finally {
        await db.close();
      }
    });
  }

  test('Real second isolate cannot recover or send another owners syncing operation', () async {
    final db = openFile(path);
    final server = SyncServer()..hold = Completer<void>();
    final dio = Dio(BaseOptions(baseUrl: 'http://test/'))
      ..httpClientAdapter = server;
    final run = SyncEngine(SyncProcessor(db, dio: () => dio)).run();
    while (server.requests.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(await competingWorker(path), isTrue);
    expect(
      (await db.select(db.syncQueue).getSingle()).syncStatus,
      SyncStatus.syncing,
    );
    server.hold!.complete();
    expect((await run).succeeded, 1);
    expect(server.applied, 1);
    dio.close(force: true);
    await db.close();
  });

  test('Expired owner cannot ACK, renew or release successors lease', () async {
    final first = openFile(path);
    final second = openFile(path, concurrent: true);
    var now = DateTime.now();
    final old = SyncLease(first, clock: () => now);
    expect(await old.acquire(), isTrue);
    now = now.add(const Duration(minutes: 3));
    final successor = SyncLease(second, clock: () => now);
    expect(await successor.acquire(), isTrue);
    await expectLater(
      first.transaction(old.renew),
      throwsA(isA<SyncLeaseLost>()),
    );
    await old.release();
    await second.transaction(successor.renew);
    await successor.release();
    await first.close();
    await second.close();
  });

  test('External connection commit refreshes live UI Drift streams', () async {
    final ui = openFile(path);
    final worker = openFile(path, concurrent: true);
    await ui.refreshExternalChanges();
    final snapshots = <int>[];
    final subscription = ui
        .select(ui.syncQueue)
        .watch()
        .listen((q) => snapshots.add(q.length));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await worker.delete(worker.syncQueue).go();
    await ui.refreshExternalChanges();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(snapshots, containsAllInOrder([1, 0]));
    await subscription.cancel();
    await worker.close();
    await ui.close();
  });

  test(
    'Late server ACK from expired owner is fenced; successor retries same key',
    () async {
      final db = openFile(path);
      final second = openFile(path, concurrent: true);
      var now = DateTime.now();
      final server = SyncServer()..hold = Completer<void>();
      final dio = Dio(BaseOptions(baseUrl: 'http://test/'))
        ..httpClientAdapter = server;
      final engine = SyncEngine(
        SyncProcessor(db, dio: () => dio, clock: () => now),
      );
      final firstRun = engine.run();
      while (server.requests.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      now = now.add(const Duration(minutes: 3));
      final successor = SyncLease(second, clock: () => now);
      expect(await successor.acquire(), isTrue);
      server.hold!.complete();
      expect((await firstRun).deferred, isTrue);
      expect(
        (await db.select(db.syncQueue).getSingle()).syncStatus,
        SyncStatus.syncing,
      );
      await successor.release();
      expect((await engine.run()).succeeded, 1);
      expect(server.keys.toSet(), hasLength(1));
      expect(server.applied, 1);
      dio.close(force: true);
      await second.close();
      await db.close();
    },
  );

  test(
    'Worker cancellation preserves frozen request for next execution',
    () async {
      final db = openFile(path);
      final server = SyncServer()..hold = Completer<void>();
      final dio = Dio(BaseOptions(baseUrl: 'http://test/'))
        ..httpClientAdapter = server;
      final control = SyncRunControl();
      final run = SyncEngine(SyncProcessor(db, dio: () => dio))
          .run(control: control);
      while (server.requests.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      control.cancel();
      server.hold!.complete();
      expect((await run).deferred, isTrue);
      final interrupted = await db.select(db.syncQueue).getSingle();
      expect(interrupted.payload, isNotNull);
      final key = interrupted.operationId;
      expect(
        (await SyncEngine(SyncProcessor(db, dio: () => dio)).run()).succeeded,
        1,
      );
      expect(server.keys.last, key);
      expect(server.applied, 1);
      dio.close(force: true);
      await db.close();
    },
  );
}
