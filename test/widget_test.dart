import 'support/memory_tile_provider.dart';
import 'support/test_database.dart';
import 'package:workingwithmaps/core/database/database_provider.dart';
import 'support/fake_location_service.dart';
import 'package:workingwithmaps/core/location/location_controller.dart';
import 'package:workingwithmaps/features/map/data/map_tile_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/app/app.dart';
import 'package:workingwithmaps/features/objects/presentation/objects_providers.dart';

void main() {
  testWidgets('Main tabs open without a backend or platform plugins', (
    tester,
  ) async {
    final locationService = FakeLocationService();
    final db = createTestDatabase();
    addTearDown(db.close);
    addTearDown(locationService.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          objectsProvider.overrideWith((ref) => Stream.value([])),
          locationServiceProvider.overrideWithValue(locationService),
          mapTileProviderFactoryProvider.overrideWithValue(
            MemoryTileProvider.new,
          ),
        ],
        child: const FieldInspectorApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Нет объектов на карте'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.location_city_outlined).last);
    await tester.pumpAndSettle();
    expect(find.text('Объектов пока нет'), findsOneWidget);

    await tester.tap(find.text('Обход'));
    await tester.pumpAndSettle();
    expect(find.text('Текущий обход'), findsOneWidget);

    await tester.tap(find.text('Синхронизация').last);
    await tester.pumpAndSettle();
    expect(find.text('Синхронизировать сейчас'), findsOneWidget);

    await tester.tap(find.text('Карта'));
    await tester.pumpAndSettle();
    expect(find.text('Нет объектов на карте'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
