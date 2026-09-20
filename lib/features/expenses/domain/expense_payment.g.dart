// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'expense_payment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ExpensePayment _$ExpensePaymentFromJson(Map<String, dynamic> json) =>
    _ExpensePayment(
      id: (json['id'] as num).toInt(),
      expenseId: (json['expenseId'] as num).toInt(),
      memberId: (json['memberId'] as num).toInt(),
      amountMinor: (json['amountMinor'] as num?)?.toInt() ?? 0,
      teamId: (json['teamId'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ExpensePaymentToJson(_ExpensePayment instance) =>
    <String, dynamic>{
      'id': instance.id,
      'expenseId': instance.expenseId,
      'memberId': instance.memberId,
      'amountMinor': instance.amountMinor,
      'teamId': instance.teamId,
    };
