import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/sync/sync_conflict.dart';
import 'package:workingwithmaps/core/sync/sync_conflict_repository.dart';
import 'package:workingwithmaps/core/sync/sync_conflict_remote_data_source.dart';
import 'package:workingwithmaps/core/sync/sync_engine.dart';
import 'package:workingwithmaps/core/sync/sync_processor.dart';
import 'package:workingwithmaps/core/sync/sync_snapshot.dart';
import 'package:workingwithmaps/core/utils/local_id.dart';
import 'package:workingwithmaps/features/objects/data/drift_objects_data_source.dart';
import 'package:workingwithmaps/features/objects/data/objects_remote_data_source.dart';
import 'package:workingwithmaps/features/objects/data/objects_repository.dart';

import '../support/test_database.dart';

void main() {
  const url = String.fromEnvironment('SYNC_TEST_URL');
  test(
    'Real backend: version conflict, refresh/review, explicit rebase, lost ACK and coalesced successor',
    () async {
      final db = createTestDatabase(seedDemoData: false);
      addTearDown(db.close);
      final dio = Dio(BaseOptions(baseUrl: url));
      addTearDown(() => dio.close(force: true));
      final repo = ObjectsRepository(
        DriftObjectsDataSource(db),
        remote: () => ObjectsRemoteDataSource(dio),
      );
      await repo.refreshObjects();
      final original = (await repo.watchObjects().first).firstWhere(
        (o) => o.id == 'demo-5',
      );
      final base = original.serverVersion!;
      final other = syncRequest(
        original.copyWith(name: 'Other device').toJson(),
      );
      await dio.patch(
        'objects/${original.id}',
        data: other,
        options: Options(headers: {'Idempotency-Key': localId()}),
      );
      await repo.saveObject(original.copyWith(name: 'Local edit'));
      var now = DateTime.now().toUtc();
      final engine = SyncEngine(
        SyncProcessor(db, dio: () => dio, clock: () => now),
      );
      expect((await engine.run()).failed, 1);
      final conflicts = SyncConflictRepository(
        db,
        remote: () => SyncConflictRemoteDataSource(dio),
      );
      final review = (await conflicts.watch().first).single;
      expect(review.localVersion, base);
      expect(review.serverVersion, base + 1);
      await conflicts.refreshServer(review);
      await conflicts.resolve(
        (await conflicts.watch().first).single,
        ConflictResolution.keepLocal,
      );
      expect((await engine.run()).succeeded, 1);
      final remote = (await dio.get<Map<String, dynamic>>(
        'objects/${original.id}',
      )).data!;
      expect(remote['name'], 'Local edit');
      expect(remote['serverVersion'], base + 2);

      var loseAck = true;
      dio.interceptors.add(
        InterceptorsWrapper(
          onResponse: (response, handler) {
            if (response.requestOptions.method == 'PATCH' && loseAck) {
              loseAck = false;
              handler.reject(
                DioException(
                  requestOptions: response.requestOptions,
                  type: DioExceptionType.receiveTimeout,
                ),
              );
            } else {
              handler.next(response);
            }
          },
        ),
      );
      await repo.saveObject(original.copyWith(name: 'A'));
      expect((await engine.run()).failed, 1);
      final frozen = await db.select(db.syncQueue).getSingle();
      await repo.saveObject(original.copyWith(name: 'B'));
      await repo.saveObject(original.copyWith(name: 'C'));
      now = now.add(const Duration(seconds: 6));
      expect((await engine.run()).succeeded, 2);
      expect(await db.select(db.syncQueue).get(), isEmpty);
      final latest = (await dio.get<Map<String, dynamic>>(
        'objects/${original.id}',
      )).data!;
      expect(latest['name'], 'C');
      expect(latest['serverVersion'], base + 4);
      // Повтор исходной операции после C: сохранённое подтверждение возвращает A без отката C.
      final replay = await dio.patch<Map<String, dynamic>>(
        'objects/${original.id}',
        data: frozen.payload,
        options: Options(
          headers: {'Idempotency-Key': frozen.operationId},
          contentType: Headers.jsonContentType,
        ),
      );
      expect(replay.data!['name'], 'A');
      expect(
        (await dio.get<Map<String, dynamic>>('objects/${original.id}'))
            .data!['name'],
        'C',
      );
    },
    skip: url.isEmpty
        ? 'Set SYNC_TEST_URL to a running isolated test backend'
        : false,
  );
}
