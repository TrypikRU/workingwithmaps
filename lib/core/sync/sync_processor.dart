import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../utils/app_logger.dart';
import 'retry_policy.dart';
import 'sync_error.dart';
import 'sync_status.dart';
import 'sync_lease.dart';
import 'sync_snapshot.dart';

/// Обработка одной операции: сохранённый захват → HTTP без блокировки SQL → атомарное подтверждение.
/// Ни DTO Drift, ни Dio не выходят в интерфейс. Движок отвечает только за порядок запусков.
class SyncProcessor {
  SyncProcessor(
    this.database, {
    required this.dio,
    this.logger = const AppLogger(),
    this.retryPolicy = const RetryPolicy(),
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final AppDatabase database;
  final Dio Function() dio;
  final AppLogger logger;
  final RetryPolicy retryPolicy;
  final DateTime Function() clock;
  Future<void> Function()? verifyOwnership;

  /// Явный повтор пользователя сохраняет идентичность запроса и прежнюю диагностику.
  /// Вызывается только внутри общей для процесса секции единственного запуска движка.
  Future<void> retryFailed() => database.transaction(() async {
    await verifyOwnership?.call();
    final failed = await (database.select(
      database.syncQueue,
    )..where((q) => q.syncStatus.equalsValue(SyncStatus.failed))).get();
    for (final item in failed) {
      // 409 требует решения человека. «Повторить ошибочные» не является
      // согласием перезаписать запись, даже для старых ошибок без снимка данных.
      try {
        if (jsonDecode(item.lastError ?? '{}')['kind'] == 'conflict') continue;
      } catch (_) {
        /* Старое значение lastError может содержать обычный текст. */
      }
      await (database.update(
        database.syncQueue,
      )..where((q) => q.id.equals(item.id))).write(
        const SyncQueueCompanion(
          syncStatus: Value(SyncStatus.pending),
          nextRetryAt: Value(null),
        ),
      );
      await _entityStatus(item, SyncStatus.pending);
    }
    logger.log('sync.retry.manual', {'operations': failed.length});
  });

  Future<void> recover() => database.transaction(() async {
    await verifyOwnership?.call();
    final interrupted = await (database.select(
      database.syncQueue,
    )..where((q) => q.syncStatus.equalsValue(SyncStatus.syncing))).get();
    for (final item in interrupted) {
      await (database.update(
        database.syncQueue,
      )..where((q) => q.id.equals(item.id))).write(
        const SyncQueueCompanion(
          syncStatus: Value(SyncStatus.pending),
          nextRetryAt: Value(null),
        ),
      );
      await _entityStatus(item, SyncStatus.pending);
      logger.log('sync.recovered', {
        'queueId': item.id,
        'operationId': item.operationId,
      });
    }
  });

  Future<List<SyncQueueData>> queued() => (database.select(
    database.syncQueue,
  )..orderBy([(q) => OrderingTerm.asc(q.id)])).get();

  Future<bool> process(SyncQueueData item, {CancelToken? cancelToken}) async {
    final started = Stopwatch()..start();
    logger.log('sync.operation.start', {
      'queueId': item.id,
      'entityType': item.entityType,
      'attempt': item.attemptCount + 1,
    });
    try {
      final claimed = await _claim(item);
      final payload = jsonDecode(claimed.payload!) as Map<String, dynamic>;
      final response = await dio().request<dynamic>(
        switch (item.entityType) {
          'object' => 'objects/${Uri.encodeComponent(item.entityId)}',
          'visit' => 'visits',
          'route' => 'routes',
          _ => 'location/batch',
        },
        cancelToken: cancelToken,
        data: item.entityType != 'location_point'
            ? payload
            : {
                'points': [payload],
              },
        // Сервер исключает дубликаты по постоянному идентификатору сущности и одинаковым данным. Ключ
        // также обозначает зафиксированную операцию в журнале, но не заменяет
        // серверную защиту от дубликатов и никогда не меняется при повторах.
        options: Options(
          method: item.entityType == 'object' ? 'PATCH' : 'POST',
          headers: {'Idempotency-Key': claimed.operationId},
        ),
      );
      final body = response.data;
      Map<String, dynamic>? ack;
      if (body is Map<String, dynamic>) {
        if (item.entityType != 'location_point') {
          ack = body;
        } else {
          final accepted = body['accepted'];
          if (accepted is List &&
              accepted.length == 1 &&
              accepted.single is Map<String, dynamic>) {
            ack = accepted.single as Map<String, dynamic>;
          }
        }
      }
      if (ack == null ||
          ack['id'] != item.entityId ||
          (['visit', 'object'].contains(item.entityType) &&
              (ack['serverVersion'] is! int ||
                  (ack['serverVersion'] as int) < 1))) {
        throw const SyncException(
          SyncErrorKind.invalidResponse,
          'Missing or mismatched acknowledgement',
        );
      }
      await _acknowledge(claimed, ack);
      logger.log('sync.operation.success', {
        'queueId': item.id,
        'operationId': claimed.operationId,
        'elapsedMs': started.elapsedMilliseconds,
      });
      return true;
    } catch (error) {
      if (error is SyncLeaseLost || (cancelToken?.isCancelled ?? false)) {
        rethrow;
      }
      final failure = error is SyncException
          ? error
          : error is DioException
          ? SyncException.fromDio(error)
          : const SyncException(SyncErrorKind.local, 'Local processing failed');
      // Если SQLite недоступна, оставляем сохранённый захват в syncing. При
      // следующем запуске восстановление повторит тот же запрос; остальные строки целы.
      await _fail(
        item,
        failure,
        current: error is DioException && error.response?.data is Map
            ? (error.response!.data as Map)['current']
            : null,
      );
      logger.log('sync.operation.failure', {
        'queueId': item.id,
        ...failure.toJson(),
        'elapsedMs': started.elapsedMilliseconds,
      });
      return false;
    }
  }

  Future<SyncQueueData> _claim(SyncQueueData item) => database.transaction(
    () async {
      await verifyOwnership?.call();
      // Репозиторий может объединить B с выбранной, ещё не отправленной A между
      // queued() и захватом. Перед фиксацией повторно читаем запись внутри транзакции.
      item = await (database.select(
        database.syncQueue,
      )..where((q) => q.id.equals(item.id))).getSingle();
      if (!(item.entityType == 'object' &&
              ['upsert', 'update', 'patch'].contains(item.operation)) &&
          !(item.entityType == 'route' && item.operation == 'create') &&
          !(item.operation == 'upsert' &&
              ['visit', 'location_point'].contains(item.entityType))) {
        throw const SyncException(
          SyncErrorKind.unsupported,
          'Backend has no writer for this operation',
        );
      }
      String? payload = item.payload;
      if (payload == null) {
        Map<String, dynamic> data;
        if (item.entityType == 'object') {
          data = syncRequest(
            await readSyncEntity(database, 'object', item.entityId),
          );
        } else if (item.entityType == 'route') {
          final route = await (database.select(
            database.routes,
          )..where((r) => r.id.equals(item.entityId))).getSingle();
          data = {
            'id': route.id,
            'name': route.name,
            'date': route.createdAt.toUtc().toIso8601String().substring(0, 10),
          };
        } else if (item.entityType == 'visit') {
          final visit = await (database.select(
            database.visits,
          )..where((v) => v.id.equals(item.entityId))).getSingleOrNull();
          if (visit == null) {
            throw const SyncException(SyncErrorKind.local, 'Visit missing');
          }
          data = {
            'id': visit.id,
            'objectId': visit.objectId,
            'routeId': visit.routeId,
            'status': visit.status.name,
            'latitude': visit.latitude,
            'longitude': visit.longitude,
            'accuracy': visit.accuracy,
            'createdAt': visit.createdAt.toUtc().toIso8601String(),
            'serverVersion': visit.serverVersion,
          };
        } else {
          final point = await (database.select(
            database.locationPoints,
          )..where((p) => p.id.equals(item.entityId))).getSingleOrNull();
          if (point == null) {
            throw const SyncException(
              SyncErrorKind.local,
              'Location point missing',
            );
          }
          data = {
            'id': point.id,
            'routeId': point.routeId,
            'latitude': point.latitude,
            'longitude': point.longitude,
            'accuracy': point.accuracy,
            'speed': point.speed,
            'timestamp': point.timestamp.toUtc().toIso8601String(),
          };
        }
        payload = jsonEncode(data);
      }
      final routeId =
          (jsonDecode(payload) as Map<String, dynamic>)['routeId'] as String?;
      if (routeId != null) {
        final registration =
            await (database.select(database.syncQueue)
                  ..where(
                    (q) =>
                        q.entityType.equals('route') &
                        q.entityId.equals(routeId) &
                        q.operation.equals('create'),
                  )
                  ..limit(1))
                .getSingleOrNull();
        if (registration != null) {
          throw const SyncException(
            SyncErrorKind.dependency,
            'Waiting for route registration',
          );
        }
      }
      final random = Random.secure();
      final operationId =
          item.operationId ??
          List.generate(
            16,
            (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join();
      await (database.update(
        database.syncQueue,
      )..where((q) => q.id.equals(item.id))).write(
        SyncQueueCompanion(
          operationId: Value(operationId),
          payload: Value(payload),
          syncStatus: const Value(SyncStatus.syncing),
        ),
      );
      await _entityStatus(item, SyncStatus.syncing);
      logger.log('sync.operation.claimed', {
        'queueId': item.id,
        'operationId': operationId,
      });
      return (database.select(
        database.syncQueue,
      )..where((q) => q.id.equals(item.id))).getSingle();
    },
  );

  Future<void> _acknowledge(
    SyncQueueData item,
    Map<String, dynamic> ack,
  ) => database.transaction(() async {
    await verifyOwnership?.call();
    await (database.delete(
      database.syncQueue,
    )..where((q) => q.id.equals(item.id))).go();
    final remaining =
        await (database.select(database.syncQueue)..where(
              (q) =>
                  q.entityType.equals(item.entityType) &
                  q.entityId.equals(item.entityId),
            ))
            .get();
    final status = remaining.isEmpty ? SyncStatus.synced : SyncStatus.pending;
    if (item.entityType == 'object') {
      await (database.update(
        database.technicalObjects,
      )..where((o) => o.id.equals(item.entityId))).write(
        TechnicalObjectsCompanion(
          serverVersion: Value(ack['serverVersion'] as int),
        ),
      );
    } else if (item.entityType == 'visit') {
      // Не копируем серверные бизнес-поля поверх более свежей локальной правки.
      // Следующая операция получит эту serverVersion при создании своего снимка.
      await (database.update(
        database.visits,
      )..where((v) => v.id.equals(item.entityId))).write(
        VisitsCompanion(
          syncStatus: Value(status),
          serverVersion: Value(ack['serverVersion'] as int),
        ),
      );
    } else {
      await _entityStatus(item, status);
    }
    // Счётчики диагностики входят в подтверждение: откат не может показать успех.
    final now = clock().toUtc();
    final countRow = await (database.select(
      database.appMetadata,
    )..where((m) => m.key.equals('sync.acknowledged_count'))).getSingleOrNull();
    final count = int.tryParse(countRow?.value ?? '') ?? 0;
    await database
        .into(database.appMetadata)
        .insertOnConflictUpdate(
          AppMetadataCompanion.insert(
            key: 'sync.acknowledged_count',
            value: '${count + 1}',
            updatedAt: Value(now),
          ),
        );
    await database
        .into(database.appMetadata)
        .insertOnConflictUpdate(
          AppMetadataCompanion.insert(
            key: 'sync.last_success_at',
            value: now.toIso8601String(),
            updatedAt: Value(now),
          ),
        );
  });

  Future<void> _fail(
    SyncQueueData item,
    SyncException failure, {
    Object? current,
  }) => database.transaction(() async {
    await verifyOwnership?.call();
    if (failure.kind == SyncErrorKind.conflict) {
      final claimed = await (database.select(
        database.syncQueue,
      )..where((q) => q.id.equals(item.id))).getSingle();
      final local = ['object', 'visit'].contains(item.entityType)
          ? jsonEncode(
              await readSyncEntity(database, item.entityType, item.entityId),
            )
          : claimed.payload ?? '{}';
      final server = validatedServerSnapshot(
        item.entityType,
        item.entityId,
        current,
      );
      await database
          .into(database.syncConflicts)
          .insert(
            SyncConflictsCompanion.insert(
              queueId: item.id,
              entityType: item.entityType,
              entityId: item.entityId,
              requestPayload: claimed.payload ?? '{}',
              localPayload: local,
              serverPayload: Value(server == null ? null : jsonEncode(server)),
              createdAt: clock().toUtc(),
            ),
          );
      logger.log('sync.conflict.detected', {
        'queueId': item.id,
        'hasServerSnapshot': server != null,
      });
    }
    final attempts = item.attemptCount + 1;
    final retryAt = failure.retryable
        ? clock().toUtc().add(retryPolicy.delay(attempts))
        : null;
    await (database.update(
      database.syncQueue,
    )..where((q) => q.id.equals(item.id))).write(
      SyncQueueCompanion(
        syncStatus: const Value(SyncStatus.failed),
        attemptCount: Value(attempts),
        lastError: Value(jsonEncode(failure.toJson())),
        nextRetryAt: Value(retryAt),
      ),
    );
    await _entityStatus(item, SyncStatus.failed);
    logger.log('sync.retry.scheduled', {
      'queueId': item.id,
      'attemptCount': attempts,
      'nextRetryAt': retryAt?.toIso8601String(),
    });
  });

  Future<void> _entityStatus(SyncQueueData item, SyncStatus status) async {
    if (item.entityType == 'visit') {
      await (database.update(database.visits)
            ..where((v) => v.id.equals(item.entityId)))
          .write(VisitsCompanion(syncStatus: Value(status)));
    } else if (item.entityType == 'location_point') {
      await (database.update(database.locationPoints)
            ..where((p) => p.id.equals(item.entityId)))
          .write(LocationPointsCompanion(syncStatus: Value(status)));
    } else if (item.entityType == 'route') {
      await (database.update(database.routes)
            ..where((r) => r.id.equals(item.entityId)))
          .write(RoutesCompanion(syncStatus: Value(status)));
    }
  }
}
