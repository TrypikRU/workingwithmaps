// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'object_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ObjectDto _$ObjectDtoFromJson(Map<String, dynamic> json) =>
    $checkedCreate('ObjectDto', json, ($checkedConvert) {
      final val = ObjectDto(
        id: $checkedConvert('id', (v) => v as String),
        name: $checkedConvert('name', (v) => v as String),
        address: $checkedConvert('address', (v) => v as String),
        latitude: $checkedConvert('latitude', (v) => (v as num).toDouble()),
        longitude: $checkedConvert('longitude', (v) => (v as num).toDouble()),
        status: $checkedConvert('status', (v) => v as String),
        priority: $checkedConvert('priority', (v) => v as String),
        updatedAt: $checkedConvert(
          'updatedAt',
          (v) => DateTime.parse(v as String),
        ),
      );
      return val;
    });

Map<String, dynamic> _$ObjectDtoToJson(ObjectDto instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'address': instance.address,
  'latitude': instance.latitude,
  'longitude': instance.longitude,
  'status': instance.status,
  'priority': instance.priority,
  'updatedAt': instance.updatedAt.toIso8601String(),
};
