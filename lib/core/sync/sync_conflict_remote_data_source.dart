import 'package:dio/dio.dart';

import 'sync_snapshot.dart';

/// Ручное обновление конфликтного snapshot. Ответ сохраняется repository в БД,
/// и только Drift stream обновляет диагностику; автоматических записей нет.
class SyncConflictRemoteDataSource {
  SyncConflictRemoteDataSource(this.dio);
  final Dio dio;
  Future<Map<String, dynamic>> fetch(String type, String id) async {
    if (!['object', 'visit'].contains(type)) {
      throw StateError('Тип конфликта пока не поддерживает загрузку записи.');
    }
    final response = await dio.get<Object?>(
      '${type == 'object' ? 'objects' : 'visits'}/${Uri.encodeComponent(id)}',
    );
    final snapshot = validatedServerSnapshot(type, id, response.data);
    if (snapshot == null) {
      throw StateError('Сервер вернул некорректную запись.');
    }
    return snapshot;
  }
}
