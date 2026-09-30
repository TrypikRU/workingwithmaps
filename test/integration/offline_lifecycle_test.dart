import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/database/app_database.dart';
import 'package:workingwithmaps/core/network/network_failure.dart';
import 'package:workingwithmaps/core/sync/sync_engine.dart';
import 'package:workingwithmaps/core/sync/sync_processor.dart';
import 'package:workingwithmaps/core/sync/sync_status.dart';
import 'package:workingwithmaps/features/objects/data/drift_objects_data_source.dart';
import 'package:workingwithmaps/features/objects/data/objects_remote_data_source.dart';
import 'package:workingwithmaps/features/objects/data/objects_repository.dart';
import 'package:workingwithmaps/features/objects/domain/technical_object.dart';
import 'package:workingwithmaps/features/visits/data/visits_repository.dart';

import '../support/fake_location_service.dart';
import '../support/sync_server.dart';

void main() {
  for (final attemptedBeforeClose in [false, true]) {
    test(
      'Offline check-in survives SQLite reopen; attempted=$attemptedBeforeClose',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'offline-lifecycle-',
        );
        final file = File('${directory.path}/app.sqlite');
        var db = AppDatabase.forTesting(NativeDatabase(file));
        final server = SyncServer()..failure = DioExceptionType.connectionError;
        final dio = Dio(BaseOptions(baseUrl: 'http://test/'))
          ..httpClientAdapter = server;
        addTearDown(() async {
          dio.close(force: true);
          await db.close();
          await directory.delete(recursive: true);
        });
        var now = DateTime.now().toUtc().add(const Duration(seconds: 1));
        ObjectsRepository objects() => ObjectsRepository(
          DriftObjectsDataSource(db),
          remote: () => ObjectsRemoteDataSource(dio),
        );
        SyncEngine engine() =>
            SyncEngine(SyncProcessor(db, dio: () => dio, clock: () => now));

        final target = (await objects().watchObjects().first).first;
        await expectLater(
          objects().refreshObjects(),
          throwsA(isA<NetworkFailure>()),
        );
        expect(await objects().watchObjects().first, contains(target));
        final id = await VisitsRepository(db).checkIn(
          objectId: target.id,
          position: fix(
            latitude: target.latitude,
            longitude: target.longitude,
            accuracy: 8,
          ),
        );
        final visit = await db.select(db.visits).getSingle();
        expect(visit.syncStatus, SyncStatus.pending);
        final queued = await db.select(db.syncQueue).getSingle();
        expect(queued.entityId, id);
        expect(queued.entityType, 'visit');
        expect(queued.operation, 'upsert');
        expect(
          server.requests,
          isEmpty,
        ); // Отметка о посещении никогда не отправляет HTTP-запрос.
        if (attemptedBeforeClose) expect((await engine().run()).failed, 1);
        final persistedQueue = await db.select(db.syncQueue).getSingle();

        // Закрываем настоящее файловое подключение, создаём новые репозитории и движок.
        // Это проверяет сохранность данных, а не повторное использование кэша провайдера в памяти.
        await db.close();
        db = AppDatabase.forTesting(NativeDatabase(file));
        expect(
          await db.select(db.visits).getSingle(),
          attemptedBeforeClose
              ? visit.copyWith(syncStatus: SyncStatus.failed)
              : visit,
        );
        expect(await db.select(db.syncQueue).getSingle(), persistedQueue);
        expect(
          (await objects().watchObjects().first)
              .firstWhere((o) => o.id == target.id)
              .status,
          ObjectStatus.visited,
        );
        await expectLater(
          objects().refreshObjects(),
          throwsA(isA<NetworkFailure>()),
        );

        server.failure = null;
        now = now.add(const Duration(hours: 1));
        final synced = db
            .select(db.visits)
            .watchSingle()
            .firstWhere((v) => v.syncStatus == SyncStatus.synced);
        expect((await engine().run()).succeeded, 1);
        expect((await synced).serverVersion, 1);
        expect(await db.select(db.syncQueue).get(), isEmpty);
        expect(server.applied, 1);
        expect((await engine().run()).succeeded, 0);
        expect(server.applied, 1);
        if (attemptedBeforeClose) expect(server.keys.toSet(), hasLength(1));
      },
    );
  }
}
