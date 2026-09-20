// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'expense.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Expense _$ExpenseFromJson(Map<String, dynamic> json) => _Expense(
  id: (json['id'] as num).toInt(),
  tripId: (json['tripId'] as num).toInt(),
  payerMemberId: (json['payerMemberId'] as num).toInt(),
  description: json['description'] as String,
  scope:
      $enumDecodeNullable(_$ExpenseScopeEnumMap, json['scope']) ??
      ExpenseScope.shared,
  segmentId: (json['segmentId'] as num?)?.toInt(),
  teamId: (json['teamId'] as num?)?.toInt(),
  teamIds:
      (json['teamIds'] as List<dynamic>?)
          ?.map((e) => (e as num).toInt())
          .toList() ??
      const <int>[],
  amountMinor: (json['amountMinor'] as num?)?.toInt() ?? 0,
  externalAmountMinor: (json['externalAmountMinor'] as num?)?.toInt() ?? 0,
  category: json['category'] as String?,
  spentAt: json['spentAt'] == null
      ? null
      : DateTime.parse(json['spentAt'] as String),
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$ExpenseToJson(_Expense instance) => <String, dynamic>{
  'id': instance.id,
  'tripId': instance.tripId,
  'payerMemberId': instance.payerMemberId,
  'description': instance.description,
  'scope': _$ExpenseScopeEnumMap[instance.scope]!,
  'segmentId': instance.segmentId,
  'teamId': instance.teamId,
  'teamIds': instance.teamIds,
  'amountMinor': instance.amountMinor,
  'externalAmountMinor': instance.externalAmountMinor,
  'category': instance.category,
  'spentAt': instance.spentAt?.toIso8601String(),
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
};

const _$ExpenseScopeEnumMap = {
  ExpenseScope.individual: 'individual',
  ExpenseScope.shared: 'shared',
  ExpenseScope.team: 'team',
  ExpenseScope.segment: 'segment',
  ExpenseScope.custom: 'custom',
};
