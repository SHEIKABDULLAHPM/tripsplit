// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'expense_share.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ExpenseShare {

 int get id; int get expenseId; int get memberId; int get shareMinor;
/// Create a copy of ExpenseShare
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExpenseShareCopyWith<ExpenseShare> get copyWith => _$ExpenseShareCopyWithImpl<ExpenseShare>(this as ExpenseShare, _$identity);

  /// Serializes this ExpenseShare to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExpenseShare&&(identical(other.id, id) || other.id == id)&&(identical(other.expenseId, expenseId) || other.expenseId == expenseId)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.shareMinor, shareMinor) || other.shareMinor == shareMinor));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,expenseId,memberId,shareMinor);

@override
String toString() {
  return 'ExpenseShare(id: $id, expenseId: $expenseId, memberId: $memberId, shareMinor: $shareMinor)';
}


}

/// @nodoc
abstract mixin class $ExpenseShareCopyWith<$Res>  {
  factory $ExpenseShareCopyWith(ExpenseShare value, $Res Function(ExpenseShare) _then) = _$ExpenseShareCopyWithImpl;
@useResult
$Res call({
 int id, int expenseId, int memberId, int shareMinor
});




}
/// @nodoc
class _$ExpenseShareCopyWithImpl<$Res>
    implements $ExpenseShareCopyWith<$Res> {
  _$ExpenseShareCopyWithImpl(this._self, this._then);

  final ExpenseShare _self;
  final $Res Function(ExpenseShare) _then;

/// Create a copy of ExpenseShare
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? expenseId = null,Object? memberId = null,Object? shareMinor = null,}) {
  return _then(ExpenseShare(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,expenseId: null == expenseId ? _self.expenseId : expenseId // ignore: cast_nullable_to_non_nullable
as int,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as int,shareMinor: null == shareMinor ? _self.shareMinor : shareMinor // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ExpenseShare].
extension ExpenseSharePatterns on ExpenseShare {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ExpenseShare value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ExpenseShare() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ExpenseShare value)  $default,){
final _that = this;
switch (_that) {
case _ExpenseShare():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ExpenseShare value)?  $default,){
final _that = this;
switch (_that) {
case _ExpenseShare() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  int expenseId,  int memberId,  int shareMinor)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ExpenseShare() when $default != null:
return $default(_that.id,_that.expenseId,_that.memberId,_that.shareMinor);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  int expenseId,  int memberId,  int shareMinor)  $default,) {final _that = this;
switch (_that) {
case _ExpenseShare():
return $default(_that.id,_that.expenseId,_that.memberId,_that.shareMinor);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  int expenseId,  int memberId,  int shareMinor)?  $default,) {final _that = this;
switch (_that) {
case _ExpenseShare() when $default != null:
return $default(_that.id,_that.expenseId,_that.memberId,_that.shareMinor);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ExpenseShare implements ExpenseShare {
  const _ExpenseShare({required this.id, required this.expenseId, required this.memberId, this.shareMinor = 0});
  factory _ExpenseShare.fromJson(Map<String, dynamic> json) => _$ExpenseShareFromJson(json);

@override final  int id;
@override final  int expenseId;
@override final  int memberId;
@override@JsonKey() final  int shareMinor;

/// Create a copy of ExpenseShare
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ExpenseShareCopyWith<_ExpenseShare> get copyWith => __$ExpenseShareCopyWithImpl<_ExpenseShare>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ExpenseShareToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ExpenseShare&&(identical(other.id, id) || other.id == id)&&(identical(other.expenseId, expenseId) || other.expenseId == expenseId)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.shareMinor, shareMinor) || other.shareMinor == shareMinor));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,expenseId,memberId,shareMinor);

@override
String toString() {
  return 'ExpenseShare(id: $id, expenseId: $expenseId, memberId: $memberId, shareMinor: $shareMinor)';
}


}

/// @nodoc
abstract mixin class _$ExpenseShareCopyWith<$Res> implements $ExpenseShareCopyWith<$Res> {
  factory _$ExpenseShareCopyWith(_ExpenseShare value, $Res Function(_ExpenseShare) _then) = __$ExpenseShareCopyWithImpl;
@override @useResult
$Res call({
 int id, int expenseId, int memberId, int shareMinor
});




}
/// @nodoc
class __$ExpenseShareCopyWithImpl<$Res>
    implements _$ExpenseShareCopyWith<$Res> {
  __$ExpenseShareCopyWithImpl(this._self, this._then);

  final _ExpenseShare _self;
  final $Res Function(_ExpenseShare) _then;

/// Create a copy of ExpenseShare
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? expenseId = null,Object? memberId = null,Object? shareMinor = null,}) {
  return _then(_ExpenseShare(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,expenseId: null == expenseId ? _self.expenseId : expenseId // ignore: cast_nullable_to_non_nullable
as int,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as int,shareMinor: null == shareMinor ? _self.shareMinor : shareMinor // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
