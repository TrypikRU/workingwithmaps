import 'package:dio/dio.dart';

/// Cooperative cancellation; durable lease recovery also covers sudden kill.
class SyncRunControl {
  final token = CancelToken();
  bool get cancelled => token.isCancelled;
  void cancel() {
    if (!cancelled) token.cancel('Sync execution stopped');
  }
}
