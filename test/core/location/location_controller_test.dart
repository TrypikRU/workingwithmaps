import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/location/location_controller.dart';
import 'package:workingwithmaps/core/location/location_service.dart';
import 'package:workingwithmaps/core/location/location_state.dart';

import '../../support/fake_location_service.dart';

void main() {
  late FakeLocationService service;
  late ProviderContainer container;
  late LocationController controller;
  LocationState state() => container.read(locationControllerProvider);

  setUp(() {
    service = FakeLocationService();
    container = ProviderContainer(
      overrides: [locationServiceProvider.overrideWithValue(service)],
    );
    container.listen(locationControllerProvider, (_, next) {});
    controller = container.read(locationControllerProvider.notifier);
  });
  tearDown(() async {
    container.dispose();
    await service.dispose();
  });

  test(
    'denied never prompts automatically; explicit grant starts updates',
    () async {
      await controller.resume();
      expect(state().status, LocationStatus.permissionDenied);
      expect(service.permissionRequests, 0);
      expect(service.currentRequests, 0);
      expect(service.positions.hasListener, isFalse);
      await controller.refresh(requestPermission: true);
      expect(service.permissionRequests, 1);
      expect(state().status, LocationStatus.available);
      expect(state().position, service.current);
      expect(service.positions.hasListener, isTrue);
    },
  );

  test(
    'deniedForever only offers settings; disabled service blocks positioning',
    () async {
      service.access = LocationAccess.deniedForever;
      await controller.resume();
      await controller.refresh(requestPermission: true);
      expect(state().status, LocationStatus.permissionDeniedForever);
      expect(service.permissionRequests, 0);
      await controller.openSettings(locationSettings: false);
      expect(service.appSettingsOpened, 1);
      service.enabled = false;
      await controller.refresh();
      expect(state().status, LocationStatus.serviceDisabled);
      expect(service.currentRequests, 0);
      await controller.openSettings(locationSettings: true);
      expect(service.locationSettingsOpened, 1);
    },
  );

  test(
    'cached position stays labelled until a fresh fix; stream updates accuracy',
    () async {
      service.access = LocationAccess.granted;
      service.lastKnown = fix(second: -30, accuracy: 150);
      final pending = Completer<LocationFix>();
      service.currentFuture = pending.future;
      final loading = controller.resume();
      await pumpEventQueue();
      expect(state().status, LocationStatus.permissionGranted);
      expect(state().position, service.lastKnown);
      expect(state().isLastKnown, isTrue);
      expect(state().canCenter, isFalse);
      pending.complete(service.current);
      await loading;
      final next = fix(second: 5, accuracy: 4);
      service.positions.add(next);
      await pumpEventQueue();
      expect(state().position, next);
      expect(state().canCenter, isTrue);
    },
  );

  test(
    'late cache and old one-shot fix never overwrite newer stream sample',
    () async {
      service.access = LocationAccess.granted;
      final current = Completer<LocationFix>();
      final cached = Completer<LocationFix?>();
      service.currentFuture = current.future;
      service.lastFuture = cached.future;
      final loading = controller.resume();
      await pumpEventQueue();
      final newest = fix(second: 10);
      service.positions.add(newest);
      await pumpEventQueue();
      cached.complete(fix(second: -20));
      current.complete(fix());
      await loading;
      expect(state().position, newest);
      expect(state().isLastKnown, isFalse);
    },
  );

  test(
    'pause cancels streams and ignores pending fix; resume rechecks permission',
    () async {
      service.access = LocationAccess.granted;
      final pending = Completer<LocationFix>();
      service.currentFuture = pending.future;
      final loading = controller.resume();
      await pumpEventQueue();
      controller.pause();
      await pumpEventQueue();
      expect(service.positions.hasListener, isFalse);
      expect(service.services.hasListener, isFalse);
      pending.complete(service.current);
      await loading;
      expect(state().status, LocationStatus.paused);
      service.access = LocationAccess.deniedForever;
      await controller.resume();
      expect(state().status, LocationStatus.permissionDeniedForever);
      expect(service.positions.hasListener, isFalse);
    },
  );

  test('concurrent explicit retries share one permission dialog', () async {
    await controller.resume();
    final pending = Completer<LocationAccess>();
    service.permissionFuture = pending.future;
    final first = controller.refresh(requestPermission: true);
    await pumpEventQueue();
    final second = controller.refresh(requestPermission: true);
    await pumpEventQueue();
    expect(service.permissionRequests, 1);
    pending.complete(LocationAccess.granted);
    await Future.wait([first, second]);
    expect(state().status, LocationStatus.available);
    expect(service.currentRequests, 1);
  });

  test(
    'service disabled invalidates pending fix; enabled restarts stream',
    () async {
      service.access = LocationAccess.granted;
      final pending = Completer<LocationFix>();
      service.currentFuture = pending.future;
      final loading = controller.resume();
      await pumpEventQueue();
      service.enabled = false;
      service.services.add(false);
      await pumpEventQueue();
      pending.complete(service.current);
      await loading;
      expect(state().status, LocationStatus.serviceDisabled);
      expect(service.positions.hasListener, isFalse);
      service.currentFuture = null;
      service.enabled = true;
      service.services.add(true);
      await pumpEventQueue();
      expect(state().status, LocationStatus.available);
      expect(service.positions.hasListener, isTrue);
    },
  );

  test('stream failure rechecks revoked permissions', () async {
    service.access = LocationAccess.granted;
    await controller.resume();
    service.access = LocationAccess.deniedForever;
    service.positions.addError(
      const LocationFailure(LocationFailureKind.permission),
    );
    await pumpEventQueue();
    expect(state().status, LocationStatus.permissionDeniedForever);
    expect(state().position, isNull);
  });

  test('timeout is recoverable; existing cached position is not considered current', () async {
    service.access = LocationAccess.granted;
    service.lastKnown = fix(second: -20);
    service.currentError = const LocationFailure(LocationFailureKind.timeout);
    await controller.resume();
    expect(state().status, LocationStatus.error);
    expect(state().message, contains('20 секунд'));
    expect(state().canCenter, isFalse);
    service.currentError = null;
    await controller.refresh();
    expect(state().status, LocationStatus.available);
  });

  test('unavailable settings become a visible error', () async {
    await controller.resume();
    service.settingsResult = false;
    await controller.openSettings(locationSettings: false);
    expect(state().status, LocationStatus.error);
    expect(state().message, contains('вручную'));
  });
}
