import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Экранная сетка Web Mercator: O(n), без попарного сравнения объектов.
/// Целый уровень масштаба сохраняет устойчивость групп при перемещении и плавном масштабировании.
List<List<Marker>> clusterMarkers(List<Marker> markers, int zoom) {
  final cells = <(int, int), List<Marker>>{};
  final scale = 256 * math.pow(2, zoom);
  for (final marker in markers) {
    final latitude = marker.point.latitude.clamp(-85.05112878, 85.05112878);
    final sinLat = math.sin(latitude * math.pi / 180);
    final x = (marker.point.longitude + 180) / 360 * scale;
    final y =
        (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * scale;
    cells
        .putIfAbsent(((x / 64).floor(), (y / 64).floor()), () => [])
        .add(marker);
  }
  return cells.values.toList(growable: false);
}

class ClusteredObjectLayer extends StatefulWidget {
  const ClusteredObjectLayer({
    super.key,
    required this.markers,
    required this.onChoose,
    required this.labelFor,
    this.focusedMarker,
  });
  final List<Marker> markers;
  final Marker? focusedMarker;
  final void Function(Marker) onChoose;
  final String Function(Marker) labelFor;

  @override
  State<ClusteredObjectLayer> createState() => _ClusteredObjectLayerState();
}

class _ClusteredObjectLayerState extends State<ClusteredObjectLayer> {
  int? _zoom;
  List<Marker> _visible = const [];

  @override
  void didUpdateWidget(covariant ClusteredObjectLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.markers, widget.markers) ||
        oldWidget.focusedMarker != widget.focusedMarker) {
      _zoom = null;
    }
  }

  void _open(List<Marker> group) {
    final controller = MapController.of(context);
    final bounds = LatLngBounds.fromPoints(group.map((m) => m.point).toList());
    // Совпадающие координаты нельзя разделить увеличением масштаба. Список
    // гарантирует доступ к каждому объекту даже на максимальном масштабе.
    if (controller.camera.zoom >= 19 ||
        group.every((m) => m.point == group.first.point)) {
      // Снимок группы живёт до закрытия панели: обновление Drift не должно
      // сопоставлять старые экземпляры маркеров с новой таблицей объектов.
      final labelFor = widget.labelFor;
      final onChoose = widget.onChoose;
      showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: ListView.builder(
            itemCount: group.length,
            itemBuilder: (_, index) => ListTile(
              title: Text(labelFor(group[index])),
              onTap: () {
                Navigator.pop(sheetContext);
                onChoose(group[index]);
              },
            ),
          ),
        ),
      );
    } else {
      controller.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(80),
          maxZoom: 19,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final zoom = MapCamera.of(context).zoom.floor();
    if (_zoom != zoom) {
      _zoom = zoom;
      final groups = clusterMarkers(
        widget.markers.where((m) => m != widget.focusedMarker).toList(),
        zoom,
      );
      _visible = [
        for (final group in groups)
          if (group.length == 1)
            group.single
          else
            Marker(
              point: LatLngBounds.fromPoints(group.map((m) => m.point).toList())
                  .center,
              width: 48,
              height: 48,
              child: Tooltip(
                message: '${group.length} объектов — открыть группу',
                child: Material(
                  color: const Color(0xFF263B60),
                  shape: const CircleBorder(
                    side: BorderSide(color: Colors.white, width: 3),
                  ),
                  elevation: 3,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _open(group),
                    child: Center(
                      child: Text(
                        '${group.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        if (widget.focusedMarker != null) widget.focusedMarker!,
      ];
    }
    // MarkerLayer сам отсекает элементы вне видимой области. Перемещение карты меняет
    // проекцию видимых элементов, но не пересоздаёт индекс и виджеты маркеров.
    return MarkerLayer(markers: _visible);
  }
}
