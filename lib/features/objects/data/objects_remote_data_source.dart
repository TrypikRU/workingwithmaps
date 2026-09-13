import 'package:dio/dio.dart';
import 'package:json_annotation/json_annotation.dart';

import '../../../core/network/network_failure.dart';
import 'object_dto.dart';

class ObjectsRemoteDataSource {
  ObjectsRemoteDataSource(this._dio);
  final Dio _dio;

  Future<List<ObjectDto>> fetchObjects() async {
    try {
      final response = await _dio.get<dynamic>('objects');
      final json = response.data;
      if (json is! List) throw const FormatException('Expected object array');
      return json
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException('Expected object');
            }
            return ObjectDto.fromJson(item);
          })
          .toList(growable: false);
    } on DioException catch (error) {
      throw NetworkFailure.fromDio(error);
    } on CheckedFromJsonException {
      throw const NetworkFailure(NetworkFailureKind.invalidData);
    } on FormatException {
      throw const NetworkFailure(NetworkFailureKind.invalidData);
    }
  }
}
