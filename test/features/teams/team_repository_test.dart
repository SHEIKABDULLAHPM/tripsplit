import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/members/data/member_repository_impl.dart';
import 'package:tripsplit/features/members/domain/member.dart';
import 'package:tripsplit/features/teams/data/team_repository_impl.dart';
import 'package:tripsplit/features/teams/domain/team_repository.dart';

void main() {
  group('TeamRepositoryImpl.watchTeamMembers', () {
    late AppDatabase db;
    late TeamRepository repository;
    late MemberRepositoryImpl memberRepository;
    late int tripId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repository = TeamRepositoryImpl(db);
      memberRepository = MemberRepositoryImpl(db);
      tripId = await db.tripDao.insert(TripsCompanion.insert(name: 'Konkan'));
    });

    tearDown(() async {
      await db.closeDatabase();
    });

    Future<int> addMember(String name) async => db.memberDao.insert(
      MembersCompanion.insert(tripId: tripId, name: name),
    );

    test('re-emits when team membership changes after subscription', () async {
      final anaId = await addMember('Ana');
      final benId = await addMember('Ben');
      final catId = await addMember('Cat');
      final teamId = await db.journeyDao.insertTeam(
        TeamsCompanion.insert(tripId: tripId, name: 'Car 1'),
      );

      await repository.addMember(teamId: teamId, memberId: anaId);

      final emitted = <List<String>>[];
      final sub = repository
          .watchTeamMembers(teamId)
          .listen(
            (members) => emitted.add(members.map((m) => m.name).toList()),
          );

      // Let the initial emission arrive.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(emitted.last, contains('Ana'));

      // Add a member: the stream must reflect the new membership without a
      // fresh subscription (this was the stale-data bug).
      await repository.addMember(teamId: teamId, memberId: benId);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(emitted.last.toSet(), {'Ana', 'Ben'});

      // Remove a member: the stream must shrink again.
      await repository.removeMember(teamId: teamId, memberId: anaId);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(emitted.last.toSet(), {'Ben'});

      // A member rename must also propagate.
      final cat = await db.memberDao.getById(catId);
      await memberRepository.save(
        Member(
          id: cat!.id,
          tripId: cat.tripId,
          name: 'Cat v2',
          joinLocationId: cat.joinLocationId,
          leaveLocationId: cat.leaveLocationId,
          createdAt: cat.createdAt,
        ),
      );
      await repository.addMember(teamId: teamId, memberId: catId);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(emitted.last, contains('Cat v2'));

      await sub.cancel();
    });

    test('yields an empty list for an unknown team', () async {
      List<int>? seen;
      final sub = repository
          .watchTeamMembers(999)
          .listen((members) => seen = members.map((m) => m.id).toList());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();
      expect(seen, isEmpty);
    });
  });
}
