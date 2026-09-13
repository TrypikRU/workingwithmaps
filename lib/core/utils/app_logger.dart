import 'dart:convert';
import 'dart:developer' as developer;

/// Общий структурированный logger. Не пишет координаты, payload и HTTP headers.
/// Sink подменяется тестом или будущим файловым логированием без изменения engine.
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
          name: 'FieldInspector',
        );
      }
    } catch (_) {
      // Сбой диагностики никогда не должен отменять commit или retry.
    }
  }
}
