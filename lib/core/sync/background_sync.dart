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

/// Точка входа верхнего уровня сохраняется в выпускной AOT-сборке и работает в движке
/// Flutter без интерфейса. ProviderScope, канал Activity и подписка GPS не нужны.
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
      active?.cancel(); // Возвращаемся сразу; при внезапном уничтожении движка действует срок блокировки.
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
    // Если планировщик недоступен, локальное приложение работает; повторяем регистрацию
    // при следующем запуске. Существующая сохранённая задача не отменяется.
    _workerLogger.log('worker.registration_failed', {
      'type': error.runtimeType.toString(),
    });
  }
}

/// Адаптер жизненного цикла. Общий SyncEngine управляет очередью, идемпотентностью,
/// захватом операций, классификацией HTTP и задержками для интерфейса и фоновых обработчиков.
/// Фабрики позволяют проверить освобождение ресурсов Drift/Dio без планировщика Android.
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
    // false означает Android Result.retry(), а не окончательный отказ. Ошибка 409/4xx без
    // retryAt остаётся в диагностике, но не вызывает бесконечных повторов со стороны ОС.
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
