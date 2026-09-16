import 'dart:convert';

enum ConflictResolution { acceptServer, keepLocal }

/// Не содержит Drift/Dio. Снимок запроса, последняя локальная правка и current
/// от сервера различаются, если пользователь изменил запись во время HTTP.
class SyncConflict {
  const SyncConflict({
    required this.id,
    required this.queueId,
    required this.entityType,
    required this.entityId,
    required this.requestPayload,
    required this.localPayload,
    required this.currentLocalPayload,
    required this.serverPayload,
    required this.createdAt,
    this.resolvedAt,
    this.resolution,
  });
  final int id, queueId;
  final String entityType,
      entityId,
      requestPayload,
      localPayload,
      currentLocalPayload;
  final String? serverPayload, resolution;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  bool get canKeepLocal => entityType == 'object';
  int? get localVersion =>
      jsonDecode(currentLocalPayload)['serverVersion'] as int?;
  int? get serverVersion => serverPayload == null
      ? null
      : jsonDecode(serverPayload!)['serverVersion'] as int?;
}
