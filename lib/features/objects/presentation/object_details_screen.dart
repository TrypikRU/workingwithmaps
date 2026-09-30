import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/feature_placeholder.dart';
import '../../../core/geometry/geo_point.dart';
import '../../../core/location/location_controller.dart';
import '../../../core/location/location_state.dart';
import '../../map/presentation/location_status_panel.dart';
import '../../visits/presentation/check_in_controller.dart';
import '../../map/presentation/map_focus_provider.dart';
import 'object_labels.dart';
import 'objects_providers.dart';

class ObjectDetailsScreen extends ConsumerWidget {
  const ObjectDetailsScreen({super.key, required this.objectId});

  final String objectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final object = ref.watch(objectProvider(objectId));
    final location = ref.watch(locationControllerProvider);
    final policy = ref.watch(checkInPolicyProvider);
    final saving = ref.watch(checkInControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Технический объект')),
      body: SafeArea(
        child: object.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) => const FeaturePlaceholder(
            icon: Icons.error_outline,
            title: 'Не удалось загрузить объект',
            message: 'Попробуйте открыть объект ещё раз.',
          ),
          data: (item) {
            if (item == null) {
              return const FeaturePlaceholder(
                icon: Icons.search_off,
                title: 'Объект не найден',
                message: 'Возможно, объект больше недоступен.',
              );
            }
            final eligibility = policy.evaluate(
              GeoPoint(item.latitude, item.longitude),
              location.position,
              isCurrent:
                  location.status == LocationStatus.available &&
                  !location.isLastKnown,
            );
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  item.name,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Text(item.address.isEmpty ? 'Адрес не указан' : item.address),
                const SizedBox(height: 24),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(item.status.icon, color: item.status.color),
                  title: const Text('Статус'),
                  subtitle: Text(item.status.label),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Приоритет'),
                  subtitle: Text(item.priority.label),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.location_on_outlined),
                  title: const Text('Координаты'),
                  subtitle: SelectableText(
                    '${item.latitude.toStringAsFixed(6)}, ${item.longitude.toStringAsFixed(6)}',
                  ),
                ),
                const LocationStatusPanel(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.straighten),
                  title: const Text('Расстояние до объекта'),
                  subtitle: Text(
                    eligibility.distance == null
                        ? 'Нет текущей позиции'
                        : '${eligibility.distance!.toStringAsFixed(1)} м',
                  ),
                ),
                Text(
                  eligibility.distance == null
                      ? 'Зона отметки о посещении пока не определена'
                      : eligibility.distance! <= policy.radius
                      ? 'Вы в допустимой зоне'
                      : 'Вы вне допустимой зоны',
                ),
                Text(
                  'Радиус отметки о посещении: ${policy.radius.toStringAsFixed(0)} м',
                ),
                if (eligibility.block != null)
                  Text(eligibility.block!.message(policy)),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: !eligibility.allowed || saving
                      ? null
                      : () async {
                          final message = await ref
                              .read(checkInControllerProvider.notifier)
                              .checkIn(item.id);
                          if (context.mounted && message != null) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(SnackBar(content: Text(message)));
                          }
                        },
                  icon: const Icon(Icons.how_to_reg_outlined),
                  label: Text(saving ? 'Проверяем позицию…' : 'Отметиться'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    ref.read(mapFocusProvider.notifier).focus(item.id);
                    context.goNamed('map');
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Показать на карте'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
