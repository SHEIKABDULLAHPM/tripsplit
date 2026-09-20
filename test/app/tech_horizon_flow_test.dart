import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/balances.dart';
import 'package:tripsplit/core/calculations/settlements.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/database/domain_mappers.dart';
import 'package:tripsplit/features/expenses/data/expense_repository_impl.dart';
import 'package:tripsplit/features/expenses/domain/expense_repository.dart';
import 'package:tripsplit/features/members/data/member_repository_impl.dart';
import 'package:tripsplit/features/members/domain/member_repository.dart';
import 'package:tripsplit/features/settlements/data/settlement_repository_impl.dart';
import 'package:tripsplit/features/settlements/domain/settlement_repository.dart';
import 'package:tripsplit/features/trips/data/trip_repository_impl.dart';
import 'package:tripsplit/features/trips/domain/trip_repository.dart';

/// The mandatory Tech Horizon end-to-end scenario exercised through the real
/// repositories and database, so every layer (persistence, composition,
/// calculation) is verified together.
///
/// Setup (from the spec narrative):
///  - Group budget ₹2,500; contributions: Shaik ₹1,650, Suganth ₹1,050,
///    Asma ₹1,650, Man ₹350 → ₹4,700 total.
///  - Registration ₹730.80 (Suganth pays; shared Suganth + Man equally).
///  - Train ₹733.60 = ₹183.40 per head (all four share it), modeled with two
///    line items so Man pays his own share: Suganth ₹550.20 and Man ₹183.40.
void main() {
  group('Tech Horizon app flow', () {
    late AppDatabase db;
    late TripRepository trips;
    late MemberRepository members;
    late ExpenseRepository expenses;
    late SettlementRepository settlements;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      trips = TripRepositoryImpl(db);
      members = MemberRepositoryImpl(db);
      expenses = ExpenseRepositoryImpl(db);
      settlements = SettlementRepositoryImpl(db);
    });

    tearDown(() async {
      await db.closeDatabase();
    });

    Future<BalanceResult> currentBalances(int tripId) async {
      final contributions = (await db.contributionDao.getByTrip(
        tripId,
      )).map((r) => r.toDomain()).toList();
      final expenseRows = await db.expenseDao.getByTrip(tripId);
      final shareRows = await db.expenseDao.getSharesByTrip(tripId);
      final settlementRows = await db.settlementDao.getByTrip(tripId);
      return BalanceCalculator.calculate(
        tripBudgetMinor: 250000,
        contributions: contributions,
        expenses: expenseRows.map((r) => r.toDomain()).toList(),
        shares: shareRows.map((r) => r.toDomain()).toList(),
        settlements: settlementRows.map((r) => r.toDomain()).toList(),
      );
    }

    Future<SettlementResult> currentPlan(int tripId) async {
      final expenseRows = await db.expenseDao.getByTrip(tripId);
      final shareRows = await db.expenseDao.getSharesByTrip(tripId);
      final settlementRows = await db.settlementDao.getByTrip(tripId);
      return SettlementCalculator.calculate(
        expenses: expenseRows.map((r) => r.toDomain()).toList(),
        shares: shareRows.map((r) => r.toDomain()).toList(),
        settlements: settlementRows.map((r) => r.toDomain()).toList(),
      );
    }

    testWidgets('seeds the full trip and matches every reported figure', (
      tester,
    ) async {
      final tripId = await trips.createWithSetup(
        name: 'Tech Horizon',
        budgetMinor: 250000,
        members: const [
          NewMemberDraft(name: 'Shaik', contributionMinor: 165000),
          NewMemberDraft(name: 'Suganth', contributionMinor: 105000),
          NewMemberDraft(name: 'Asma', contributionMinor: 165000),
          NewMemberDraft(name: 'Man', contributionMinor: 35000),
        ],
      );

      final memberRows = await members.getByTrip(tripId);
      final ids = {for (final m in memberRows) m.name: m.id};

      await expenses.createExpense(
        tripId: tripId,
        description: 'Registration',
        amountMinor: 73080,
        payerMemberId: ids['Suganth']!,
        participantMemberIds: [ids['Suganth']!, ids['Man']!],
      );
      await expenses.createExpense(
        tripId: tripId,
        description: 'Train (Suganth)',
        amountMinor: 55020,
        payerMemberId: ids['Suganth']!,
        participantMemberIds: memberRows.map((m) => m.id).toList(),
      );
      await expenses.createExpense(
        tripId: tripId,
        description: 'Train (Man)',
        amountMinor: 18340,
        payerMemberId: ids['Man']!,
        participantMemberIds: memberRows.map((m) => m.id).toList(),
      );

      final balances = await currentBalances(tripId);
      expect(balances.totalContributions, 470000);
      expect(balances.totalExpenses, 146440);
      expect(balances.remainingBudget, 103560);

      final man = balances.members.firstWhere(
        (MemberBalance m) => m.memberId == ids['Man'],
      );
      expect(man.contribution, 35000);
      expect(man.actualPaid, 18340);
      expect(man.expenseShare, 54880);
      expect(man.netPosition, -36540);
      expect(man.cashRemaining, 16660);

      final plan = await currentPlan(tripId);
      expect(plan.totalOutstanding, 73220);
      expect(plan.suggestions.first.fromMemberId, ids['Man']);
      expect(plan.suggestions.first.toMemberId, ids['Suganth']);
      expect(plan.suggestions.first.minor, 36540);

      await settlements.recordPayment(
        tripId: tripId,
        fromMemberId: ids['Man']!,
        toMemberId: ids['Suganth']!,
        amountMinor: 36540,
        paidMinor: 36540,
      );

      final rows = await db.settlementDao.getByTrip(tripId);
      expect(rows, hasLength(1));
      expect(rows.single.amountMinor, 36540);
      expect(rows.single.amountPaidMinor, 36540);
      expect(rows.single.paidAt, isNotNull);

      final after = await currentBalances(tripId);
      final manAfter = after.members.firstWhere(
        (MemberBalance m) => m.memberId == ids['Man'],
      );
      expect(manAfter.cashRemaining, -19880);

      final settled = await currentPlan(tripId);
      expect(
        settled.suggestions.any(
          (s) => s.fromMemberId == ids['Man'] && s.minor == 36540,
        ),
        isFalse,
      );
    });
  });
}
