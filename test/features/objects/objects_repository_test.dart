import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/features/objects/data/drift_objects_data_source.dart';
import 'package:workingwithmaps/features/objects/data/objects_repository.dart';
import 'package:workingwithmaps/features/objects/domain/technical_object.dart';

import '../../support/test_database.dart';

void main() {
  test(
    'Repository emits committed SQLite changes and enqueues local mutation',
    () async {
      final database = createTestDatabase(seedDemoData: false);
      addTearDown(database.close);
      final repository = ObjectsRepository(DriftObjectsDataSource(database));
      const object = TechnicalObject(
        id: 'object-1',
        name: 'Технический объект',
        address: 'Москва, тестовый адрес',
        latitude: 55.75,
        longitude: 37.62,
        status: ObjectStatus.visited,
        priority: ObjectPriority.critical,
      );
      final stream = StreamIterator(repository.watchObjects());
      addTearDown(stream.cancel);
      expect(await stream.moveNext(), isTrue);
      expect(stream.current, isEmpty);
      await repository.saveObject(object);
      expect(await stream.moveNext(), isTrue);
      expect(stream.current, [object]);
      final operations = await database.select(database.syncQueue).get();
      expect(operations, hasLength(1));
      expect(operations.single.entityId, object.id);
      expect(operations.single.entityType, 'object');
      expect(operations.single.operation, 'upsert');
      expect(operations.single.attemptCount, 0);
      expect(operations.single.nextRetryAt, isNull);
      final row = await database.select(database.technicalObjects).getSingle();
      expect(row.updatedAt.isAfter(DateTime.utc(2020)), isTrue);
      final updated = object.copyWith(status: ObjectStatus.error);
      await repository.saveObject(updated);
      expect(await stream.moveNext(), isTrue);
      expect(stream.current, [updated]);
    },
  );

  test(
    'Queue failure rolls back object update and emits no intermediate state',
    () async {
      final database = createTestDatabase(seedDemoData: false);
      addTearDown(database.close);
      final repository = ObjectsRepository(DriftObjectsDataSource(database));
      const object = TechnicalObject(
        id: 'rollback',
        name: 'Исходное имя',
        latitude: 55,
        longitude: 37,
      );
      await repository.saveObject(object);
      final emissions = <List<TechnicalObject>>[];
      final subscription = repository.watchObjects().listen(emissions.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      // Имитируем сбой второй записи транзакции, не меняя production-код.
      await database.customStatement('''
      CREATE TEMP TRIGGER reject_queue BEFORE INSERT ON sync_queue
      BEGIN SELECT RAISE(ABORT, 'test queue failure'); END
    ''');
      await expectLater(
        repository.saveObject(object.copyWith(name: 'Не должно сохраниться')),
        throwsA(isA<Exception>()),
      );
      await pumpEventQueue();
      expect(await repository.watchObjects().first, [object]);
      expect(
        emissions.every((rows) => rows.single.name == object.name),
        isTrue,
      );
      expect(await database.select(database.syncQueue).get(), hasLength(1));
    },
  );

  test('Generated model preserves fields in JSON round trip', () {
    const object = TechnicalObject(
      id: 'object-1',
      name: 'Технический объект',
      latitude: 55.75,
      longitude: 37.62,
    );
    expect(TechnicalObject.fromJson(object.toJson()), object);
  });
}
