import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/location/location_service.dart';
import '../../../core/location/native_tracking.dart';
import '../../../core/utils/local_id.dart';
import '../../tracking/domain/location_point_filter.dart';
import '../domain/route_snapshot.dart';
import '../domain/route_status.dart';

class RouteRepository {
  RouteRepository(this._db, {this.filter = const LocationPointFilter()});
  final AppDatabase _db;
  final LocationPointFilter filter;

  /// Постоянные идентификаторы платформы делают повторный импорт после потери подтверждения безопасным,
  /// даже если сервер уже подтвердил исходящую очередь. Поздняя доставка в завершённый
  /// обход допустима: сам сбор уже остановлен платформенным барьером записи.
  Future<void> importRecordedPoints(List<RecordedPoint> points) =>
      _db.transaction(() async {
        for (final point in points) {
          final existing = await (_db.select(
            _db.locationPoints,
          )..where((p) => p.id.equals(point.id))).getSingleOrNull();
          if (existing != null) continue;
          final fix = point.fix;
          if (filter.reject(fix) != null ||
              point.id.isEmpty ||
              point.segmentId.isEmpty) {
            throw const FormatException('Invalid native GPS point');
          }
          await _db
              .into(_db.locationPoints)
              .insert(
                LocationPointsCompanion.insert(
                  id: point.id,
                  routeId: point.routeId,
                  segmentId: Value(point.segmentId),
                  latitude: fix.latitude,
                  longitude: fix.longitude,
                  accuracy: fix.accuracy,
                  speed: Value(fix.speed),
                  timestamp: fix.timestamp,
                ),
              );
          await _db
              .into(_db.syncQueue)
              .insert(
                SyncQueueCompanion.insert(
                  entityType: 'location_point',
                  entityId: point.id,
                  operation: 'upsert',
                ),
              );
        }
      });

  Future<String> start() => _db.transaction(() async {
    final active =
        await (_db.select(_db.routes)
              ..where((r) => r.status.equalsValue(RouteStatus.active))
              ..limit(1))
            .getSingleOrNull();
    if (active != null) return active.id;
    final id = localId();
    final now = DateTime.now().toUtc();
    await _db
        .into(_db.routes)
        .insert(
          RoutesCompanion.insert(
            id: id,
            name: 'Пеший обход',
            status: const Value(RouteStatus.active),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    await _db
        .into(_db.syncQueue)
        .insert(
          SyncQueueCompanion.insert(
            entityType: 'route',
            entityId: id,
            operation: 'create',
          ),
        );
    return id;
  });

  Future<void> finish(String id) async {
    await (_db.update(_db.routes)..where(
          (r) => r.id.equals(id) & r.status.equalsValue(RouteStatus.active),
        ))
        .write(
          RoutesCompanion(
            status: const Value(RouteStatus.completed),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  /// Точка и исходящая операция сохраняются атомарно. Проверка статуса упорядочивает завершение
  /// и ожидающие записи GPS; завершённый обход не принимает поздние измерения.
  Future<bool> append(
    String routeId,
    String segmentId,
    LocationFix fix, {
    bool Function()? stillActive,
  }) => _db.transaction(() async {
    // Drift хранит DateTime в целых секундах. Фильтруем то же время, которое будет
    // сохранено в SQLite: изменения долей секунды не должны менять порядок маршрута.
    fix = LocationFix(
      latitude: fix.latitude,
      longitude: fix.longitude,
      accuracy: fix.accuracy,
      speed: fix.speed,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        fix.timestamp.millisecondsSinceEpoch ~/ 1000 * 1000,
        isUtc: true,
      ),
    );
    final route = await (_db.select(
      _db.routes,
    )..where((r) => r.id.equals(routeId))).getSingleOrNull();
    if (route?.status != RouteStatus.active ||
        (stillActive != null && !stillActive())) {
      return false;
    }
    final latest =
        await (_db.select(_db.locationPoints)
              ..where((p) => p.routeId.equals(routeId))
              ..orderBy([(p) => OrderingTerm.desc(p.timestamp)])
              ..limit(1))
            .getSingleOrNull();
    // Отклоняем устаревшие координаты и после перезапуска; новый сегмент сбрасывает только геометрию.
    if (latest != null && !fix.timestamp.isAfter(latest.timestamp)) {
      return false;
    }
    final previous = latest?.segmentId == segmentId && latest != null
        ? LocationFix(
            latitude: latest.latitude,
            longitude: latest.longitude,
            accuracy: latest.accuracy,
            timestamp: latest.timestamp,
            speed: latest.speed,
          )
        : null;
    if (filter.reject(fix, previous: previous) != null ||
        (stillActive != null && !stillActive())) {
      return false;
    }
    final id = localId();
    await _db
        .into(_db.locationPoints)
        .insert(
          LocationPointsCompanion.insert(
            id: id,
            routeId: routeId,
            segmentId: Value(segmentId),
            latitude: fix.latitude,
            longitude: fix.longitude,
            accuracy: fix.accuracy,
            speed: Value(fix.speed),
            timestamp: fix.timestamp.toUtc(),
          ),
        );
    await _db
        .into(_db.syncQueue)
        .insert(
          SyncQueueCompanion.insert(
            entityType: 'location_point',
            entityId: id,
            operation: 'upsert',
          ),
        );
    return true;
  });

  Stream<RouteSnapshot?> watchCurrent() => _db
      .customSelect(
        '''
    SELECT r.*, p.id AS point_id, p.latitude, p.longitude, p.accuracy, p.speed, p.timestamp, p.segment_id,
      (SELECT json_group_array(o.name) FROM objects o WHERE EXISTS
       (SELECT 1 FROM visits v WHERE v.object_id = o.id AND v.route_id = r.id AND v.status = 'completed')) AS visited_names
    FROM routes r LEFT JOIN location_points p ON p.route_id = r.id
    WHERE r.id = (SELECT id FROM routes WHERE status IN ('active', 'completed')
      ORDER BY CASE status WHEN 'active' THEN 0 ELSE 1 END, created_at DESC, id DESC LIMIT 1)
    ORDER BY p.timestamp, p.id
  ''',
        readsFrom: {
          _db.routes,
          _db.locationPoints,
          _db.visits,
          _db.technicalObjects,
        },
      )
      .watch()
      .map((rows) {
        if (rows.isEmpty) return null;
        final r = rows.first;
        final status = RouteStatus.values.byName(r.read<String>('status'));
        return RouteSnapshot(
          id: r.read<String>('id'),
          name: r.read<String>('name'),
          status: status,
          startedAt: r.read<DateTime>('created_at'),
          endedAt: status == RouteStatus.completed
              ? r.read<DateTime>('updated_at')
              : null,
          visitedNames: List<String>.from(
            jsonDecode(r.read<String>('visited_names')) as List,
          ),
          points: rows
              .where((r) => r.readNullable<String>('point_id') != null)
              .map(
                (r) => TrackPoint(
                  LocationFix(
                    latitude: r.read<double>('latitude'),
                    longitude: r.read<double>('longitude'),
                    accuracy: r.read<double>('accuracy'),
                    speed: r.readNullable<double>('speed'),
                    timestamp: r.read<DateTime>('timestamp'),
                  ),
                  r.readNullable<String>('segment_id'),
                ),
              )
              .toList(growable: false),
        );
      });
}
