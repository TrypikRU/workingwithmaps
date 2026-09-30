import 'dart:convert';

import '../../../core/sync/sync_status.dart';

extension SyncStatusPresentation on SyncStatus {
  String get label => switch (this) {
    SyncStatus.synced => 'Синхронизировано',
    SyncStatus.pending => 'Ожидает отправки',
    SyncStatus.syncing => 'Отправляется',
    SyncStatus.failed => 'Ошибка',
  };
}

String syncEntityLabel(String value) => switch (value) {
  'object' => 'Объект',
  'visit' => 'Посещение',
  'route' => 'Обход',
  'location_point' => 'Точка маршрута',
  _ => value,
};

String syncOperationLabel(String value) => switch (value) {
  'create' => 'Создание',
  'upsert' => 'Создание или обновление',
  'update' || 'patch' => 'Обновление',
  'delete' => 'Удаление',
  _ => value,
};

const _fieldLabels = {
  'id': 'Идентификатор',
  'objectId': 'Идентификатор объекта',
  'routeId': 'Идентификатор обхода',
  'operationId': 'Идентификатор операции',
  'name': 'Название',
  'address': 'Адрес',
  'latitude': 'Широта',
  'longitude': 'Долгота',
  'accuracy': 'Точность',
  'speed': 'Скорость',
  'timestamp': 'Время записи',
  'date': 'Дата',
  'status': 'Статус',
  'priority': 'Приоритет',
  'serverVersion': 'Версия на сервере',
  'createdAt': 'Создано',
  'updatedAt': 'Обновлено',
  'polygon': 'Границы области',
  'geofenceRadius': 'Радиус зоны',
  'kind': 'Тип ошибки',
  'message': 'Сообщение',
  'statusCode': 'Код ответа сервера',
  'retryable': 'Возможен повтор',
};

const _valueLabels = {
  'planned': 'Запланирован',
  'visited': 'Посещён',
  'error': 'Ошибка',
  'completed': 'Завершено',
  'failed': 'Ошибка',
  'active': 'Активен',
  'low': 'Низкий',
  'normal': 'Обычный',
  'high': 'Высокий',
  'critical': 'Критический',
  'network': 'Ошибка сети',
  'dependency': 'Ожидание связанной операции',
  'timeout': 'Превышено время ожидания',
  'server': 'Ошибка сервера',
  'client': 'Ошибка запроса',
  'conflict': 'Конфликт версий',
  'unsupported': 'Неподдерживаемая операция',
  'invalidResponse': 'Некорректный ответ сервера',
  'local': 'Ошибка обработки на устройстве',
};

const _errorMessages = {
  'Connection interrupted': 'Соединение прервано',
  'Request timed out': 'Превышено время ожидания ответа',
  'Remote request failed': 'Не удалось выполнить запрос к серверу',
  'Missing or mismatched acknowledgement':
      'Подтверждение сервера отсутствует или не соответствует операции',
  'Local processing failed': 'Не удалось обработать данные на устройстве',
  'Backend has no writer for this operation':
      'Сервер не поддерживает эту операцию',
  'Visit missing': 'Посещение не найдено',
  'Location point missing': 'Точка маршрута не найдена',
  'Waiting for route registration': 'Ожидание регистрации обхода',
};

// Переводим только представление; сохранённые снимки и ключи протокола не меняются.
String formatSyncDetails(String value) {
  Object? translate(Object? data, [String? field]) {
    if (data is Map) {
      return {
        for (final entry in data.entries)
          _fieldLabels[entry.key] ?? entry.key: translate(
            entry.value,
            entry.key.toString(),
          ),
      };
    }
    if (data is List) {
      return data.map((item) => translate(item, field)).toList();
    }
    if (data == null) return 'Нет';
    if (data is bool) return data ? 'Да' : 'Нет';
    if (data is String) {
      if (field == 'message') return _errorMessages[data] ?? data;
      if (['status', 'priority', 'kind'].contains(field)) {
        return _valueLabels[data] ?? data;
      }
    }
    return data;
  }

  try {
    return const JsonEncoder.withIndent('  ')
        .convert(translate(jsonDecode(value)));
  } on FormatException {
    return _errorMessages[value] ?? value;
  }
}
