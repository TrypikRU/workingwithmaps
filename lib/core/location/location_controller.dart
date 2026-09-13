import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'geolocator_location_service.dart';
import 'location_service.dart';
import 'location_state.dart';

final locationServiceProvider = Provider<LocationService>(
  (ref) => GeolocatorLocationService(),
);

final locationControllerProvider =
    NotifierProvider<LocationController, LocationState>(LocationController.new);

class LocationController extends Notifier<LocationState> {
  late LocationService _service;
  StreamSubscription<LocationFix>? _positions;
  StreamSubscription<bool>? _services;
  Future<LocationAccess>? _permissionRequest;
  bool _foreground = false;
  bool _disposed = false;
  int _generation = 0;
  int _monitorGeneration = 0;

  @override
  LocationState build() {
    _service = ref.read(locationServiceProvider);
    ref.onDispose(() {
      _disposed = true;
      _generation++;
      unawaited(_positions?.cancel());
      unawaited(_services?.cancel());
    });
    return const LocationState();
  }

  bool _active(int generation) =>
      !_disposed && _foreground && generation == _generation;

  Future<void> resume() async {
    if (_disposed || _foreground) return;
    _foreground = true;
    final monitor = ++_monitorGeneration;
    // Статус сервиса наблюдается даже при denied: после включения GPS
    // повторно проверяем доступ, но сами не открываем permission dialog.
    _services = _service.watchServiceEnabled().listen(
      (enabled) {
        if (_disposed || !_foreground || monitor != _monitorGeneration) return;
        if (enabled) {
          unawaited(refresh());
        } else {
          _generation++;
          unawaited(_stopPositions());
          state = const LocationState(status: LocationStatus.serviceDisabled);
        }
      },
      onError: (Object error) {
        if (!_disposed && _foreground && monitor == _monitorGeneration) {
          unawaited(_handleError(error, _generation));
        }
      },
    );
    await refresh();
  }

  void pause() {
    if (_disposed) return;
    _foreground = false;
    _generation++;
    _monitorGeneration++;
    unawaited(_stopPositions());
    final services = _services;
    _services = null;
    unawaited(services?.cancel());
    state = LocationState(
      status: LocationStatus.paused,
      position: state.position,
      isLastKnown: true,
    );
  }

  Future<void> _stopPositions() async {
    final positions = _positions;
    _positions = null;
    await positions?.cancel();
  }

  Future<void> refresh({bool requestPermission = false}) async {
    if (!_foreground || _disposed) return;
    // Нельзя отменить каждый platform Future, поэтому поколение блокирует
    // запоздалый ответ после pause, отключения GPS или нового запроса.
    final generation = ++_generation;
    final previous = state.position;
    state = LocationState(
      status: LocationStatus.loading,
      position: previous,
      isLastKnown: true,
    );
    try {
      await _stopPositions();
      if (!_active(generation)) return;
      if (!await _service.isServiceEnabled()) {
        if (_active(generation)) {
          state = const LocationState(status: LocationStatus.serviceDisabled);
        }
        return;
      }
      if (!_active(generation)) return;
      var access = await (_permissionRequest ?? _service.checkPermission());
      if (!_active(generation)) return;
      if (access == LocationAccess.denied && requestPermission) {
        // Диалог открываем только по кнопке. deniedForever требует настроек;
        // resume во время диалога присоединяется к тому же Future.
        final pending = _permissionRequest ??= _service.requestPermission();
        try {
          access = await pending;
        } finally {
          if (identical(_permissionRequest, pending)) _permissionRequest = null;
        }
      }
      if (!_active(generation)) return;
      if (access != LocationAccess.granted) {
        state = LocationState(
          status: access == LocationAccess.deniedForever
              ? LocationStatus.permissionDeniedForever
              : LocationStatus.permissionDenied,
        );
        return;
      }
      state = LocationState(
        status: LocationStatus.permissionGranted,
        position: previous,
        isLastKnown: true,
      );
      var receivedLive = false;
      _positions = _service.watchPosition().listen(
        (position) {
          if (!_active(generation)) return;
          receivedLive = true;
          _publish(position);
        },
        onError: (Object error) {
          unawaited(_handleError(error, generation));
        },
        onDone: () {
          if (_active(generation)) {
            unawaited(
              _handleError(
                const LocationFailure(LocationFailureKind.unknown),
                generation,
              ),
            );
          }
        },
        cancelOnError: true,
      );

      // Кэш — только временная подсказка, не свежий fix. Его ошибка не мешает
      // основному запросу; поздний кэш не должен затереть stream update.
      unawaited(_loadLastKnown(generation, () => receivedLive));
      try {
        final position = await _service.getCurrentPosition();
        if (_active(generation)) {
          receivedLive = true;
          _publish(position);
        }
      } catch (error) {
        // Если stream уже дал координаты, timeout одиночного запроса не ошибка UI.
        if (!receivedLive) await _handleError(error, generation);
      }
    } catch (error) {
      await _handleError(error, generation);
    }
  }

  Future<void> _loadLastKnown(
    int generation,
    bool Function() receivedLive,
  ) async {
    try {
      final position = await _service.getLastKnownPosition();
      if (_active(generation) && !receivedLive() && position != null) {
        state = LocationState(
          status: LocationStatus.permissionGranted,
          position: position,
          isLastKnown: true,
        );
      }
    } catch (_) {
      // Отсутствующий или недоступный platform cache не блокирует свежий GPS fix.
    }
  }

  void _publish(LocationFix position) {
    final previous = state.position;
    if (!state.isLastKnown &&
        previous != null &&
        position.timestamp.isBefore(previous.timestamp)) {
      return;
    }
    state = LocationState(status: LocationStatus.available, position: position);
  }

  Future<void> _handleError(Object error, int generation) async {
    if (!_active(generation)) return;
    final failedGeneration = ++_generation;
    final previous = state.position;
    await _stopPositions();
    if (!_active(failedGeneration)) return;
    // Разрешение может быть отозвано и GPS выключен во время stream.
    // Перепроверка отличает эти ситуации от произвольной platform-ошибки.
    var status = LocationStatus.error;
    try {
      if (!await _service.isServiceEnabled()) {
        status = LocationStatus.serviceDisabled;
      } else {
        status = switch (await _service.checkPermission()) {
          LocationAccess.denied => LocationStatus.permissionDenied,
          LocationAccess.deniedForever =>
            LocationStatus.permissionDeniedForever,
          LocationAccess.granted => LocationStatus.error,
        };
      }
    } catch (_) {
      if (error is LocationFailure &&
          error.kind == LocationFailureKind.serviceDisabled) {
        status = LocationStatus.serviceDisabled;
      }
    }
    if (!_active(failedGeneration)) return;
    state = LocationState(
      status: status,
      position: status == LocationStatus.error ? previous : null,
      isLastKnown: true,
      message:
          error is LocationFailure && error.kind == LocationFailureKind.timeout
          ? 'Не удалось получить GPS-позицию за 20 секунд. Попробуйте ещё раз.'
          : 'Не удалось получить геолокацию. Попробуйте ещё раз.',
    );
  }

  Future<void> openSettings({required bool locationSettings}) async {
    try {
      final opened = await (locationSettings
          ? _service.openLocationSettings()
          : _service.openAppSettings());
      if (!opened) throw const LocationFailure(LocationFailureKind.unknown);
    } catch (_) {
      if (!_disposed && _foreground) {
        state = const LocationState(
          status: LocationStatus.error,
          message: 'Не удалось открыть настройки. Откройте их вручную.',
        );
      }
    }
  }
}
