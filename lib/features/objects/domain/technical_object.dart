import 'package:freezed_annotation/freezed_annotation.dart';
import '../../../core/geometry/geo_point.dart';

part 'technical_object.freezed.dart';
part 'technical_object.g.dart';

enum ObjectStatus { planned, visited, error }

enum ObjectPriority { low, normal, high, critical }

/// Модель не зависит от Drift/Dio: детали хранения не попадают в UI.
/// JSON модели не является контрактом backend: API использует отдельный ObjectDto.
@freezed
abstract class TechnicalObject with _$TechnicalObject {
  const factory TechnicalObject({
    required String id,
    required String name,
    @Default('') String address,
    required double latitude,
    required double longitude,
    @Default(ObjectStatus.planned) ObjectStatus status,
    @Default(ObjectPriority.normal) ObjectPriority priority,
    @Default(50.0) double geofenceRadius,
    @Default(<GeoPoint>[]) List<GeoPoint> polygon,
  }) = _TechnicalObject;

  factory TechnicalObject.fromJson(Map<String, dynamic> json) =>
      _$TechnicalObjectFromJson(json);
}
