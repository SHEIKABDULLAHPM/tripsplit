import '../../journey/domain/journey.dart';
import '../../members/domain/member.dart';

/// Persistence for teams and their memberships.
///
/// Teams group trip members so an expense can be scoped to a sub-group. When a
/// member is removed from a team (or a team is deleted), expenses that used
/// the team keep their explicit participant lists, so the UI flags them for
/// reconciliation rather than silently changing who owes what.
abstract interface class TeamRepository {
  Stream<List<Team>> watchTeams(int tripId);
  Future<List<Team>> getTeams(int tripId);
  Future<Team> createTeam(int tripId, String name);
  Future<void> renameTeam(int teamId, String name);

  /// Removes a team (and its memberships). Fails while expenses reference the
  /// team; reassign those expenses first.
  Future<void> deleteTeam(int teamId);

  Stream<List<Member>> watchTeamMembers(int teamId);
  Future<List<Member>> getTeamMembers(int teamId);
  Future<void> addMember({required int teamId, required int memberId});
  Future<void> removeMember({required int teamId, required int memberId});
}
