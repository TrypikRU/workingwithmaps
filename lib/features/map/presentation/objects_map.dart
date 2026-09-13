import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/location/location_state.dart';

import '../../objects/domain/technical_object.dart';
import '../../objects/presentation/object_labels.dart';
import '../../route/domain/route_snapshot.dart';

class ObjectsMap extends StatefulWidget {
  const ObjectsMap({
    super.key,
    required this.objects,
    required this.createTileProvider,
    required this.location,
    this.focusObjectId,
    this.track = const [],
  });

  final List<TechnicalObject> objects;
  final String? focusObjectId;
  final TileProvider Function() createTileProvider;
  final LocationState location;
  final List<TrackPoint> track;

  @override
  State<ObjectsMap> createState() => _ObjectsMapState();
}

class _ObjectsMapState extends State<ObjectsMap> {
  final _controller = MapController();
  late final _tileProvider = widget.createTileProvider();

  LatLng _point(TechnicalObject object) =>
      LatLng(object.latitude, object.longitude);

  CameraFit? get _region => widget.objects.isEmpty
      ? null
      : CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(widget.objects.map(_point).toList()),
          padding: const EdgeInsets.fromLTRB(56, 72, 56, 96),
          maxZoom: 16,
        );

  @override
  void dispose() {
    _controller.dispose();
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
    final segments = <String?, List<LatLng>>{};
    for (final point in widget.track) {
      segments
          .putIfAbsent(point.segmentId, () => [])
          .add(LatLng(point.fix.latitude, point.fix.longitude));
    }
    return Stack(
      children: [
        FlutterMap(
          mapController: _controller,
          options: MapOptions(
            // initialCameraFit работает только при создании карты. Последующие
            // действия пользователя управляют камерой через локальный controller.
            initialCenter: focused != null
                ? _point(focused)
                : widget.objects.isNotEmpty
                ? _point(widget.objects.first)
                : userPoint ?? const LatLng(55.75, 37.62),
            initialZoom: 16,
            initialCameraFit: focused == null ? _region : null,
            minZoom: 3,
            maxZoom: 19,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.klochkov.workingwithmaps',
              tileProvider: _tileProvider,
              maxNativeZoom: 19,
            ),
            PolygonLayer(
              key: const ValueKey('object-polygons'),
              polygons: widget.objects
                  .where((o) => o.polygon.length >= 3)
                  .map(
                    (o) => Polygon(
                      points: o.polygon
                          .map((p) => LatLng(p.latitude, p.longitude))
                          .toList(),
                      color: o.status.color.withValues(alpha: 0.16),
                      borderColor: o.status.color,
                      borderStrokeWidth: 2,
                    ),
                  )
                  .toList(),
            ),
            PolylineLayer(
              key: const ValueKey('saved-route-polyline'),
              polylines: segments.values
                  .where((points) => points.length >= 2)
                  .map(
                    (points) => Polyline(
                      points: points,
                      color: Colors.deepPurple,
                      strokeWidth: 4,
                    ),
                  )
                  .toList(),
            ),
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
            MarkerLayer(
              markers: widget.objects
                  .map(
                    (object) => Marker(
                      point: _point(object),
                      width: 48,
                      height: 48,
                      child: Tooltip(
                        message: '${object.name} — ${object.status.label}',
                        child: Material(
                          color: object.status.color,
                          shape: CircleBorder(
                            side: BorderSide(
                              color: object.id == widget.focusObjectId
                                  ? Colors.amber
                                  : Colors.white,
                              width: 3,
                            ),
                          ),
                          elevation: 4,
                          child: InkWell(
                            key: ValueKey('marker-${object.id}'),
                            customBorder: const CircleBorder(),
                            onTap: () {
                              _controller.move(_point(object), 16);
                              context.pushNamed(
                                'object-details',
                                pathParameters: {'objectId': object.id},
                              );
                            },
                            child: Semantics(
                              button: true,
                              label: '${object.name}, ${object.status.label}',
                              child: Icon(
                                object.status.icon,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
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
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      '© OpenStreetMap contributors',
                      style: TextStyle(color: Colors.black87, fontSize: 12),
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
