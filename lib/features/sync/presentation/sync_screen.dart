import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/sync_status.dart';
import '../domain/sync_diagnostics.dart';
import 'sync_diagnostics_providers.dart';
import 'sync_conflicts_panel.dart';
import 'sync_labels.dart';

class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final diagnostics = ref.watch(syncDiagnosticsProvider);
    final running = ref.watch(syncRunningProvider).asData?.value ?? false;
    final actionPending = ref.watch(syncActionsProvider);
    final busy = running || actionPending;
    final data = diagnostics.asData?.value;
    Future<void> synchronize({bool retryFailed = false}) async {
      final message = await ref
          .read(syncActionsProvider.notifier)
          .synchronize(retryFailed: retryFailed);
      if (context.mounted && message != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Диагностика синхронизации')),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Последняя успешная синхронизация',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      data == null
                          ? 'Загрузка…'
                          : data.lastSuccessAt == null
                          ? 'Пока не было'
                          : formatSyncTime(data.lastSuccessAt!),
                    ),
                    const Text(
                      'Время последнего подтверждения сервером · время устройства',
                    ),
                    const SizedBox(height: 16),
                    if (data != null)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _StatusCount(
                            label: 'Синхронизировано',
                            count: data.synced,
                            icon: Icons.cloud_done_outlined,
                          ),
                          _StatusCount(
                            label: 'Ожидает отправки',
                            count: data.count(SyncStatus.pending),
                            icon: Icons.schedule,
                          ),
                          _StatusCount(
                            label: 'Отправляется',
                            count: data.count(SyncStatus.syncing),
                            icon: Icons.sync,
                          ),
                          _StatusCount(
                            label: 'Ошибки',
                            count: data.count(SyncStatus.failed),
                            icon: Icons.error_outline,
                          ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    const Text(
                      '«Синхронизировано» — всего подтверждённых операций с включения диагностики. Остальные счётчики — текущая очередь.',
                    ),
                    if (busy)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          children: [
                            LinearProgressIndicator(),
                            SizedBox(height: 6),
                            Text('Синхронизация выполняется…'),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: busy
                              ? null
                              : () async {
                                  await synchronize();
                                },
                          icon: const Icon(Icons.sync),
                          label: const Text('Синхронизировать сейчас'),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              busy ||
                                  data == null ||
                                  data.count(SyncStatus.failed) == 0
                              ? null
                              : () async {
                                  await synchronize(retryFailed: true);
                                },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Повторить ошибочные'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Обычный запуск учитывает время следующей попытки. Повтор ошибочных снимает задержку, но не разрешает конфликт автоматически. Ошибки сохраняются до успешного подтверждения.',
                    ),
                    const SizedBox(height: 24),
                    const SyncConflictsPanel(),
                    Text(
                      'Операции в очереди',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Порядок создания · новые операции появляются автоматически',
                    ),
                  ],
                ),
              ),
            ),
            ...diagnostics.when(
              loading: () => [
                const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (_, _) => [
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Не удалось прочитать диагностику. Проверьте локальную БД.',
                    ),
                  ),
                ),
              ],
              data: (state) => state.operations.isEmpty
                  ? [
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('Очередь пуста'),
                        ),
                      ),
                    ]
                  : [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        sliver: SliverList.builder(
                          itemCount: state.operations.length,
                          itemBuilder: (context, index) => _OperationCard(
                            operation: state.operations[index],
                          ),
                        ),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

String formatSyncTime(DateTime value) {
  final local = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year} ${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

class _StatusCount extends StatelessWidget {
  const _StatusCount({
    required this.label,
    required this.count,
    required this.icon,
  });
  final String label;
  final int count;
  final IconData icon;
  @override
  Widget build(BuildContext context) =>
      Chip(avatar: Icon(icon, size: 18), label: Text('$label: $count'));
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({required this.operation});
  final QueueOperation operation;
  @override
  Widget build(BuildContext context) {
    final item = operation;
    return Card(
      key: ValueKey('queue-operation-${item.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '#${item.id} · ${item.status.label}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text('Тип записи: ${syncEntityLabel(item.entityType)}'),
            SelectableText('Идентификатор записи: ${item.entityId}'),
            Text('Операция: ${syncOperationLabel(item.operation)}'),
            Text('Создано: ${formatSyncTime(item.createdAt)}'),
            Text('Количество попыток: ${item.attemptCount}'),
            Text(
              'Следующая попытка: ${item.nextRetryAt == null
                  ? item.status == SyncStatus.failed
                        ? 'Автоповтор отключён'
                        : 'Без задержки'
                  : formatSyncTime(item.nextRetryAt!)}',
            ),
            Text(
              'Последняя ошибка: ${item.lastError == null ? 'Нет' : formatSyncDetails(item.lastError!)}',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (item.status == SyncStatus.failed)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.bug_report_outlined),
                  label: const Text('Подробности ошибки'),
                  onPressed: () {
                    final details = formatSyncDetails(
                      item.lastError ?? 'Подробности не сохранены',
                    );
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text('Ошибка операции #${item.id}'),
                        scrollable: true,
                        content: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SelectableText(
                              '${syncEntityLabel(item.entityType)} / ${item.entityId}',
                            ),
                            SelectableText(
                              'Идентификатор операции: ${item.operationId ?? 'Ещё не назначен'}',
                            ),
                            const SizedBox(height: 12),
                            SelectableText(details),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Закрыть'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
