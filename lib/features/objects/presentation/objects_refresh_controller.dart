import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/network_failure.dart';
import 'objects_providers.dart';

final objectsRefreshControllerProvider =
    NotifierProvider<ObjectsRefreshController, bool>(
      ObjectsRefreshController.new,
    );

/// Состояние обновления отделено от StreamProvider: сбой HTTP не заменяет кэш
/// экраном ошибки. Один контроллер предотвращает параллельные ручные загрузки.
class ObjectsRefreshController extends Notifier<bool> {
  @override
  bool build() => false;

  Future<String?> refresh() async {
    if (state) return null;
    state = true;
    try {
      await ref.read(objectsRepositoryProvider).refreshObjects();
      return 'Обновление завершено';
    } on NetworkFailure catch (error) {
      return switch (error.kind) {
        NetworkFailureKind.offline =>
          'Нет соединения с сервером. Сохранённые объекты доступны.',
        NetworkFailureKind.timeout =>
          'Сервер не ответил вовремя. Сохранённые объекты доступны.',
        NetworkFailureKind.server =>
          'Ошибка сервера. Сохранённые объекты доступны.',
        NetworkFailureKind.conflict =>
          'Конфликт на сервере. Сохранённые объекты доступны.',
        NetworkFailureKind.invalidData =>
          'Некорректный ответ сервера. Данные не обновлены.',
        NetworkFailureKind.cancelled => null,
        NetworkFailureKind.other =>
          'Не удалось обновить объекты. Сохранённые данные доступны.',
      };
    } catch (_) {
      return 'Не удалось обновить объекты. Проверьте настройки API или повторите позже.';
    } finally {
      if (ref.mounted) state = false;
    }
  }
}
