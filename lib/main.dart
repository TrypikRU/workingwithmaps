import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/sync/sync_lifecycle.dart';
import 'core/sync/background_sync.dart';
import 'features/tracking/presentation/tracking_lifecycle.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(initializeBackgroundSync());
  runApp(
    const ProviderScope(
      child: SyncLifecycle(
        child: TrackingLifecycle(child: FieldInspectorApp()),
      ),
    ),
  );
}
