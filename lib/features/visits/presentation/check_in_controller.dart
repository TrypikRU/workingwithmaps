import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/location/location_controller.dart';
import '../../../core/location/location_state.dart';
import '../data/visits_repository.dart';
import '../domain/check_in_policy.dart';

final checkInPolicyProvider = Provider<CheckInPolicy>(
  (ref) => const CheckInPolicy(),
);
final visitsRepositoryProvider = Provider<VisitsRepository>(
  (ref) => VisitsRepository(
    ref.watch(appDatabaseProvider),
    policy: ref.watch(checkInPolicyProvider),
  ),
);
final checkInControllerProvider = NotifierProvider<CheckInController, bool>(
  CheckInController.new,
);

extension CheckInBlockMessage on CheckInBlock {
  String message(CheckInPolicy policy) => switch (this) {
    CheckInBlock.locationUnavailable =>
      'Для отметки о посещении нужно текущее местоположение.',
    CheckInBlock.poorAccuracy =>
      'Недостаточная точность GPS. Нужно не хуже ±${policy.maxAccuracy.toStringAsFixed(0)} м.',
    CheckInBlock.outsideRadius =>
      'Подойдите к объекту ближе: допустимый радиус ${policy.radius.toStringAsFixed(0)} м.',
  };
}

class CheckInController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<String?> checkIn(String objectId) async {
    if (state) return null;
    state = true;
    try {
      // Кнопка могла отображаться по прежним координатам. Перед сохранением заново
      // проверяем разрешение и сервис, получаем позицию через общий слой геолокации.
      await ref.read(locationControllerProvider.notifier).refresh();
      if (!ref.mounted) return null;
      final location = ref.read(locationControllerProvider);
      if (location.status != LocationStatus.available ||
          location.isLastKnown ||
          location.position == null) {
        throw const CheckInRejected(CheckInBlock.locationUnavailable);
      }
      await ref
          .read(visitsRepositoryProvider)
          .checkIn(objectId: objectId, position: location.position!);
      return 'Отметка о посещении сохранена на устройстве';
    } on CheckInRejected catch (error) {
      if (!ref.mounted) return null;
      return error.reason.message(ref.read(checkInPolicyProvider));
    } catch (_) {
      return 'Не удалось сохранить отметку о посещении. Попробуйте ещё раз.';
    } finally {
      if (ref.mounted) state = false;
    }
  }
}
