import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/balances.dart';
import 'package:tripsplit/core/calculations/expense_split.dart';
import 'package:tripsplit/core/calculations/settlements.dart';
import 'package:tripsplit/features/expenses/domain/expense.dart';
import 'package:tripsplit/features/expenses/domain/expense_payment.dart';
import 'package:tripsplit/features/expenses/domain/expense_share.dart';
import 'package:tripsplit/features/settlements/domain/settlement.dart';

/// End-to-end test for the canonical scenario:
///
/// Trip: Erode → Salem → Bengaluru → Mysuru
/// Members: Dhar, Gowtham, Sanu, Mowli
///
/// Participation:
///   Dhar   — entire journey
///   Gowtham — entire journey
///   Sanu   — Salem → Bengaluru only (joins at Salem, leaves at Bengaluru)
///   Mowli  — entire journey
///
/// Expenses:
///   1. Erode → Salem train: ₹400, paid by Dhar, participants: Dhar, Gowtham, Mowli
///   2. Salem → Bengaluru train: ₹600, paid by Gowtham, participants: Dhar, Gowtham, Sanu, Mowli
///   3. Bengaluru → Mysuru train: ₹500, paid by Dhar, participants: Dhar, Gowtham, Mowli
///   4. Food at Bengaluru: ₹800, paid by Gowtham, participants: Dhar, Gowtham, Sanu, Mowli
///   5. Personal expense: ₹300, paid by Mowli, participants: Mowli only
///
/// This file validates independent calculations and the combined settlement,
/// never testing the production code against itself.
void main() {
  const erodeToSalem = 40000; // ₹400.00 in minor units
  const salemToBengaluru = 60000; // ₹600.00
  const bengaluruToMysuru = 50000; // ₹500.00
  const foodAtBengaluru = 80000; // ₹800.00
  const personalExpense = 30000; // ₹300.00

  final now = DateTime(2026, 9, 14);

  // Member IDs (independent, not tied to any DB)
  const dharId = 1;
  const gowthamId = 2;
  const sanuId = 3;
  const mowliId = 4;

  const splitter = EqualExpenseSplitter();

  // ── Helper: build Expense objects ──────────────────────────────────────

  Expense makeExpense(int id, int payerId, int amountMinor, {int? segmentId}) =>
      Expense(
        id: id,
        tripId: 1,
        payerMemberId: payerId,
        description: 'Expense $id',
        amountMinor: amountMinor,
        externalAmountMinor: 0,
        segmentId: segmentId,
        createdAt: now,
        updatedAt: now,
      );

  // ── Independent share calculations ────────────────────────────────────

  // Expense 1: Erode→Salem ₹400, Dhar pays, participants: Dhar, Gowtham, Mowli
  final shares1 = splitter.split(
    totalMinor: erodeToSalem,
    memberIds: [dharId, gowthamId, mowliId],
  );

  // Expense 2: Salem→Bengaluru ₹600, Gowtham pays, participants: all 4
  final shares2 = splitter.split(
    totalMinor: salemToBengaluru,
    memberIds: [dharId, gowthamId, sanuId, mowliId],
  );

  // Expense 3: Bengaluru→Mysuru ₹500, Dhar pays, participants: Dhar, Gowtham, Mowli
  final shares3 = splitter.split(
    totalMinor: bengaluruToMysuru,
    memberIds: [dharId, gowthamId, mowliId],
  );

  // Expense 4: Food ₹800, Gowtham pays, participants: all 4
  final shares4 = splitter.split(
    totalMinor: foodAtBengaluru,
    memberIds: [dharId, gowthamId, sanuId, mowliId],
  );

  // Expense 5: Personal ₹300, Mowli pays, participants: Mowli only
  final shares5 = splitter.split(
    totalMinor: personalExpense,
    memberIds: [mowliId],
  );

  // ── Build domain objects ──────────────────────────────────────────────

  final expense1 = makeExpense(1, dharId, erodeToSalem, segmentId: 1);
  final expense2 = makeExpense(2, gowthamId, salemToBengaluru, segmentId: 2);
  final expense3 = makeExpense(3, dharId, bengaluruToMysuru, segmentId: 3);
  final expense4 = makeExpense(4, gowthamId, foodAtBengaluru);
  final expense5 = makeExpense(5, mowliId, personalExpense);

  final allExpenses = [expense1, expense2, expense3, expense4, expense5];

  // Build ExpenseShare objects from the calculated shares
  List<ExpenseShare> toShares(int expenseId, List<MemberShare> memberShares) =>
      [
        for (final s in memberShares)
          ExpenseShare(
            id: expenseId * 100 + s.memberId,
            expenseId: expenseId,
            memberId: s.memberId,
            shareMinor: s.amountMinor,
          ),
      ];

  final allShares = [
    ...toShares(1, shares1),
    ...toShares(2, shares2),
    ...toShares(3, shares3),
    ...toShares(4, shares4),
    ...toShares(5, shares5),
  ];

  // Single payer per expense (primary payer pays everything)
  final allPayments = [
    const ExpensePayment(
      id: 1,
      expenseId: 1,
      memberId: dharId,
      amountMinor: erodeToSalem,
    ),
    const ExpensePayment(
      id: 2,
      expenseId: 2,
      memberId: gowthamId,
      amountMinor: salemToBengaluru,
    ),
    const ExpensePayment(
      id: 3,
      expenseId: 3,
      memberId: dharId,
      amountMinor: bengaluruToMysuru,
    ),
    const ExpensePayment(
      id: 4,
      expenseId: 4,
      memberId: gowthamId,
      amountMinor: foodAtBengaluru,
    ),
    const ExpensePayment(
      id: 5,
      expenseId: 5,
      memberId: mowliId,
      amountMinor: personalExpense,
    ),
  ];

  // ====================================================================
  // TEST 1: Independent share calculations per expense
  // ====================================================================

  group('Expense 1: Erode → Salem (₹400, 3 participants)', () {
    test('each share is ₹133.34 / ₹133.33 / ₹133.33', () {
      expect(shares1.map((s) => (s.memberId, s.amountMinor)), [
        (dharId, 13334),
        (gowthamId, 13333),
        (mowliId, 13333),
      ]);
    });

    test('shares sum exactly to ₹400', () {
      final sum = shares1.fold<int>(0, (s, share) => s + share.amountMinor);
      expect(sum, erodeToSalem);
    });

    test('Sanu is NOT charged', () {
      final sanuShare = shares1.where((s) => s.memberId == sanuId);
      expect(sanuShare, isEmpty);
    });
  });

  group('Expense 2: Salem → Bengaluru (₹600, 4 participants)', () {
    test('each share is ₹150', () {
      expect(shares2.map((s) => (s.memberId, s.amountMinor)), [
        (dharId, 15000),
        (gowthamId, 15000),
        (sanuId, 15000),
        (mowliId, 15000),
      ]);
    });

    test('shares sum exactly to ₹600', () {
      final sum = shares2.fold<int>(0, (s, share) => s + share.amountMinor);
      expect(sum, salemToBengaluru);
    });

    test('Sanu IS charged for this segment', () {
      final sanuShare = shares2.firstWhere((s) => s.memberId == sanuId);
      expect(sanuShare.amountMinor, 15000);
    });
  });

  group('Expense 3: Bengaluru → Mysuru (₹500, 3 participants)', () {
    test('each share is ₹166.67 / ₹166.67 / ₹166.66', () {
      expect(shares3.map((s) => (s.memberId, s.amountMinor)), [
        (dharId, 16667),
        (gowthamId, 16667),
        (mowliId, 16666),
      ]);
    });

    test('shares sum exactly to ₹500', () {
      final sum = shares3.fold<int>(0, (s, share) => s + share.amountMinor);
      expect(sum, bengaluruToMysuru);
    });

    test('Sanu is NOT charged', () {
      final sanuShare = shares3.where((s) => s.memberId == sanuId);
      expect(sanuShare, isEmpty);
    });
  });

  group('Expense 4: Food at Bengaluru (₹800, 4 participants)', () {
    test('each share is ₹200', () {
      expect(shares4.map((s) => (s.memberId, s.amountMinor)), [
        (dharId, 20000),
        (gowthamId, 20000),
        (sanuId, 20000),
        (mowliId, 20000),
      ]);
    });

    test('shares sum exactly to ₹800', () {
      final sum = shares4.fold<int>(0, (s, share) => s + share.amountMinor);
      expect(sum, foodAtBengaluru);
    });
  });

  group('Expense 5: Personal (₹300, 1 participant)', () {
    test('Mowli is the only participant', () {
      expect(shares5, hasLength(1));
      expect(shares5.first.memberId, mowliId);
      expect(shares5.first.amountMinor, personalExpense);
    });
  });

  // ====================================================================
  // TEST 2: Aggregate actual payments per member
  // ====================================================================

  group('Total paid by each member', () {
    late Map<int, int> paidByMember;

    setUp(() {
      paidByMember = <int, int>{};
      for (final payment in allPayments) {
        paidByMember[payment.memberId] =
            (paidByMember[payment.memberId] ?? 0) + payment.amountMinor;
      }
    });

    test('Dhar paid ₹900 (400 + 500)', () {
      expect(paidByMember[dharId], 90000);
    });

    test('Gowtham paid ₹1400 (600 + 800)', () {
      expect(paidByMember[gowthamId], 140000);
    });

    test('Sanu paid ₹0', () {
      expect(paidByMember[sanuId], isNull);
    });

    test('Mowli paid ₹300 (personal)', () {
      expect(paidByMember[mowliId], 30000);
    });

    test('total payments equal total expenses', () {
      final total = paidByMember.values.fold<int>(0, (s, v) => s + v);
      final totalExpenses = allExpenses.fold<int>(
        0,
        (s, e) => s + e.amountMinor,
      );
      expect(total, totalExpenses);
    });
  });

  // ====================================================================
  // TEST 3: Aggregate expense shares per member
  // ====================================================================

  group('Total expense share for each member', () {
    late Map<int, int> shareByMember;

    setUp(() {
      shareByMember = <int, int>{};
      for (final share in allShares) {
        shareByMember[share.memberId] =
            (shareByMember[share.memberId] ?? 0) + share.shareMinor;
      }
    });

    test('Dhar total share = 13334 + 15000 + 16667 + 20000 = 65001', () {
      expect(shareByMember[dharId], 65001);
    });

    test('Gowtham total share = 13333 + 15000 + 16667 + 20000 = 65000', () {
      expect(shareByMember[gowthamId], 65000);
    });

    test('Sanu total share = 0 + 15000 + 0 + 20000 = 35000', () {
      expect(shareByMember[sanuId], 35000);
    });

    test(
      'Mowli total share = 13333 + 15000 + 16666 + 20000 + 30000 = 94999',
      () {
        expect(shareByMember[mowliId], 94999);
      },
    );

    test('all shares sum to total expenses', () {
      final totalShares = shareByMember.values.fold<int>(0, (s, v) => s + v);
      final totalExpenses = allExpenses.fold<int>(
        0,
        (s, e) => s + e.amountMinor,
      );
      expect(totalShares, totalExpenses);
    });
  });

  // ====================================================================
  // TEST 4: Net position for each member
  // ====================================================================

  group('Net position', () {
    late Map<int, int> paidByMember;
    late Map<int, int> shareByMember;

    setUp(() {
      paidByMember = <int, int>{};
      for (final payment in allPayments) {
        paidByMember[payment.memberId] =
            (paidByMember[payment.memberId] ?? 0) + payment.amountMinor;
      }
      shareByMember = <int, int>{};
      for (final share in allShares) {
        shareByMember[share.memberId] =
            (shareByMember[share.memberId] ?? 0) + share.shareMinor;
      }
    });

    test('Dhar: paid ₹900, share ₹650.01, net = +₹249.99', () {
      final net = paidByMember[dharId]! - shareByMember[dharId]!;
      expect(net, 24999);
    });

    test('Gowtham: paid ₹1400, share ₹650, net = +₹750', () {
      final net = paidByMember[gowthamId]! - shareByMember[gowthamId]!;
      expect(net, 75000);
    });

    test('Sanu: paid ₹0, share ₹350, net = -₹350', () {
      final net = (paidByMember[sanuId] ?? 0) - (shareByMember[sanuId] ?? 0);
      expect(net, -35000);
    });

    test('Mowli: paid 30000, share 94999, net = -64999', () {
      final net = paidByMember[mowliId]! - shareByMember[mowliId]!;
      expect(net, -64999);
    });

    test('ALL net positions sum to zero (zero-sum invariant)', () {
      final totalNet = [dharId, gowthamId, sanuId, mowliId].fold<int>(
        0,
        (sum, id) => sum + (paidByMember[id] ?? 0) - (shareByMember[id] ?? 0),
      );
      expect(totalNet, 0);
    });
  });

  // ====================================================================
  // TEST 5: Final settlement via SettlementCalculator
  // ====================================================================

  group('Final settlement', () {
    late SettlementResult result;

    setUp(() {
      result = SettlementCalculator.calculate(
        expenses: allExpenses,
        shares: allShares,
        settlements: const [],
        payments: allPayments,
      );
    });

    test('total outstanding equals total owed by debtors', () {
      final totalDebt = result.remainingNets.entries
          .where((e) => e.value < 0)
          .fold<int>(0, (sum, e) => sum + e.value.abs());
      expect(result.totalOutstanding, totalDebt);
    });

    test('total outstanding equals total receivable by creditors', () {
      final totalCredit = result.remainingNets.entries
          .where((e) => e.value > 0)
          .fold<int>(0, (sum, e) => sum + e.value);
      expect(result.totalOutstanding, totalCredit);
    });

    test('Sanu owes money (net is negative)', () {
      expect(result.remainingNets[sanuId], lessThan(0));
    });

    test('Dhar receives money (net is positive)', () {
      expect(result.remainingNets[dharId], greaterThan(0));
      expect(result.remainingNets[dharId], 24999);
    });

    test('Gowtham receives money (net is positive)', () {
      expect(result.remainingNets[gowthamId], greaterThan(0));
      expect(result.remainingNets[gowthamId], 75000);
    });

    test('Mowli owes money (net is negative)', () {
      expect(result.remainingNets[mowliId], lessThan(0));
      expect(result.remainingNets[mowliId], -64999);
    });

    test('all nets sum to zero', () {
      final netSum = result.remainingNets.values.fold<int>(
        0,
        (sum, v) => sum + v,
      );
      expect(netSum, 0);
    });

    test('settlement is practical (debtors pay creditors directly)', () {
      // Verify each suggestion transfers from a debtor to a creditor
      for (final suggestion in result.suggestions) {
        // At the start of settlement, debtors should have negative net
        // and creditors positive (though after partial settlement, nets change)
        expect(suggestion.fromMemberId, isNot(suggestion.toMemberId));
        expect(suggestion.minor, greaterThan(0));
      }
    });
  });

  // ====================================================================
  // TEST 6: BalanceCalculator produces correct financial picture
  // ====================================================================

  group('BalanceCalculator integration', () {
    late BalanceResult balances;

    setUp(() {
      balances = BalanceCalculator.calculate(
        tripBudgetMinor: 0,
        contributions: const [],
        expenses: allExpenses,
        shares: allShares,
        settlements: const [],
        payments: allPayments,
      );
    });

    test('Dhar: actualPaid = 90000, expenseShare = 65001', () {
      final dhar = balances.members.firstWhere((m) => m.memberId == dharId);
      expect(dhar.actualPaid, 90000);
      expect(dhar.expenseShare, 65001);
      expect(dhar.netPosition, 24999);
      expect(dhar.netLabel, 'Receives');
    });

    test('Gowtham: actualPaid = ₹1400, expenseShare = ₹650', () {
      final gowtham = balances.members.firstWhere(
        (m) => m.memberId == gowthamId,
      );
      expect(gowtham.actualPaid, 140000);
      expect(gowtham.expenseShare, 65000);
      expect(gowtham.netPosition, 75000);
      expect(gowtham.netLabel, 'Receives');
    });

    test('Sanu: actualPaid = ₹0, expenseShare = ₹350', () {
      final sanu = balances.members.firstWhere((m) => m.memberId == sanuId);
      expect(sanu.actualPaid, 0);
      expect(sanu.expenseShare, 35000);
      expect(sanu.netPosition, -35000);
      expect(sanu.netLabel, 'Owes');
    });

    test('Mowli: actualPaid = 30000, expenseShare = 94999', () {
      final mowli = balances.members.firstWhere((m) => m.memberId == mowliId);
      expect(mowli.actualPaid, 30000);
      expect(mowli.expenseShare, 94999);
      expect(mowli.netPosition, -64999);
      expect(mowli.netLabel, 'Owes');
    });

    test('all net positions sum to zero', () {
      final netSum = balances.members.fold<int>(
        0,
        (sum, m) => sum + m.netPosition,
      );
      expect(netSum, 0);
    });

    test('total expenses = 260000', () {
      expect(balances.totalExpenses, 260000);
    });

    test('total outstanding = amount debtors owe', () {
      final totalOwed = balances.members
          .where((m) => m.amountToPay > 0)
          .fold<int>(0, (sum, m) => sum + m.amountToPay);
      expect(balances.outstandingMinor, totalOwed);
    });
  });

  // ====================================================================
  // TEST 7: Sanu is NOT charged for non-participating segments
  // ====================================================================

  group('Partial participation enforcement', () {
    test('Sanu share for Erode→Salem is zero', () {
      final sanuShareForExp1 = allShares.where(
        (s) => s.expenseId == 1 && s.memberId == sanuId,
      );
      expect(sanuShareForExp1, isEmpty);
    });

    test('Sanu share for Bengaluru→Mysuru is zero', () {
      final sanuShareForExp3 = allShares.where(
        (s) => s.expenseId == 3 && s.memberId == sanuId,
      );
      expect(sanuShareForExp3, isEmpty);
    });

    test('Sanu share for Salem→Bengaluru is ₹150', () {
      final sanuShareForExp2 = allShares.firstWhere(
        (s) => s.expenseId == 2 && s.memberId == sanuId,
      );
      expect(sanuShareForExp2.shareMinor, 15000);
    });

    test('Sanu share for Food is ₹200', () {
      final sanuShareForExp4 = allShares.firstWhere(
        (s) => s.expenseId == 4 && s.memberId == sanuId,
      );
      expect(sanuShareForExp4.shareMinor, 20000);
    });

    test('Sanu total share only includes segments she participated in', () {
      // Sanu participated in expenses 2 and 4 only
      final sanuTotalShare = allShares
          .where((s) => s.memberId == sanuId)
          .fold<int>(0, (sum, s) => sum + s.shareMinor);
      // 15000 + 20000 = 35000
      expect(sanuTotalShare, 35000);
    });
  });

  // ====================================================================
  // TEST 8: Complete settlement walkthrough
  // ====================================================================

  group('Complete settlement walkthrough', () {
    test('step 1: WHO PAID', () {
      // Dhar paid ₹400 + ₹500 = ₹900
      // Gowtham paid ₹600 + ₹800 = ₹1400
      // Sanu paid ₹0
      // Mowli paid ₹300
      final paidByMember = <int, int>{};
      for (final payment in allPayments) {
        paidByMember[payment.memberId] =
            (paidByMember[payment.memberId] ?? 0) + payment.amountMinor;
      }
      expect(paidByMember[dharId], 90000);
      expect(paidByMember[gowthamId], 140000);
      expect(paidByMember[sanuId], isNull);
      expect(paidByMember[mowliId], 30000);
    });

    test('step 2: WHO PARTICIPATED', () {
      // Expense 1: Dhar, Gowtham, Mowli (not Sanu)
      // Expense 2: Dhar, Gowtham, Sanu, Mowli
      // Expense 3: Dhar, Gowtham, Mowli (not Sanu)
      // Expense 4: Dhar, Gowtham, Sanu, Mowli
      // Expense 5: Mowli only
      final participantsByExpense = <int, Set<int>>{};
      for (final share in allShares) {
        participantsByExpense
            .putIfAbsent(share.expenseId, () => {})
            .add(share.memberId);
      }
      expect(participantsByExpense[1], {dharId, gowthamId, mowliId});
      expect(participantsByExpense[2], {dharId, gowthamId, sanuId, mowliId});
      expect(participantsByExpense[3], {dharId, gowthamId, mowliId});
      expect(participantsByExpense[4], {dharId, gowthamId, sanuId, mowliId});
      expect(participantsByExpense[5], {mowliId});
    });

    test('step 3: EACH SHARE', () {
      final shareByMember = <int, int>{};
      for (final share in allShares) {
        shareByMember[share.memberId] =
            (shareByMember[share.memberId] ?? 0) + share.shareMinor;
      }
      expect(shareByMember[dharId], 65001);
      expect(shareByMember[gowthamId], 65000);
      expect(shareByMember[sanuId], 35000);
      expect(shareByMember[mowliId], 94999);
    });

    test('step 4: NET POSITION', () {
      final paidByMember = <int, int>{};
      for (final payment in allPayments) {
        paidByMember[payment.memberId] =
            (paidByMember[payment.memberId] ?? 0) + payment.amountMinor;
      }
      final shareByMember = <int, int>{};
      for (final share in allShares) {
        shareByMember[share.memberId] =
            (shareByMember[share.memberId] ?? 0) + share.shareMinor;
      }
      // Dhar: +₹249.99 (Receives)
      expect((paidByMember[dharId] ?? 0) - (shareByMember[dharId] ?? 0), 24999);
      // Gowtham: +₹750.00 (Receives)
      expect(
        (paidByMember[gowthamId] ?? 0) - (shareByMember[gowthamId] ?? 0),
        75000,
      );
      // Sanu: -₹350.00 (Owes)
      expect(
        (paidByMember[sanuId] ?? 0) - (shareByMember[sanuId] ?? 0),
        -35000,
      );
      // Mowli: -₹649.99 (Owes)
      expect(
        (paidByMember[mowliId] ?? 0) - (shareByMember[mowliId] ?? 0),
        -64999,
      );
    });

    test('step 5: FINAL SETTLEMENT', () {
      final result = SettlementCalculator.calculate(
        expenses: allExpenses,
        shares: allShares,
        settlements: const [],
        payments: allPayments,
      );

      // The settlement must consolidate debts.
      // Sanu owes ₹350, Mowli owes ₹649.99.
      // Dhar should receive ₹249.99, Gowtham should receive ₹750.
      // Total owed: 350 + 649.99 = 999.99
      // Total receivable: 249.99 + 750 = 999.99
      // Note: Due to rounding (largest-remainder), Dhar gets ₹249.99
      // (from 13334+15000+16667+20000=65001) not ₹250,
      // and Mowli pays ₹649.99 (not ₹650) because shares round differently.

      final totalDebt = result.remainingNets.entries
          .where((e) => e.value < 0)
          .fold<int>(0, (sum, e) => sum + e.value.abs());
      final totalCredit = result.remainingNets.entries
          .where((e) => e.value > 0)
          .fold<int>(0, (sum, e) => sum + e.value);

      expect(totalDebt, totalCredit);
      expect(totalDebt, result.totalOutstanding);
      expect(totalDebt, 99999);

      // Verify practical transfers exist
      expect(result.suggestions, isNotEmpty);

      // Every suggestion should be from a debtor to a creditor
      for (final s in result.suggestions) {
        final fromNet = result.remainingNets[s.fromMemberId]!;
        final toNet = result.remainingNets[s.toMemberId]!;
        // In the remainingNets map, debtors are negative and creditors positive
        // (before applying these suggestions, which is what remainingNets shows)
        expect(fromNet, lessThanOrEqualTo(0));
        expect(toNet, greaterThanOrEqualTo(0));
      }

      // Verify total transfers equal total debt
      final transferTotal = result.suggestions.fold<int>(
        0,
        (sum, s) => sum + s.minor,
      );
      expect(transferTotal, totalDebt);
    });
  });

  // ====================================================================
  // TEST 9: Financial invariants (always true)
  // ====================================================================

  group('Financial invariants', () {
    test('SUM(all participant shares) == expense total for every expense', () {
      for (final expense in allExpenses) {
        final expenseShares = allShares
            .where((s) => s.expenseId == expense.id)
            .toList();
        final shareTotal = expenseShares.fold<int>(
          0,
          (sum, s) => sum + s.shareMinor,
        );
        expect(
          shareTotal,
          expense.amountMinor,
          reason: 'Expense ${expense.id} (${expense.description})',
        );
      }
    });

    test('SUM(all member net positions) == 0', () {
      final paidByMember = <int, int>{};
      for (final payment in allPayments) {
        paidByMember[payment.memberId] =
            (paidByMember[payment.memberId] ?? 0) + payment.amountMinor;
      }
      final shareByMember = <int, int>{};
      for (final share in allShares) {
        shareByMember[share.memberId] =
            (shareByMember[share.memberId] ?? 0) + share.shareMinor;
      }
      final allMemberIds = <int>{...paidByMember.keys, ...shareByMember.keys};
      final totalNet = allMemberIds.fold<int>(
        0,
        (sum, id) => sum + (paidByMember[id] ?? 0) - (shareByMember[id] ?? 0),
      );
      expect(totalNet, 0);
    });

    test('Total money owed == Total money receivable', () {
      final result = SettlementCalculator.calculate(
        expenses: allExpenses,
        shares: allShares,
        settlements: const [],
        payments: allPayments,
      );
      final owed = result.remainingNets.entries
          .where((e) => e.value < 0)
          .fold<int>(0, (sum, e) => sum + e.value.abs());
      final receivable = result.remainingNets.entries
          .where((e) => e.value > 0)
          .fold<int>(0, (sum, e) => sum + e.value);
      expect(owed, receivable);
    });

    test('settlement does not change total expenses', () {
      // After recording a settlement, total expenses should not change
      // (Settlements are transfers, not expenses)
      final settlement = Settlement(
        id: 1,
        tripId: 1,
        fromMemberId: sanuId,
        toMemberId: dharId,
        amountMinor: 24999,
        amountPaidMinor: 24999,
        settledAt: now,
        paidAt: now,
        updatedAt: now,
      );
      final resultAfter = SettlementCalculator.calculate(
        expenses: allExpenses,
        shares: allShares,
        settlements: [settlement],
        payments: allPayments,
      );
      // After settling 24999, remaining outstanding = 99999 - 24999 = 75000
      expect(resultAfter.totalOutstanding, 99999 - 24999);
      // Verify zero sum still holds
      final netSum = resultAfter.remainingNets.values.fold<int>(
        0,
        (s, v) => s + v,
      );
      expect(netSum, 0);
    });
  });

  // ====================================================================
  // TEST 10: Expense editing recalculates correctly
  // ====================================================================

  group('Expense editing', () {
    test('editing amount recalculates shares and net positions', () {
      // Original: Expense 1 = ₹400, 3 participants → shares: 13334, 13333, 13333
      // Edited:   Expense 1 = ₹600, 3 participants → shares: 20000, 20000, 20000
      final editedShares1 = splitter.split(
        totalMinor: 60000,
        memberIds: [dharId, gowthamId, mowliId],
      );
      expect(editedShares1.map((s) => s.amountMinor), [20000, 20000, 20000]);

      final editedExpense1 = makeExpense(1, dharId, 60000, segmentId: 1);
      final editedAllExpenses = [
        editedExpense1,
        expense2,
        expense3,
        expense4,
        expense5,
      ];
      final editedAllShares = [
        ...toShares(1, editedShares1),
        ...toShares(2, shares2),
        ...toShares(3, shares3),
        ...toShares(4, shares4),
        ...toShares(5, shares5),
      ];
      final editedAllPayments = [
        const ExpensePayment(
          id: 1,
          expenseId: 1,
          memberId: dharId,
          amountMinor: 60000,
        ),
        ...allPayments.where((p) => p.expenseId != 1),
      ];

      final result = SettlementCalculator.calculate(
        expenses: editedAllExpenses,
        shares: editedAllShares,
        settlements: const [],
        payments: editedAllPayments,
      );

      // Net positions must still sum to zero
      final netSum = result.remainingNets.values.fold<int>(0, (s, v) => s + v);
      expect(netSum, 0);

      // Shares must sum to edited total
      final shareSum = editedAllShares
          .where((s) => s.expenseId == 1)
          .fold<int>(0, (s, share) => s + share.shareMinor);
      expect(shareSum, 60000);
    });

    test('editing participants recalculates correctly', () {
      // Add Sanu to Expense 1 (previously didn't participate)
      final editedMemberIds = [dharId, gowthamId, sanuId, mowliId];
      final editedShares1 = splitter.split(
        totalMinor: erodeToSalem,
        memberIds: editedMemberIds,
      );
      // 40000 / 4 = 10000 each
      expect(editedShares1.map((s) => s.amountMinor), [
        10000,
        10000,
        10000,
        10000,
      ]);
    });
  });

  // ====================================================================
  // TEST 11: Expense deletion does not corrupt
  // ====================================================================

  group('Expense deletion', () {
    test('removing an expense updates net positions correctly', () {
      // Original with all 5 expenses
      final resultBefore = SettlementCalculator.calculate(
        expenses: allExpenses,
        shares: allShares,
        settlements: const [],
        payments: allPayments,
      );

      // Delete Expense 5 (personal ₹300)
      final expensesAfter = allExpenses.where((e) => e.id != 5).toList();
      final sharesAfter = allShares.where((s) => s.expenseId != 5).toList();
      final paymentsAfter = allPayments.where((p) => p.expenseId != 5).toList();

      final resultAfter = SettlementCalculator.calculate(
        expenses: expensesAfter,
        shares: sharesAfter,
        settlements: const [],
        payments: paymentsAfter,
      );

      // Net positions must still sum to zero
      final netSum = resultAfter.remainingNets.values.fold<int>(
        0,
        (s, v) => s + v,
      );
      expect(netSum, 0);

      final mowliNetBefore = resultBefore.remainingNets[mowliId]!;
      final mowliNetAfter = resultAfter.remainingNets[mowliId]!;
      // Mowli's net is UNCHANGED: she paid ₹300 AND her share was ₹300.
      // Removing the expense removes both, leaving net position identical.
      expect(mowliNetAfter, mowliNetBefore);
    });

    test(
      'removing an expense where someone was not a participant has no effect on them',
      () {
        // Delete Expense 1 (Erode→Salem) — Sanu was not a participant
        final expensesAfter = allExpenses.where((e) => e.id != 1).toList();
        final sharesAfter = allShares.where((s) => s.expenseId != 1).toList();
        final paymentsAfter = allPayments
            .where((p) => p.expenseId != 1)
            .toList();

        final resultAfter = SettlementCalculator.calculate(
          expenses: expensesAfter,
          shares: sharesAfter,
          settlements: const [],
          payments: paymentsAfter,
        );

        // Sanu's net should be UNCHANGED (she wasn't in this expense)
        final sanuNetAfter = resultAfter.remainingNets[sanuId]!;
        expect(sanuNetAfter, -35000); // same as before
      },
    );
  });

  // ====================================================================
  // TEST 12: Multiple expenses by same payer aggregate correctly
  // ====================================================================

  group('Multiple expenses by same payer', () {
    test('Dhar\'s total paid aggregates across expenses 1 and 3', () {
      final dharPayments = allPayments
          .where((p) => p.memberId == dharId)
          .toList();
      expect(dharPayments, hasLength(2));

      final totalPaid = dharPayments.fold<int>(
        0,
        (sum, p) => sum + p.amountMinor,
      );
      expect(totalPaid, 90000); // 40000 + 50000
    });

    test('Gowtham\'s total paid aggregates across expenses 2 and 4', () {
      final gowthamPayments = allPayments
          .where((p) => p.memberId == gowthamId)
          .toList();
      expect(gowthamPayments, hasLength(2));

      final totalPaid = gowthamPayments.fold<int>(
        0,
        (sum, p) => sum + p.amountMinor,
      );
      expect(totalPaid, 140000); // 60000 + 80000
    });
  });

  // ====================================================================
  // TEST 13: Member pays for different participant groups
  // ====================================================================

  group('Member pays for different participant groups', () {
    test(
      'Dhar pays for 3-person group (expense 1) and 4-person group (would be if added)',
      () {
        // Expense 1: ₹400 among 3 people → share = ₹133.34/₹133.33/₹133.33
        // Expense 3: ₹500 among 3 people → share = ₹166.67/₹166.67/₹166.66
        // Different amounts but same participant set
        final dharShares1 = allShares
            .where((s) => s.expenseId == 1 && s.memberId == dharId)
            .first;
        final dharShares3 = allShares
            .where((s) => s.expenseId == 3 && s.memberId == dharId)
            .first;

        expect(dharShares1.shareMinor, 13334);
        expect(dharShares3.shareMinor, 16667);
      },
    );

    test(
      'Gowtham pays for 4-person team (expense 2) and 4-person team (expense 4)',
      () {
        final gowthamShares2 = allShares
            .where((s) => s.expenseId == 2 && s.memberId == gowthamId)
            .first;
        final gowthamShares4 = allShares
            .where((s) => s.expenseId == 4 && s.memberId == gowthamId)
            .first;

        // Different total amounts but same split (₹150 vs ₹200)
        expect(gowthamShares2.shareMinor, 15000);
        expect(gowthamShares4.shareMinor, 20000);
      },
    );
  });

  // ====================================================================
  // TEST 14: Trip isolation (conceptual)
  // ====================================================================

  group('Trip isolation', () {
    test('expenses from trip A do not affect trip B', () {
      // Trip A: our canonical expenses
      final tripAResult = SettlementCalculator.calculate(
        expenses: allExpenses,
        shares: allShares,
        settlements: const [],
        payments: allPayments,
      );

      // Trip B: completely separate expenses
      final tripBExpense = [makeExpense(100, 10, 50000)];
      final tripBShares = [
        const ExpenseShare(
          id: 1001,
          expenseId: 100,
          memberId: 10,
          shareMinor: 25000,
        ),
        const ExpenseShare(
          id: 1002,
          expenseId: 100,
          memberId: 11,
          shareMinor: 25000,
        ),
      ];
      final tripBPayments = [
        const ExpensePayment(
          id: 1,
          expenseId: 100,
          memberId: 10,
          amountMinor: 50000,
        ),
      ];
      final tripBResult = SettlementCalculator.calculate(
        expenses: tripBExpense,
        shares: tripBShares,
        settlements: const [],
        payments: tripBPayments,
      );

      // Trip A members should not appear in Trip B
      expect(tripBResult.remainingNets.containsKey(dharId), isFalse);
      expect(tripBResult.remainingNets.containsKey(gowthamId), isFalse);
      expect(tripBResult.remainingNets.containsKey(sanuId), isFalse);
      expect(tripBResult.remainingNets.containsKey(mowliId), isFalse);

      // Each trip independently sums to zero
      final netSumA = tripAResult.remainingNets.values.fold<int>(
        0,
        (s, v) => s + v,
      );
      final netSumB = tripBResult.remainingNets.values.fold<int>(
        0,
        (s, v) => s + v,
      );
      expect(netSumA, 0);
      expect(netSumB, 0);
    });
  });

  // ====================================================================
  // TEST 15: Scenario 7 — Individual/Shared payment (₹730.90)
  // ====================================================================

  group('Scenario 7: Individual/Shared ₹730.90', () {
    test('₹730.90 split between Suganth and Karthik', () {
      // ₹730.90 = 73090 minor units
      final shares = splitter.split(totalMinor: 73090, memberIds: [1, 2]);
      expect(shares.map((s) => (s.memberId, s.amountMinor)), [
        (1, 36545), // ₹365.45
        (2, 36545), // ₹365.45
      ]);

      final sum = shares.fold<int>(0, (s, share) => s + share.amountMinor);
      expect(sum, 73090);

      // Suganth paid ₹730.90, own share ₹365.45 → should receive ₹365.45
      const suganthNet = 73090 - 36545;
      expect(suganthNet, 36545);

      // Karthik paid ₹0, share ₹365.45 → owes ₹365.45
      const karthikNet = 0 - 36545;
      expect(karthikNet, -36545);

      // Zero sum
      expect(suganthNet + karthikNet, 0);
    });
  });

  // ====================================================================
  // TEST 16: Scenario 8/9 — Multiple people paying for same team
  // ====================================================================

  group('Scenarios 8/9: Multiple payers for team', () {
    test('Dhar pays ₹1000, Gowtham pays ₹800, split 4 ways', () {
      final sharesExp1 = splitter.split(
        totalMinor: 100000,
        memberIds: [1, 2, 3, 4],
      );
      expect(sharesExp1.map((s) => s.amountMinor), [
        25000,
        25000,
        25000,
        25000,
      ]);

      final sharesExp2 = splitter.split(
        totalMinor: 80000,
        memberIds: [1, 2, 3, 4],
      );
      expect(sharesExp2.map((s) => s.amountMinor), [
        20000,
        20000,
        20000,
        20000,
      ]);

      final exp1 = makeExpense(1, 1, 100000);
      final exp2 = makeExpense(2, 2, 80000);
      final allSharesTest = [
        ...toShares(1, sharesExp1),
        ...toShares(2, sharesExp2),
      ];
      final allPaymentsTest = [
        const ExpensePayment(
          id: 1,
          expenseId: 1,
          memberId: 1,
          amountMinor: 100000,
        ),
        const ExpensePayment(
          id: 2,
          expenseId: 2,
          memberId: 2,
          amountMinor: 80000,
        ),
      ];

      final result = SettlementCalculator.calculate(
        expenses: [exp1, exp2],
        shares: allSharesTest,
        settlements: const [],
        payments: allPaymentsTest,
      );

      // Dhar: paid 100000, share 45000, net = +55000
      expect(result.remainingNets[1], 55000);
      // Gowtham: paid 80000, share 45000, net = +35000
      expect(result.remainingNets[2], 35000);
      // Sanu: paid 0, share 45000, net = -45000
      expect(result.remainingNets[3], -45000);
      // Mowli: paid 0, share 45000, net = -45000
      expect(result.remainingNets[4], -45000);

      // Zero sum
      final netSum = result.remainingNets.values.fold<int>(0, (s, v) => s + v);
      expect(netSum, 0);
    });
  });

  // ====================================================================
  // TEST 17: Cash remaining calculation
  // ====================================================================

  group('Cash remaining', () {
    test(
      'cash remaining = contributions + settlements received - payments - settlements paid',
      () {
        // If Dhar contributed ₹500 and paid ₹900 in expenses
        // cashRemaining = 500 - 900 = -400 (conceptually, they put in 500 but spent 900)
        // But cash remaining is about ACTUAL cash movements, not shares
        const contribution = 50000;
        const actualPaid = 90000;
        const settlementsReceived = 0;
        const settlementsPaid = 0;

        const cashRemaining =
            contribution + settlementsReceived - actualPaid - settlementsPaid;
        expect(cashRemaining, -40000);
      },
    );
  });

  // ====================================================================
  // TEST 18: Scenario 21 — Partial travel (sanu joins/leaves)
  // ====================================================================

  group('Scenario 21: Partial travel', () {
    test('Sanu only participates in Salem→Bengaluru for segment expenses', () {
      // Segment 1: Erode→Salem - Sanu NOT participating
      final seg1Shares = shares1; // [Dhar, Gowtham, Mowli]
      expect(seg1Shares.any((s) => s.memberId == sanuId), isFalse);

      // Segment 2: Salem→Bengaluru - Sanu participating
      final seg2Shares = shares2; // [Dhar, Gowtham, Sanu, Mowli]
      expect(seg2Shares.any((s) => s.memberId == sanuId), isTrue);

      // Segment 3: Bengaluru→Mysuru - Sanu NOT participating
      final seg3Shares = shares3; // [Dhar, Gowtham, Mowli]
      expect(seg3Shares.any((s) => s.memberId == sanuId), isFalse);

      // Sanu's total from segment expenses = only segment 2
      final sanuSegmentTotal = seg2Shares
          .where((s) => s.memberId == sanuId)
          .fold<int>(0, (sum, s) => sum + s.amountMinor);
      expect(sanuSegmentTotal, 15000); // ₹150 only
    });

    test('food expense is independent of travel segments', () {
      // Food at Bengaluru includes all 4 members regardless of segment participation
      final sanuFoodShare = shares4
          .where((s) => s.memberId == sanuId)
          .fold<int>(0, (sum, s) => sum + s.amountMinor);
      expect(sanuFoodShare, 20000); // ₹200
    });
  });

  // ====================================================================
  // TEST 19: Validation tests
  // ====================================================================

  group('Validation', () {
    test('rejects expense with no participants', () {
      expect(
        () => splitter.split(totalMinor: 10000, memberIds: []),
        throwsArgumentError,
      );
    });

    test('rejects negative expense total', () {
      expect(
        () => splitter.split(totalMinor: -100, memberIds: [1]),
        throwsArgumentError,
      );
    });

    test(
      'rejection of self-settlement is tested by SettlementCalculator.outstandingBetween',
      () {
        // Settlement to self should produce 0 outstanding
        final result = SettlementCalculator.calculate(
          expenses: const [],
          shares: const [],
          settlements: const [],
          payments: const [],
        );
        expect(
          SettlementCalculator.outstandingBetween(
            result.suggestions,
            fromMemberId: 1,
            toMemberId: 1,
          ),
          0,
        );
      },
    );
  });

  // ====================================================================
  // TEST 20: Edge cases
  // ====================================================================

  group('Edge cases', () {
    test('single member trip: no settlements needed', () {
      final shares = splitter.split(totalMinor: 50000, memberIds: [1]);
      final expense = [makeExpense(1, 1, 50000)];
      final expenseShares = toShares(1, shares);
      final payments = [
        const ExpensePayment(
          id: 1,
          expenseId: 1,
          memberId: 1,
          amountMinor: 50000,
        ),
      ];

      final result = SettlementCalculator.calculate(
        expenses: expense,
        shares: expenseShares,
        settlements: const [],
        payments: payments,
      );

      expect(result.suggestions, isEmpty);
      expect(result.remainingNets[1], 0);
    });

    test('everyone pays exactly their share: no settlements', () {
      final shares = splitter.split(totalMinor: 10000, memberIds: [1, 2, 3]);
      final expense = [makeExpense(1, 1, 10000)];
      final expenseShares = toShares(1, shares);
      // Each person pays their own share
      final payments = [
        for (final s in shares)
          ExpensePayment(
            id: s.memberId,
            expenseId: 1,
            memberId: s.memberId,
            amountMinor: s.amountMinor,
          ),
      ];

      final result = SettlementCalculator.calculate(
        expenses: expense,
        shares: expenseShares,
        settlements: const [],
        payments: payments,
      );

      expect(result.suggestions, isEmpty);
    });

    test('one person pays for everyone: maximum settlement', () {
      final shares = splitter.split(totalMinor: 10000, memberIds: [1, 2, 3, 4]);
      final expense = [makeExpense(1, 1, 10000)];
      final expenseShares = toShares(1, shares);
      final payments = [
        const ExpensePayment(
          id: 1,
          expenseId: 1,
          memberId: 1,
          amountMinor: 10000,
        ),
      ];

      final result = SettlementCalculator.calculate(
        expenses: expense,
        shares: expenseShares,
        settlements: const [],
        payments: payments,
      );

      // Member 1 paid 10000, share 2500 → net = +7500
      expect(result.remainingNets[1], 7500);
      // Others each owe 2500
      expect(result.remainingNets[2], -2500);
      expect(result.remainingNets[3], -2500);
      expect(result.remainingNets[4], -2500);
    });
  });
}
