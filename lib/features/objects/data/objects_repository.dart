import '../domain/technical_object.dart';
import 'drift_objects_data_source.dart';
import '../../../core/network/network_failure.dart';
import 'object_dto.dart';
import 'objects_remote_data_source.dart';

/// Единственный источник объектов для UI — локальная БД.
/// Repository не экспортирует Drift rows, companions или QueryExecutor.
class ObjectsRepository {
  ObjectsRepository(this._source, {this.remote});

  final DriftObjectsDataSource _source;
  final ObjectsRemoteDataSource Function()? remote;

  Stream<List<TechnicalObject>> watchObjects() => _source.watchObjects();

  Future<void> saveObject(TechnicalObject object) => _source.saveObject(object);

  /// HTTP никогда не публикует список в UI: подписчики увидят только commit БД.
  Future<void> refreshObjects() async {
    final source = remote;
    if (source == null) throw StateError('Remote source is not configured');
    final dtos = await source().fetchObjects();
    final records = <({TechnicalObject object, DateTime updatedAt})>[];
    try {
      final ids = <String>{};
      for (final dto in dtos) {
        if (!ids.add(dto.id)) {
          throw const FormatException('Duplicate object id');
        }
        records.add((object: dto.toDomain(), updatedAt: dto.updatedAt.toUtc()));
      }
    } on FormatException {
      throw const NetworkFailure(NetworkFailureKind.invalidData);
    } on ArgumentError {
      throw const NetworkFailure(NetworkFailureKind.invalidData);
    }
    // Валидация всего ответа до записи исключает частичное обновление cache.
    await _source.mergeRemoteObjects(records);
  }
}
