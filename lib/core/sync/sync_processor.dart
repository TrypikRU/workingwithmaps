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

/// Обработка одной операции: durable claim → HTTP без SQL lock → atomic ACK.
/// Ни DTO Drift, ни Dio не выходят в UI. Engine отвечает только за порядок запусков.
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

  /// Explicit user retry preserves the request identity and previous diagnostics.
  /// Called only inside the engine's process-wide single-flight section.
  Future<void> retryFailed() => database.transaction(() async {
    await verifyOwnership?.call();
    final failed = await (database.select(
      database.syncQueue,
    )..where((q) => q.syncStatus.equalsValue(SyncStatus.failed))).get();
    for (final item in failed) {
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
      final response = await dio().post<dynamic>(
        switch (item.entityType) {
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
        // Backend deduplicates by stable entity ID + identical payload. This key
        // also identifies one frozen operation in logs; it is NOT a substitute
        // for server-side deduplication and never changes on retries.
        options: Options(headers: {'Idempotency-Key': claimed.operationId}),
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
          (item.entityType == 'visit' &&
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
      // Если сам SQLite недоступен, оставляем durable claim как syncing. При
      // следующем запуске recover повторит тот же запрос; остальные строки целы.
      await _fail(item, failure);
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
      if (!(item.entityType == 'route' && item.operation == 'create') &&
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
        if (item.entityType == 'route') {
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
    if (item.entityType == 'visit') {
      // Не копируем remote бизнес-поля поверх более свежей локальной правки.
      // Следующая операция получит эту serverVersion при создании своего snapshot.
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
    // Diagnostic counters are part of ACK: a rollback cannot report success.
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

  Future<void> _fail(SyncQueueData item, SyncException failure) =>
      database.transaction(() async {
        await verifyOwnership?.call();
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
