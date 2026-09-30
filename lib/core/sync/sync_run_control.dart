import 'package:dio/dio.dart';

/// Согласованная отмена; восстановление сохранённой блокировки учитывает и внезапное завершение.
class SyncRunControl {
  final token = CancelToken();
  bool get cancelled => token.isCancelled;
  void cancel() {
    if (!cancelled) token.cancel('Sync execution stopped');
  }
}
