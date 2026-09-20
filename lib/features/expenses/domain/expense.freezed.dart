// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'expense.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$Expense {

 int get id; int get tripId;/// Primary payer of the expense (kept for display and migration
/// compatibility; payment rows are authoritative for calculations).
 int get payerMemberId; String get description;/// What the expense applies to; drives participant defaults.
 ExpenseScope get scope;/// Travel segment this expense belongs to, when segment-based.
 int? get segmentId;/// Team this expense applies to, when team-scoped.
 int? get teamId;/// Every team this expense applies to, when team-scoped. The join rows
/// behind this are authoritative; [teamId] mirrors the first entry for
/// back-compatibility with older consumers.
 List<int> get teamIds; int get amountMinor;/// Cash paid by the payer that is not shared with the group.
 int get externalAmountMinor; String? get category; DateTime? get spentAt; DateTime get createdAt; DateTime get updatedAt;
/// Create a copy of Expense
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExpenseCopyWith<Expense> get copyWith => _$ExpenseCopyWithImpl<Expense>(this as Expense, _$identity);

  /// Serializes this Expense to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Expense&&(identical(other.id, id) || other.id == id)&&(identical(other.tripId, tripId) || other.tripId == tripId)&&(identical(other.payerMemberId, payerMemberId) || other.payerMemberId == payerMemberId)&&(identical(other.description, description) || other.description == description)&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.segmentId, segmentId) || other.segmentId == segmentId)&&(identical(other.teamId, teamId) || other.teamId == teamId)&&const DeepCollectionEquality().equals(other.teamIds, teamIds)&&(identical(other.amountMinor, amountMinor) || other.amountMinor == amountMinor)&&(identical(other.externalAmountMinor, externalAmountMinor) || other.externalAmountMinor == externalAmountMinor)&&(identical(other.category, category) || other.category == category)&&(identical(other.spentAt, spentAt) || other.spentAt == spentAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,tripId,payerMemberId,description,scope,segmentId,teamId,const DeepCollectionEquality().hash(teamIds),amountMinor,externalAmountMinor,category,spentAt,createdAt,updatedAt);

@override
String toString() {
  return 'Expense(id: $id, tripId: $tripId, payerMemberId: $payerMemberId, description: $description, scope: $scope, segmentId: $segmentId, teamId: $teamId, teamIds: $teamIds, amountMinor: $amountMinor, externalAmountMinor: $externalAmountMinor, category: $category, spentAt: $spentAt, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $ExpenseCopyWith<$Res>  {
  factory $ExpenseCopyWith(Expense value, $Res Function(Expense) _then) = _$ExpenseCopyWithImpl;
@useResult
$Res call({
 int id, int tripId, int payerMemberId, String description, ExpenseScope scope, int? segmentId, int? teamId, List<int> teamIds, int amountMinor, int externalAmountMinor, String? category, DateTime? spentAt, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class _$ExpenseCopyWithImpl<$Res>
    implements $ExpenseCopyWith<$Res> {
  _$ExpenseCopyWithImpl(this._self, this._then);

  final Expense _self;
  final $Res Function(Expense) _then;

/// Create a copy of Expense
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? tripId = null,Object? payerMemberId = null,Object? description = null,Object? scope = null,Object? segmentId = freezed,Object? teamId = freezed,Object? teamIds = null,Object? amountMinor = null,Object? externalAmountMinor = null,Object? category = freezed,Object? spentAt = freezed,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(Expense(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,tripId: null == tripId ? _self.tripId : tripId // ignore: cast_nullable_to_non_nullable
as int,payerMemberId: null == payerMemberId ? _self.payerMemberId : payerMemberId // ignore: cast_nullable_to_non_nullable
as int,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ExpenseScope,segmentId: freezed == segmentId ? _self.segmentId : segmentId // ignore: cast_nullable_to_non_nullable
as int?,teamId: freezed == teamId ? _self.teamId : teamId // ignore: cast_nullable_to_non_nullable
as int?,teamIds: null == teamIds ? _self.teamIds : teamIds // ignore: cast_nullable_to_non_nullable
as List<int>,amountMinor: null == amountMinor ? _self.amountMinor : amountMinor // ignore: cast_nullable_to_non_nullable
as int,externalAmountMinor: null == externalAmountMinor ? _self.externalAmountMinor : externalAmountMinor // ignore: cast_nullable_to_non_nullable
as int,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,spentAt: freezed == spentAt ? _self.spentAt : spentAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [Expense].
extension ExpensePatterns on Expense {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Expense value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Expense() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Expense value)  $default,){
final _that = this;
switch (_that) {
case _Expense():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Expense value)?  $default,){
final _that = this;
switch (_that) {
case _Expense() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int id,  int tripId,  int payerMemberId,  String description,  ExpenseScope scope,  int? segmentId,  int? teamId,  List<int> teamIds,  int amountMinor,  int externalAmountMinor,  String? category,  DateTime? spentAt,  DateTime createdAt,  DateTime updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Expense() when $default != null:
return $default(_that.id,_that.tripId,_that.payerMemberId,_that.description,_that.scope,_that.segmentId,_that.teamId,_that.teamIds,_that.amountMinor,_that.externalAmountMinor,_that.category,_that.spentAt,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int id,  int tripId,  int payerMemberId,  String description,  ExpenseScope scope,  int? segmentId,  int? teamId,  List<int> teamIds,  int amountMinor,  int externalAmountMinor,  String? category,  DateTime? spentAt,  DateTime createdAt,  DateTime updatedAt)  $default,) {final _that = this;
switch (_that) {
case _Expense():
return $default(_that.id,_that.tripId,_that.payerMemberId,_that.description,_that.scope,_that.segmentId,_that.teamId,_that.teamIds,_that.amountMinor,_that.externalAmountMinor,_that.category,_that.spentAt,_that.createdAt,_that.updatedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int id,  int tripId,  int payerMemberId,  String description,  ExpenseScope scope,  int? segmentId,  int? teamId,  List<int> teamIds,  int amountMinor,  int externalAmountMinor,  String? category,  DateTime? spentAt,  DateTime createdAt,  DateTime updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Expense() when $default != null:
return $default(_that.id,_that.tripId,_that.payerMemberId,_that.description,_that.scope,_that.segmentId,_that.teamId,_that.teamIds,_that.amountMinor,_that.externalAmountMinor,_that.category,_that.spentAt,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Expense implements Expense {
  const _Expense({required this.id, required this.tripId, required this.payerMemberId, required this.description, this.scope = ExpenseScope.shared, this.segmentId, this.teamId,  List<int> teamIds = const <int>[], this.amountMinor = 0, this.externalAmountMinor = 0, this.category, this.spentAt, required this.createdAt, required this.updatedAt}): _teamIds = teamIds;
  factory _Expense.fromJson(Map<String, dynamic> json) => _$ExpenseFromJson(json);

@override final  int id;
@override final  int tripId;
/// Primary payer of the expense (kept for display and migration
/// compatibility; payment rows are authoritative for calculations).
@override final  int payerMemberId;
@override final  String description;
/// What the expense applies to; drives participant defaults.
@override@JsonKey() final  ExpenseScope scope;
/// Travel segment this expense belongs to, when segment-based.
@override final  int? segmentId;
/// Team this expense applies to, when team-scoped.
@override final  int? teamId;
/// Every team this expense applies to, when team-scoped. The join rows
/// behind this are authoritative; [teamId] mirrors the first entry for
/// back-compatibility with older consumers.
 final  List<int> _teamIds;
/// Every team this expense applies to, when team-scoped. The join rows
/// behind this are authoritative; [teamId] mirrors the first entry for
/// back-compatibility with older consumers.
@override@JsonKey() List<int> get teamIds {
  if (_teamIds is EqualUnmodifiableListView) return _teamIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_teamIds);
}

@override@JsonKey() final  int amountMinor;
/// Cash paid by the payer that is not shared with the group.
@override@JsonKey() final  int externalAmountMinor;
@override final  String? category;
@override final  DateTime? spentAt;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;

/// Create a copy of Expense
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ExpenseCopyWith<_Expense> get copyWith => __$ExpenseCopyWithImpl<_Expense>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ExpenseToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Expense&&(identical(other.id, id) || other.id == id)&&(identical(other.tripId, tripId) || other.tripId == tripId)&&(identical(other.payerMemberId, payerMemberId) || other.payerMemberId == payerMemberId)&&(identical(other.description, description) || other.description == description)&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.segmentId, segmentId) || other.segmentId == segmentId)&&(identical(other.teamId, teamId) || other.teamId == teamId)&&const DeepCollectionEquality().equals(other._teamIds, _teamIds)&&(identical(other.amountMinor, amountMinor) || other.amountMinor == amountMinor)&&(identical(other.externalAmountMinor, externalAmountMinor) || other.externalAmountMinor == externalAmountMinor)&&(identical(other.category, category) || other.category == category)&&(identical(other.spentAt, spentAt) || other.spentAt == spentAt)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,tripId,payerMemberId,description,scope,segmentId,teamId,const DeepCollectionEquality().hash(_teamIds),amountMinor,externalAmountMinor,category,spentAt,createdAt,updatedAt);

@override
String toString() {
  return 'Expense(id: $id, tripId: $tripId, payerMemberId: $payerMemberId, description: $description, scope: $scope, segmentId: $segmentId, teamId: $teamId, teamIds: $teamIds, amountMinor: $amountMinor, externalAmountMinor: $externalAmountMinor, category: $category, spentAt: $spentAt, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$ExpenseCopyWith<$Res> implements $ExpenseCopyWith<$Res> {
  factory _$ExpenseCopyWith(_Expense value, $Res Function(_Expense) _then) = __$ExpenseCopyWithImpl;
@override @useResult
$Res call({
 int id, int tripId, int payerMemberId, String description, ExpenseScope scope, int? segmentId, int? teamId, List<int> teamIds, int amountMinor, int externalAmountMinor, String? category, DateTime? spentAt, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class __$ExpenseCopyWithImpl<$Res>
    implements _$ExpenseCopyWith<$Res> {
  __$ExpenseCopyWithImpl(this._self, this._then);

  final _Expense _self;
  final $Res Function(_Expense) _then;

/// Create a copy of Expense
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? tripId = null,Object? payerMemberId = null,Object? description = null,Object? scope = null,Object? segmentId = freezed,Object? teamId = freezed,Object? teamIds = null,Object? amountMinor = null,Object? externalAmountMinor = null,Object? category = freezed,Object? spentAt = freezed,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_Expense(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as int,tripId: null == tripId ? _self.tripId : tripId // ignore: cast_nullable_to_non_nullable
as int,payerMemberId: null == payerMemberId ? _self.payerMemberId : payerMemberId // ignore: cast_nullable_to_non_nullable
as int,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as ExpenseScope,segmentId: freezed == segmentId ? _self.segmentId : segmentId // ignore: cast_nullable_to_non_nullable
as int?,teamId: freezed == teamId ? _self.teamId : teamId // ignore: cast_nullable_to_non_nullable
as int?,teamIds: null == teamIds ? _self._teamIds : teamIds // ignore: cast_nullable_to_non_nullable
as List<int>,amountMinor: null == amountMinor ? _self.amountMinor : amountMinor // ignore: cast_nullable_to_non_nullable
as int,externalAmountMinor: null == externalAmountMinor ? _self.externalAmountMinor : externalAmountMinor // ignore: cast_nullable_to_non_nullable
as int,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as String?,spentAt: freezed == spentAt ? _self.spentAt : spentAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
