import '../../../core/sync/sync_status.dart';

class QueueOperation {
  const QueueOperation({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.operation,
    required this.createdAt,
    required this.attemptCount,
    required this.status,
    this.lastError,
    this.nextRetryAt,
    this.operationId,
  });
  final int id;
  final String entityType;
  final String entityId;
  final String operation;
  final DateTime createdAt;
  final int attemptCount;
  final SyncStatus status;
  final String? lastError;
  final DateTime? nextRetryAt;
  final String? operationId;
}

class SyncDiagnostics {
  const SyncDiagnostics({
    required this.operations,
    required this.synced,
    this.lastSuccessAt,
  });
  final List<QueueOperation> operations;
  final int synced;
  final DateTime? lastSuccessAt;
  int count(SyncStatus status) =>
      operations.where((item) => item.status == status).length;
}
