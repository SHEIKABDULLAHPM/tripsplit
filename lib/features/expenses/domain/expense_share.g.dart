// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'expense_share.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ExpenseShare _$ExpenseShareFromJson(Map<String, dynamic> json) =>
    _ExpenseShare(
      id: (json['id'] as num).toInt(),
      expenseId: (json['expenseId'] as num).toInt(),
      memberId: (json['memberId'] as num).toInt(),
      shareMinor: (json['shareMinor'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$ExpenseShareToJson(_ExpenseShare instance) =>
    <String, dynamic>{
      'id': instance.id,
      'expenseId': instance.expenseId,
      'memberId': instance.memberId,
      'shareMinor': instance.shareMinor,
    };
