import 'dart:math';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/geometry/geo_point.dart';
import '../../../core/location/location_service.dart';
import '../../../core/sync/sync_status.dart';
import '../../objects/domain/technical_object.dart';
import '../../route/domain/route_status.dart';
import '../domain/check_in_policy.dart';
import '../domain/visit_status.dart';

class VisitsRepository {
  VisitsRepository(this._database, {this.policy = const CheckInPolicy()});
  final AppDatabase _database;
  final CheckInPolicy policy;

  Future<String> checkIn({
    required String objectId,
    required LocationFix position,
  }) => _database.transaction(() async {
    final object = await (_database.select(
      _database.technicalObjects,
    )..where((row) => row.id.equals(objectId))).getSingleOrNull();
    if (object == null) throw StateError('Object no longer exists');
    // Проверяем координаты объекта из БД внутри транзакции: HTTP refresh мог
    // изменить их после построения экрана. UI не может обойти бизнес-правило.
    final eligibility = policy.evaluate(
      GeoPoint(object.latitude, object.longitude),
      position,
    );
    if (!eligibility.allowed) throw CheckInRejected(eligibility.block!);
    final now = DateTime.now().toUtc();
    final activeRoute =
        await (_database.select(_database.routes)
              ..where((r) => r.status.equalsValue(RouteStatus.active))
              ..limit(1))
            .getSingleOrNull();
    // 128 случайных бит: offline ID не требует сервера и стабилен для retry.
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await _database
        .into(_database.visits)
        .insert(
          VisitsCompanion.insert(
            id: id,
            objectId: objectId,
            routeId: Value(activeRoute?.id),
            latitude: position.latitude,
            longitude: position.longitude,
            accuracy: position.accuracy,
            createdAt: Value(now),
            updatedAt: Value(now),
            status: const Value(VisitStatus.completed),
            syncStatus: const Value(SyncStatus.pending),
          ),
        );
    await _database
        .into(_database.syncQueue)
        .insert(
          SyncQueueCompanion.insert(
            entityType: 'visit',
            entityId: id,
            operation: 'upsert',
            createdAt: Value(now),
          ),
        );
    // Визит, очередь и видимый статус коммитятся вместе. Отдельная исходящая
    // операция object не нужна: SyncEngine отправит событие визита.
    await (_database.update(
      _database.technicalObjects,
    )..where((row) => row.id.equals(objectId))).write(
      TechnicalObjectsCompanion(
        status: const Value(ObjectStatus.visited),
        updatedAt: Value(now),
      ),
    );
    return id;
  });
}
