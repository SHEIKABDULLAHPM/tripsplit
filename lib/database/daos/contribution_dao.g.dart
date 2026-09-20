// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'contribution_dao.dart';

// ignore_for_file: type=lint
mixin _$ContributionDaoMixin on DatabaseAccessor<AppDatabase> {
  $TripsTable get trips => attachedDatabase.trips;
  $LocationsTable get locations => attachedDatabase.locations;
  $MembersTable get members => attachedDatabase.members;
  $ContributionsTable get contributions => attachedDatabase.contributions;
  ContributionDaoManager get managers => ContributionDaoManager(this);
}

class ContributionDaoManager {
  final _$ContributionDaoMixin _db;
  ContributionDaoManager(this._db);
  $$TripsTableTableManager get trips =>
      $$TripsTableTableManager(_db.attachedDatabase, _db.trips);
  $$LocationsTableTableManager get locations =>
      $$LocationsTableTableManager(_db.attachedDatabase, _db.locations);
  $$MembersTableTableManager get members =>
      $$MembersTableTableManager(_db.attachedDatabase, _db.members);
  $$ContributionsTableTableManager get contributions =>
      $$ContributionsTableTableManager(_db.attachedDatabase, _db.contributions);
}
