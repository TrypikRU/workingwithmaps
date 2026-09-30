import '../../../core/location/native_tracking.dart';
import '../../route/data/route_repository.dart';

/// Подтверждение отправляется только ПОСЛЕ фиксации Drift. Сбой до него приводит к безопасному повтору.
/// При ошибке SQLite весь пакет платформы остаётся доступным для следующей попытки.
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
