import 'package:workingwithmaps/core/location/native_tracking.dart';

class FakeNativeTracking implements NativeTracking {
  final inbox = <RecordedPoint>[];
  bool running = false;
  bool failAck = false;
  String? routeId;
  int stops = 0;
  @override
  Future<bool> requestNotificationPermission() async => true;
  @override
  Future<void> startTracking(String routeId) async {
    this.routeId = routeId;
    running = true;
  }

  @override
  Future<void> stopTracking() async {
    running = false;
    stops++;
  }

  @override
  Future<NativeTrackingStatus> isTracking() async =>
      NativeTrackingStatus(running: running, routeId: routeId);
  @override
  Future<List<RecordedPoint>> readPoints() async => inbox.take(200).toList();
  @override
  Future<void> ackPoints(List<String> ids) async {
    if (failAck) throw StateError('lost native ACK');
    inbox.removeWhere((p) => ids.contains(p.id));
  }
}
