import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/balances.dart';
import 'package:tripsplit/core/calculations/settlements.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/contributions/data/contribution_repository_impl.dart';
import 'package:tripsplit/features/expenses/data/expense_repository_impl.dart';
import 'package:tripsplit/features/expenses/domain/expense_share.dart';
import 'package:tripsplit/features/members/data/member_repository_impl.dart';
import 'package:tripsplit/features/trips/data/trip_repository_impl.dart';
import 'package:tripsplit/features/trips/domain/trip_repository.dart';

/// End-to-end scenario for external (non-group) payments through the real
/// repository stack, mirroring requirements 50.12-50.15.
///
/// Suganth pays ₹730.90 for an event registration. Suganth's own share of the
/// registration is ₹365.40; the other ₹365.50 is for a person who is not a
/// member of the group. The group must remember the FULL ₹730.90 payment for
/// cash tracking, but only the ₹365.40 group portion may ever create a debt
/// or consume budget.
void main() {
  late AppDatabase db;
  late TripRepositoryImpl trips;
  late MemberRepositoryImpl members;
  late ContributionRepositoryImpl contributions;
  late ExpenseRepositoryImpl expenses;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    trips = TripRepositoryImpl(db);
    members = MemberRepositoryImpl(db);
    contributions = ContributionRepositoryImpl(db);
    expenses = ExpenseRepositoryImpl(db);
  });

  tearDown(() async {
    await db.closeDatabase();
  });

  Future<({int tripId, int shaik, int suganth, int asma, int man})>
  seedTrip() async {
    final tripId = await trips.createWithSetup(
      name: 'Tech Horizon',
      budgetMinor: 10000 * 100,
      members: const [
        NewMemberDraft(name: 'Shaik', contributionMinor: 1650 * 100),
        NewMemberDraft(name: 'Suganth', contributionMinor: 1345 * 100),
        NewMemberDraft(name: 'Asma', contributionMinor: 3250 * 100),
        NewMemberDraft(name: 'Man', contributionMinor: 1350 * 100),
      ],
    );

    final byName = <String, int>{};
    for (final m in await members.getByTrip(tripId)) {
      byName[m.name] = m.id;
    }

    return (
      tripId: tripId,
      shaik: byName['Shaik']!,
      suganth: byName['Suganth']!,
      asma: byName['Asma']!,
      man: byName['Man']!,
    );
  }

  Future<List<ExpenseShare>> sharesForTrip(int tripId) async {
    final allExpenses = await expenses.getByTrip(tripId);
    final allShares = <ExpenseShare>[];
    for (final e in allExpenses) {
      allShares.addAll(await expenses.getSharesFor(e.id));
    }
    return allShares;
  }

  test(
    'external registration stays out of group debt, spend and cash',
    () async {
      final t = await seedTrip();

      await expenses.createExpense(
        tripId: t.tripId,
        description: 'Registration',
        amountMinor: 730_90,
        externalAmountMinor: 365_50,
        payerMemberId: t.suganth,
        participantMemberIds: [t.suganth],
      );

      final allExpenses = await expenses.getByTrip(t.tripId);
      final allShares = await sharesForTrip(t.tripId);
      final allContributions = await contributions.getByTrip(t.tripId);
      final trip = (await trips.findById(t.tripId))!;

      final balances = BalanceCalculator.calculate(
        tripBudgetMinor: trip.totalBudgetMinor,
        contributions: allContributions,
        expenses: allExpenses,
        shares: allShares,
        settlements: const [],
      );

      // Requirement 50.13: group spend only sees the ₹365.40 group share.
      expect(balances.totalExpenses, 365_40);
      expect(balances.remainingBudget, 10000 * 100 - 365_40);

      final plan = SettlementCalculator.calculate(
        expenses: allExpenses,
        shares: allShares,
        settlements: const [],
      );
      // Requirement 50.14 + 50.15: no group debt, external shared with no one.
      expect(plan.suggestions, isEmpty);
      expect(plan.totalOutstanding, 0);

      final suganth = balances.members.firstWhere(
        (m) => m.memberId == t.suganth,
      );
      // Requirement 50.15a: actual payment is the FULL ₹730.90.
      expect(suganth.actualPaid, 730_90);
      // Requirement 50.15b: group expense share is only ₹365.40.
      expect(suganth.expenseShare, 365_40);
      // No one owes Suganth for the external ₹365.50.
      expect(suganth.netPosition, 0);
      // Requirement 50.15c: cash remaining = contribution - actual payment.
      expect(suganth.cashRemaining, 1345 * 100 - 730_90);
    },
  );

  test(
    'external portion with other participants only shares the group part',
    () async {
      final t = await seedTrip();

      // Registration: Suganth pays 730.90, 350.00 of it is external, the
      // remaining 380.90 is split equally between Suganth and Man.
      await expenses.createExpense(
        tripId: t.tripId,
        description: 'Registration',
        amountMinor: 730_90,
        externalAmountMinor: 350_00,
        payerMemberId: t.suganth,
        participantMemberIds: [t.suganth, t.man],
      );

      final allExpenses = await expenses.getByTrip(t.tripId);
      final shares = await expenses.getSharesFor(allExpenses.single.id);
      final allContributions = await contributions.getByTrip(t.tripId);
      final trip = (await trips.findById(t.tripId))!;

      expect(shares, hasLength(2));
      final manShare = shares.firstWhere((s) => s.memberId == t.man);
      expect(manShare.shareMinor, 380_90 ~/ 2);

      final balances = BalanceCalculator.calculate(
        tripBudgetMinor: trip.totalBudgetMinor,
        contributions: allContributions,
        expenses: allExpenses,
        shares: shares,
        settlements: const [],
      );

      expect(balances.totalExpenses, 380_90);

      final suganth = balances.members.firstWhere(
        (m) => m.memberId == t.suganth,
      );
      final man = balances.members.firstWhere((m) => m.memberId == t.man);
      // Only the group 380.90 creates a debt between Suganth and Man.
      expect(suganth.netPosition, 190_45);
      expect(man.netPosition, -190_45);
      // Cash still reflects the full 730.90 out of Suganth's pocket.
      expect(suganth.cashRemaining, 1345 * 100 - 730_90);
      expect(man.cashRemaining, 1350 * 100);

      final plan = SettlementCalculator.calculate(
        expenses: allExpenses,
        shares: shares,
        settlements: const [],
      );
      expect(plan.totalOutstanding, 190_45);
      expect(plan.suggestions.single.fromMemberId, t.man);
      expect(plan.suggestions.single.toMemberId, t.suganth);
    },
  );

  test(
    'mixing external and ordinary group expenses keeps figures distinct',
    () async {
      final t = await seedTrip();

      await expenses.createExpense(
        tripId: t.tripId,
        description: 'Registration',
        amountMinor: 730_90,
        externalAmountMinor: 365_50,
        payerMemberId: t.suganth,
        participantMemberIds: [t.suganth],
      );
      await expenses.createExpense(
        tripId: t.tripId,
        description: 'Train',
        amountMinor: 733_60,
        payerMemberId: t.suganth,
        participantMemberIds: [t.shaik, t.suganth, t.asma, t.man],
      );

      final allExpenses = await expenses.getByTrip(t.tripId);
      final allShares = await sharesForTrip(t.tripId);
      final allContributions = await contributions.getByTrip(t.tripId);
      final trip = (await trips.findById(t.tripId))!;

      final balances = BalanceCalculator.calculate(
        tripBudgetMinor: trip.totalBudgetMinor,
        contributions: allContributions,
        expenses: allExpenses,
        shares: allShares,
        settlements: const [],
      );

      // Spend = registration group 365.40 + train 733.60 = 1099.00.
      expect(balances.totalExpenses, 1099 * 100);
      expect(balances.remainingBudget, 10000 * 100 - 1099 * 100);

      final suganth = balances.members.firstWhere(
        (m) => m.memberId == t.suganth,
      );
      // actualPaid = 730.90 + 733.60 = 1464.50 (full cash out).
      expect(suganth.actualPaid, 1464 * 100 + 50);
      expect(suganth.expenseShare, 365_40 + 183_40);
      // groupOutlay (1099.00) - share (548.80) = +550.20.
      expect(suganth.netPosition, 550_20);
      expect(suganth.cashRemaining, 1345 * 100 - 1464 * 100 - 50);

      final plan = SettlementCalculator.calculate(
        expenses: allExpenses,
        shares: allShares,
        settlements: const [],
      );
      expect(plan.totalOutstanding, 550_20);
      final froms = plan.suggestions.map((s) => s.fromMemberId).toSet();
      expect(froms, {t.shaik, t.asma, t.man});
      expect(plan.suggestions.every((s) => s.toMemberId == t.suganth), isTrue);
    },
  );
}
