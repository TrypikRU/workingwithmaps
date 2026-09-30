import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workingwithmaps/core/database/app_database.dart';
import 'package:workingwithmaps/core/network/network_failure.dart';
import 'package:workingwithmaps/features/objects/data/drift_objects_data_source.dart';
import 'package:workingwithmaps/features/objects/data/object_dto.dart';
import 'package:workingwithmaps/features/objects/data/objects_remote_data_source.dart';
import 'package:workingwithmaps/features/objects/data/objects_repository.dart';
import 'package:workingwithmaps/features/objects/presentation/objects_providers.dart';
import 'package:workingwithmaps/features/objects/presentation/objects_refresh_controller.dart';

import '../../support/test_database.dart';

// Подменяем только передачу по HTTP. Репозиторий, разбор DTO и SQLite настоящие.
class TestAdapter implements HttpClientAdapter {
  Object body = <Object>[];
  int status = 200;
  DioExceptionType? failure;
  Completer<void>? wait;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    expect(options.uri.path, '/objects');
    if (wait != null) await wait!.future;
    if (failure != null) {
      throw DioException(requestOptions: options, type: failure!);
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object> objectJson({
  String id = 'remote-1',
  String name = 'С сервера',
}) => {
  'id': id,
  'name': name,
  'address': 'Сыктывкар',
  'latitude': 61.650478,
  'longitude': 50.770391,
  'status': 'planned',
  'priority': 'high',
  'updatedAt': '2026-09-12T12:00:00Z',
};

void main() {
  late TestAdapter adapter;
  late ObjectsRepository repository;

  // У каждого теста отдельная БД; сеть и эмулятор не требуются.
  setUp(() {
    adapter = TestAdapter();
  });

  ObjectsRepository createRepository(AppDatabase database) {
    final dio = Dio(BaseOptions(baseUrl: 'http://test/'))
      ..httpClientAdapter = adapter;
    addTearDown(() => dio.close(force: true));
    return ObjectsRepository(
      DriftObjectsDataSource(database),
      remote: () => ObjectsRemoteDataSource(dio),
    );
  }

  test('Successful refresh inserts/updates via reactive DB and does not enqueue uploads', () async {
    final database = createTestDatabase(seedDemoData: false);
    addTearDown(database.close);
    repository = createRepository(database);
    final stream = StreamIterator(repository.watchObjects());
    addTearDown(stream.cancel);
    await stream.moveNext();
    expect(stream.current, isEmpty);
    adapter.body = [objectJson()];
    await repository.refreshObjects();
    await stream.moveNext();
    expect(stream.current.single.name, 'С сервера');
    adapter.body = [objectJson(name: 'Обновлён')];
    await repository.refreshObjects();
    await stream.moveNext();
    expect(stream.current.single.name, 'Обновлён');
    expect(await database.select(database.syncQueue).get(), isEmpty);
    expect(
      (await database.select(database.technicalObjects).getSingle()).updatedAt
          .toUtc(),
      DateTime.utc(2026, 9, 12, 12),
    );
  });

  for (final cached in [false, true]) {
    for (final kind in [
      NetworkFailureKind.offline,
      NetworkFailureKind.server,
      NetworkFailureKind.timeout,
    ]) {
      test('$kind with cache=$cached keeps local stream readable', () async {
        final database = createTestDatabase(seedDemoData: false);
        addTearDown(database.close);
        repository = createRepository(database);
        if (cached) {
          adapter.body = [objectJson()];
          await repository.refreshObjects();
        }
        final before = await repository.watchObjects().first;
        if (kind == NetworkFailureKind.server) {
          adapter.status = 500;
        } else {
          adapter.failure = kind == NetworkFailureKind.offline
              ? DioExceptionType.connectionError
              : DioExceptionType.receiveTimeout;
        }
        await expectLater(
          repository.refreshObjects(),
          throwsA(isA<NetworkFailure>().having((e) => e.kind, 'kind', kind)),
        );
        expect(await repository.watchObjects().first, before);
        expect(before, hasLength(cached ? 1 : 0));
      });
    }
  }

  test(
    'Pending local edits made during HTTP are protected from overwrite',
    () async {
      final database = createTestDatabase(seedDemoData: false);
      addTearDown(database.close);
      repository = createRepository(database);
      adapter.body = [objectJson()];
      adapter.wait = Completer<void>();
      final refresh = repository.refreshObjects();
      final local = ObjectDto.fromJson(objectJson(name: 'Локальная правка'))
          .toDomain();
      await repository.saveObject(local);
      adapter.wait!.complete();
      await refresh;
      expect(await repository.watchObjects().first, [local]);
      expect(await database.select(database.syncQueue).get(), hasLength(1));
    },
  );

  test('Invalid payload cannot partially overwrite cache', () async {
    final database = createTestDatabase(seedDemoData: false);
    addTearDown(database.close);
    repository = createRepository(database);
    adapter.body = [objectJson()];
    await repository.refreshObjects();
    adapter.body = [
      objectJson(name: 'Не сохранять'),
      {...objectJson(id: 'bad'), 'status': 'unknown'},
    ];
    await expectLater(
      repository.refreshObjects(),
      throwsA(isA<NetworkFailure>()),
    );
    expect((await repository.watchObjects().first).single.name, 'С сервера');
  });

  test('SQL failure rolls back the entire remote batch', () async {
    final database = createTestDatabase(seedDemoData: false);
    addTearDown(database.close);
    repository = createRepository(database);
    adapter.body = [objectJson()];
    await repository.refreshObjects();
    await database.customStatement(
      "CREATE TEMP TRIGGER reject_remote BEFORE INSERT ON objects WHEN NEW.id = 'reject' BEGIN SELECT RAISE(ABORT, 'test'); END",
    );
    adapter.body = [objectJson(name: 'Не сохранять'), objectJson(id: 'reject')];
    await expectLater(repository.refreshObjects(), throwsA(isA<Exception>()));
    expect((await repository.watchObjects().first).single.name, 'С сервера');
  });

  test('Refresh controller reports HTTP error without putting objectsProvider in error', () async {
    final database = createTestDatabase(seedDemoData: false);
    addTearDown(database.close);
    repository = createRepository(database);
    adapter.body = [objectJson()];
    await repository.refreshObjects();
    final container = ProviderContainer(
      overrides: [objectsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(objectsProvider, (_, _) {});
    addTearDown(subscription.close);
    final before = await container.read(objectsProvider.future);
    adapter.status = 500;
    final controller = container.read(
      objectsRefreshControllerProvider.notifier,
    );
    final refresh = controller.refresh();
    expect(container.read(objectsRefreshControllerProvider), isTrue);
    expect(await refresh, contains('Ошибка сервера'));
    expect(container.read(objectsRefreshControllerProvider), isFalse);
    expect(container.read(objectsProvider).hasError, isFalse);
    expect(await container.read(objectsProvider.future), before);
  });

  test(
    'DTO domain mapper round trip preserves API fields and server timestamp',
    () {
      final dto = ObjectDto.fromJson(objectJson());
      expect(
        dto.toDomain().toDto(updatedAt: dto.updatedAt).toJson(),
        dto.toJson(),
      );
    },
  );
}
