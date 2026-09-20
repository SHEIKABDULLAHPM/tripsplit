import 'package:drift/drift.dart';

import 'members.dart';
import 'teams.dart';

/// Membership of a member in a team.
@DataClassName('TeamMemberRow')
@TableIndex(name: 'idx_team_members_team', columns: {#teamId})
@TableIndex(name: 'idx_team_members_member', columns: {#memberId})
class TeamMembers extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get teamId =>
      integer().references(Teams, #id, onDelete: KeyAction.cascade)();
  IntColumn get memberId =>
      integer().references(Members, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  @override
  List<Set<Column>> get uniqueKeys => [
    {teamId, memberId},
  ];
}
