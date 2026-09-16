import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/database/database_provider.dart';
import 'package:workingwithmaps/core/location/location_controller.dart';
import 'package:workingwithmaps/core/location/location_lifecycle.dart';
import 'package:workingwithmaps/core/location/location_service.dart';
import 'package:workingwithmaps/features/objects/data/drift_objects_data_source.dart';
import 'package:workingwithmaps/features/objects/domain/technical_object.dart';
import 'package:workingwithmaps/features/objects/presentation/object_details_screen.dart';

import '../../support/fake_location_service.dart';
import '../../support/test_database.dart';

void main() {
  for (final access in [LocationAccess.denied, LocationAccess.deniedForever]) {
    testWidgets(
      'Object details remain readable; Check-in blocked for $access',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final db = createTestDatabase(seedDemoData: false);
        addTearDown(db.close);
        const object = TechnicalObject(
          id: 'target',
          name: 'Насосная',
          address: 'Улица, 1',
          latitude: 55,
          longitude: 37,
          priority: ObjectPriority.critical,
        );
        await DriftObjectsDataSource(
          db,
        ).mergeRemoteObjects([(object: object, updatedAt: DateTime.utc(2026))]);
        final location = FakeLocationService()
          ..access = access
          ..requestedAccess = access;
        addTearDown(location.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appDatabaseProvider.overrideWithValue(db),
              locationServiceProvider.overrideWithValue(location),
            ],
            child: const LocationLifecycle(
              child: MaterialApp(home: ObjectDetailsScreen(objectId: 'target')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Насосная'), findsOneWidget);
        expect(find.text('Улица, 1'), findsOneWidget);
        expect(find.text('55.000000, 37.000000'), findsOneWidget);
        expect(find.text('Нет текущей позиции'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Check-in'),
              )
              .onPressed,
          isNull,
        );
        expect(await db.select(db.visits).get(), isEmpty);
        expect(await db.select(db.syncQueue).get(), isEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'Live distance and accuracy gate the button; check-in updates status offline',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = createTestDatabase(seedDemoData: false);
      addTearDown(db.close);
      const object = TechnicalObject(
        id: 'target',
        name: 'Объект',
        latitude: 0,
        longitude: 0,
      );
      await DriftObjectsDataSource(
        db,
      ).mergeRemoteObjects([(object: object, updatedAt: DateTime.utc(2026))]);
      final location = FakeLocationService()
        ..access = LocationAccess.granted
        ..current = fix(latitude: 0, longitude: 0.001);
      addTearDown(location.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(db),
            locationServiceProvider.overrideWithValue(location),
          ],
          child: const LocationLifecycle(
            child: MaterialApp(home: ObjectDetailsScreen(objectId: 'target')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      FilledButton button() =>
          tester.widget(find.widgetWithText(FilledButton, 'Check-in'));
      expect(find.text('Вы вне допустимой зоны'), findsOneWidget);
      expect(button().onPressed, isNull);
      location.positions.add(
        fix(latitude: 0, longitude: 0, accuracy: 70, second: 1),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Точность: ±70 м'), findsOneWidget);
      expect(find.textContaining('Недостаточная точность GPS'), findsOneWidget);
      expect(button().onPressed, isNull);
      location.current = fix(latitude: 0, longitude: 0, second: 2);
      location.positions.add(location.current);
      await tester.pumpAndSettle();
      expect(find.text('Вы в допустимой зоне'), findsOneWidget);
      expect(find.text('0.0 м'), findsOneWidget);
      expect(button().onPressed, isNotNull);
      // Stream cancellation may complete in the root zone. Await the button's
      // async action outside fake time, including its real SQLite transaction.
      final onPressed = button().onPressed! as Future<void> Function();
      await tester.runAsync(onPressed);
      await tester.pumpAndSettle();
      expect(find.text('Посещён'), findsOneWidget);
      expect(find.text('Check-in сохранён на устройстве'), findsOneWidget);
      expect(await db.select(db.visits).get(), hasLength(1));
      expect(await db.select(db.syncQueue).get(), hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
