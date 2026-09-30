import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_status.dart';
import '../domain/sync_diagnostics.dart';

class SyncDiagnosticsRepository {
  SyncDiagnosticsRepository(this._database);
  final AppDatabase _database;

  Stream<SyncDiagnostics> watch() {
    // Один снимок SQL исключает промежуточное состояние «очередь удалена, успех не учтён».
    // LEFT JOIN возвращает метаданные даже при пустой очереди.
    return _database
        .customSelect(
          '''
      SELECT q.*,
        (SELECT value FROM app_metadata WHERE key = 'sync.acknowledged_count') AS acknowledged,
        (SELECT value FROM app_metadata WHERE key = 'sync.last_success_at') AS last_success
      FROM (SELECT 1) AS singleton
      LEFT JOIN sync_queue AS q ON 1 = 1
      ORDER BY q.id ASC
    ''',
          readsFrom: {_database.syncQueue, _database.appMetadata},
        )
        .watch()
        .map((rows) {
          final first = rows.first;
          return SyncDiagnostics(
            synced:
                int.tryParse(
                  first.readNullable<String>('acknowledged') ?? '',
                ) ??
                0,
            lastSuccessAt: DateTime.tryParse(
              first.readNullable<String>('last_success') ?? '',
            ),
            operations: List.unmodifiable(
              rows
                  .where((row) => row.readNullable<int>('id') != null)
                  .map(
                    (row) => QueueOperation(
                      id: row.read<int>('id'),
                      entityType: row.read<String>('entity_type'),
                      entityId: row.read<String>('entity_id'),
                      operation: row.read<String>('operation'),
                      createdAt: row.read<DateTime>('created_at'),
                      attemptCount: row.read<int>('attempt_count'),
                      status: SyncStatus.values.byName(
                        row.read<String>('sync_status'),
                      ),
                      lastError: row.readNullable<String>('last_error'),
                      nextRetryAt: row.readNullable<DateTime>('next_retry_at'),
                      operationId: row.readNullable<String>('operation_id'),
                    ),
                  ),
            ),
          );
        });
  }
}
