import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/location_controller.dart';
import '../../../core/location/location_state.dart';

class LocationStatusPanel extends ConsumerWidget {
  const LocationStatusPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(locationControllerProvider);
    final controller = ref.read(locationControllerProvider.notifier);
    final message = switch (location.status) {
      LocationStatus.loading => 'Проверяем геолокацию…',
      LocationStatus.permissionGranted =>
        'Доступ разрешён. Определяем позицию…',
      LocationStatus.permissionDenied => 'Разрешите доступ к местоположению.',
      LocationStatus.permissionDeniedForever =>
        'Доступ запрещён. Разрешите геолокацию в настройках приложения.',
      LocationStatus.serviceDisabled =>
        'Геолокация выключена. Включите её в настройках устройства.',
      LocationStatus.available => 'Текущая позиция',
      LocationStatus.error => location.message ?? 'Ошибка геолокации.',
      LocationStatus.paused => 'Обновление позиции приостановлено.',
    };
    final action = switch (location.status) {
      LocationStatus.permissionDenied => TextButton(
        onPressed: () => controller.refresh(requestPermission: true),
        child: const Text('Разрешить'),
      ),
      LocationStatus.permissionDeniedForever => TextButton(
        onPressed: () => controller.openSettings(locationSettings: false),
        child: const Text('Настройки приложения'),
      ),
      LocationStatus.serviceDisabled => TextButton(
        onPressed: () => controller.openSettings(locationSettings: true),
        child: const Text('Включить геолокацию'),
      ),
      LocationStatus.error => TextButton(
        onPressed: () => controller.refresh(),
        child: const Text('Повторить'),
      ),
      _ => null,
    };
    final position = location.position;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(message),
            if (position != null)
              Text(
                '${location.isLastKnown ? 'Последняя известная позиция. ' : ''}'
                'Точность: ±${position.accuracy.toStringAsFixed(0)} м'
                '${location.isLastKnown ? ' · ${position.timestamp.toLocal().toIso8601String().substring(0, 16).replaceFirst('T', ' ')}' : ''}',
              ),
            if (location.status == LocationStatus.loading ||
                location.status == LocationStatus.permissionGranted)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: LinearProgressIndicator(),
              ),
            if (action != null)
              Align(alignment: Alignment.centerLeft, child: action),
          ],
        ),
      ),
    );
  }
}
