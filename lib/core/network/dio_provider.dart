import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Клиент удалённых источников данных; интерфейс не использует его напрямую.
/// Провайдер создаётся лениво: запуск приложения не требует адреса сервера.
final dioProvider = Provider<Dio>((ref) {
  final dio = createApiDio();
  ref.onDispose(() => dio.close(force: true));
  return dio;
});

/// Общая конфигурация репозиториев открытого приложения и фоновых обработчиков.
Dio createApiDio() {
  const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5080/',
  );
  final uri = Uri.tryParse(baseUrl);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      (uri.scheme != 'https' && uri.scheme != 'http')) {
    throw StateError(
      'Перед использованием API задайте --dart-define=API_BASE_URL=https://.../',
    );
  }

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl.endsWith('/') ? baseUrl : '$baseUrl/',
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
      contentType: Headers.jsonContentType,
    ),
  );
  return dio;
}
