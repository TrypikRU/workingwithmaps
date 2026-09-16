import 'dart:convert';
import '../database/app_database.dart';
import '../../features/objects/data/object_dto.dart';
import '../../features/visits/domain/visit_status.dart';

/// Snapshot только для локальной диагностики/optimistic review. Он не DTO UI.
Future<Map<String, dynamic>> readSyncEntity(
  AppDatabase db,
  String type,
  String id,
) async {
  if (type == 'object') {
    final o = await (db.select(
      db.technicalObjects,
    )..where((o) => o.id.equals(id))).getSingle();
    return {
      'id': o.id,
      'name': o.name,
      'address': o.address,
      'latitude': o.latitude,
      'longitude': o.longitude,
      'status': o.status.name,
      'priority': o.priority.name,
      'serverVersion': o.serverVersion,
      'updatedAt': o.updatedAt.toUtc().toIso8601String(),
      'polygon': o.polygon.map((p) => p.toJson()).toList(),
      'geofenceRadius': o.geofenceRadius,
    };
  }
  if (type == 'visit') {
    final v = await (db.select(
      db.visits,
    )..where((v) => v.id.equals(id))).getSingle();
    return {
      'id': v.id,
      'objectId': v.objectId,
      'routeId': v.routeId,
      'status': v.status.name,
      'latitude': v.latitude,
      'longitude': v.longitude,
      'accuracy': v.accuracy,
      'createdAt': v.createdAt.toUtc().toIso8601String(),
      'serverVersion': v.serverVersion,
    };
  }
  throw StateError('Unsupported conflict entity');
}

/// 409 от proxy/debug может не содержать current или содержать чужую сущность.
/// Такой ответ сохраняется как конфликт без возможности применить его в БД.
Map<String, dynamic>? validatedServerSnapshot(
  String type,
  String id,
  Object? data,
) {
  try {
    if (data is! Map<String, dynamic> ||
        data['id'] != id ||
        data['serverVersion'] is! int ||
        (data['serverVersion'] as int) < 1) {
      return null;
    }
    if (type == 'object') {
      final dto = ObjectDto.fromJson(data);
      dto.toDomain();
      return dto.toJson();
    }
    if (type == 'visit') {
      final lat = (data['latitude'] as num).toDouble();
      final lon = (data['longitude'] as num).toDouble();
      final accuracy = (data['accuracy'] as num).toDouble();
      if (!lat.isFinite ||
          lat.abs() > 90 ||
          !lon.isFinite ||
          lon.abs() > 180 ||
          !accuracy.isFinite ||
          accuracy < 0 ||
          data['objectId'] is! String ||
          (data['objectId'] as String).isEmpty ||
          (data['routeId'] != null && data['routeId'] is! String)) {
        return null;
      }
      final status = VisitStatus.values.byName(data['status'] as String);
      return {
        'id': id,
        'objectId': data['objectId'],
        'routeId': data['routeId'],
        'status': status.name,
        'latitude': lat,
        'longitude': lon,
        'accuracy': accuracy,
        'createdAt': DateTime.parse(
          data['createdAt'] as String,
        ).toUtc().toIso8601String(),
        'updatedAt': DateTime.parse(
          data['updatedAt'] as String,
        ).toUtc().toIso8601String(),
        'serverVersion': data['serverVersion'],
      };
    }
  } catch (_) {
    return null;
  }
  return null;
}

Map<String, dynamic> syncRequest(Map<String, dynamic> snapshot) =>
    Map.of(snapshot)
      ..remove('polygon')
      ..remove('geofenceRadius')
      ..remove('updatedAt');

String prettySnapshot(String value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(value));
  } catch (_) {
    return value;
  }
}
