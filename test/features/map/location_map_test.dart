import '../../support/test_database.dart';

import 'package:workingwithmaps/core/database/database_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/app/app.dart';
import 'package:workingwithmaps/core/location/location_controller.dart';
import 'package:workingwithmaps/core/location/location_service.dart';
import 'package:workingwithmaps/features/map/data/map_tile_provider.dart';

import '../../support/fake_location_service.dart';
import '../../support/memory_tile_provider.dart';

Future<void> showApp(WidgetTester tester, FakeLocationService service) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(service.dispose);
  final database = createTestDatabase();
  addTearDown(database.close);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        locationServiceProvider.overrideWithValue(service),
        mapTileProviderFactoryProvider.overrideWithValue(
          MemoryTileProvider.new,
        ),
      ],
      child: const FieldInspectorApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> closeApp(WidgetTester tester) async {
  // Drift откладывает освобождение query stream до следующей microtask/timer.
  // Завершаем её до проверки Flutter test invariants, а не в позднем tearDown.
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('location marker, accuracy, centering and app lifecycle', (
    tester,
  ) async {
    final service = FakeLocationService()..access = LocationAccess.granted;
    await showApp(tester, service);
    expect(find.byKey(const ValueKey('user-location-marker')), findsOneWidget);
    expect(find.text('Точность: ±8 м'), findsOneWidget);
    expect(service.positions.hasListener, isTrue);
    await tester.tap(find.byTooltip('Моя позиция'));
    await tester.pumpAndSettle();
    final controller = tester
        .widget<FlutterMap>(find.byType(FlutterMap))
        .mapController!;
    expect(
      controller.camera.center.latitude,
      closeTo(service.current.latitude, 0.00001),
    );
    expect(
      controller.camera.center.longitude,
      closeTo(service.current.longitude, 0.00001),
    );
    final oldCenter = controller.camera.center;
    service.positions.add(fix(latitude: 61.660478, accuracy: 3, second: 5));
    await tester.pumpAndSettle();
    expect(find.text('Точность: ±3 м'), findsOneWidget);
    // GPS обновляет маркер, но не отнимает управление камерой у пользователя.
    expect(controller.camera.center, oldCenter);
    await tester.tap(find.byTooltip('Моя позиция'));
    await tester.pumpAndSettle();
    expect(controller.camera.center.latitude, closeTo(61.660478, 0.00001));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(service.positions.hasListener, isFalse);
    expect(service.services.hasListener, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(service.positions.hasListener, isTrue);
    await closeApp(tester);
  });

  testWidgets(
    'denied and deniedForever show actions; settings return rechecks access',
    (tester) async {
      final service = FakeLocationService()
        ..requestedAccess = LocationAccess.deniedForever;
      await showApp(tester, service);
      expect(find.text('Разрешить'), findsOneWidget);
      expect(service.permissionRequests, 0);
      await tester.tap(find.text('Разрешить'));
      await tester.pumpAndSettle();
      expect(find.text('Настройки приложения'), findsOneWidget);
      expect(find.byKey(const ValueKey('user-location-marker')), findsNothing);
      await tester.tap(find.text('Настройки приложения'));
      await tester.pumpAndSettle();
      expect(service.appSettingsOpened, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      service.access = LocationAccess.granted;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Текущая позиция'), findsOneWidget);
      expect(service.permissionRequests, 1);
      await closeApp(tester);
    },
  );

  testWidgets(
    'disabled GPS has a settings action and recovers on service event',
    (tester) async {
      final service = FakeLocationService()
        ..enabled = false
        ..access = LocationAccess.granted;
      await showApp(tester, service);
      expect(find.text('Включить геолокацию'), findsOneWidget);
      await tester.tap(find.text('Включить геолокацию'));
      await tester.pumpAndSettle();
      expect(service.locationSettingsOpened, 1);
      service.enabled = true;
      service.services.add(true);
      await tester.pumpAndSettle();
      expect(find.text('Текущая позиция'), findsOneWidget);
      await closeApp(tester);
    },
  );
}
