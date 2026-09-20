// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'expense_dao.dart';

// ignore_for_file: type=lint
mixin _$ExpenseDaoMixin on DatabaseAccessor<AppDatabase> {
  $TripsTable get trips => attachedDatabase.trips;
  $LocationsTable get locations => attachedDatabase.locations;
  $MembersTable get members => attachedDatabase.members;
  $TravelSegmentsTable get travelSegments => attachedDatabase.travelSegments;
  $TeamsTable get teams => attachedDatabase.teams;
  $ExpensesTable get expenses => attachedDatabase.expenses;
  $ExpenseSharesTable get expenseShares => attachedDatabase.expenseShares;
  $ExpenseTeamsTable get expenseTeams => attachedDatabase.expenseTeams;
  ExpenseDaoManager get managers => ExpenseDaoManager(this);
}

class ExpenseDaoManager {
  final _$ExpenseDaoMixin _db;
  ExpenseDaoManager(this._db);
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
  $$ExpenseSharesTableTableManager get expenseShares =>
      $$ExpenseSharesTableTableManager(_db.attachedDatabase, _db.expenseShares);
  $$ExpenseTeamsTableTableManager get expenseTeams =>
      $$ExpenseTeamsTableTableManager(_db.attachedDatabase, _db.expenseTeams);
}
