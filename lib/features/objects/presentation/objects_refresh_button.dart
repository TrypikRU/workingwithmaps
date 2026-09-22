import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'objects_refresh_controller.dart';

class ObjectsRefreshButton extends ConsumerWidget {
  const ObjectsRefreshButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refreshing = ref.watch(objectsRefreshControllerProvider);
    return IconButton(
      tooltip: 'Обновить объекты с сервера',
      onPressed: refreshing
          ? null
          : () async {
              final message = await ref
                  .read(objectsRefreshControllerProvider.notifier)
                  .refresh();
              if (context.mounted && message != null) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(message)));
              }
            },
      icon: refreshing
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.refresh),
    );
  }
}
