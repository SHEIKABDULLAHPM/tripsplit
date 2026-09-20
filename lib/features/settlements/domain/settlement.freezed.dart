// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'settlement.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Settlement {

 int get id; int get tripId; int get fromMemberId; int get toMemberId;/// The obligation this settlement records, in minor units.
 int get amountMinor;/// Cash actually transferred so far, in minor units. May accumulate over
/// several payments; partial settlements are fully representable.
 int get amountPaidMinor; String? get note;/// When the obligation was recorded.
 DateTime get settledAt;/// When the transfer was fully paid, if it is.
 DateTime? get paidAt; DateTime get updatedAt;
/// Create a copy of Settlement
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SettlementCopyWith<Settlement> get copyWith => _$SettlementCopyWithImpl<Settlement>(this as Settlement, _$identity);

  /// Serializes this Settlement to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Settlement&&(identical(other.id, id) || other.id == id)&&(identical(other.tripId, tripId) || other.tripId == tripId)&&(identical(other.fromMemberId, fromMemberId) || other.fromMemberId == fromMemberId)&&(identical(other.toMemberId, toMemberId) || other.toMemberId == toMemberId)&&(identical(other.amountMinor, amountMinor) || other.amountMinor == amountMinor)&&(identical(other.amountPaidMinor, amountPaidMinor) || other.amountPaidMinor == amountPaidMinor)&&(identical(other.note, note) || other.note == note)&&(identical(other.settledAt, settledAt) || other.settledAt == settledAt)&&(identical(other.paidAt, paidAt) || other.paidAt == paidAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,tripId,fromMemberId,toMemberId,amountMinor,amountPaidMinor,note,settledAt,paidAt,updatedAt);

@override
String toString() {
  return 'Settlement(id: $id, tripId: $tripId, fromMemberId: $fromMemberId, toMemberId: $toMemberId, amountMinor: $amountMinor, amountPaidMinor: $amountPaidMinor, note: $note, settledAt: $settledAt, paidAt: $paidAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $SettlementCopyWith<$Res>  {
  factory $SettlementCopyWith(Settlement value, $Res Function(Settlement) _then) = _$SettlementCopyWithImpl;
@useResult
$Res call({
 int id, int tripId, int fromMemberId, int toMemberId, int amountMinor, int amountPaidMinor, String? note, DateTime settledAt, DateTime? paidAt, DateTime updatedAt
});




}
/// @nodoc
class _$SettlementCopyWithImpl<$Res>
    implements $SettlementCopyWith<$Res> {
  _$SettlementCopyWithImpl(this._self, this._then);

  final Settlement _self;
  final $Res Function(Settlement) _then;

/// Create a copy of Settlement
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? tripId = null,Object? fromMemberId = null,Object? toMemberId = null,Object? amountMinor = null,Object? amountPaidMinor = null,Object? note = freezed,Object? settledAt = null,Object? paidAt = freezed,Object? updatedAt = null,}) {
  return _then(Settlement(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,tripId: null == tripId ? _self.tripId : tripId // ignore: cast_nullable_to_non_nullable
as int,fromMemberId: null == fromMemberId ? _self.fromMemberId : fromMemberId // ignore: cast_nullable_to_non_nullable
as int,toMemberId: null == toMemberId ? _self.toMemberId : toMemberId // ignore: cast_nullable_to_non_nullable
as int,amountMinor: null == amountMinor ? _self.amountMinor : amountMinor // ignore: cast_nullable_to_non_nullable
as int,amountPaidMinor: null == amountPaidMinor ? _self.amountPaidMinor : amountPaidMinor // ignore: cast_nullable_to_non_nullable
as int,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,settledAt: null == settledAt ? _self.settledAt : settledAt // ignore: cast_nullable_to_non_nullable
as DateTime,paidAt: freezed == paidAt ? _self.paidAt : paidAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [Settlement].
extension SettlementPatterns on Settlement {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Settlement value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Settlement() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Settlement value)  $default,){
final _that = this;
switch (_that) {
case _Settlement():
return $default(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Settlement value)?  $default,){
final _that = this;
switch (_that) {
case _Settlement() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  int tripId,  int fromMemberId,  int toMemberId,  int amountMinor,  int amountPaidMinor,  String? note,  DateTime settledAt,  DateTime? paidAt,  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Settlement() when $default != null:
return $default(_that.id,_that.tripId,_that.fromMemberId,_that.toMemberId,_that.amountMinor,_that.amountPaidMinor,_that.note,_that.settledAt,_that.paidAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  int tripId,  int fromMemberId,  int toMemberId,  int amountMinor,  int amountPaidMinor,  String? note,  DateTime settledAt,  DateTime? paidAt,  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _Settlement():
return $default(_that.id,_that.tripId,_that.fromMemberId,_that.toMemberId,_that.amountMinor,_that.amountPaidMinor,_that.note,_that.settledAt,_that.paidAt,_that.updatedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  int tripId,  int fromMemberId,  int toMemberId,  int amountMinor,  int amountPaidMinor,  String? note,  DateTime settledAt,  DateTime? paidAt,  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Settlement() when $default != null:
return $default(_that.id,_that.tripId,_that.fromMemberId,_that.toMemberId,_that.amountMinor,_that.amountPaidMinor,_that.note,_that.settledAt,_that.paidAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Settlement extends Settlement {
  const _Settlement({required this.id, required this.tripId, required this.fromMemberId, required this.toMemberId, this.amountMinor = 0, this.amountPaidMinor = 0, this.note, required this.settledAt, this.paidAt, required this.updatedAt}): super._();
  factory _Settlement.fromJson(Map<String, dynamic> json) => _$SettlementFromJson(json);

@override final  int id;
@override final  int tripId;
@override final  int fromMemberId;
@override final  int toMemberId;
/// The obligation this settlement records, in minor units.
@override@JsonKey() final  int amountMinor;
/// Cash actually transferred so far, in minor units. May accumulate over
/// several payments; partial settlements are fully representable.
@override@JsonKey() final  int amountPaidMinor;
@override final  String? note;
/// When the obligation was recorded.
@override final  DateTime settledAt;
/// When the transfer was fully paid, if it is.
@override final  DateTime? paidAt;
@override final  DateTime updatedAt;

/// Create a copy of Settlement
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SettlementCopyWith<_Settlement> get copyWith => __$SettlementCopyWithImpl<_Settlement>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SettlementToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Settlement&&(identical(other.id, id) || other.id == id)&&(identical(other.tripId, tripId) || other.tripId == tripId)&&(identical(other.fromMemberId, fromMemberId) || other.fromMemberId == fromMemberId)&&(identical(other.toMemberId, toMemberId) || other.toMemberId == toMemberId)&&(identical(other.amountMinor, amountMinor) || other.amountMinor == amountMinor)&&(identical(other.amountPaidMinor, amountPaidMinor) || other.amountPaidMinor == amountPaidMinor)&&(identical(other.note, note) || other.note == note)&&(identical(other.settledAt, settledAt) || other.settledAt == settledAt)&&(identical(other.paidAt, paidAt) || other.paidAt == paidAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,tripId,fromMemberId,toMemberId,amountMinor,amountPaidMinor,note,settledAt,paidAt,updatedAt);

@override
String toString() {
  return 'Settlement(id: $id, tripId: $tripId, fromMemberId: $fromMemberId, toMemberId: $toMemberId, amountMinor: $amountMinor, amountPaidMinor: $amountPaidMinor, note: $note, settledAt: $settledAt, paidAt: $paidAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$SettlementCopyWith<$Res> implements $SettlementCopyWith<$Res> {
  factory _$SettlementCopyWith(_Settlement value, $Res Function(_Settlement) _then) = __$SettlementCopyWithImpl;
@override @useResult
$Res call({
 int id, int tripId, int fromMemberId, int toMemberId, int amountMinor, int amountPaidMinor, String? note, DateTime settledAt, DateTime? paidAt, DateTime updatedAt
});




}
/// @nodoc
class __$SettlementCopyWithImpl<$Res>
    implements _$SettlementCopyWith<$Res> {
  __$SettlementCopyWithImpl(this._self, this._then);

  final _Settlement _self;
  final $Res Function(_Settlement) _then;

/// Create a copy of Settlement
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? tripId = null,Object? fromMemberId = null,Object? toMemberId = null,Object? amountMinor = null,Object? amountPaidMinor = null,Object? note = freezed,Object? settledAt = null,Object? paidAt = freezed,Object? updatedAt = null,}) {
  return _then(_Settlement(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,tripId: null == tripId ? _self.tripId : tripId // ignore: cast_nullable_to_non_nullable
as int,fromMemberId: null == fromMemberId ? _self.fromMemberId : fromMemberId // ignore: cast_nullable_to_non_nullable
as int,toMemberId: null == toMemberId ? _self.toMemberId : toMemberId // ignore: cast_nullable_to_non_nullable
as int,amountMinor: null == amountMinor ? _self.amountMinor : amountMinor // ignore: cast_nullable_to_non_nullable
as int,amountPaidMinor: null == amountPaidMinor ? _self.amountPaidMinor : amountPaidMinor // ignore: cast_nullable_to_non_nullable
as int,note: freezed == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String?,settledAt: null == settledAt ? _self.settledAt : settledAt // ignore: cast_nullable_to_non_nullable
as DateTime,paidAt: freezed == paidAt ? _self.paidAt : paidAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
