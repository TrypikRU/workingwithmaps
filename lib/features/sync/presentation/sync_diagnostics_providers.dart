import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/sync/sync_providers.dart';
import '../data/sync_diagnostics_repository.dart';
import '../domain/sync_diagnostics.dart';

final syncDiagnosticsRepositoryProvider = Provider<SyncDiagnosticsRepository>(
  (ref) => SyncDiagnosticsRepository(ref.watch(appDatabaseProvider)),
);
final syncDiagnosticsProvider = StreamProvider<SyncDiagnostics>(
  (ref) => ref.watch(syncDiagnosticsRepositoryProvider).watch(),
);
final syncRunningProvider = StreamProvider<bool>(
  (ref) => ref.watch(syncEngineProvider).watchRunning(),
);
final syncActionsProvider = NotifierProvider<SyncActions, bool>(
  SyncActions.new,
);

class SyncActions extends Notifier<bool> {
  @override
  bool build() => false;

  Future<String?> synchronize({bool retryFailed = false}) async {
    if (state) return null;
    state = true;
    try {
      final result = await ref
          .read(syncEngineProvider)
          .run(retryFailed: retryFailed);
      return result.deferred
          ? 'Синхронизация отложена или прервана. Очередь сохранена для следующего запуска.'
          : 'Подтверждено: ${result.succeeded}. Ошибок: ${result.failed}.';
    } catch (_) {
      return 'Синхронизация прервана. Очередь и сведения об ошибках сохранены.';
    } finally {
      if (ref.mounted) state = false;
    }
  }
}
