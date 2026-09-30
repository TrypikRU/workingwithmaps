import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'location_controller.dart';

/// Жизненный цикл приложения, а не вкладки: IndexedStack сохраняет скрытые экраны.
class LocationLifecycle extends ConsumerStatefulWidget {
  const LocationLifecycle({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<LocationLifecycle> createState() => _LocationLifecycleState();
}

class _LocationLifecycleState extends ConsumerState<LocationLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      if (lifecycle == null || lifecycle == AppLifecycleState.resumed) {
        unawaited(ref.read(locationControllerProvider.notifier).resume());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(locationControllerProvider.notifier);
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(controller.resume());
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        controller.pause();
      case AppLifecycleState.inactive:
        // Диалог разрешения тоже переводит Activity в inactive. Не прерываем диалог;
        // подписки отменяются при фактическом уходе в hidden/paused.
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
