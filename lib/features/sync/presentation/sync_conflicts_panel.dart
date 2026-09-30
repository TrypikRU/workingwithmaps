import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/sync/sync_conflict_remote_data_source.dart';
import '../../../core/sync/sync_conflict.dart';
import '../../../core/sync/sync_conflict_repository.dart';
import 'sync_labels.dart';

final syncConflictRepositoryProvider = Provider(
  (ref) => SyncConflictRepository(
    ref.watch(appDatabaseProvider),
    remote: () => SyncConflictRemoteDataSource(ref.read(dioProvider)),
  ),
);
final syncConflictsProvider = StreamProvider(
  (ref) => ref.watch(syncConflictRepositoryProvider).watch(),
);
final conflictActionsProvider = NotifierProvider<ConflictActions, bool>(
  ConflictActions.new,
);

class ConflictActions extends Notifier<bool> {
  @override
  bool build() => false;
  Future<String?> refresh(SyncConflict conflict) async {
    if (state) return 'Операция уже выполняется.';
    state = true;
    try {
      await ref.read(syncConflictRepositoryProvider).refreshServer(conflict);
      return null;
    } catch (_) {
      return 'Не удалось получить запись. Проверьте сеть и доступность записи на сервере.';
    } finally {
      if (ref.mounted) state = false;
    }
  }

  Future<String?> resolve(
    SyncConflict conflict,
    ConflictResolution resolution,
  ) async {
    if (state) return 'Разрешение уже выполняется.';
    state = true;
    try {
      await ref
          .read(syncConflictRepositoryProvider)
          .resolve(conflict, resolution);
      return null;
    } on StateError catch (error) {
      return error.message;
    } catch (_) {
      return 'Не удалось разрешить конфликт. Локальные данные и очередь сохранены.';
    } finally {
      if (ref.mounted) state = false;
    }
  }
}

class SyncConflictsPanel extends ConsumerWidget {
  const SyncConflictsPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ref
      .watch(syncConflictsProvider)
      .when(
        loading: () => const Text('Загрузка конфликтов…'),
        error: (_, _) => const Text('Не удалось прочитать историю конфликтов'),
        data: (conflicts) => conflicts.isEmpty
            ? const SizedBox.shrink()
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Конфликты и история решений',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  for (final conflict in conflicts)
                    Card(
                      child: ListTile(
                        title: Text(
                          '${syncEntityLabel(conflict.entityType)} / ${conflict.entityId}',
                        ),
                        subtitle: Text(
                          conflict.resolvedAt == null
                              ? 'Требуется решение · локальная ${conflict.localVersion ?? 'неизвестна'} / серверная ${conflict.serverVersion ?? 'неизвестна'}'
                              : 'Разрешён: ${conflict.resolution == 'keepLocal' ? 'повтор локальной правки' : 'принята серверная версия'}',
                        ),
                        trailing: const Icon(Icons.compare_arrows),
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (_) =>
                              SyncConflictDialog(conflict: conflict),
                        ),
                      ),
                    ),
                ],
              ),
      );
}

class SyncConflictDialog extends ConsumerStatefulWidget {
  const SyncConflictDialog({super.key, required this.conflict});
  final SyncConflict conflict;
  @override
  ConsumerState<SyncConflictDialog> createState() => _SyncConflictDialogState();
}

class _SyncConflictDialogState extends ConsumerState<SyncConflictDialog> {
  String? error;
  Future<void> resolve(ConflictResolution strategy) async {
    final message = await ref
        .read(conflictActionsProvider.notifier)
        .resolve(widget.conflict, strategy);
    if (!mounted) return;
    if (message == null) {
      Navigator.pop(context);
    } else {
      setState(() => error = message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conflict;
    final busy = ref.watch(conflictActionsProvider);
    final available = !busy && c.resolvedAt == null && c.serverPayload != null;
    return AlertDialog(
      title: const Text('Конфликт синхронизации'),
      scrollable: true,
      content: SizedBox(
        width: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText('${syncEntityLabel(c.entityType)} / ${c.entityId}'),
            Text('Локальная версия: ${c.localVersion ?? 'неизвестна'}'),
            SelectableText(formatSyncDetails(c.currentLocalPayload)),
            const Divider(),
            Text('Серверная версия: ${c.serverVersion ?? 'неизвестна'}'),
            SelectableText(
              c.serverPayload == null
                  ? 'Ответ 409 не содержит корректной серверной записи. Обновите серверную версию после устранения ошибки сервера.'
                  : formatSyncDetails(c.serverPayload!),
            ),
            ExpansionTile(
              title: const Text('Отправленный запрос'),
              children: [SelectableText(formatSyncDetails(c.requestPayload))],
            ),
            if (c.resolvedAt == null)
              Text(
                c.canKeepLocal
                    ? 'Принять серверную: заменить локальные поля и отменить ожидающие правки. Повторить локальную: отправить текущие поля с увиденной серверной версией; возможен новый конфликт.'
                    : 'Посещение — факт события. Сервер не перезаписывается. При принятии серверной записи локальный вариант останется в истории конфликта.',
              ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        if (c.resolvedAt == null && ['object', 'visit'].contains(c.entityType))
          TextButton(
            onPressed: busy
                ? null
                : () async {
                    final message = await ref
                        .read(conflictActionsProvider.notifier)
                        .refresh(c);
                    if (!context.mounted) return;
                    if (message == null) {
                      Navigator.pop(context);
                    } else {
                      setState(() => error = message);
                    }
                  },
            child: const Text('Обновить серверную версию'),
          ),
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
        if (c.resolvedAt == null)
          TextButton(
            onPressed: available
                ? () => resolve(ConflictResolution.acceptServer)
                : null,
            child: const Text('Принять серверную'),
          ),
        if (c.resolvedAt == null && c.canKeepLocal)
          FilledButton(
            onPressed: available
                ? () => resolve(ConflictResolution.keepLocal)
                : null,
            child: const Text('Повторить локальную'),
          ),
      ],
    );
  }
}
