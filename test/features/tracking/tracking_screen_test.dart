import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/location/location_controller.dart';
import 'package:workingwithmaps/core/location/location_state.dart';
import 'package:workingwithmaps/features/map/presentation/objects_map.dart';
import 'package:workingwithmaps/features/route/domain/route_snapshot.dart';
import 'package:workingwithmaps/features/route/domain/route_status.dart';
import 'package:workingwithmaps/features/route/presentation/current_route_screen.dart';
import 'package:workingwithmaps/features/tracking/presentation/tracking_controller.dart';

import '../../support/memory_tile_provider.dart';
import 'tracking_test.dart' show sample;

class ScreenTracking extends TrackingController {
  bool finished = false;
  @override
  String build() => 'Запись GPS-точек';
  @override
  Future<void> finish() async {
    finished = true;
  }
}

class ScreenLocation extends LocationController {
  @override
  LocationState build() =>
      LocationState(status: LocationStatus.available, position: sample(0, 0));
}

void main() {
  final points = [
    TrackPoint(sample(0, 0), 'one'),
    TrackPoint(sample(0.0001, 2), 'one'),
    TrackPoint(sample(1, 10), 'two'),
    TrackPoint(sample(1.0001, 12), 'two'),
  ];
  testWidgets(
    'Map draws separate saved segments without connecting background gap',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ObjectsMap(
              objects: const [],
              createTileProvider: MemoryTileProvider.new,
              location: const LocationState(),
              track: points,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final layer = tester.widget<PolylineLayer>(
        find.byKey(const ValueKey('saved-route-polyline')),
      );
      expect(layer.polylines, hasLength(2));
      expect(layer.polylines.map((p) => p.points.length), [2, 2]);
      expect(layer.polylines.last.points.first.longitude, 1);
    },
  );
  testWidgets('Route screen displays saved statistics and delegates finish', (
    tester,
  ) async {
    final controller = ScreenTracking();
    final route = RouteSnapshot(
      id: 'r',
      name: 'Route',
      status: RouteStatus.active,
      startedAt: sample(0, 0).timestamp,
      points: points,
      visitedNames: ['Тестовый объект'],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentRouteProvider.overrideWith((ref) => Stream.value(route)),
          trackingControllerProvider.overrideWith(() => controller),
          locationControllerProvider.overrideWith(ScreenLocation.new),
          routeClockProvider.overrideWith(
            (ref) => Stream.value(sample(0, 30).timestamp),
          ),
        ],
        child: const MaterialApp(home: CurrentRouteScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('GPS-точек: 4'), findsOneWidget);
    expect(find.text('Продолжительность: 00:00:30'), findsOneWidget);
    expect(find.text('Пройдено примерно: 22.2 м'), findsOneWidget);
    expect(find.text('• Тестовый объект'), findsOneWidget);
    expect(find.text('Запись маршрута: Запись GPS-точек'), findsOneWidget);
    await tester.ensureVisible(find.text('Завершить обход'));
    await tester.tap(find.text('Завершить обход'));
    await tester.pumpAndSettle();
    expect(controller.finished, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
