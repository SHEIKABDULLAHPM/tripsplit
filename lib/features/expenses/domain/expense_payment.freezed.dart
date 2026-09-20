// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'expense_payment.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$ExpensePayment {

 int get id; int get expenseId; int get memberId; int get amountMinor;/// Team this payer paid on behalf of, when team-scoped. Must be a team the
/// payer belongs to.
 int? get teamId;
/// Create a copy of ExpensePayment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExpensePaymentCopyWith<ExpensePayment> get copyWith => _$ExpensePaymentCopyWithImpl<ExpensePayment>(this as ExpensePayment, _$identity);

  /// Serializes this ExpensePayment to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExpensePayment&&(identical(other.id, id) || other.id == id)&&(identical(other.expenseId, expenseId) || other.expenseId == expenseId)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.amountMinor, amountMinor) || other.amountMinor == amountMinor)&&(identical(other.teamId, teamId) || other.teamId == teamId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,expenseId,memberId,amountMinor,teamId);

@override
String toString() {
  return 'ExpensePayment(id: $id, expenseId: $expenseId, memberId: $memberId, amountMinor: $amountMinor, teamId: $teamId)';
}


}

/// @nodoc
abstract mixin class $ExpensePaymentCopyWith<$Res>  {
  factory $ExpensePaymentCopyWith(ExpensePayment value, $Res Function(ExpensePayment) _then) = _$ExpensePaymentCopyWithImpl;
@useResult
$Res call({
 int id, int expenseId, int memberId, int amountMinor, int? teamId
});




}
/// @nodoc
class _$ExpensePaymentCopyWithImpl<$Res>
    implements $ExpensePaymentCopyWith<$Res> {
  _$ExpensePaymentCopyWithImpl(this._self, this._then);

  final ExpensePayment _self;
  final $Res Function(ExpensePayment) _then;

/// Create a copy of ExpensePayment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? expenseId = null,Object? memberId = null,Object? amountMinor = null,Object? teamId = freezed,}) {
  return _then(ExpensePayment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,expenseId: null == expenseId ? _self.expenseId : expenseId // ignore: cast_nullable_to_non_nullable
as int,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as int,amountMinor: null == amountMinor ? _self.amountMinor : amountMinor // ignore: cast_nullable_to_non_nullable
as int,teamId: freezed == teamId ? _self.teamId : teamId // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [ExpensePayment].
extension ExpensePaymentPatterns on ExpensePayment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ExpensePayment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ExpensePayment() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ExpensePayment value)  $default,){
final _that = this;
switch (_that) {
case _ExpensePayment():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ExpensePayment value)?  $default,){
final _that = this;
switch (_that) {
case _ExpensePayment() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  int expenseId,  int memberId,  int amountMinor,  int? teamId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ExpensePayment() when $default != null:
return $default(_that.id,_that.expenseId,_that.memberId,_that.amountMinor,_that.teamId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  int expenseId,  int memberId,  int amountMinor,  int? teamId)  $default,) {final _that = this;
switch (_that) {
case _ExpensePayment():
return $default(_that.id,_that.expenseId,_that.memberId,_that.amountMinor,_that.teamId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  int expenseId,  int memberId,  int amountMinor,  int? teamId)?  $default,) {final _that = this;
switch (_that) {
case _ExpensePayment() when $default != null:
return $default(_that.id,_that.expenseId,_that.memberId,_that.amountMinor,_that.teamId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ExpensePayment implements ExpensePayment {
  const _ExpensePayment({required this.id, required this.expenseId, required this.memberId, this.amountMinor = 0, this.teamId});
  factory _ExpensePayment.fromJson(Map<String, dynamic> json) => _$ExpensePaymentFromJson(json);

@override final  int id;
@override final  int expenseId;
@override final  int memberId;
@override@JsonKey() final  int amountMinor;
/// Team this payer paid on behalf of, when team-scoped. Must be a team the
/// payer belongs to.
@override final  int? teamId;

/// Create a copy of ExpensePayment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ExpensePaymentCopyWith<_ExpensePayment> get copyWith => __$ExpensePaymentCopyWithImpl<_ExpensePayment>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ExpensePaymentToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ExpensePayment&&(identical(other.id, id) || other.id == id)&&(identical(other.expenseId, expenseId) || other.expenseId == expenseId)&&(identical(other.memberId, memberId) || other.memberId == memberId)&&(identical(other.amountMinor, amountMinor) || other.amountMinor == amountMinor)&&(identical(other.teamId, teamId) || other.teamId == teamId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,expenseId,memberId,amountMinor,teamId);

@override
String toString() {
  return 'ExpensePayment(id: $id, expenseId: $expenseId, memberId: $memberId, amountMinor: $amountMinor, teamId: $teamId)';
}


}

/// @nodoc
abstract mixin class _$ExpensePaymentCopyWith<$Res> implements $ExpensePaymentCopyWith<$Res> {
  factory _$ExpensePaymentCopyWith(_ExpensePayment value, $Res Function(_ExpensePayment) _then) = __$ExpensePaymentCopyWithImpl;
@override @useResult
$Res call({
 int id, int expenseId, int memberId, int amountMinor, int? teamId
});




}
/// @nodoc
class __$ExpensePaymentCopyWithImpl<$Res>
    implements _$ExpensePaymentCopyWith<$Res> {
  __$ExpensePaymentCopyWithImpl(this._self, this._then);

  final _ExpensePayment _self;
  final $Res Function(_ExpensePayment) _then;

/// Create a copy of ExpensePayment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? expenseId = null,Object? memberId = null,Object? amountMinor = null,Object? teamId = freezed,}) {
  return _then(_ExpensePayment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,expenseId: null == expenseId ? _self.expenseId : expenseId // ignore: cast_nullable_to_non_nullable
as int,memberId: null == memberId ? _self.memberId : memberId // ignore: cast_nullable_to_non_nullable
as int,amountMinor: null == amountMinor ? _self.amountMinor : amountMinor // ignore: cast_nullable_to_non_nullable
as int,teamId: freezed == teamId ? _self.teamId : teamId // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
