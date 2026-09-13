import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/geometry/geo_point.dart';
import 'package:workingwithmaps/core/location/location_controller.dart';
import 'package:workingwithmaps/core/location/location_service.dart';
import 'package:workingwithmaps/core/location/location_state.dart';
import 'package:workingwithmaps/features/map/presentation/map_screen.dart';
import 'package:workingwithmaps/features/map/data/map_tile_provider.dart';
import 'package:workingwithmaps/features/objects/domain/technical_object.dart';
import 'package:workingwithmaps/features/objects/presentation/objects_providers.dart';
import 'package:workingwithmaps/features/tracking/presentation/tracking_controller.dart';
import '../../support/memory_tile_provider.dart';

class GeometryLocation extends LocationController {
  LocationState fix(double longitude, double accuracy) => LocationState(
    status: LocationStatus.available,
    position: LocationFix(
      latitude: 0,
      longitude: longitude,
      accuracy: accuracy,
      timestamp: DateTime.now(),
    ),
  );
  @override
  LocationState build() => fix(0.0009, 5);
  void move(double longitude, {double accuracy = 5}) =>
      state = fix(longitude, accuracy);
}

void main() {
  testWidgets(
    'Map draws polygon; approaching hint follows location and hides for unreliable GPS',
    (tester) async {
      final location = GeometryLocation();
      const object = TechnicalObject(
        id: 'area',
        name: 'Тестовая зона',
        latitude: 0,
        longitude: 0,
        polygon: [
          GeoPoint(-0.001, -0.001),
          GeoPoint(-0.001, 0.001),
          GeoPoint(0.001, 0),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            objectsProvider.overrideWith((ref) => Stream.value([object])),
            currentRouteProvider.overrideWith((ref) => Stream.value(null)),
            locationControllerProvider.overrideWith(() => location),
            mapTileProviderFactoryProvider.overrideWithValue(
              MemoryTileProvider.new,
            ),
          ],
          child: const MaterialApp(home: MapScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final layer = tester.widget<PolygonLayer>(
        find.byKey(const ValueKey('object-polygons')),
      );
      expect(layer.polygons, hasLength(1));
      expect(layer.polygons.single.points, hasLength(3));
      expect(
        find.text('Вы находитесь рядом с объектом: Тестовая зона'),
        findsOneWidget,
      );
      location.move(0); // Inside: no approaching hint, no automatic Check-in.
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('approaching-object')), findsNothing);
      location.move(0.0009, accuracy: 80);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('approaching-object')), findsNothing);
      location.move(0.002);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('approaching-object')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
