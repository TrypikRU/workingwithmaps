// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'technical_object.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TechnicalObject {

 String get id; String get name; String get address; double get latitude; double get longitude; ObjectStatus get status; ObjectPriority get priority; double get geofenceRadius; List<GeoPoint> get polygon;
/// Create a copy of TechnicalObject
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TechnicalObjectCopyWith<TechnicalObject> get copyWith => _$TechnicalObjectCopyWithImpl<TechnicalObject>(this as TechnicalObject, _$identity);

  /// Serializes this TechnicalObject to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TechnicalObject&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.address, address) || other.address == address)&&(identical(other.latitude, latitude) || other.latitude == latitude)&&(identical(other.longitude, longitude) || other.longitude == longitude)&&(identical(other.status, status) || other.status == status)&&(identical(other.priority, priority) || other.priority == priority)&&(identical(other.geofenceRadius, geofenceRadius) || other.geofenceRadius == geofenceRadius)&&const DeepCollectionEquality().equals(other.polygon, polygon));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,address,latitude,longitude,status,priority,geofenceRadius,const DeepCollectionEquality().hash(polygon));

@override
String toString() {
  return 'TechnicalObject(id: $id, name: $name, address: $address, latitude: $latitude, longitude: $longitude, status: $status, priority: $priority, geofenceRadius: $geofenceRadius, polygon: $polygon)';
}


}

/// @nodoc
abstract mixin class $TechnicalObjectCopyWith<$Res>  {
  factory $TechnicalObjectCopyWith(TechnicalObject value, $Res Function(TechnicalObject) _then) = _$TechnicalObjectCopyWithImpl;
@useResult
$Res call({
 String id, String name, String address, double latitude, double longitude, ObjectStatus status, ObjectPriority priority, double geofenceRadius, List<GeoPoint> polygon
});




}
/// @nodoc
class _$TechnicalObjectCopyWithImpl<$Res>
    implements $TechnicalObjectCopyWith<$Res> {
  _$TechnicalObjectCopyWithImpl(this._self, this._then);

  final TechnicalObject _self;
  final $Res Function(TechnicalObject) _then;

/// Create a copy of TechnicalObject
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? address = null,Object? latitude = null,Object? longitude = null,Object? status = null,Object? priority = null,Object? geofenceRadius = null,Object? polygon = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,latitude: null == latitude ? _self.latitude : latitude // ignore: cast_nullable_to_non_nullable
as double,longitude: null == longitude ? _self.longitude : longitude // ignore: cast_nullable_to_non_nullable
as double,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ObjectStatus,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as ObjectPriority,geofenceRadius: null == geofenceRadius ? _self.geofenceRadius : geofenceRadius // ignore: cast_nullable_to_non_nullable
as double,polygon: null == polygon ? _self.polygon : polygon // ignore: cast_nullable_to_non_nullable
as List<GeoPoint>,
  ));
}

}


/// Adds pattern-matching-related methods to [TechnicalObject].
extension TechnicalObjectPatterns on TechnicalObject {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TechnicalObject value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TechnicalObject() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TechnicalObject value)  $default,){
final _that = this;
switch (_that) {
case _TechnicalObject():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TechnicalObject value)?  $default,){
final _that = this;
switch (_that) {
case _TechnicalObject() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String address,  double latitude,  double longitude,  ObjectStatus status,  ObjectPriority priority,  double geofenceRadius,  List<GeoPoint> polygon)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TechnicalObject() when $default != null:
return $default(_that.id,_that.name,_that.address,_that.latitude,_that.longitude,_that.status,_that.priority,_that.geofenceRadius,_that.polygon);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String address,  double latitude,  double longitude,  ObjectStatus status,  ObjectPriority priority,  double geofenceRadius,  List<GeoPoint> polygon)  $default,) {final _that = this;
switch (_that) {
case _TechnicalObject():
return $default(_that.id,_that.name,_that.address,_that.latitude,_that.longitude,_that.status,_that.priority,_that.geofenceRadius,_that.polygon);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String address,  double latitude,  double longitude,  ObjectStatus status,  ObjectPriority priority,  double geofenceRadius,  List<GeoPoint> polygon)?  $default,) {final _that = this;
switch (_that) {
case _TechnicalObject() when $default != null:
return $default(_that.id,_that.name,_that.address,_that.latitude,_that.longitude,_that.status,_that.priority,_that.geofenceRadius,_that.polygon);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TechnicalObject implements TechnicalObject {
  const _TechnicalObject({required this.id, required this.name, this.address = '', required this.latitude, required this.longitude, this.status = ObjectStatus.planned, this.priority = ObjectPriority.normal, this.geofenceRadius = 50.0, final  List<GeoPoint> polygon = const <GeoPoint>[]}): _polygon = polygon;
  factory _TechnicalObject.fromJson(Map<String, dynamic> json) => _$TechnicalObjectFromJson(json);

@override final  String id;
@override final  String name;
@override@JsonKey() final  String address;
@override final  double latitude;
@override final  double longitude;
@override@JsonKey() final  ObjectStatus status;
@override@JsonKey() final  ObjectPriority priority;
@override@JsonKey() final  double geofenceRadius;
 final  List<GeoPoint> _polygon;
@override@JsonKey() List<GeoPoint> get polygon {
  if (_polygon is EqualUnmodifiableListView) return _polygon;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_polygon);
}


/// Create a copy of TechnicalObject
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TechnicalObjectCopyWith<_TechnicalObject> get copyWith => __$TechnicalObjectCopyWithImpl<_TechnicalObject>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TechnicalObjectToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TechnicalObject&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.address, address) || other.address == address)&&(identical(other.latitude, latitude) || other.latitude == latitude)&&(identical(other.longitude, longitude) || other.longitude == longitude)&&(identical(other.status, status) || other.status == status)&&(identical(other.priority, priority) || other.priority == priority)&&(identical(other.geofenceRadius, geofenceRadius) || other.geofenceRadius == geofenceRadius)&&const DeepCollectionEquality().equals(other._polygon, _polygon));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,address,latitude,longitude,status,priority,geofenceRadius,const DeepCollectionEquality().hash(_polygon));

@override
String toString() {
  return 'TechnicalObject(id: $id, name: $name, address: $address, latitude: $latitude, longitude: $longitude, status: $status, priority: $priority, geofenceRadius: $geofenceRadius, polygon: $polygon)';
}


}

/// @nodoc
abstract mixin class _$TechnicalObjectCopyWith<$Res> implements $TechnicalObjectCopyWith<$Res> {
  factory _$TechnicalObjectCopyWith(_TechnicalObject value, $Res Function(_TechnicalObject) _then) = __$TechnicalObjectCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String address, double latitude, double longitude, ObjectStatus status, ObjectPriority priority, double geofenceRadius, List<GeoPoint> polygon
});




}
/// @nodoc
class __$TechnicalObjectCopyWithImpl<$Res>
    implements _$TechnicalObjectCopyWith<$Res> {
  __$TechnicalObjectCopyWithImpl(this._self, this._then);

  final _TechnicalObject _self;
  final $Res Function(_TechnicalObject) _then;

/// Create a copy of TechnicalObject
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? address = null,Object? latitude = null,Object? longitude = null,Object? status = null,Object? priority = null,Object? geofenceRadius = null,Object? polygon = null,}) {
  return _then(_TechnicalObject(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,address: null == address ? _self.address : address // ignore: cast_nullable_to_non_nullable
as String,latitude: null == latitude ? _self.latitude : latitude // ignore: cast_nullable_to_non_nullable
as double,longitude: null == longitude ? _self.longitude : longitude // ignore: cast_nullable_to_non_nullable
as double,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ObjectStatus,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as ObjectPriority,geofenceRadius: null == geofenceRadius ? _self.geofenceRadius : geofenceRadius // ignore: cast_nullable_to_non_nullable
as double,polygon: null == polygon ? _self._polygon : polygon // ignore: cast_nullable_to_non_nullable
as List<GeoPoint>,
  ));
}


}

// dart format on
