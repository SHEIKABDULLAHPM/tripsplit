import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/expense_payments.dart';
import '../tables/expenses.dart';
import '../tables/locations.dart';
import '../tables/member_segment_participations.dart';
import '../tables/team_members.dart';
import '../tables/teams.dart';
import '../tables/travel_segments.dart';
part 'journey_dao.g.dart';

/// Low-level data access for the journey model (locations, segments,
/// participation), teams, and expense payments.
@DriftAccessor(
  tables: [
    Expenses,
    Locations,
    TravelSegments,
    MemberSegmentParticipations,
    Teams,
    TeamMembers,
    ExpensePayments,
  ],
)
class JourneyDao extends DatabaseAccessor<AppDatabase> with _$JourneyDaoMixin {
  JourneyDao(super.db);

  // -- Locations --------------------------------------------------------------

  Stream<List<LocationRow>> watchLocations(int tripId) =>
      (select(locations)..where((l) => l.tripId.equals(tripId))).watch();

  Future<List<LocationRow>> getLocations(int tripId) =>
      (select(locations)..where((l) => l.tripId.equals(tripId))).get();

  Future<LocationRow?> getLocationById(int id) =>
      (select(locations)..where((l) => l.id.equals(id))).getSingleOrNull();

  Future<int> insertLocation(LocationsCompanion entry) =>
      into(locations).insert(entry);

  Future<int> deleteLocation(int id) =>
      (delete(locations)..where((l) => l.id.equals(id))).go();

  // -- Travel segments ----------------------------------------------------------

  Stream<List<TravelSegmentRow>> watchSegments(int tripId) =>
      (select(travelSegments)
            ..where((s) => s.tripId.equals(tripId))
            ..orderBy([(s) => OrderingTerm.asc(s.sequence)]))
          .watch();

  Future<List<TravelSegmentRow>> getSegments(int tripId) =>
      (select(travelSegments)
            ..where((s) => s.tripId.equals(tripId))
            ..orderBy([(s) => OrderingTerm.asc(s.sequence)]))
          .get();

  Future<void> insertSegment(TravelSegmentsCompanion entry) =>
      into(travelSegments).insert(entry);

  Future<TravelSegmentRow?> getSegmentById(int id) =>
      (select(travelSegments)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<void> updateSegment(int id, TravelSegmentsCompanion entry) async {
    await (update(travelSegments)..where((s) => s.id.equals(id))).write(entry);
  }

  Future<void> deleteSegment(int id) async {
    await (delete(travelSegments)..where((s) => s.id.equals(id))).go();
  }

  Future<void> resequenceSegments(Map<int, int> idToSequence) async {
    // Batch in one transaction so watchers get a single notification instead
    // of one per updated segment (avoiding a full screen rebuild per write).
    await db.transaction(() async {
      for (final entry in idToSequence.entries) {
        await updateSegment(
          entry.key,
          TravelSegmentsCompanion(sequence: Value(entry.value)),
        );
      }
    });
  }

  Future<void> deleteParticipationsForSegment(int segmentId) async {
    await (delete(
      memberSegmentParticipations,
    )..where((p) => p.segmentId.equals(segmentId))).go();
  }

  // -- Participation ------------------------------------------------------------

  Stream<List<MemberSegmentParticipationRow>> watchParticipations(
    int tripId,
  ) async* {
    final segmentIds = selectOnly(travelSegments)
      ..addColumns([travelSegments.id])
      ..where(travelSegments.tripId.equals(tripId));

    yield* (select(
      memberSegmentParticipations,
    )..where((p) => p.segmentId.isInQuery(segmentIds))).watch();
  }

  Future<List<MemberSegmentParticipationRow>> getParticipationsForMember(
    int memberId,
  ) => (select(
    memberSegmentParticipations,
  )..where((p) => p.memberId.equals(memberId))).get();

  Future<List<MemberSegmentParticipationRow>> getParticipations(
    int tripId,
  ) async {
    final segmentIds = selectOnly(travelSegments)
      ..addColumns([travelSegments.id])
      ..where(travelSegments.tripId.equals(tripId));

    return (select(
      memberSegmentParticipations,
    )..where((p) => p.segmentId.isInQuery(segmentIds))).get();
  }

  Future<void> upsertParticipation({
    required int memberId,
    required int segmentId,
    required bool participating,
  }) async {
    final existing =
        await (select(memberSegmentParticipations)..where(
              (p) =>
                  p.memberId.equals(memberId) & p.segmentId.equals(segmentId),
            ))
            .getSingleOrNull();
    if (existing == null) {
      await into(memberSegmentParticipations).insert(
        MemberSegmentParticipationsCompanion.insert(
          memberId: memberId,
          segmentId: segmentId,
          participating: Value(participating),
        ),
      );
    } else {
      await (update(memberSegmentParticipations)..where(
            (p) => p.memberId.equals(memberId) & p.segmentId.equals(segmentId),
          ))
          .write(
            MemberSegmentParticipationsCompanion(
              participating: Value(participating),
            ),
          );
    }
  }

  Future<void> deleteParticipationForMember(int memberId) async {
    await (delete(
      memberSegmentParticipations,
    )..where((p) => p.memberId.equals(memberId))).go();
  }

  // -- Teams ----------------------------------------------------------------------

  Stream<List<TeamRow>> watchTeams(int tripId) =>
      (select(teams)..where((t) => t.tripId.equals(tripId))).watch();

  Future<List<TeamRow>> getTeams(int tripId) =>
      (select(teams)..where((t) => t.tripId.equals(tripId))).get();

  Future<int> insertTeam(TeamsCompanion entry) => into(teams).insert(entry);

  Future<TeamRow?> getTeamById(int id) =>
      (select(teams)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> updateTeam(int id, TeamsCompanion entry) async {
    await (update(teams)..where((t) => t.id.equals(id))).write(entry);
  }

  Future<void> deleteTeam(int id) async {
    await (delete(teamMembers)..where((tm) => tm.teamId.equals(id))).go();
    await (delete(teams)..where((t) => t.id.equals(id))).go();
  }

  Future<List<TeamMemberRow>> getTeamMembers(int teamId) =>
      (select(teamMembers)..where((tm) => tm.teamId.equals(teamId))).get();

  Stream<List<TeamMemberRow>> watchTeamMembers(int teamId) =>
      (select(teamMembers)..where((tm) => tm.teamId.equals(teamId))).watch();

  Future<List<TeamMemberRow>> getTeamMembersByTrip(int tripId) {
    final teamIds = selectOnly(teams)
      ..addColumns([teams.id])
      ..where(teams.tripId.equals(tripId));
    return (select(
      teamMembers,
    )..where((tm) => tm.teamId.isInQuery(teamIds))).get();
  }

  Stream<List<TeamMemberRow>> watchTeamMembersByTrip(int tripId) {
    final teamIds = selectOnly(teams)
      ..addColumns([teams.id])
      ..where(teams.tripId.equals(tripId));
    return (select(
      teamMembers,
    )..where((tm) => tm.teamId.isInQuery(teamIds))).watch();
  }

  Future<List<TeamMemberRow>> getMembershipsForMembers(List<int> memberIds) {
    final query = select(teamMembers);
    if (memberIds.isNotEmpty) {
      query.where((tm) => tm.memberId.isIn(memberIds));
    }
    return query.get();
  }

  Future<void> addTeamMember(int teamId, int memberId) => into(
    teamMembers,
  ).insert(TeamMembersCompanion.insert(teamId: teamId, memberId: memberId));

  Future<void> removeTeamMember(int teamId, int memberId) async {
    await (delete(teamMembers)..where(
          (tm) => tm.teamId.equals(teamId) & tm.memberId.equals(memberId),
        ))
        .go();
  }

  // -- Expense payments --------------------------------------------------------------

  Stream<List<ExpensePaymentRow>> watchPaymentsByTrip(int tripId) {
    final expenseIds = selectOnly(expenses)
      ..addColumns([expenses.id])
      ..where(expenses.tripId.equals(tripId));

    return (select(
      expensePayments,
    )..where((p) => p.expenseId.isInQuery(expenseIds))).watch();
  }

  Future<List<ExpensePaymentRow>> getPaymentsByTrip(int tripId) async {
    final expenseIds = selectOnly(expenses)
      ..addColumns([expenses.id])
      ..where(expenses.tripId.equals(tripId));

    return (select(
      expensePayments,
    )..where((p) => p.expenseId.isInQuery(expenseIds))).get();
  }

  Future<List<ExpensePaymentRow>> getPaymentsFor(int expenseId) => (select(
    expensePayments,
  )..where((p) => p.expenseId.equals(expenseId))).get();

  Future<void> insertPayment(ExpensePaymentsCompanion entry) =>
      into(expensePayments).insert(entry);

  Future<void> deletePaymentsFor(int expenseId) async {
    await (delete(
      expensePayments,
    )..where((p) => p.expenseId.equals(expenseId))).go();
  }

  Future<bool> hasPaymentsByMember(int memberId) async => (await (select(
    expensePayments,
  )..where((p) => p.memberId.equals(memberId))).get()).isNotEmpty;
}
