import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/database_provider.dart';
import '../network/dio_provider.dart';
import '../utils/app_logger.dart';
import 'sync_engine.dart';
import 'sync_processor.dart';

final appLoggerProvider = Provider<AppLogger>((ref) => const AppLogger());
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final logger = ref.watch(appLoggerProvider);
  return SyncEngine(
    SyncProcessor(
      ref.watch(appDatabaseProvider),
      dio: () => ref.read(dioProvider),
      logger: logger,
    ),
    logger: logger,
  );
});

final syncQueueSummaryProvider =
    StreamProvider<({int pending, int syncing, int failed})>((ref) {
      final db = ref.watch(appDatabaseProvider);
      return db
          .select(db.syncQueue)
          .watch()
          .map(
            (rows) => (
              pending: rows
                  .where((row) => row.syncStatus.name == 'pending')
                  .length,
              syncing: rows
                  .where((row) => row.syncStatus.name == 'syncing')
                  .length,
              failed: rows
                  .where((row) => row.syncStatus.name == 'failed')
                  .length,
            ),
          );
    });
