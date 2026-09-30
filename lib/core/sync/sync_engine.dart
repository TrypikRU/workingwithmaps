import 'dart:async';

import '../utils/app_logger.dart';
import 'sync_processor.dart';
import 'sync_result.dart';
import 'sync_status.dart';
import 'sync_lease.dart';
import 'sync_run_control.dart';

/// Совместный запуск объединяет вызовы в одном изоляте; блокировка SQLite согласует движки
/// интерфейса и WorkManager между изолятами. Все отправители используют этот движок.
/// Сам движок не зависит от Flutter, Riverpod, таймеров интерфейса или WorkManager.
class SyncEngine {
  SyncEngine(
    this.processor, {
    this.logger = const AppLogger(),
    this.maxRunDuration = const Duration(minutes: 4),
  });
  final SyncProcessor processor;
  final AppLogger logger;
  final Duration maxRunDuration;
  static Future<SyncResult>? _active;
  static final _activity = StreamController<bool>.broadcast(sync: true);

  /// Только подсказка планировщику; классификация повторов и порядок сущностей остаются здесь,
  /// а не в WorkManager. Неразрешённый конфликт блокирует следующие версии своей сущности.
  Future<bool> hasRetryableWork() async {
    final heads = <String>{};
    for (final item in await processor.queued()) {
      if (!heads.add('${item.entityType}:${item.entityId}')) continue;
      if (item.syncStatus == SyncStatus.pending ||
          item.syncStatus == SyncStatus.syncing ||
          (item.syncStatus == SyncStatus.failed && item.nextRetryAt != null)) {
        return true;
      }
    }
    return false;
  }

  /// Учитывает автоматические запуски и другие экземпляры, а не только кнопку экрана.
  Stream<bool> watchRunning() => Stream<bool>.multi((controller) {
    String? value;
    void emit() => controller.add(_active != null || SyncLease.isActive(value));
    final subscription = _activity.stream.listen((_) => emit());
    final db = processor.database;
    final remote =
        (db.select(db.appMetadata)..where((m) => m.key.equals(SyncLease.key)))
            .watchSingleOrNull()
            .listen((row) {
              value = row?.value;
              emit();
            }, onError: controller.addError);
    final timer = Timer.periodic(const Duration(seconds: 5), (_) => emit());
    emit();
    controller.onCancel = () {
      timer.cancel();
      // Синхронно отменяем обе подписки до ожидания освобождения ресурсов.
      // Это позволяет Drift запланировать закрытие потока в зоне его интерфейса.
      unawaited(subscription.cancel());
      unawaited(remote.cancel());
    };
  }, isBroadcast: true).distinct();

  Future<SyncResult> run({bool retryFailed = false, SyncRunControl? control}) {
    if (_active != null) {
      logger.log('sync.run.joined');
      // Явный повтор ждёт текущего прохода, не меняя строки, которые тот может отправлять.
      // Обычные запуски по-прежнему объединяются.
      if (retryFailed) {
        return _active!.then((_) => run(retryFailed: true, control: control));
      }
      return _active!;
    }
    final result = _active =
        _run(
          retryFailed: retryFailed,
          control: control ?? SyncRunControl(),
        ).whenComplete(() {
          _active = null;
          _activity.add(false);
        });
    _activity.add(true);
    return result;
  }

  Future<SyncResult> _run({
    required bool retryFailed,
    required SyncRunControl control,
  }) async {
    logger.log('sync.run.start');
    var succeeded = 0;
    var failed = 0;
    final lease = SyncLease(processor.database, clock: processor.clock);
    if (control.cancelled || !await lease.acquire()) {
      logger.log('sync.run.deferred');
      return const SyncResult(deferred: true);
    }
    processor.verifyOwnership = lease.renew;
    final deadline = Timer(maxRunDuration, control.cancel);
    try {
      await processor.recover();
      if (retryFailed) await processor.retryFailed();
      final initial = await processor.queued();
      final watermark = initial.isEmpty ? 0 : initial.last.id;
      final attempted = <int>{};
      while (true) {
        if (control.cancelled) {
          return SyncResult(
            succeeded: succeeded,
            failed: failed,
            deferred: true,
          );
        }
        final queue = await processor.queued();
        final heads = <String>{};
        final now = processor.clock().toUtc();
        final due = queue.where((item) {
          // Не обгоняем старую операцию той же сущности, включая конфликт и повтор.
          final key = '${item.entityType}:${item.entityId}';
          if (!heads.add(key) ||
              attempted.contains(item.id) ||
              item.id > watermark) {
            return false;
          }
          return (item.syncStatus == SyncStatus.pending &&
                  (item.nextRetryAt == null ||
                      !item.nextRetryAt!.isAfter(now))) ||
              (item.syncStatus == SyncStatus.failed &&
                  item.nextRetryAt != null &&
                  !item.nextRetryAt!.isAfter(now));
        }).firstOrNull;
        if (due == null) break;
        attempted.add(due.id);
        if (await processor.process(due, cancelToken: control.token)) {
          succeeded++;
        } else {
          failed++;
        }
      }
      logger.log('sync.run.complete', {
        'succeeded': succeeded,
        'failed': failed,
      });
      return SyncResult(succeeded: succeeded, failed: failed);
    } catch (error) {
      logger.log('sync.run.interrupted', {
        'succeeded': succeeded,
        'failed': failed,
      });
      if (control.cancelled || error is SyncLeaseLost) {
        return SyncResult(succeeded: succeeded, failed: failed, deferred: true);
      }
      rethrow;
    } finally {
      deadline.cancel();
      processor.verifyOwnership = null;
      try {
        await lease.release();
      } catch (_) {
        logger.log('sync.lease.release_failed');
      }
    }
  }
}
