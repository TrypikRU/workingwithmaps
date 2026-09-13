import 'package:dio/dio.dart';

enum NetworkFailureKind {
  offline,
  timeout,
  server,
  conflict,
  cancelled,
  invalidData,
  other,
}

/// Ошибка remote-операции не является ошибкой потока локальных данных.
class NetworkFailure implements Exception {
  const NetworkFailure(this.kind, {this.statusCode});

  final NetworkFailureKind kind;
  final int? statusCode;

  factory NetworkFailure.fromDio(DioException error) {
    final kind = switch (error.type) {
      DioExceptionType.connectionError => NetworkFailureKind.offline,
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => NetworkFailureKind.timeout,
      DioExceptionType.cancel => NetworkFailureKind.cancelled,
      DioExceptionType.badResponse when error.response?.statusCode == 409 =>
        NetworkFailureKind.conflict,
      DioExceptionType.badResponse
          when (error.response?.statusCode ?? 0) >= 500 =>
        NetworkFailureKind.server,
      _ => NetworkFailureKind.other,
    };
    return NetworkFailure(kind, statusCode: error.response?.statusCode);
  }
}
