import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/location/location_controller.dart';
import '../../../core/location/location_service.dart';
import '../../../core/location/native_tracking.dart';
import '../../route/data/route_repository.dart';
import '../../route/domain/route_snapshot.dart';
import '../../route/domain/route_status.dart';
import '../data/native_track_importer.dart';

final routeRepositoryProvider = Provider<RouteRepository>(
  (ref) => RouteRepository(ref.watch(appDatabaseProvider)),
);
final currentRouteProvider = StreamProvider<RouteSnapshot?>(
  (ref) => ref.watch(routeRepositoryProvider).watchCurrent(),
);
final routeClockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
});
final nativeTrackImporterProvider = Provider<NativeTrackImporter>(
  (ref) => NativeTrackImporter(
    ref.watch(nativeTrackingProvider),
    ref.watch(routeRepositoryProvider),
  ),
);
final trackingControllerProvider = NotifierProvider<TrackingController, String>(
  TrackingController.new,
);

/// Только команды интерфейса и сверка входящей очереди. Цикла записи на Dart здесь НЕТ:
/// приостановка приложения, удаление виджета или уничтожение движка не останавливают FGS.
class TrackingController extends Notifier<String> {
  bool _command = false;
  bool _refreshing = false;
  Timer? _timer;
  @override
  String build() {
    ref.onDispose(() => _timer?.cancel());
    return 'Проверка записи маршрута';
  }

  void setForeground(bool active) {
    _timer?.cancel();
    if (!active) {
      return; // Останавливает только сверку интерфейса, но не платформенный сервис.
    }
    unawaited(refresh());
    _timer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(refresh()),
    );
  }

  Future<void> refresh() async {
    if (_refreshing || _command) return;
    _refreshing = true;
    try {
      await ref.read(nativeTrackImporterProvider).drain();
      if (!ref.mounted) return;
      final status = await ref.read(nativeTrackingProvider).isTracking();
      if (!ref.mounted) return;
      state = status.running
          ? status.message
          : '${status.message}. Для записи нажмите «Возобновить запись маршрута»';
    } catch (error) {
      if (ref.mounted) {
        state = 'Не удалось получить состояние записи маршрута: $error';
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> start() async {
    if (_command) return;
    _command = true;
    try {
      // Запрашиваем при видимой Activity. Kotlin повторно проверяет точное разрешение и
      // видимость непосредственно перед созданием активного сервиса Android.
      final location = ref.read(locationServiceProvider);
      if (!await location.isServiceEnabled()) {
        throw const TrackingFailure('Включите геолокацию');
      }
      var permission = await location.checkPermission();
      if (permission == LocationAccess.denied) {
        permission = await location.requestPermission();
      }
      if (permission != LocationAccess.granted) {
        throw const TrackingFailure(
          'Разрешите точную геолокацию в настройках приложения',
        );
      }
      if (!ref.mounted) return;
      final native = ref.read(nativeTrackingProvider);
      final notifications = await native.requestNotificationPermission();
      if (!ref.mounted) return;
      final id = await ref.read(routeRepositoryProvider).start();
      await native.startTracking(id);
      if (ref.mounted) {
        state = notifications ? 'Маршрут отслеживается' : 'Запись маршрута активна; уведомления отключены в настройках Android';
      }
    } catch (error) {
      if (ref.mounted) state = '$error';
      rethrow;
    } finally {
      _command = false;
    }
  }

  Future<void> finish() async {
    if (_command) return;
    _command = true;
    try {
      final repository = ref.read(routeRepositoryProvider);
      final importer = ref.read(nativeTrackImporterProvider);
      // Подтверждение остановки — платформенный барьер записи. Повторяем импорт, если прежний
      // ещё выполнялся: так захватываем последнюю запись перед остановкой.
      await ref.read(nativeTrackingProvider).stopTracking();
      await importer.drain();
      await importer.drain();
      final route = await repository.watchCurrent().first;
      if (route?.status == RouteStatus.active) {
        await repository.finish(route!.id);
      }
      if (ref.mounted) state = 'Обход завершён';
    } catch (error) {
      if (ref.mounted) state = 'Не удалось завершить обход: $error';
      rethrow;
    } finally {
      _command = false;
    }
  }

  Future<void> flush() => ref.read(nativeTrackImporterProvider).drain();
}
