// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'contribution.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Contribution _$ContributionFromJson(Map<String, dynamic> json) =>
    _Contribution(
      id: (json['id'] as num).toInt(),
      tripId: (json['tripId'] as num).toInt(),
      memberId: (json['memberId'] as num).toInt(),
      amountMinor: (json['amountMinor'] as num?)?.toInt() ?? 0,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$ContributionToJson(_Contribution instance) =>
    <String, dynamic>{
      'id': instance.id,
      'tripId': instance.tripId,
      'memberId': instance.memberId,
      'amountMinor': instance.amountMinor,
      'note': instance.note,
      'createdAt': instance.createdAt.toIso8601String(),
    };
