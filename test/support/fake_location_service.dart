import 'dart:async';

import 'package:workingwithmaps/core/location/location_service.dart';

LocationFix fix({
  double latitude = 55.759,
  double longitude = 37.643,
  double accuracy = 8,
  int second = 0,
}) => LocationFix(
  latitude: latitude,
  longitude: longitude,
  accuracy: accuracy,
  timestamp: DateTime.utc(2026, 9, 12, 12, 0, second),
);

class FakeLocationService implements LocationService {
  bool enabled = true;
  LocationAccess access = LocationAccess.denied;
  LocationAccess requestedAccess = LocationAccess.granted;
  int permissionRequests = 0;
  int currentRequests = 0;
  int appSettingsOpened = 0;
  int locationSettingsOpened = 0;
  bool settingsResult = true;
  LocationFix current = fix();
  LocationFix? lastKnown;
  Future<LocationFix>? currentFuture;
  Future<LocationFix?>? lastFuture;
  Future<LocationAccess>? permissionFuture;
  Object? currentError;
  final positions = StreamController<LocationFix>.broadcast();
  final services = StreamController<bool>.broadcast();

  @override
  Future<bool> isServiceEnabled() async => enabled;
  @override
  Future<LocationAccess> checkPermission() async => access;
  @override
  Future<LocationAccess> requestPermission() async {
    permissionRequests++;
    return access = await (permissionFuture ?? Future.value(requestedAccess));
  }

  @override
  Future<LocationFix> getCurrentPosition() async {
    currentRequests++;
    if (currentError != null) throw currentError!;
    return await (currentFuture ?? Future.value(current));
  }

  @override
  Future<LocationFix?> getLastKnownPosition() async =>
      await (lastFuture ?? Future.value(lastKnown));
  @override
  Stream<LocationFix> watchPosition() => positions.stream;
  @override
  Stream<bool> watchServiceEnabled() => services.stream;
  @override
  Future<bool> openAppSettings() async {
    appSettingsOpened++;
    return settingsResult;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsOpened++;
    return settingsResult;
  }

  Future<void> dispose() async {
    await positions.close();
    await services.close();
  }
}
