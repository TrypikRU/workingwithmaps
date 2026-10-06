import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'clustered_object_layer.dart';
import 'object_marker.dart';

import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/location/location_state.dart';

import '../../objects/domain/technical_object.dart';
import '../../objects/presentation/object_labels.dart';
import '../../route/domain/route_snapshot.dart';
import '../domain/offline_map_pack.dart';

class ObjectsMap extends StatefulWidget {
  const ObjectsMap({
    super.key,
    required this.objects,
    required this.createTileProvider,
    required this.location,
    this.focusObjectId,
    this.focusRevision = 0,
    this.track = const [],
    this.tileRevision = 0,
    this.offlineTilesAvailable = false,
    this.tileAttribution = '',
  });

  final List<TechnicalObject> objects;
  final String? focusObjectId;
  final int focusRevision;
  final TileProvider Function() createTileProvider;
  final LocationState location;
  final List<TrackPoint> track;
  final int tileRevision;
  final bool offlineTilesAvailable;
  final String tileAttribution;

  @override
  State<ObjectsMap> createState() => _ObjectsMapState();
}

class _ObjectsMapState extends State<ObjectsMap> {
  final _controller = MapController();
  final _tileReset = StreamController<void>.broadcast();
  late final _tileProvider = widget.createTileProvider();

  LatLng _point(TechnicalObject object) =>
      LatLng(object.latitude, object.longitude);

  CameraFit? _region;
  CameraFit? _routeFit;
  late Widget _objectsLayer;
  late PolygonLayer _polygons;
  late PolylineLayer _polyline;
  final _markers = <String, Marker>{};

  CameraFit? _fit(List<LatLng> points) => points.isEmpty
      ? null
      : CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.fromLTRB(64, 100, 88, 96),
          maxZoom: 16,
        );

  void _select(TechnicalObject object) {
    _controller.move(_point(object), 16);
    context.pushNamed(
      'object-details',
      pathParameters: {'objectId': object.id},
    );
  }

  void _cacheObjects([
    List<TechnicalObject> previous = const [],
    String? previousFocus,
  ]) {
    final old = {for (final o in previous) o.id: o};
    final ids = widget.objects.map((o) => o.id).toSet();
    _markers.removeWhere((id, _) => !ids.contains(id));
    for (final object in widget.objects) {
      final focused = object.id == widget.focusObjectId;
      if (old[object.id] != object || focused != (object.id == previousFocus)) {
        _markers[object.id] = buildObjectMarker(
          object,
          focused,
          () => _select(object),
        );
      }
    }
    final byMarker = {for (final o in widget.objects) _markers[o.id]!: o};
    _objectsLayer = ClusteredObjectLayer(
      markers: byMarker.keys.toList(growable: false),
      focusedMarker: _markers[widget.focusObjectId],
      onChoose: (marker) => _select(byMarker[marker]!),
      labelFor: (marker) {
        final o = byMarker[marker]!;
        return '${o.name} — ${o.status.label}, ${o.priority.label}';
      },
    );
    _polygons = PolygonLayer(
      key: const ValueKey('object-polygons'),
      polygons: [
        for (final o in widget.objects)
          if (o.polygon.length >= 3)
            Polygon(
              points: o.polygon
                  .map((p) => LatLng(p.latitude, p.longitude))
                  .toList(),
              color: o.status.color.withValues(alpha: 0.16),
              borderColor: o.status.color,
              borderStrokeWidth: 2,
            ),
      ],
    );
    _region = _fit([
      for (final o in widget.objects) ...[
        _point(o),
        ...o.polygon.map((p) => LatLng(p.latitude, p.longitude)),
      ],
    ]);
  }

  void _cacheTrack() {
    final segments = <String?, List<LatLng>>{};
    for (final point in widget.track) {
      segments
          .putIfAbsent(point.segmentId, () => [])
          .add(LatLng(point.fix.latitude, point.fix.longitude));
    }
    _polyline = PolylineLayer(
      key: const ValueKey('saved-route-polyline'),
      polylines: [
        for (final points in segments.values)
          if (points.length >= 2)
            Polyline(points: points, color: Colors.deepPurple, strokeWidth: 4),
      ],
    );
    _routeFit = _fit(segments.values.expand((points) => points).toList());
  }

  @override
  void initState() {
    super.initState();
    _cacheObjects();
    _cacheTrack();
  }

  @override
  void didUpdateWidget(covariant ObjectsMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tileRevision != widget.tileRevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tileReset.add(null);
      });
    }
    // Drift может прислать новый список с прежними значениями. GPS меняется
    // чаще объектов: сохраняем сами виджеты слоёв, а не только их входные данные.
    if (!listEquals(oldWidget.objects, widget.objects) ||
        oldWidget.focusObjectId != widget.focusObjectId) {
      _cacheObjects(oldWidget.objects, oldWidget.focusObjectId);
    }
    if (!identical(oldWidget.track, widget.track)) _cacheTrack();
    if (oldWidget.focusRevision != widget.focusRevision ||
        oldWidget.focusObjectId != widget.focusObjectId ||
        (oldWidget.objects.isEmpty && widget.objects.isNotEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final object = widget.objects
            .where((o) => o.id == widget.focusObjectId)
            .firstOrNull;
        if (object != null) {
          _controller.move(_point(object), 16);
        } else if (_region != null) {
          _controller.fitCamera(_region!);
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    unawaited(_tileReset.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = widget.objects
        .where((object) => object.id == widget.focusObjectId)
        .firstOrNull;
    final position = widget.location.position;
    final userPoint = position == null
        ? null
        : LatLng(position.latitude, position.longitude);
    final userColor = widget.location.isLastKnown ? Colors.grey : Colors.blue;
    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            // initialCameraFit работает только при создании карты. Последующие
            // действия пользователя управляют камерой через локальный контроллер.
            initialCenter: focused != null
                ? _point(focused)
                : widget.objects.isNotEmpty
                ? _point(widget.objects.first)
                : userPoint ??
                      const LatLng(
                        (OfflineMapPack.south + OfflineMapPack.north) / 2,
                        (OfflineMapPack.west + OfflineMapPack.east) / 2,
                      ),
            initialZoom: 16,
            initialCameraFit: focused == null ? _region : null,
            cameraConstraint: CameraConstraint.containCenter(
              bounds: LatLngBounds(
                const LatLng(-85, -180),
                const LatLng(85, 180),
              ),
            ),
            minZoom: 3,
            maxZoom: 19,
          ),
          children: [
            TileLayer(
              reset: _tileReset.stream,
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.klochkov.workingwithmaps',
              tileProvider: _tileProvider,
              maxNativeZoom: widget.offlineTilesAvailable ? 16 : 19,
            ),
            _polygons,
            _polyline,
            if (userPoint != null && position != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: userPoint,
                    radius: position.accuracy,
                    useRadiusInMeter: true,
                    color: userColor.withValues(alpha: 0.12),
                    borderColor: userColor.withValues(alpha: 0.5),
                    borderStrokeWidth: 1,
                  ),
                ],
              ),
            _objectsLayer,
            if (userPoint != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: userPoint,
                    width: 28,
                    height: 28,
                    child: Tooltip(
                      message: widget.location.isLastKnown
                          ? 'Последняя известная позиция'
                          : 'Вы здесь',
                      child: DecoratedBox(
                        key: const ValueKey('user-location-marker'),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: userColor,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        child: const Icon(
                          Icons.person,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            // Атрибуция OSM остаётся видимой, а не прячется за кнопкой.
            Align(
              alignment: Alignment.bottomLeft,
              child: Material(
                color: Colors.white.withValues(alpha: 0.95),
                child: InkWell(
                  onTap: () => launchUrl(
                    Uri.parse('https://www.openstreetmap.org/copyright'),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      '© OpenStreetMap contributors',
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          top: 8,
          left: 8,
          right: 8,
          child: Align(
            alignment: Alignment.topLeft,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: ObjectStatus.values
                      .map(
                        (status) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(status.icon, size: 18, color: status.color),
                            const SizedBox(width: 4),
                            Text(status.label),
                          ],
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 168,
          child: FloatingActionButton.small(
            heroTag: 'map-route',
            tooltip: 'Весь маршрут',
            onPressed: _routeFit == null
                ? null
                : () => _controller.fitCamera(_routeFit!),
            child: const Icon(Icons.route),
          ),
        ),
        Positioned(
          left: 16,
          bottom: 48,
          child: Column(
            children: [
              FloatingActionButton.small(
                heroTag: 'map-zoom-in',
                tooltip: 'Приблизить',
                onPressed: () => _controller.move(
                  _controller.camera.center,
                  (_controller.camera.zoom + 1).clamp(3, 19),
                ),
                child: const Icon(Icons.add),
              ),
              const SizedBox(height: 8),
              FloatingActionButton.small(
                heroTag: 'map-zoom-out',
                tooltip: 'Отдалить',
                onPressed: () => _controller.move(
                  _controller.camera.center,
                  (_controller.camera.zoom - 1).clamp(3, 19),
                ),
                child: const Icon(Icons.remove),
              ),
            ],
          ),
        ),
        if (widget.offlineTilesAvailable)
          Positioned(
            left: 16,
            bottom: 168,
            child: FloatingActionButton.small(
              heroTag: 'map-offline-region',
              tooltip: 'Офлайн-регион',
              onPressed: () => _controller.fitCamera(
                CameraFit.bounds(
                  bounds: LatLngBounds(
                    const LatLng(OfflineMapPack.south, OfflineMapPack.west),
                    const LatLng(OfflineMapPack.north, OfflineMapPack.east),
                  ),
                  padding: const EdgeInsets.all(64),
                  maxZoom: 16,
                ),
              ),
              child: const Icon(Icons.download_done),
            ),
          ),
        Positioned(
          right: 16,
          bottom: 48,
          child: FloatingActionButton.small(
            heroTag: 'map-region',
            tooltip: 'Все объекты',
            onPressed: widget.objects.isEmpty
                ? null
                : () => _controller.fitCamera(_region!),
            child: const Icon(Icons.center_focus_strong),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 108,
          child: FloatingActionButton.small(
            heroTag: 'map-user',
            tooltip: 'Моя позиция',
            onPressed: widget.location.canCenter && userPoint != null
                ? () => _controller.move(userPoint, 16)
                : null,
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }
}
