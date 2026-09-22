import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/database/app_database.dart';
import 'package:workingwithmaps/core/location/location_service.dart';
import 'package:workingwithmaps/core/sync/sync_engine.dart';
import 'package:workingwithmaps/core/sync/sync_processor.dart';
import 'package:workingwithmaps/core/sync/sync_status.dart';
import 'package:workingwithmaps/features/objects/data/drift_objects_data_source.dart';
import 'package:workingwithmaps/features/objects/data/objects_remote_data_source.dart';
import 'package:workingwithmaps/features/objects/data/objects_repository.dart';
import 'package:workingwithmaps/features/visits/data/visits_repository.dart';
import 'package:workingwithmaps/features/route/data/route_repository.dart';

import '../support/test_database.dart';

void main() {
  const url = String.fromEnvironment('SYNC_TEST_URL');
  test(
    'Real backend: local route, lost registration ACK and point retry',
    () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final dio = Dio(BaseOptions(baseUrl: url));
      addTearDown(() => dio.close(force: true));
      final repository = RouteRepository(db);
      final routeId = await repository.start();
      await repository.append(
        routeId,
        'segment',
        LocationFix(
          latitude: 61.650478,
          longitude: 50.760391,
          accuracy: 5,
          speed: 1,
          timestamp: DateTime.now().toUtc(),
        ),
      );
      var loseAck = true;
      dio.interceptors.add(
        InterceptorsWrapper(
          onResponse: (response, handler) {
            if (response.requestOptions.path == 'routes' && loseAck) {
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
      var now = DateTime.now().toUtc();
      final engine = SyncEngine(
        SyncProcessor(db, dio: () => dio, clock: () => now),
      );
      expect((await engine.run()).failed, 2);
      now = now.add(const Duration(seconds: 6));
      expect((await engine.run()).succeeded, 2);
      expect(await db.select(db.syncQueue).get(), isEmpty);
      final response = await dio.get<Map<String, dynamic>>('sync');
      expect(
        (response.data!['routes'] as List).where((r) => r['id'] == routeId),
        hasLength(1),
      );
      expect(
        (response.data!['locationPoints'] as List).where(
          (p) => p['routeId'] == routeId,
        ),
        hasLength(1),
      );
      await repository.finish(routeId);
      expect((await repository.watchCurrent().first)!.status.name, 'completed');
    },
    skip: url.isEmpty
        ? 'Set SYNC_TEST_URL to a running isolated test backend'
        : false,
  );
  test(
    'Real backend: commit, lost ACK, retry and duplicate preserve one server visit',
    () async {
      final db = createTestDatabase(seedDemoData: false);
      addTearDown(db.close);
      final dio = Dio(BaseOptions(baseUrl: url));
      addTearDown(() => dio.close(force: true));
      await ObjectsRepository(
        DriftObjectsDataSource(db),
        remote: () => ObjectsRemoteDataSource(dio),
      ).refreshObjects();
      final object = await (db.select(
        db.technicalObjects,
      )..limit(1)).getSingle();
      final id = await VisitsRepository(db).checkIn(
        objectId: object.id,
        position: LocationFix(
          latitude: object.latitude,
          longitude: object.longitude,
          accuracy: 5,
          timestamp: DateTime.now(),
        ),
      );
      var loseAck = true;
      dio.interceptors.add(
        InterceptorsWrapper(
          onResponse: (response, handler) {
            // Реальный сервер уже завершил commit. Теряем только ответ на клиенте.
            if (response.requestOptions.path == 'visits' && loseAck) {
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
      var now = DateTime.now().toUtc();
      final engine = SyncEngine(
        SyncProcessor(db, dio: () => dio, clock: () => now),
      );
      expect((await engine.run()).failed, 1);
      now = now.add(const Duration(seconds: 6));
      expect((await engine.run()).succeeded, 1);
      await db
          .into(db.syncQueue)
          .insert(
            SyncQueueCompanion.insert(
              entityType: 'visit',
              entityId: id,
              operation: 'upsert',
            ),
          );
      expect((await engine.run()).succeeded, 1);
      expect(
        (await db.select(db.visits).getSingle()).syncStatus,
        SyncStatus.synced,
      );
      final response = await dio.get<Map<String, dynamic>>('sync');
      final visits = (response.data!['visits'] as List)
          .where((v) => v['id'] == id)
          .toList();
      expect(visits, hasLength(1));
      expect(visits.single['serverVersion'], 1);
      await ObjectsRepository(
        DriftObjectsDataSource(db),
        remote: () => ObjectsRemoteDataSource(dio),
      ).refreshObjects();
      expect(
        (await (db.select(
          db.technicalObjects,
        )..where((o) => o.id.equals(object.id))).getSingle()).status.name,
        'visited',
      );
    },
    skip: url.isEmpty
        ? 'Set SYNC_TEST_URL to a running isolated test backend'
        : false,
  );
}
