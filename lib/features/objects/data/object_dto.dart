import 'package:json_annotation/json_annotation.dart';

import '../domain/technical_object.dart';

part 'object_dto.g.dart';

/// Контракт GET /objects. updatedAt — метаданные сервера, не состояние UI.
@JsonSerializable(checked: true)
class ObjectDto {
  const ObjectDto({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.priority,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String status;
  final String priority;
  final DateTime updatedAt;

  factory ObjectDto.fromJson(Map<String, dynamic> json) =>
      _$ObjectDtoFromJson(json);
  Map<String, dynamic> toJson() => _$ObjectDtoToJson(this);
}

extension ObjectDtoMapper on ObjectDto {
  TechnicalObject toDomain() {
    if (id.trim().isEmpty ||
        !latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const FormatException('Invalid object coordinates or id');
    }
    return TechnicalObject(
      id: id,
      name: name,
      address: address,
      latitude: latitude,
      longitude: longitude,
      status: ObjectStatus.values.byName(status),
      priority: ObjectPriority.values.byName(priority),
    );
  }
}

extension TechnicalObjectDtoMapper on TechnicalObject {
  // Domain не придумывает серверное время: его явно передаёт data-слой.
  ObjectDto toDto({required DateTime updatedAt}) => ObjectDto(
    id: id,
    name: name,
    address: address,
    latitude: latitude,
    longitude: longitude,
    status: status.name,
    priority: priority.name,
    updatedAt: updatedAt.toUtc(),
  );
}
