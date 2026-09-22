import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/geometry/circular_geofence.dart';
import '../../../core/geometry/geo_point.dart';
import '../../../core/location/location_controller.dart';
import '../../../core/location/location_state.dart';
import '../../objects/presentation/objects_providers.dart';

/// Informational zones only. Missing/unreliable GPS is unknown (empty map), not
/// outside. This provider never creates visits or changes Check-in eligibility.
final objectGeofencesProvider = Provider<Map<String, GeofenceState>>((ref) {
  final location = ref.watch(locationControllerProvider);
  final fix = location.position;
  final objects = ref.watch(objectsProvider).asData?.value;
  if (objects == null ||
      fix == null ||
      location.isLastKnown ||
      location.status != LocationStatus.available ||
      !fix.accuracy.isFinite ||
      fix.accuracy < 0 ||
      fix.accuracy > 50 ||
      !GeoPoint(fix.latitude, fix.longitude).isValid) {
    return {};
  }
  return {
    for (final object in objects)
      object.id: CircularGeofence(
        center: GeoPoint(object.latitude, object.longitude),
        radius: object.geofenceRadius,
      ).classify(GeoPoint(fix.latitude, fix.longitude)),
  };
});
