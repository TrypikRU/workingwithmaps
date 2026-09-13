import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'location_service.dart';

class GeolocatorLocationService implements LocationService {
  LocationAccess _access(LocationPermission permission) => switch (permission) {
    LocationPermission.always ||
    LocationPermission.whileInUse => LocationAccess.granted,
    LocationPermission.deniedForever => LocationAccess.deniedForever,
    LocationPermission.denied ||
    LocationPermission.unableToDetermine => LocationAccess.denied,
  };

  LocationFix _fix(Position position) => LocationFix(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracy: position.accuracy,
    timestamp: position.timestamp,
    speed: position.speed.isFinite && position.speed >= 0
        ? position.speed
        : null,
  );

  LocationFailure _failure(Object error) => LocationFailure(switch (error) {
    LocationServiceDisabledException() => LocationFailureKind.serviceDisabled,
    PermissionDeniedException() => LocationFailureKind.permission,
    TimeoutException() => LocationFailureKind.timeout,
    _ => LocationFailureKind.unknown,
  });

  Future<T> _call<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<bool> isServiceEnabled() => _call(Geolocator.isLocationServiceEnabled);

  @override
  Future<LocationAccess> checkPermission() =>
      _call(() async => _access(await Geolocator.checkPermission()));

  @override
  Future<LocationAccess> requestPermission() =>
      _call(() async => _access(await Geolocator.requestPermission()));

  @override
  Future<LocationFix> getCurrentPosition() => _call(
    () async => _fix(
      await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      ),
    ),
  );

  @override
  Future<LocationFix?> getLastKnownPosition() => _call(() async {
    final position = await Geolocator.getLastKnownPosition();
    return position == null ? null : _fix(position);
  });

  @override
  Stream<LocationFix> watchPosition() async* {
    try {
      // Нет foregroundNotificationConfig: Android foreground service и
      // background location не запускаются. Lifecycle контролируется снаружи.
      yield* Geolocator.getPositionStream(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
          intervalDuration: const Duration(seconds: 5),
        ),
      ).map(_fix);
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Stream<bool> watchServiceEnabled() async* {
    try {
      yield* Geolocator.getServiceStatusStream().map(
        (status) => status == ServiceStatus.enabled,
      );
    } catch (error) {
      throw _failure(error);
    }
  }

  @override
  Future<bool> openAppSettings() => _call(Geolocator.openAppSettings);

  @override
  Future<bool> openLocationSettings() => _call(Geolocator.openLocationSettings);
}
