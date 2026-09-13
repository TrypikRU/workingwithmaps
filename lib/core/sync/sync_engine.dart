import 'dart:async';

import '../utils/app_logger.dart';
import 'sync_processor.dart';
import 'sync_result.dart';
import 'sync_status.dart';
import 'sync_lease.dart';
import 'sync_run_control.dart';

/// Single-flight coalesces callers in one isolate; SQLite lease coordinates UI
/// and WorkManager engines across isolates. Every writer uses this same engine.
/// Нет Flutter, Riverpod, таймеров UI или WorkManager в самом engine.
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

  /// Scheduling hint only; retry classification and per-entity order stay here,
  /// not in WorkManager. Permanent conflict at a head blocks later revisions.
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

  /// Includes automatic runs and other instances, not just the screen's button.
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
      // Cancel both subscriptions synchronously before awaiting any cleanup.
      // This also lets Drift schedule stream disposal in the owning UI zone.
      unawaited(subscription.cancel());
      unawaited(remote.cancel());
    };
  }, isBroadcast: true).distinct();

  Future<SyncResult> run({bool retryFailed = false, SyncRunControl? control}) {
    if (_active != null) {
      logger.log('sync.run.joined');
      // Explicit retry is queued behind a foreground run instead of mutating
      // rows that it may currently be sending. Ordinary runs still coalesce.
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
          // Не обгоняем старую операцию той же сущности, включая conflict и retry.
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
