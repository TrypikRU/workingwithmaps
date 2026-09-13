import 'location_service.dart';

enum LocationStatus {
  loading,
  permissionGranted,
  permissionDenied,
  permissionDeniedForever,
  serviceDisabled,
  available,
  error,
  paused,
}

class LocationState {
  const LocationState({
    this.status = LocationStatus.loading,
    this.position,
    this.isLastKnown = false,
    this.message,
  });

  final LocationStatus status;
  final LocationFix? position;
  final bool isLastKnown;
  final String? message;

  bool get canCenter => status == LocationStatus.available && !isLastKnown;
}
