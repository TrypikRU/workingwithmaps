import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tracking_controller.dart';

class TrackingLifecycle extends ConsumerStatefulWidget {
  const TrackingLifecycle({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<TrackingLifecycle> createState() => _TrackingLifecycleState();
}

class _TrackingLifecycleState extends ConsumerState<TrackingLifecycle>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final status = WidgetsBinding.instance.lifecycleState;
      ref
          .read(trackingControllerProvider.notifier)
          .setForeground(status == null || status == AppLifecycleState.resumed);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ref
        .read(trackingControllerProvider.notifier)
        .setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(trackingControllerProvider);
    return widget.child;
  }
}
