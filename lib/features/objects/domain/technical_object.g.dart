// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'technical_object.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TechnicalObject _$TechnicalObjectFromJson(Map<String, dynamic> json) =>
    _TechnicalObject(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String? ?? '',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      status:
          $enumDecodeNullable(_$ObjectStatusEnumMap, json['status']) ??
          ObjectStatus.planned,
      priority:
          $enumDecodeNullable(_$ObjectPriorityEnumMap, json['priority']) ??
          ObjectPriority.normal,
      geofenceRadius: (json['geofenceRadius'] as num?)?.toDouble() ?? 50.0,
      polygon:
          (json['polygon'] as List<dynamic>?)
              ?.map((e) => GeoPoint.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <GeoPoint>[],
    );

Map<String, dynamic> _$TechnicalObjectToJson(_TechnicalObject instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'address': instance.address,
      'latitude': instance.latitude,
      'longitude': instance.longitude,
      'status': _$ObjectStatusEnumMap[instance.status]!,
      'priority': _$ObjectPriorityEnumMap[instance.priority]!,
      'geofenceRadius': instance.geofenceRadius,
      'polygon': instance.polygon.map((e) => e.toJson()).toList(),
    };

const _$ObjectStatusEnumMap = {
  ObjectStatus.planned: 'planned',
  ObjectStatus.visited: 'visited',
  ObjectStatus.error: 'error',
};

const _$ObjectPriorityEnumMap = {
  ObjectPriority.low: 'low',
  ObjectPriority.normal: 'normal',
  ObjectPriority.high: 'high',
  ObjectPriority.critical: 'critical',
};
