import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/network/dio_provider.dart';
import '../data/objects_remote_data_source.dart';
import '../data/drift_objects_data_source.dart';
import '../data/objects_repository.dart';
import '../domain/technical_object.dart';

// Сборка зависимостей: экран не знает о SQLite или формате таблиц.
final objectsRepositoryProvider = Provider<ObjectsRepository>((ref) {
  return ObjectsRepository(
    DriftObjectsDataSource(ref.watch(appDatabaseProvider)),
    // Dio создаётся только по refresh: неправильная настройка API не мешает cache.
    remote: () => ObjectsRemoteDataSource(ref.read(dioProvider)),
  );
});

final objectsProvider = StreamProvider<List<TechnicalObject>>((ref) {
  return ref.watch(objectsRepositoryProvider).watchObjects();
});

// Список, карта и детали читают один поток, без отдельных копий данных.
final objectProvider = Provider.family<AsyncValue<TechnicalObject?>, String>(
  (ref, id) => ref
      .watch(objectsProvider)
      .whenData(
        (objects) => objects.where((object) => object.id == id).firstOrNull,
      ),
);
