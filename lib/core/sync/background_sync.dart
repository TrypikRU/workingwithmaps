import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../database/app_database.dart';
import '../network/dio_provider.dart';
import '../utils/app_logger.dart';
import 'sync_engine.dart';
import 'sync_processor.dart';
import 'sync_run_control.dart';

const backgroundSyncTask = 'field_inspector.sync.v1';
const backgroundSyncUniqueName = 'field-inspector-periodic-sync';
void _workerLog(String event, Map<String, Object?> fields) =>
    debugPrint('[FieldSyncWorker] ${jsonEncode({'event': event, ...fields})}');
final _workerLogger = AppLogger(sink: _workerLog);

/// Top-level entry point is retained in release AOT and runs in a headless
/// Flutter engine. No ProviderScope, Activity channel or GPS subscription needed.
@pragma('vm:entry-point')
void syncCallbackDispatcher() {
  WidgetsFlutterBinding.ensureInitialized();
  SyncRunControl? active;
  Workmanager().executeTask(
    (task, input) async {
      if (task != backgroundSyncTask) {
        _workerLogger.log('worker.unknown_task', {'task': task});
        return true;
      }
      final control = active = SyncRunControl();
      try {
        return await executeBackgroundSync(
          control: control,
          logger: _workerLogger,
        );
      } finally {
        if (identical(active, control)) active = null;
      }
    },
    onTaskStopped: (task, reason) async {
      _workerLogger.log('worker.stopped', {
        'task': task,
        'reason': reason.name,
      });
      active
          ?.cancel(); // Return promptly; sudden engine destruction uses lease expiry.
    },
  );
}

Future<void> initializeBackgroundSync() async {
  if (!Platform.isAndroid) return;
  try {
    final scheduler = Workmanager();
    await scheduler.initialize(syncCallbackDispatcher);
    await scheduler.registerPeriodicTask(
      backgroundSyncUniqueName,
      backgroundSyncTask,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(seconds: 30),
      tag: 'field-inspector-sync',
    );
    _workerLogger.log('worker.registered');
  } catch (error) {
    // Local app remains usable if scheduling is unavailable; retry registration
    // on the next application launch. Existing persisted work is not cancelled.
    _workerLogger.log('worker.registration_failed', {
      'type': error.runtimeType.toString(),
    });
  }
}

/// Thin lifecycle adapter. The same SyncEngine performs all queue decisions,
/// idempotency, claims, HTTP classification and backoff for both UI and workers.
/// Factories permit tests of real Drift/Dio cleanup without an Android scheduler.
Future<bool> executeBackgroundSync({
  AppDatabase Function()? openDatabase,
  Dio Function()? createDio,
  SyncRunControl? control,
  AppLogger logger = const AppLogger(),
}) async {
  final elapsed = Stopwatch()..start();
  AppDatabase? database;
  Dio? dio;
  logger.log('worker.start');
  try {
    database = (openDatabase ?? AppDatabase.new)();
    dio = (createDio ?? createApiDio)();
    final client = dio;
    final engine = SyncEngine(
      SyncProcessor(database, dio: () => client, logger: logger),
      logger: logger,
    );
    final result = await engine.run(control: control);
    final retry = result.deferred || await engine.hasRetryableWork();
    logger.log('worker.complete', {
      'succeeded': result.succeeded,
      'failed': result.failed,
      'retry': retry,
      'elapsedMs': elapsed.elapsedMilliseconds,
    });
    // false maps to Android Result.retry(), not permanent failure. A 409/4xx with
    // no retryAt remains visible in diagnostics but does not cause an OS retry loop.
    return !retry;
  } catch (error) {
    logger.log('worker.error', {
      'type': error.runtimeType.toString(),
      'elapsedMs': elapsed.elapsedMilliseconds,
    });
    return false;
  } finally {
    dio?.close(force: true);
    try {
      await database?.close();
    } catch (_) {
      logger.log('worker.close_failed');
    }
    logger.log('worker.disposed');
  }
}
