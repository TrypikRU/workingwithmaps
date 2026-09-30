import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/location/location_controller.dart';
import '../../tracking/presentation/tracking_controller.dart';
import '../domain/route_status.dart';
import '../../map/presentation/location_status_panel.dart';

class CurrentRouteScreen extends ConsumerStatefulWidget {
  const CurrentRouteScreen({super.key});
  @override
  ConsumerState<CurrentRouteScreen> createState() => _CurrentRouteScreenState();
}

class _CurrentRouteScreenState extends ConsumerState<CurrentRouteScreen> {
  bool busy = false;
  @override
  Widget build(BuildContext context) {
    final route = ref.watch(currentRouteProvider);
    final tracking = ref.watch(trackingControllerProvider);
    final location = ref.watch(locationControllerProvider);
    final active = route.asData?.value?.status == RouteStatus.active;
    final now = active
        ? ref.watch(routeClockProvider).asData?.value ?? DateTime.now()
        : DateTime.now();
    Future<void> action({bool resume = false}) async {
      setState(() => busy = true);
      try {
        final controller = ref.read(trackingControllerProvider.notifier);
        if (active && !resume) {
          await controller.finish();
        } else {
          await controller.start();
        }
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не удалось изменить обход: $error')),
          );
        }
      } finally {
        if (mounted) setState(() => busy = false);
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Текущий обход')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            route.when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const Text('Ошибка чтения обхода'),
              data: (value) {
                if (value == null) return const Text('Обход ещё не начат');
                final duration = value.duration(now);
                String two(int n) => n.toString().padLeft(2, '0');
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active ? 'Обход активен' : 'Обход завершён',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      'Продолжительность: ${two(duration.inHours)}:${two(duration.inMinutes % 60)}:${two(duration.inSeconds % 60)}',
                    ),
                    Text('GPS-точек: ${value.points.length}'),
                    Text(
                      'Пройдено примерно: ${value.distance.toStringAsFixed(1)} м',
                    ),
                    const SizedBox(height: 12),
                    Text('Посещённые объекты: ${value.visitedNames.length}'),
                    for (final name in value.visitedNames) Text('• $name'),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            const LocationStatusPanel(),
            Text(
              'Текущая точность геолокации: ${location.position == null || location.isLastKnown ? 'недоступна' : '±${location.position!.accuracy.toStringAsFixed(1)} м'}',
            ),
            Text('Запись маршрута: ${active ? tracking : 'остановлена'}'),
            if (active)
              TextButton.icon(
                onPressed: busy ? null : () => action(resume: true),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Возобновить запись маршрута'),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: busy || route.isLoading || route.hasError
                  ? null
                  : action,
              icon: Icon(active ? Icons.stop : Icons.play_arrow),
              label: Text(active ? 'Завершить обход' : 'Начать обход'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Android-сервис записывает GPS при свёрнутом приложении. Длительность включает паузы. Если Android остановил сервис, нажмите «Возобновить запись маршрута».',
            ),
          ],
        ),
      ),
    );
  }
}
