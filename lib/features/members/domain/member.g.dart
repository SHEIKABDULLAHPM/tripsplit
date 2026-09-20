// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'member.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Member _$MemberFromJson(Map<String, dynamic> json) => _Member(
  id: (json['id'] as num).toInt(),
  tripId: (json['tripId'] as num).toInt(),
  name: json['name'] as String,
  joinLocationId: (json['joinLocationId'] as num?)?.toInt(),
  leaveLocationId: (json['leaveLocationId'] as num?)?.toInt(),
  createdAt: DateTime.parse(json['createdAt'] as String),
);

Map<String, dynamic> _$MemberToJson(_Member instance) => <String, dynamic>{
  'id': instance.id,
  'tripId': instance.tripId,
  'name': instance.name,
  'joinLocationId': instance.joinLocationId,
  'leaveLocationId': instance.leaveLocationId,
  'createdAt': instance.createdAt.toIso8601String(),
};
