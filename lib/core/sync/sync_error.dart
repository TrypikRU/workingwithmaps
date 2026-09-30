import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

enum SyncErrorKind {
  network,
  dependency,
  timeout,
  server,
  client,
  conflict,
  unsupported,
  invalidResponse,
  local,
}

class SyncException implements Exception {
  const SyncException(this.kind, this.message, {this.statusCode});
  final SyncErrorKind kind;
  final String message;
  final int? statusCode;
  bool get retryable =>
      kind == SyncErrorKind.dependency ||
      kind == SyncErrorKind.network ||
      kind == SyncErrorKind.timeout ||
      kind == SyncErrorKind.server;

  factory SyncException.fromDio(DioException error) {
    final status = error.response?.statusCode;
    if (error.error is SocketException ||
        error.type == DioExceptionType.cancel) {
      // Штатное завершение может отменить текущий запрос уже после фиксации на сервере.
      // Оставляем возможность повтора с теми же зафиксированными данными при следующем запуске.
      return const SyncException(
        SyncErrorKind.network,
        'Connection interrupted',
      );
    }
    if (error.error is TimeoutException) {
      return const SyncException(SyncErrorKind.timeout, 'Request timed out');
    }
    final kind = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.sendTimeout => SyncErrorKind.timeout,
      DioExceptionType.connectionError => SyncErrorKind.network,
      DioExceptionType.badResponse when status == 409 => SyncErrorKind.conflict,
      DioExceptionType.badResponse when (status ?? 0) >= 500 =>
        SyncErrorKind.server,
      DioExceptionType.badResponse => SyncErrorKind.client,
      _ => SyncErrorKind.client,
    };
    // Не сохраняем error.toString(): Dio может включить конфиденциальные данные запроса.
    return SyncException(kind, 'Remote request failed', statusCode: status);
  }

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'message': message,
    'statusCode': statusCode,
    'retryable': retryable,
  };
}
