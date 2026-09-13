import '../../../core/location/native_tracking.dart';
import '../../route/data/route_repository.dart';

/// ACK only AFTER a Drift commit. A crash before ACK causes harmless replay.
/// A SQLite error leaves the complete native batch available for a later retry.
class NativeTrackImporter {
  NativeTrackImporter(this.native, this.repository);
  final NativeTracking native;
  final RouteRepository repository;
  Future<void>? _inFlight;
  Future<void> drain() =>
      _inFlight ??= _drain().whenComplete(() => _inFlight = null);
  Future<void> _drain() async {
    while (true) {
      final batch = await native.readPoints();
      if (batch.isEmpty) return;
      await repository.importRecordedPoints(batch);
      await native.ackPoints(batch.map((p) => p.id).toList());
    }
  }
}
