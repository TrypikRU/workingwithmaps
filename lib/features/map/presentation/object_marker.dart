import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../objects/domain/technical_object.dart';
import '../../objects/presentation/object_labels.dart';

Marker buildObjectMarker(
  TechnicalObject object,
  bool focused,
  VoidCallback onTap,
) {
  final priority = switch (object.priority) {
    ObjectPriority.low => '↓',
    ObjectPriority.normal => '•',
    ObjectPriority.high => '↑',
    ObjectPriority.critical => '!',
  };
  return Marker(
    point: LatLng(object.latitude, object.longitude),
    width: 48,
    height: 48,
    child: Tooltip(
      message:
          '${object.name} — ${object.status.label}, приоритет: ${object.priority.label}',
      child: Material(
        color: object.status.color,
        // Рамка маркера должна оставаться под значком приоритета.
        borderOnForeground: false,
        shape: CircleBorder(
          side: BorderSide(
            color: focused ? Colors.amber : Colors.white,
            width: 3,
          ),
        ),
        elevation: 4,
        child: InkWell(
          key: ValueKey('marker-${object.id}'),
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Semantics(
            button: true,
            label:
                '${object.name}, ${object.status.label}, приоритет: ${object.priority.label}',
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(object.status.icon, color: Colors.white),
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: object.priority == ObjectPriority.critical
                          ? Colors.amber
                          : Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      priority,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
