import '../../support/test_database.dart';
import '../../support/memory_tile_provider.dart';
import '../../support/fake_location_service.dart';

import 'package:workingwithmaps/core/location/location_controller.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:workingwithmaps/app/app.dart';
import 'package:workingwithmaps/app/router/app_router.dart';
import 'package:workingwithmaps/core/database/database_provider.dart';
import 'package:workingwithmaps/features/map/data/map_tile_provider.dart';
import 'package:workingwithmaps/features/objects/data/demo_objects.dart';
import 'package:workingwithmaps/features/objects/domain/technical_object.dart';
import 'package:workingwithmaps/features/objects/presentation/object_labels.dart';
import 'package:workingwithmaps/features/objects/presentation/objects_providers.dart';

Future<void> pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final database = createTestDatabase();
  addTearDown(database.close);
  final locationService = FakeLocationService();
  addTearDown(locationService.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        locationServiceProvider.overrideWithValue(locationService),
        mapTileProviderFactoryProvider.overrideWithValue(
          MemoryTileProvider.new,
        ),
        // Проверяем UI через реальную SQLite в памяти.
        appDatabaseProvider.overrideWithValue(database),
      ],
      child: const FieldInspectorApp(),
    ),
  );
  await tester.pumpAndSettle();
}

MapController controller(WidgetTester tester) =>
    tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;

void expectFocused(WidgetTester tester, TechnicalObject object) {
  final camera = controller(tester).camera;
  expect(camera.center.latitude, closeTo(object.latitude, 0.00001));
  expect(camera.center.longitude, closeTo(object.longitude, 0.00001));
  expect(camera.zoom, 16);
}

void main() {
  testWidgets('Markers open details; focus and region reset work repeatedly', (
    tester,
  ) async {
    await pumpApp(tester);
    const objects = demoObjects;
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    for (final object in objects) {
      final marker = find.byKey(ValueKey('marker-${object.id}'));
      expect(marker, findsOneWidget);
      expect(
        find.descendant(of: marker, matching: find.byIcon(object.status.icon)),
        findsOneWidget,
      );
      expect(
        controller(tester).camera.visibleBounds
            .contains(LatLng(object.latitude, object.longitude)),
        isTrue,
      );
    }

    final object = objects.first;
    await tester.tap(find.byKey(ValueKey('marker-${object.id}')));
    await tester.pumpAndSettle();
    expect(find.text(object.name), findsOneWidget);
    expect(find.text(object.address), findsOneWidget);
    expect(find.text(object.priority.label), findsOneWidget);
    expect(find.text('Нет текущей позиции'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Check-in'))
          .onPressed,
      isNull,
    );

    await tester.ensureVisible(find.text('Показать на карте'));
    await tester.tap(find.text('Показать на карте'));
    await tester.pumpAndSettle();
    expectFocused(tester, object);

    controller(tester).move(const LatLng(56, 38), 10);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Все объекты'));
    await tester.pumpAndSettle();
    for (final item in objects) {
      expect(
        controller(tester).camera.visibleBounds
            .contains(LatLng(item.latitude, item.longitude)),
        isTrue,
      );
    }

    // Повторный выбор того же id должен дать новую команду камеры.
    await tester.tap(find.byKey(ValueKey('marker-${object.id}')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Показать на карте'));
    await tester.tap(find.text('Показать на карте'));
    await tester.pumpAndSettle();
    expectFocused(tester, object);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('List opens same details and shows selected object on map', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Объекты'));
    await tester.pumpAndSettle();
    final object = demoObjects.last;
    await tester.tap(find.text(object.name));
    await tester.pumpAndSettle();
    expect(find.text(object.address), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(object.name), findsOneWidget);
    await tester.tap(find.text(object.name));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Показать на карте'));
    await tester.tap(find.text('Показать на карте'));
    await tester.pumpAndSettle();
    expectFocused(tester, object);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('Unknown object id is handled without a crash', (tester) async {
    await pumpApp(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FieldInspectorApp)),
    );
    container
        .read(appRouterProvider)
        .pushNamed('object-details', pathParameters: {'objectId': 'missing'});
    await tester.pumpAndSettle();
    expect(find.text('Объект не найден'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  test(
    'Default repository exposes SQLite seed fields through Riverpod',
    () async {
      final database = createTestDatabase();
      addTearDown(database.close);
      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
      );
      addTearDown(container.dispose);
      // Riverpod 3 приостанавливает поток без активных слушателей. Здесь
      // подписка имитирует ref.watch экрана, а не одиночное чтение provider.
      final subscription = container.listen(
        objectsProvider,
        (previous, next) {},
      );
      addTearDown(subscription.close);
      final objects = await container.read(objectsProvider.future);
      expect(objects, hasLength(5));
      expect(
        objects.map((object) => object.status).toSet(),
        ObjectStatus.values.toSet(),
      );
      expect(
        objects.map((object) => object.priority).toSet(),
        ObjectPriority.values.toSet(),
      );
      for (final object in objects) {
        expect(object.address, isNotEmpty);
        expect(TechnicalObject.fromJson(object.toJson()), object);
        expect(container.read(objectProvider(object.id)).requireValue, object);
      }
    },
  );
}
