import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:workingwithmaps/core/location/location_service.dart';
import 'package:workingwithmaps/core/location/location_state.dart';
import 'package:workingwithmaps/features/map/presentation/clustered_object_layer.dart';
import 'package:workingwithmaps/features/map/presentation/objects_map.dart';
import 'package:workingwithmaps/features/objects/data/drift_objects_data_source.dart';
import 'package:workingwithmaps/features/objects/data/objects_repository.dart';
import 'package:workingwithmaps/features/objects/domain/technical_object.dart';
import 'package:workingwithmaps/features/route/domain/route_snapshot.dart';

import '../../support/dense_map_objects.dart';
import '../../support/memory_tile_provider.dart';
import '../../support/test_database.dart';

LocationFix fix(double latitude, double longitude) => LocationFix(
  latitude: latitude,
  longitude: longitude,
  accuracy: 8,
  timestamp: DateTime.utc(2026),
);

void main() {
  test(
    'Grid preserves all 500 objects and splits groups as zoom increases',
    () {
      final markers = denseMapObjects()
          .map(
            (o) => Marker(
              point: LatLng(o.latitude, o.longitude),
              child: const SizedBox(),
            ),
          )
          .toList();
      var previousCount = 0;
      for (var zoom = 3; zoom <= 19; zoom++) {
        final groups = clusterMarkers(markers, zoom);
        expect(groups.expand((g) => g).toSet(), markers.toSet());
        expect(groups.expand((g) => g), hasLength(500));
        expect(groups.length, greaterThanOrEqualTo(previousCount));
        previousCount = groups.length;
      }
      expect(clusterMarkers([], 16), isEmpty);
      expect(
        clusterMarkers([
          Marker(point: const LatLng(90, 180), child: const SizedBox()),
        ], 19),
        hasLength(1),
      );
    },
  );

  testWidgets(
    '500 SQLite objects: clustering, cached layers on GPS, incremental edits, camera bounds',
    (tester) async {
      final objects = await tester.runAsync(() async {
        final database = createTestDatabase(seedDemoData: false);
        try {
          final source = DriftObjectsDataSource(database);
          final repository = ObjectsRepository(source);
          await database.transaction(() async {
            for (final object in denseMapObjects()) {
              await repository.saveObject(object);
            }
          });
          return await repository.watchObjects().first;
        } finally {
          await database.close();
        }
      });
      expect(objects, hasLength(500));
      final track = [
        TrackPoint(fix(61.649478, 50.769391), 'segment'),
        TrackPoint(fix(61.656478, 50.777391), 'segment'),
      ];
      Future<void> pump(
        List<TechnicalObject> items,
        double latitude, {
        int revision = 0,
        String? focused,
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ObjectsMap(
                objects: items,
                location: LocationState(
                  status: LocationStatus.available,
                  position: fix(latitude, 50.770391),
                ),
                track: track,
                focusObjectId: focused,
                focusRevision: revision,
                createTileProvider: MemoryTileProvider.new,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      ClusteredObjectLayer cluster() =>
          tester.widget(find.byType(ClusteredObjectLayer));
      MarkerLayer renderedLayer() => tester.widget(
        find.descendant(
          of: find.byType(ClusteredObjectLayer),
          matching: find.byType(MarkerLayer),
        ),
      );
      await pump(objects!, 61.650478);
      final original = cluster();
      final originalRendered = renderedLayer().markers;
      final polygons = tester.widget<PolygonLayer>(find.byType(PolygonLayer));
      final line = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
      final controller = tester
          .widget<FlutterMap>(find.byType(FlutterMap))
          .mapController!;
      final center = controller.camera.center;
      expect(original.markers, hasLength(500));
      expect(polygons.polygons, hasLength(500));
      expect(originalRendered.length, lessThan(100));
      for (var i = 1; i <= 20; i++) {
        await pump(objects, 61.650478 + i * 0.00001);
        expect(cluster(), same(original));
        expect(renderedLayer().markers, same(originalRendered));
        expect(
          tester.widget<PolygonLayer>(find.byType(PolygonLayer)),
          same(polygons),
        );
        expect(
          tester.widget<PolylineLayer>(find.byType(PolylineLayer)),
          same(line),
        );
        expect(controller.camera.center, center);
      }
      await pump(
        List.of(objects),
        61.650478,
      ); // Эквивалентное обновление Drift также повторно использует слои.
      expect(cluster(), same(original));
      final edited = [...objects];
      edited[0] = edited[0].copyWith(
        status: ObjectStatus.visited,
        priority: ObjectPriority.critical,
      );
      await pump(edited, 61.650478);
      expect(cluster().markers[0], isNot(same(original.markers[0])));
      for (var i = 1; i < 500; i++) {
        expect(cluster().markers[i], same(original.markers[i]));
      }
      await tester.tap(find.byTooltip('Весь маршрут'));
      await tester.pumpAndSettle();
      for (final p in track) {
        expect(
          controller.camera.visibleBounds.contains(
            LatLng(p.fix.latitude, p.fix.longitude),
          ),
          isTrue,
        );
      }
      await tester.tap(find.byTooltip('Все объекты'));
      await tester.pumpAndSettle();
      for (final o in objects) {
        for (final p in o.polygon) {
          expect(
            controller.camera.visibleBounds.contains(
              LatLng(p.latitude, p.longitude),
            ),
            isTrue,
          );
        }
      }
      final zoom = controller.camera.zoom;
      await tester.tap(find.byTooltip('Приблизить'));
      await tester.pumpAndSettle();
      expect(controller.camera.zoom, closeTo(zoom + 1, 0.00001));
      // Команда фокуса показывает выбранный объект даже внутри плотного кластера,
      // сохраняя существующий контроллер карты без её пересоздания.
      await pump(edited, 61.650478, revision: 1, focused: edited.first.id);
      expect(
        tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController,
        same(controller),
      );
      expect(find.byKey(ValueKey('marker-${edited.first.id}')), findsOneWidget);
      expect(
        controller.camera.center,
        LatLng(edited.first.latitude, edited.first.longitude),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Coincident objects remain individually selectable', (
    tester,
  ) async {
    final markers = List.generate(
      3,
      (i) => Marker(
        point: const LatLng(61.650478, 50.770391),
        child: Text('marker $i'),
      ),
    );
    Marker? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlutterMap(
            options: const MapOptions(
              initialCenter: LatLng(61.650478, 50.770391),
              initialZoom: 16,
            ),
            children: [
              ClusteredObjectLayer(
                markers: markers,
                labelFor: (m) => 'Объект ${markers.indexOf(m)}',
                onChoose: (m) => chosen = m,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('3 объектов — открыть группу'));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile), findsNWidgets(3));
    await tester.tap(find.text('Объект 2'));
    await tester.pumpAndSettle();
    expect(chosen, same(markers[2]));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
