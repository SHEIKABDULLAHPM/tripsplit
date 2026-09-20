// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settlement.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Settlement _$SettlementFromJson(Map<String, dynamic> json) => _Settlement(
  id: (json['id'] as num).toInt(),
  tripId: (json['tripId'] as num).toInt(),
  fromMemberId: (json['fromMemberId'] as num).toInt(),
  toMemberId: (json['toMemberId'] as num).toInt(),
  amountMinor: (json['amountMinor'] as num?)?.toInt() ?? 0,
  amountPaidMinor: (json['amountPaidMinor'] as num?)?.toInt() ?? 0,
  note: json['note'] as String?,
  settledAt: DateTime.parse(json['settledAt'] as String),
  paidAt: json['paidAt'] == null
      ? null
      : DateTime.parse(json['paidAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
);

Map<String, dynamic> _$SettlementToJson(_Settlement instance) =>
    <String, dynamic>{
      'id': instance.id,
      'tripId': instance.tripId,
      'fromMemberId': instance.fromMemberId,
      'toMemberId': instance.toMemberId,
      'amountMinor': instance.amountMinor,
      'amountPaidMinor': instance.amountPaidMinor,
      'note': instance.note,
      'settledAt': instance.settledAt.toIso8601String(),
      'paidAt': instance.paidAt?.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };
