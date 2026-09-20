// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'journey_dao.dart';

// ignore_for_file: type=lint
mixin _$JourneyDaoMixin on DatabaseAccessor<AppDatabase> {
  $TripsTable get trips => attachedDatabase.trips;
  $LocationsTable get locations => attachedDatabase.locations;
  $MembersTable get members => attachedDatabase.members;
  $TravelSegmentsTable get travelSegments => attachedDatabase.travelSegments;
  $TeamsTable get teams => attachedDatabase.teams;
  $ExpensesTable get expenses => attachedDatabase.expenses;
  $MemberSegmentParticipationsTable get memberSegmentParticipations =>
      attachedDatabase.memberSegmentParticipations;
  $TeamMembersTable get teamMembers => attachedDatabase.teamMembers;
  $ExpensePaymentsTable get expensePayments => attachedDatabase.expensePayments;
  JourneyDaoManager get managers => JourneyDaoManager(this);
}

class JourneyDaoManager {
  final _$JourneyDaoMixin _db;
  JourneyDaoManager(this._db);
  $$TripsTableTableManager get trips =>
      $$TripsTableTableManager(_db.attachedDatabase, _db.trips);
  $$LocationsTableTableManager get locations =>
      $$LocationsTableTableManager(_db.attachedDatabase, _db.locations);
  $$MembersTableTableManager get members =>
      $$MembersTableTableManager(_db.attachedDatabase, _db.members);
  $$TravelSegmentsTableTableManager get travelSegments =>
      $$TravelSegmentsTableTableManager(
        _db.attachedDatabase,
        _db.travelSegments,
      );
  $$TeamsTableTableManager get teams =>
      $$TeamsTableTableManager(_db.attachedDatabase, _db.teams);
  $$ExpensesTableTableManager get expenses =>
      $$ExpensesTableTableManager(_db.attachedDatabase, _db.expenses);
  $$MemberSegmentParticipationsTableTableManager
  get memberSegmentParticipations =>
      $$MemberSegmentParticipationsTableTableManager(
        _db.attachedDatabase,
        _db.memberSegmentParticipations,
      );
  $$TeamMembersTableTableManager get teamMembers =>
      $$TeamMembersTableTableManager(_db.attachedDatabase, _db.teamMembers);
  $$ExpensePaymentsTableTableManager get expensePayments =>
      $$ExpensePaymentsTableTableManager(
        _db.attachedDatabase,
        _db.expensePayments,
      );
}
