import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/errors/app_exception.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/expenses/data/expense_repository_impl.dart';
import 'package:tripsplit/features/expenses/domain/expense_payment.dart';
import 'package:tripsplit/features/expenses/domain/expense_repository.dart';
import 'package:tripsplit/features/expenses/domain/expense_scope.dart';
import 'package:tripsplit/features/teams/data/team_repository_impl.dart';
import 'package:tripsplit/features/teams/domain/team_repository.dart';

/// Tests for team payer attribution: one expense spanning several teams,
/// each team designating its own payer.
void main() {
  group('Team payer attribution', () {
    late AppDatabase db;
    late ExpenseRepository expenseRepository;
    late TeamRepository teamRepository;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      expenseRepository = ExpenseRepositoryImpl(db);
      teamRepository = TeamRepositoryImpl(db);
    });

    tearDown(() async {
      await db.closeDatabase();
    });

    Future<(int tripId, List<int> memberIds)> seedTripWithMembers(
      List<String> names, {
      String tripName = 'Trip',
    }) async {
      final tripId = await db.tripDao.insert(
        TripsCompanion.insert(name: tripName),
      );
      final ids = <int>[];
      for (final name in names) {
        ids.add(
          await db.memberDao.insert(
            MembersCompanion.insert(tripId: tripId, name: name),
          ),
        );
      }
      return (tripId, ids);
    }

    Future<(int teamId, List<int> memberIds)> seedTeam(
      int tripId,
      String name,
      List<int> memberIds,
    ) async {
      final team = await teamRepository.createTeam(tripId, name);
      for (final memberId in memberIds) {
        await teamRepository.addMember(teamId: team.id, memberId: memberId);
      }
      return (team.id, memberIds);
    }

    test('two teams with their own payers: full team-payer scenario '
        'produces correct join rows, attributions and balances', () async {
      final (tripId, ids) = await seedTripWithMembers([
        'A',
        'B',
        'C',
        'D',
        'E',
        'F',
        'G',
        'H',
        'I',
        'J',
      ]);
      final (team1, team1Members) = await seedTeam(tripId, 'Team 1', [
        ids[0],
        ids[1],
        ids[2],
        ids[3],
        ids[4],
      ]);
      final (team2, team2Members) = await seedTeam(tripId, 'Team 2', [
        ids[5],
        ids[6],
        ids[7],
        ids[8],
        ids[9],
      ]);

      // One expense of ₹4,000 across both teams.
      // Team 1 (A–E) has A pay ₹2,000; Team 2 (F–J) has F pay ₹2,000.
      // All 10 split equally → ₹400 each.
      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Restaurant',
        amountMinor: 4000_00,
        payerMemberId: ids[0],
        scope: ExpenseScope.team,
        teamIds: [team1, team2],
        payerTeamId: team1,
        participantMemberIds: ids,
        otherPayers: [
          ExpensePayment(
            id: 0,
            expenseId: 0,
            memberId: ids[5],
            amountMinor: 2000_00,
            teamId: team2,
          ),
        ],
      );

      final expense = (await expenseRepository.getByTrip(tripId)).single;
      expect(expense.scope, ExpenseScope.team);
      expect(expense.amountMinor, 4000_00);
      // Legacy column keeps the first team; hydration restores all teams.
      expect(expense.teamId, team1);
      expect(expense.teamIds.toSet(), {team1, team2});

      // getById hydrates teamIds too.
      final byId = await expenseRepository.getById(expense.id);
      expect(byId?.teamIds.toSet(), {team1, team2});

      // Exactly one join row per team.
      final links = await db.expenseDao.getTeamLinksFor(expense.id);
      expect(links.map((link) => link.teamId).toSet(), {team1, team2});
      expect(links, hasLength(2));

      // Payments carry team attribution and total the full amount.
      final payments = await expenseRepository.getPaymentsFor(expense.id);
      expect(payments, hasLength(2));
      final aPayment = payments.singleWhere((p) => p.memberId == ids[0]);
      expect(aPayment.amountMinor, 2000_00);
      expect(aPayment.teamId, team1);
      final fPayment = payments.singleWhere((p) => p.memberId == ids[5]);
      expect(fPayment.amountMinor, 2000_00);
      expect(fPayment.teamId, team2);
      final totalPaid = payments.fold<int>(0, (sum, p) => sum + p.amountMinor);
      expect(totalPaid, 4000_00);

      // Global equal split across all 10 participants.
      final shares = await expenseRepository.getSharesFor(expense.id);
      expect(shares, hasLength(10));
      for (final share in shares) {
        expect(share.shareMinor, 400_00);
      }

      // Member-level balances: payer net = paid − share.
      final netByMember = <int, int>{};
      for (final p in payments) {
        netByMember[p.memberId] = p.amountMinor;
      }
      for (final s in shares) {
        netByMember[s.memberId] = (netByMember[s.memberId] ?? 0) - s.shareMinor;
      }
      expect(netByMember[ids[0]], 1600_00); // A pays 2000, owes 400.
      expect(netByMember[ids[5]], 1600_00); // F pays 2000, owes 400.
      for (final i in [1, 2, 3, 4, 6, 7, 8, 9]) {
        expect(netByMember[ids[i]], -400_00); // Everyone else just owes.
      }
      final settled = netByMember.values.fold<int>(0, (sum, v) => sum + v);
      expect(settled, 0);
    });

    test('cross-team payer is allowed for common expenses', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B', 'C']);
      final (team1, _) = await seedTeam(tripId, 'Team 1', [ids[0], ids[1]]);

      // 'C' pays ₹100 for Team 1 but is not in Team 1. This is valid for
      // common expenses where any participant can pay on behalf of any team.
      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Dinner',
        amountMinor: 100_00,
        payerMemberId: ids[2],
        scope: ExpenseScope.team,
        teamIds: [team1],
        payerTeamId: team1,
        participantMemberIds: ids,
      );

      final expense = (await expenseRepository.getByTrip(tripId)).single;
      expect(expense.scope, ExpenseScope.team);
      expect(expense.amountMinor, 100_00);
      expect(expense.teamIds, [team1]);

      final payments = await expenseRepository.getPaymentsFor(expense.id);
      expect(payments.single.memberId, ids[2]);
      expect(payments.single.amountMinor, 100_00);
      expect(payments.single.teamId, team1);
    });

    test('payer team must be one of the expense teams', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B', 'C', 'D']);
      final (team1, _) = await seedTeam(tripId, 'Team 1', [ids[0], ids[1]]);
      final (team2, team2Members) = await seedTeam(tripId, 'Team 2', [
        ids[2],
        ids[3],
      ]);

      // A pays for team2, but team2 is not one of the expense teams.
      await expectLater(
        expenseRepository.createExpense(
          tripId: tripId,
          description: 'Dinner',
          amountMinor: 100_00,
          payerMemberId: ids[0],
          scope: ExpenseScope.team,
          teamIds: [team1],
          payerTeamId: team2,
          participantMemberIds: ids,
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains("the expense's teams"),
          ),
        ),
      );

      // D pays ₹100 for team2 which is also not among the expense teams.
      await expectLater(
        expenseRepository.createExpense(
          tripId: tripId,
          description: 'Dinner',
          amountMinor: 200_00,
          payerMemberId: ids[0],
          scope: ExpenseScope.team,
          teamIds: [team1],
          payerTeamId: team1,
          participantMemberIds: ids,
          otherPayers: [
            ExpensePayment(
              id: 0,
              expenseId: 0,
              memberId: team2Members[1],
              amountMinor: 100_00,
              teamId: team2,
            ),
          ],
        ),
        throwsA(
          isA<ValidationException>().having(
            (e) => e.message,
            'message',
            contains("one of the expense's teams"),
          ),
        ),
      );
    });

    test('team scope requires at least one team', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B']);

      await expectLater(
        expenseRepository.createExpense(
          tripId: tripId,
          description: 'Dinner',
          amountMinor: 100_00,
          payerMemberId: ids[0],
          scope: ExpenseScope.team,
          participantMemberIds: ids,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('teams can only apply to team-scoped expenses', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B']);
      final (team1, _) = await seedTeam(tripId, 'Team 1', ids);

      await expectLater(
        expenseRepository.createExpense(
          tripId: tripId,
          description: 'Dinner',
          amountMinor: 100_00,
          payerMemberId: ids[0],
          scope: ExpenseScope.shared,
          teamIds: [team1],
          participantMemberIds: ids,
        ),
        throwsA(isA<ValidationException>()),
      );

      await expectLater(
        expenseRepository.createExpense(
          tripId: tripId,
          description: 'Dinner',
          amountMinor: 100_00,
          payerMemberId: ids[0],
          scope: ExpenseScope.segment,
          teamIds: [team1],
          participantMemberIds: ids,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('duplicate teams rejected', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B']);
      final (team1, _) = await seedTeam(tripId, 'Team 1', ids);

      await expectLater(
        expenseRepository.createExpense(
          tripId: tripId,
          description: 'Dinner',
          amountMinor: 100_00,
          payerMemberId: ids[0],
          scope: ExpenseScope.team,
          teamIds: [team1, team1],
          participantMemberIds: ids,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('every team must belong to the trip', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B']);
      final (otherTripId, otherTripMembers) = await seedTripWithMembers([
        'X',
        'Y',
      ], tripName: 'Other Trip');
      final (foreignTeam, _) = await seedTeam(
        otherTripId,
        'Foreign Team',
        otherTripMembers,
      );

      await expectLater(
        expenseRepository.createExpense(
          tripId: tripId,
          description: 'Dinner',
          amountMinor: 100_00,
          payerMemberId: ids[0],
          scope: ExpenseScope.team,
          teamIds: [foreignTeam],
          participantMemberIds: ids,
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('one team may cover an expense on behalf of all teams', () async {
      final (tripId, ids) = await seedTripWithMembers([
        'A',
        'B',
        'C',
        'D',
        'E',
        'F',
        'G',
        'H',
      ]);
      final (team1, _) = await seedTeam(tripId, 'Team 1', ids.sublist(0, 4));
      final (team2, _) = await seedTeam(tripId, 'Team 2', ids.sublist(4));

      // Only Team 1 pays (A pays the entire ₹3,200); Team 2 has no payer.
      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Hotel',
        amountMinor: 3200_00,
        payerMemberId: ids[0],
        scope: ExpenseScope.team,
        teamIds: [team1, team2],
        payerTeamId: team1,
        participantMemberIds: ids,
      );

      final expense = (await expenseRepository.getByTrip(tripId)).single;
      expect(expense.teamIds.toSet(), {team1, team2});

      final links = await db.expenseDao.getTeamLinksFor(expense.id);
      expect(links, hasLength(2));

      final payments = await expenseRepository.getPaymentsFor(expense.id);
      expect(payments, hasLength(1));
      expect(payments.single.memberId, ids[0]);
      expect(payments.single.amountMinor, 3200_00);
      expect(payments.single.teamId, team1);
    });

    test('update rewrites join rows, payments and legacy team', () async {
      final (tripId, ids) = await seedTripWithMembers([
        'A',
        'B',
        'C',
        'D',
        'E',
        'F',
        'G',
        'H',
      ]);
      final (team1, _) = await seedTeam(tripId, 'Team 1', ids.sublist(0, 4));
      final (team2, _) = await seedTeam(tripId, 'Team 2', ids.sublist(4));

      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Hotel',
        amountMinor: 3200_00,
        payerMemberId: ids[0],
        scope: ExpenseScope.team,
        teamIds: [team1, team2],
        payerTeamId: team1,
        participantMemberIds: ids,
        otherPayers: [
          ExpensePayment(
            id: 0,
            expenseId: 0,
            memberId: ids[4],
            amountMinor: 1600_00,
            teamId: team2,
          ),
        ],
      );
      final expense = (await expenseRepository.getByTrip(tripId)).single;

      // Update: expense is now only for Team 2, paid entirely by F.
      await expenseRepository.updateExpense(
        expenseId: expense.id,
        description: 'Hotel',
        amountMinor: 3200_00,
        payerMemberId: ids[4],
        scope: ExpenseScope.team,
        teamIds: [team2],
        payerTeamId: team2,
        participantMemberIds: ids,
      );

      final updated = await expenseRepository.getById(expense.id);
      expect(updated?.teamIds, [team2]);
      expect(updated?.teamId, team2);

      final links = await db.expenseDao.getTeamLinksFor(expense.id);
      expect(links.map((link) => link.teamId).toSet(), {team2});

      final payments = await expenseRepository.getPaymentsFor(expense.id);
      expect(payments, hasLength(1));
      expect(payments.single.memberId, ids[4]);
      expect(payments.single.amountMinor, 3200_00);
      expect(payments.single.teamId, team2);
    });

    test('delete cleans up join rows and payments', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B', 'C', 'D']);
      final (team1, _) = await seedTeam(tripId, 'Team 1', [ids[0], ids[1]]);
      final (team2, _) = await seedTeam(tripId, 'Team 2', [ids[2], ids[3]]);

      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Dinner',
        amountMinor: 200_00,
        payerMemberId: ids[0],
        scope: ExpenseScope.team,
        teamIds: [team1, team2],
        payerTeamId: team1,
        participantMemberIds: ids,
      );
      final expense = (await expenseRepository.getByTrip(tripId)).single;

      await expenseRepository.deleteExpense(
        tripId: tripId,
        expenseId: expense.id,
      );

      expect(await db.expenseDao.getTeamLinksFor(expense.id), isEmpty);
      expect(await expenseRepository.getPaymentsFor(expense.id), isEmpty);
    });

    test(
      'legacy single-team create still writes join row and team payment',
      () async {
        final (tripId, ids) = await seedTripWithMembers(['A', 'B']);
        final (team1, _) = await seedTeam(tripId, 'Team 1', ids);

        // Old API: only `teamId`, no `teamIds`.
        await expenseRepository.createExpense(
          tripId: tripId,
          description: 'Gas',
          amountMinor: 50_00,
          payerMemberId: ids[0],
          scope: ExpenseScope.team,
          teamId: team1,
          participantMemberIds: ids,
        );

        final expense = (await expenseRepository.getByTrip(tripId)).single;
        expect(expense.teamId, team1);
        expect(expense.teamIds, [team1]);

        final links = await db.expenseDao.getTeamLinksFor(expense.id);
        expect(links.single.teamId, team1);

        final payments = await expenseRepository.getPaymentsFor(expense.id);
        expect(payments.single.teamId, team1);
      },
    );
  });
}
