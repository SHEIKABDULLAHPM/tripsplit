// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'settlement_dao.dart';

// ignore_for_file: type=lint
mixin _$SettlementDaoMixin on DatabaseAccessor<AppDatabase> {
  $TripsTable get trips => attachedDatabase.trips;
  $LocationsTable get locations => attachedDatabase.locations;
  $MembersTable get members => attachedDatabase.members;
  $SettlementsTable get settlements => attachedDatabase.settlements;
  SettlementDaoManager get managers => SettlementDaoManager(this);
}

class SettlementDaoManager {
  final _$SettlementDaoMixin _db;
  SettlementDaoManager(this._db);
  $$TripsTableTableManager get trips =>
      $$TripsTableTableManager(_db.attachedDatabase, _db.trips);
  $$LocationsTableTableManager get locations =>
      $$LocationsTableTableManager(_db.attachedDatabase, _db.locations);
  $$MembersTableTableManager get members =>
      $$MembersTableTableManager(_db.attachedDatabase, _db.members);
  $$SettlementsTableTableManager get settlements =>
      $$SettlementsTableTableManager(_db.attachedDatabase, _db.settlements);
}
