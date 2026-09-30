import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_providers.dart';
import '../database/database_provider.dart';

/// Только точка запуска приложения. Сам SyncEngine не знает о жизненном цикле Flutter.
/// Таймер работает лишь в открытом приложении; сроки отправки остаются в SQLite.
class SyncLifecycle extends ConsumerStatefulWidget {
  const SyncLifecycle({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<SyncLifecycle> createState() => _SyncLifecycleState();
}

class _SyncLifecycleState extends ConsumerState<SyncLifecycle>
    with WidgetsBindingObserver {
  Timer? _timer;
  Timer? _refreshTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          (WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed)) {
        _start();
      }
    });
  }

  void _start() {
    if (_timer != null) return;
    unawaited(_run());
    unawaited(_refresh());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_refresh()),
    );
    _timer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_run()),
    );
  }

  Future<void> _run() async {
    try {
      await ref.read(syncEngineProvider).run();
    } catch (_) {
      if (mounted) ref.read(appLoggerProvider).log('sync.foreground.failed');
    }
  }

  Future<void> _refresh() async {
    try {
      await ref.read(appDatabaseProvider).refreshExternalChanges();
    } catch (_) {
      if (mounted) {
        ref.read(appLoggerProvider).log('sync.external_refresh.failed');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else if (state != AppLifecycleState.inactive) {
      _timer?.cancel();
      _refreshTimer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
