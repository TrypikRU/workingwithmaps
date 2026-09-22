import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'location_service.dart';

class RecordedPoint {
  const RecordedPoint({
    required this.id,
    required this.routeId,
    required this.segmentId,
    required this.fix,
  });
  final String id;
  final String routeId;
  final String segmentId;
  final LocationFix fix;
  factory RecordedPoint.fromJson(Map<String, dynamic> p) => RecordedPoint(
    id: p['id'] as String,
    routeId: p['routeId'] as String,
    segmentId: p['segmentId'] as String,
    fix: LocationFix(
      latitude: (p['latitude'] as num).toDouble(),
      longitude: (p['longitude'] as num).toDouble(),
      accuracy: (p['accuracy'] as num).toDouble(),
      speed: (p['speed'] as num?)?.toDouble(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        p['timestamp'] as int,
        isUtc: true,
      ),
    ),
  );
}

class NativeTrackingStatus {
  const NativeTrackingStatus({
    this.running = false,
    this.routeId,
    this.message = 'Запись не запущена',
    this.count = 0,
    this.accuracy,
  });
  final bool running;
  final String? routeId;
  final String message;
  final int count;
  final double? accuracy;
}

class TrackingFailure implements Exception {
  const TrackingFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Durable pull/ACK transport. Events alone would lose fixes when Flutter is absent.
abstract interface class NativeTracking {
  Future<bool> requestNotificationPermission();
  Future<void> startTracking(String routeId);
  Future<void> stopTracking();
  Future<NativeTrackingStatus> isTracking();
  Future<List<RecordedPoint>> readPoints();
  Future<void> ackPoints(List<String> ids);
}

final nativeTrackingProvider = Provider<NativeTracking>(
  (ref) => AndroidNativeTracking(),
);

class AndroidNativeTracking implements NativeTracking {
  static const _channel = MethodChannel('field_inspector/tracking');
  Future<T?> _call<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw TrackingFailure(error.message ?? 'Ошибка Android tracking');
    } on MissingPluginException {
      throw const TrackingFailure(
        'Нативный tracking доступен только в Android-сборке',
      );
    }
  }

  @override
  Future<bool> requestNotificationPermission() async =>
      await _call<bool>('requestNotificationPermission') ?? false;
  @override
  Future<void> startTracking(String routeId) async {
    await _call<void>('startTracking', {'routeId': routeId});
  }

  @override
  Future<void> stopTracking() async {
    await _call<void>('stopTracking');
  }

  @override
  Future<NativeTrackingStatus> isTracking() async {
    final p = jsonDecode(
      await _call<String>('isTracking') ?? '{}',
    ) as Map<String, dynamic>;
    return NativeTrackingStatus(
      running: p['running'] == true,
      routeId: p['routeId'] as String?,
      message: p['message'] as String? ?? 'Запись не запущена',
      count: p['count'] as int? ?? 0,
      accuracy: (p['accuracy'] as num?)?.toDouble(),
    );
  }

  @override
  Future<List<RecordedPoint>> readPoints() async =>
      (await _call<List<Object?>>('readPoints') ?? [])
          .map(
            (p) => RecordedPoint.fromJson(
              jsonDecode(p as String) as Map<String, dynamic>,
            ),
          )
          .toList();
  @override
  Future<void> ackPoints(List<String> ids) async {
    await _call<void>('ackPoints', {'ids': ids});
  }
}
