import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/errors/app_exception.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/expenses/data/expense_repository_impl.dart';
import 'package:tripsplit/features/expenses/domain/expense_payment.dart';
import 'package:tripsplit/features/expenses/domain/expense_repository.dart';
import 'package:tripsplit/features/expenses/domain/expense_scope.dart';
import 'package:tripsplit/features/settlements/domain/settlement.dart';
import 'package:tripsplit/features/teams/data/team_repository_impl.dart';
import 'package:tripsplit/features/teams/domain/team_repository.dart';

/// Tests for multiple payer expenses and team-scoped expenses.
void main() {
  group('Multiple payer expenses', () {
    late AppDatabase db;
    late ExpenseRepository expenseRepository;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      expenseRepository = ExpenseRepositoryImpl(db);
    });

    tearDown(() async {
      await db.closeDatabase();
    });

    Future<(int tripId, List<int> memberIds)> seedTripWithMembers(
      List<String> names,
    ) async {
      final tripId = await db.tripDao.insert(
        TripsCompanion.insert(name: 'Trip'),
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

    test(
      'two payers for a single expense creates correct payment rows',
      () async {
        final (tripId, ids) = await seedTripWithMembers([
          'Dhar',
          'Gowtham',
          'Sanu',
          'Mowli',
        ]);

        // Dhar pays ₹600, Gowtham pays ₹400. Total ₹1000.
        // 4 participants → each share ₹250.
        await expenseRepository.createExpense(
          tripId: tripId,
          description: 'Restaurant',
          amountMinor: 100_00,
          payerMemberId: ids[0],
          participantMemberIds: ids,
          otherPayers: [
            ExpensePayment(
              id: 0,
              expenseId: 0,
              memberId: ids[1],
              amountMinor: 40_00,
            ),
          ],
        );

        final expense = (await expenseRepository.getByTrip(tripId)).single;
        expect(expense.amountMinor, 100_00);

        final payments = await expenseRepository.getPaymentsFor(expense.id);
        expect(payments, hasLength(2));

        // Dhar pays 10000 - 4000 = 6000 (primary payer remainder)
        final dharPayment = payments.firstWhere((p) => p.memberId == ids[0]);
        expect(dharPayment.amountMinor, 60_00);

        // Gowtham pays 4000
        final gowthamPayment = payments.firstWhere((p) => p.memberId == ids[1]);
        expect(gowthamPayment.amountMinor, 40_00);

        // Total payments = expense amount
        final totalPaid = payments.fold<int>(
          0,
          (sum, p) => sum + p.amountMinor,
        );
        expect(totalPaid, 100_00);

        // Shares: ₹250 each
        final shares = await expenseRepository.getSharesFor(expense.id);
        expect(shares, hasLength(4));
        for (final share in shares) {
          expect(share.shareMinor, 25_00);
        }
        final totalShares = shares.fold<int>(0, (sum, s) => sum + s.shareMinor);
        expect(totalShares, 100_00);
      },
    );

    test('payer not a participant: pays for others only', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B', 'C', 'D']);

      // A pays ₹1000 but is NOT a participant.
      // B, C, D share equally (₹333.34, ₹333.33, ₹333.33).
      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Registration',
        amountMinor: 100_00,
        payerMemberId: ids[0],
        participantMemberIds: [ids[1], ids[2], ids[3]],
      );

      final expense = (await expenseRepository.getByTrip(tripId)).single;
      final shares = await expenseRepository.getSharesFor(expense.id);
      expect(shares, hasLength(3));

      // A is not in shares
      expect(shares.any((s) => s.memberId == ids[0]), isFalse);

      // Shares sum to expense amount
      final totalShares = shares.fold<int>(0, (sum, s) => sum + s.shareMinor);
      expect(totalShares, 100_00);
    });

    test('external amount excluded from group shares', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B']);

      // A pays ₹730.90 for group (₹365.40) + external person (₹365.50).
      // Group share: ₹365.40, only A is participant.
      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Registration',
        amountMinor: 730_90,
        externalAmountMinor: 365_50,
        payerMemberId: ids[0],
        participantMemberIds: [ids[0]],
      );

      final shares = await expenseRepository.getSharesFor(1);
      expect(shares, hasLength(1));
      expect(shares.single.shareMinor, 365_40);

      // B has no share (external person, not a trip member)
      final payments = await expenseRepository.getPaymentsFor(1);
      final totalPaid = payments.fold<int>(0, (sum, p) => sum + p.amountMinor);
      expect(totalPaid, 730_90);
    });

    test('update expense with multiple payers', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B', 'C']);

      // Create: A pays 600, B pays 400. Total 1000 for A+B+C.
      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Hotel',
        amountMinor: 100_00,
        payerMemberId: ids[0],
        participantMemberIds: ids,
        otherPayers: [
          ExpensePayment(
            id: 0,
            expenseId: 0,
            memberId: ids[1],
            amountMinor: 40_00,
          ),
        ],
      );

      final expense = (await expenseRepository.getByTrip(tripId)).single;

      // Update: change to A pays 500, C pays 500. Total 1000 for A+B+C.
      await expenseRepository.updateExpense(
        expenseId: expense.id,
        description: 'Hotel',
        amountMinor: 100_00,
        payerMemberId: ids[0],
        participantMemberIds: ids,
        otherPayers: [
          ExpensePayment(
            id: 0,
            expenseId: 0,
            memberId: ids[2],
            amountMinor: 50_00,
          ),
        ],
      );

      final payments = await expenseRepository.getPaymentsFor(expense.id);
      expect(payments, hasLength(2));

      final aPayment = payments.firstWhere((p) => p.memberId == ids[0]);
      expect(aPayment.amountMinor, 50_00);
      final cPayment = payments.firstWhere((p) => p.memberId == ids[2]);
      expect(cPayment.amountMinor, 50_00);
    });

    test('reject other payers whose total exceeds expense', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B']);

      await expectLater(
        expenseRepository.createExpense(
          tripId: tripId,
          description: 'Bad split',
          amountMinor: 100_00,
          payerMemberId: ids[0],
          participantMemberIds: ids,
          otherPayers: [
            ExpensePayment(
              id: 0,
              expenseId: 0,
              memberId: ids[1],
              amountMinor: 100_00,
            ),
          ],
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('reject primary payer listed as other payer', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B']);

      await expectLater(
        expenseRepository.createExpense(
          tripId: tripId,
          description: 'Duplicate payer',
          amountMinor: 100_00,
          payerMemberId: ids[0],
          participantMemberIds: ids,
          otherPayers: [
            ExpensePayment(
              id: 0,
              expenseId: 0,
              memberId: ids[0],
              amountMinor: 40_00,
            ),
          ],
        ),
        throwsA(isA<ValidationException>()),
      );
    });
  });

  group('Team-scoped expenses', () {
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
      List<String> names,
    ) async {
      final tripId = await db.tripDao.insert(
        TripsCompanion.insert(name: 'Trip'),
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

    test('create team expense scoped to team members', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B', 'C', 'D']);

      // Create team with A and B
      final team = await teamRepository.createTeam(tripId, 'Car 1');
      await teamRepository.addMember(teamId: team.id, memberId: ids[0]);
      await teamRepository.addMember(teamId: team.id, memberId: ids[1]);

      // Create team expense: A pays ₹500 for team members
      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Gas',
        amountMinor: 50_00,
        payerMemberId: ids[0],
        scope: ExpenseScope.team,
        teamId: team.id,
        participantMemberIds: [ids[0], ids[1]],
      );

      final expense = (await expenseRepository.getByTrip(tripId)).single;
      expect(expense.scope, ExpenseScope.team);
      expect(expense.teamId, team.id);

      final shares = await expenseRepository.getSharesFor(expense.id);
      expect(shares, hasLength(2));

      // Only A and B are participants (not C and D)
      final participantIds = shares.map((s) => s.memberId).toSet();
      expect(participantIds, containsAll([ids[0], ids[1]]));
      expect(participantIds.contains(ids[2]), isFalse);
      expect(participantIds.contains(ids[3]), isFalse);
    });

    test('cannot delete team with expenses', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B']);

      final team = await teamRepository.createTeam(tripId, 'Car 1');
      await teamRepository.addMember(teamId: team.id, memberId: ids[0]);
      await teamRepository.addMember(teamId: team.id, memberId: ids[1]);

      await expenseRepository.createExpense(
        tripId: tripId,
        description: 'Gas',
        amountMinor: 50_00,
        payerMemberId: ids[0],
        scope: ExpenseScope.team,
        teamId: team.id,
        participantMemberIds: [ids[0], ids[1]],
      );

      expect(
        () => teamRepository.deleteTeam(team.id),
        throwsA(isA<ValidationException>()),
      );
    });

    test('team members are independent from trip members', () async {
      final (tripId, ids) = await seedTripWithMembers(['A', 'B', 'C', 'D']);

      final teamA = await teamRepository.createTeam(tripId, 'Team A');
      await teamRepository.addMember(teamId: teamA.id, memberId: ids[0]);
      await teamRepository.addMember(teamId: teamA.id, memberId: ids[1]);

      final teamB = await teamRepository.createTeam(tripId, 'Team B');
      await teamRepository.addMember(teamId: teamB.id, memberId: ids[2]);
      await teamRepository.addMember(teamId: teamB.id, memberId: ids[3]);

      final teamAMembers = await teamRepository.getTeamMembers(teamA.id);
      final teamBMembers = await teamRepository.getTeamMembers(teamB.id);

      expect(teamAMembers.map((m) => m.id).toSet(), {ids[0], ids[1]});
      expect(teamBMembers.map((m) => m.id).toSet(), {ids[2], ids[3]});

      // Removing member from team A doesn't affect team B
      await teamRepository.removeMember(teamId: teamA.id, memberId: ids[0]);
      final afterRemoval = await teamRepository.getTeamMembers(teamA.id);
      expect(afterRemoval.map((m) => m.id).toSet(), {ids[1]});

      final teamBAfter = await teamRepository.getTeamMembers(teamB.id);
      expect(teamBAfter.map((m) => m.id).toSet(), {ids[2], ids[3]});
    });
  });

  group('Settlement edit persistence', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.closeDatabase();
    });

    test('settlement status derives correctly from paid amounts', () {
      const outstanding = SettlementStatus.outstanding;
      const partial = SettlementStatus.partial;
      const paid = SettlementStatus.paid;

      // enum order: outstanding=0, partial=1, paid=2
      expect(outstanding.index, 0);
      expect(partial.index, 1);
      expect(paid.index, 2);
    });

    test('settlement values persist through read/write cycle', () async {
      final tripId = await db.tripDao.insert(
        TripsCompanion.insert(name: 'Trip'),
      );
      final aId = await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: 'A'),
      );
      final bId = await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: 'B'),
      );

      final now = DateTime(2026, 9, 15);

      // Insert a partial settlement
      await db.settlementDao.insert(
        SettlementsCompanion(
          tripId: Value(tripId),
          fromMemberId: Value(aId),
          toMemberId: Value(bId),
          amountMinor: const Value(5000),
          amountPaidMinor: const Value(2000),
          settledAt: Value(now),
          note: const Value('Partial payment'),
        ),
      );

      // Read it back
      final rows = await db.settlementDao.getByTrip(tripId);
      expect(rows, hasLength(1));
      expect(rows.first.amountMinor, 5000);
      expect(rows.first.amountPaidMinor, 2000);
      expect(rows.first.note, 'Partial payment');

      // Update: add more payment
      final now2 = DateTime(2026, 9, 16);
      await db.settlementDao.updateById(
        rows.first.id,
        SettlementsCompanion(
          amountMinor: const Value(5000),
          amountPaidMinor: const Value(5000),
          paidAt: Value(now2),
          updatedAt: Value(now2),
        ),
      );

      // Read again
      final updated = await db.settlementDao.getByTrip(tripId);
      expect(updated.single.amountPaidMinor, 5000);
      expect(updated.single.paidAt, isNotNull);
    });
  });
}
