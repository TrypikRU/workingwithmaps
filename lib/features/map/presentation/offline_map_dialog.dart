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
      title: const Text('Офлайн-карта'),
      scrollable: true,
      content: SizedBox(
        width: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(OfflineMapPack.regionName),
            Text(
              '${OfflineMapPack.expectedTiles().length} фрагментов карты в формате PNG · масштаб 13–16 · до 12 МиБ',
            ),
            const Text(
              '${OfflineMapPack.south}–${OfflineMapPack.north} с. ш., '
              '${OfflineMapPack.west}–${OfflineMapPack.east} в. д.',
            ),
            const SizedBox(height: 12),
            Text(
              state.hasPack
                  ? 'Регион сохранён на устройстве'
                  : 'Регион ещё не скачан',
            ),
            const Text(
              'Сначала используются сохранённые фрагменты карты. Вне покрытия карта OpenStreetMap загружается через интернет. Без сети карта доступна только в сохранённой области при масштабе 13–16; объекты и маршрут остаются видны.',
            ),
            const Text(
              'Пакет готовится из растровой карты в формате MBTiles с разрешением на использование без интернета и загружается с вашего компьютера. Области с общедоступного сервера карт OpenStreetMap не скачиваются.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Только сохранённая карта'),
              value: state.offlineOnly,
              onChanged: state.busy
                  ? null
                  : ref
                        .read(offlineMapControllerProvider.notifier)
                        .setOfflineOnly,
            ),
            if (state.busy) ...[
              const LinearProgressIndicator(),
              Text('Получено: ${state.received ~/ 1024} КиБ'),
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
          child: const Text('Обновить карту'),
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
