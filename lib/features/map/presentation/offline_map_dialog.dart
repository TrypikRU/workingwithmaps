import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/offline_map_pack.dart';
import 'offline_map_controller.dart';

class OfflineMapDialog extends ConsumerWidget {
  const OfflineMapDialog({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(offlineMapControllerProvider);
    return AlertDialog(
      title: const Text('Offline-карта'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(OfflineMapPack.regionName),
            Text(
              '${OfflineMapPack.expectedTiles().length} PNG-тайлов · zoom 13–16 · до 12 MiB',
            ),
            const Text(
              '${OfflineMapPack.south}–${OfflineMapPack.north} N, '
              '${OfflineMapPack.west}–${OfflineMapPack.east} E',
            ),
            const SizedBox(height: 12),
            Text(
              state.hasPack
                  ? 'Регион сохранён на устройстве'
                  : 'Регион ещё не скачан',
            ),
            const Text(
              'Сохранённые тайлы используются первыми. Вне покрытия — online OSM. Без сети вне области и zoom 13–16 карта недоступна; объекты и маршрут остаются видны.',
            ),
            const Text(
              'Пакет готовится из разрешённого raster MBTiles и загружается с вашего ПК. Скачивание областей с публичного OSM tile server не выполняется.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Только offline-тайлы'),
              value: state.offlineOnly,
              onChanged: state.busy
                  ? null
                  : ref
                        .read(offlineMapControllerProvider.notifier)
                        .setOfflineOnly,
            ),
            if (state.busy) ...[
              const LinearProgressIndicator(),
              Text('Получено: ${state.received ~/ 1024} KiB'),
            ],
            if (state.error != null)
              Text(
                state.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
        TextButton(
          onPressed: state.busy
              ? null
              : () {
                  ref
                      .read(offlineMapControllerProvider.notifier)
                      .refreshTiles();
                  Navigator.pop(context);
                },
          child: const Text('Обновить тайлы'),
        ),
        FilledButton(
          onPressed: state.busy
              ? null
              : ref.read(offlineMapControllerProvider.notifier).download,
          child: Text(state.hasPack ? 'Обновить пакет' : 'Скачать регион'),
        ),
      ],
    );
  }
}
