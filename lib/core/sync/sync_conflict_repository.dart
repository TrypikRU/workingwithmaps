import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart' hide SyncConflict;
import '../utils/app_logger.dart';
import '../../features/objects/data/object_dto.dart';
import '../../features/objects/domain/technical_object.dart';
import '../../features/visits/domain/visit_status.dart';
import 'sync_conflict.dart';
import 'sync_lease.dart';
import 'sync_snapshot.dart';
import 'sync_status.dart';
import 'queue_coalescing.dart';
import 'sync_conflict_remote_data_source.dart';

class SyncConflictRepository {
  SyncConflictRepository(this.db, {this.remote});
  final AppDatabase db;
  final SyncConflictRemoteDataSource Function()? remote;

  Future<void> refreshServer(SyncConflict conflict) async {
    final source = remote;
    if (source == null) throw StateError('Источник сервера не настроен.');
    final snapshot = await source().fetch(
      conflict.entityType,
      conflict.entityId,
    );
    await db.transaction(() async {
      final current = await (db.select(
        db.syncConflicts,
      )..where((c) => c.id.equals(conflict.id))).getSingle();
      if (current.resolvedAt != null) {
        throw StateError('Конфликт уже разрешён.');
      }
      await (db.update(
        db.syncConflicts,
      )..where((c) => c.id.equals(conflict.id))).write(
        SyncConflictsCompanion(serverPayload: Value(jsonEncode(snapshot))),
      );
    });
  }

  Stream<List<SyncConflict>> watch() => db
      .customSelect(
        'SELECT * FROM sync_conflicts ORDER BY id DESC',
        readsFrom: {db.syncConflicts, db.technicalObjects, db.visits},
      )
      .watch()
      .asyncMap((rows) async {
        final result = <SyncConflict>[];
        for (final raw in rows) {
          final row = db.syncConflicts.map(raw.data);
          var current = row.localPayload;
          if (row.resolvedAt == null &&
              ['visit', 'object'].contains(row.entityType)) {
            try {
              current = jsonEncode(
                await readSyncEntity(db, row.entityType, row.entityId),
              );
            } on StateError {
              // Старая очередь могла ссылаться на уже отсутствующую запись.
              // Сам конфликт должен оставаться видимым для диагностики.
            }
          }
          result.add(
            SyncConflict(
              id: row.id,
              queueId: row.queueId,
              entityType: row.entityType,
              entityId: row.entityId,
              requestPayload: row.requestPayload,
              localPayload: row.localPayload,
              currentLocalPayload: current,
              serverPayload: row.serverPayload,
              createdAt: row.createdAt,
              resolvedAt: row.resolvedAt,
              resolution: row.resolution,
            ),
          );
        }
        return List.unmodifiable(result);
      });

  Future<void> resolve(
    SyncConflict reviewed,
    ConflictResolution strategy,
  ) async {
    final lease = SyncLease(db);
    if (!await lease.acquire()) {
      throw StateError(
        'Синхронизация выполняется. Повторите после её завершения.',
      );
    }
    try {
      await db.transaction(() async {
        await lease.renew();
        final row = await (db.select(
          db.syncConflicts,
        )..where((c) => c.id.equals(reviewed.id))).getSingle();
        if (row.resolvedAt != null) throw StateError('Конфликт уже разрешён.');
        final local = jsonEncode(
          await readSyncEntity(db, row.entityType, row.entityId),
        );
        if (local != reviewed.currentLocalPayload ||
            row.serverPayload != reviewed.serverPayload) {
          throw StateError(
            'Запись изменилась. Закройте диалог и просмотрите версии заново.',
          );
        }
        final server = validatedServerSnapshot(
          row.entityType,
          row.entityId,
          row.serverPayload == null ? null : jsonDecode(row.serverPayload!),
        );
        if (server == null) {
          throw StateError(
            'Сервер не предоставил корректный снимок. Разрешение недоступно.',
          );
        }
        if (strategy == ConflictResolution.keepLocal &&
            row.entityType != 'object') {
          throw StateError(
            'Посещения — факты событий: перезапись серверной записи запрещена.',
          );
        }
        final queue =
            await (db.select(db.syncQueue)..where(
                  (q) =>
                      q.entityType.equals(row.entityType) &
                      q.entityId.equals(row.entityId),
                ))
                .get();
        if (!queue.any((q) => q.id == row.queueId) ||
            queue.any(
              (q) =>
                  q.id != row.queueId &&
                  (q.payload != null || q.syncStatus == SyncStatus.syncing),
            )) {
          throw StateError(
            'Очередь изменилась или содержит другой отправленный запрос.',
          );
        }
        final now = DateTime.now().toUtc();
        if (row.entityType == 'object') {
          final object = ObjectDto.fromJson(server).toDomain();
          if (strategy == ConflictResolution.acceptServer) {
            final pendingVisits =
                await (db.select(db.visits)..where(
                      (v) =>
                          v.objectId.equals(object.id) &
                          v.syncStatus.equalsValue(SyncStatus.synced).not(),
                    ))
                    .get();
            await (db.update(
              db.technicalObjects,
            )..where((o) => o.id.equals(object.id))).write(
              TechnicalObjectsCompanion(
                name: Value(object.name),
                address: Value(object.address),
                latitude: Value(object.latitude),
                longitude: Value(object.longitude),
                status: Value(
                  pendingVisits.any((v) => v.status == VisitStatus.completed)
                      ? ObjectStatus.visited
                      : object.status,
                ),
                priority: Value(object.priority),
                updatedAt: Value(now),
                serverVersion: Value(object.serverVersion),
              ),
            );
          } else {
            // Явное применение правки поверх показанной версии. Новое параллельное изменение сервера
            // снова даст 409; принудительной перезаписи или выбора по времени здесь нет.
            await (db.update(
              db.technicalObjects,
            )..where((o) => o.id.equals(object.id))).write(
              TechnicalObjectsCompanion(
                serverVersion: Value(object.serverVersion),
              ),
            );
          }
        } else {
          await (db.update(
            db.visits,
          )..where((v) => v.id.equals(row.entityId))).write(
            VisitsCompanion(
              objectId: Value(server['objectId'] as String),
              routeId: Value(server['routeId'] as String?),
              status: Value(
                VisitStatus.values.byName(server['status'] as String),
              ),
              latitude: Value(server['latitude'] as double),
              longitude: Value(server['longitude'] as double),
              accuracy: Value(server['accuracy'] as double),
              createdAt: Value(DateTime.parse(server['createdAt'] as String)),
              updatedAt: Value(DateTime.parse(server['updatedAt'] as String)),
              syncStatus: const Value(SyncStatus.synced),
              serverVersion: Value(server['serverVersion'] as int),
            ),
          );
        }
        await (db.delete(db.syncQueue)..where(
              (q) =>
                  q.entityType.equals(row.entityType) &
                  q.entityId.equals(row.entityId),
            ))
            .go();
        await (db.update(
          db.syncConflicts,
        )..where((c) => c.id.equals(row.id))).write(
          SyncConflictsCompanion(
            localPayload: Value(local),
            resolvedAt: Value(now),
            resolution: Value(strategy.name),
          ),
        );
        if (strategy == ConflictResolution.keepLocal) {
          await enqueueObjectUpdate(db, row.entityId, now);
        }
        const AppLogger().log('sync.conflict.resolved', {
          'conflictId': row.id,
          'strategy': strategy.name,
        });
      });
    } finally {
      await lease.release();
    }
  }
}
