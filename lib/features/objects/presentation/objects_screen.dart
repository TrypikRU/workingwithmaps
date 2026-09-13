import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/feature_placeholder.dart';
import 'objects_providers.dart';
import 'objects_refresh_button.dart';
import 'object_labels.dart';

class ObjectsScreen extends ConsumerWidget {
  const ObjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final objects = ref.watch(objectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Объекты'),
        actions: const [ObjectsRefreshButton()],
      ),
      body: SafeArea(
        child: objects.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => const FeaturePlaceholder(
            icon: Icons.error_outline,
            title: 'Не удалось загрузить объекты',
            message:
                'Ошибка чтения данных. '
                'Попробуйте перезапустить приложение.',
          ),
          data: (items) {
            if (items.isEmpty) {
              return const FeaturePlaceholder(
                icon: Icons.location_city_outlined,
                title: 'Объектов пока нет',
                message:
                    'Здесь появятся сохранённые на устройстве '
                    'технические объекты.',
              );
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final object = items[index];
                return ListTile(
                  leading: Icon(object.status.icon, color: object.status.color),
                  title: Text(object.name),
                  subtitle: Text(
                    '${object.address}\n${object.status.label} · ${object.priority.label}',
                  ),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.pushNamed(
                    'object-details',
                    pathParameters: {'objectId': object.id},
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
