import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router/app_router.dart';
import 'theme/app_theme.dart';
import '../core/location/location_lifecycle.dart';

class FieldInspectorApp extends ConsumerWidget {
  const FieldInspectorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LocationLifecycle(
      child: MaterialApp.router(
        title: 'Field Inspector',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        routerConfig: ref.watch(appRouterProvider),
      ),
    );
  }
}
