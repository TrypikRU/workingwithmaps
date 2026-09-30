import 'dart:convert';
import 'dart:developer' as developer;

/// Общий структурированный журнал. Не записывает координаты, данные запросов и HTTP-заголовки.
/// Получатель записей заменяется тестом или файловым журналом без изменения движка.
class AppLogger {
  const AppLogger({this.sink});
  final void Function(String event, Map<String, Object?> fields)? sink;

  void log(String event, [Map<String, Object?> fields = const {}]) {
    try {
      if (sink != null) {
        sink!(event, fields);
      } else {
        developer.log(
          jsonEncode({'event': event, ...fields}),
          name: 'Полевой инспектор',
        );
      }
    } catch (_) {
      // Сбой диагностики никогда не должен отменять фиксацию или повтор.
    }
  }
}
