import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/balances.dart';
import 'package:tripsplit/core/calculations/expense_split.dart';
import 'package:tripsplit/core/calculations/participation.dart';
import 'package:tripsplit/core/calculations/settlements.dart';
import 'package:tripsplit/features/expenses/domain/expense.dart';
import 'package:tripsplit/features/expenses/domain/expense_payment.dart';
import 'package:tripsplit/features/expenses/domain/expense_scope.dart';
import 'package:tripsplit/features/expenses/domain/expense_share.dart';
import 'package:tripsplit/features/journey/domain/journey.dart';
import 'package:tripsplit/features/members/domain/member.dart';

void main() {
  // ── Problem 9: Complex journey with duplicate locations ──────────────

  group('Problem 9 — Complex journey: Erode→Chennai→Hyderabad→Bengaluru→'
      'Chennai→Bengaluru→Erode', () {
    late List<TripLocation> locations;
    late List<TravelSegment> segments;

    setUp(() {
      // Erode=1, Chennai=2, Hyderabad=3, Bengaluru=4
      locations = const [
        TripLocation(id: 1, tripId: 1, name: 'Erode'),
        TripLocation(id: 2, tripId: 1, name: 'Chennai'),
        TripLocation(id: 3, tripId: 1, name: 'Hyderabad'),
        TripLocation(id: 4, tripId: 1, name: 'Bengaluru'),
      ];

      // Segments:
      // 0: Erode→Chennai
      // 1: Chennai→Hyderabad
      // 2: Hyderabad→Bengaluru
      // 3: Bengaluru→Chennai
      // 4: Chennai→Bengaluru
      // 5: Bengaluru→Erode
      segments = const [
        TravelSegment(
          id: 1,
          tripId: 1,
          sequence: 0,
          startLocationId: 1,
          endLocationId: 2,
        ),
        TravelSegment(
          id: 2,
          tripId: 1,
          sequence: 1,
          startLocationId: 2,
          endLocationId: 3,
        ),
        TravelSegment(
          id: 3,
          tripId: 1,
          sequence: 2,
          startLocationId: 3,
          endLocationId: 4,
        ),
        TravelSegment(
          id: 4,
          tripId: 1,
          sequence: 3,
          startLocationId: 4,
          endLocationId: 2,
        ),
        TravelSegment(
          id: 5,
          tripId: 1,
          sequence: 4,
          startLocationId: 2,
          endLocationId: 4,
        ),
        TravelSegment(
          id: 6,
          tripId: 1,
          sequence: 5,
          startLocationId: 4,
          endLocationId: 1,
        ),
      ];
    });

    Member member(int id, String name, {int? joinId, int? leaveId}) => Member(
      id: id,
      tripId: 1,
      name: name,
      joinLocationId: joinId,
      leaveLocationId: leaveId,
      createdAt: DateTime(2026, 9, 15),
    );

    test('Sanusha joins at Bengaluru and leaves at Bengaluru — '
        'participates only in segments 3 and 4', () {
      // Sanusha: join=Bengaluru(4), leave=Bengaluru(4)
      // With duplicate locations, she should participate in:
      //   Segment 3: Bengaluru→Chennai (starts at first Bengaluru)
      //   Segment 4: Chennai→Bengaluru (ends at second Bengaluru)
      final sanusha = member(1, 'Sanusha', joinId: 4, leaveId: 4);
      final members = [sanusha];

      final results = <int, bool>{};
      for (var i = 0; i < segments.length; i++) {
        results[segments[i].id] = ParticipationCalculator.participatesInSegment(
          memberId: sanusha.id,
          segment: segments[i],
          segmentOrder: i,
          members: members,
          segments: segments,
          locations: locations,
          participations: const [],
        );
      }

      // Segments 1, 2, 5 should NOT participate
      expect(results[1], isFalse, reason: 'Erode→Chennai');
      expect(results[2], isFalse, reason: 'Chennai→Hyderabad');
      expect(results[3], isFalse, reason: 'Hyderabad→Bengaluru');
      // Segments 3, 4 SHOULD participate
      expect(results[4], isTrue, reason: 'Bengaluru→Chennai');
      expect(results[5], isTrue, reason: 'Chennai→Bengaluru');
      // Segment 6 should NOT participate
      expect(results[6], isFalse, reason: 'Bengaluru→Erode');
    });

    test('Member joins at Chennai (first) and leaves at Chennai (second) — '
        'participates in segments 1, 2, 3', () {
      final member1 = member(2, 'Karthik', joinId: 2, leaveId: 2);
      final members = [member1];

      final results = <int, bool>{};
      for (var i = 0; i < segments.length; i++) {
        results[segments[i].id] = ParticipationCalculator.participatesInSegment(
          memberId: member1.id,
          segment: segments[i],
          segmentOrder: i,
          members: members,
          segments: segments,
          locations: locations,
          participations: const [],
        );
      }

      expect(results[1], isFalse, reason: 'Erode→Chennai (before join)');
      expect(results[2], isTrue, reason: 'Chennai→Hyderabad');
      expect(results[3], isTrue, reason: 'Hyderabad→Bengaluru');
      expect(results[4], isTrue, reason: 'Bengaluru→Chennai');
      expect(results[5], isFalse, reason: 'Chennai→Bengaluru (after leave)');
      expect(results[6], isFalse, reason: 'Bengaluru→Erode (after leave)');
    });

    test('Member joins at Erode (start) and leaves at Erode (end) — '
        'participates in all segments', () {
      final member1 = member(3, 'Full', joinId: 1, leaveId: 1);
      final members = [member1];

      final results = <int, bool>{};
      for (var i = 0; i < segments.length; i++) {
        results[segments[i].id] = ParticipationCalculator.participatesInSegment(
          memberId: member1.id,
          segment: segments[i],
          segmentOrder: i,
          members: members,
          segments: segments,
          locations: locations,
          participations: [],
        );
      }

      // Erode appears at index 0 and index 6.
      // joinIndex = 0 (first Erode), leaveIndex = 6 (first Erode after 0)
      for (final segment in segments) {
        expect(
          results[segment.id],
          isTrue,
          reason: 'Segment ${segment.id} should be participated',
        );
      }
    });

    test(
      'Member with no join/leave — participates in all segments (default)',
      () {
        final member1 = member(4, 'Default');
        final members = [member1];

        for (var i = 0; i < segments.length; i++) {
          final result = ParticipationCalculator.participatesInSegment(
            memberId: member1.id,
            segment: segments[i],
            segmentOrder: i,
            members: members,
            segments: segments,
            locations: locations,
            participations: const [],
          );
          expect(result, isTrue, reason: 'Segment ${segments[i].id}');
        }
      },
    );

    test('explicit override still wins over join/leave derivation', () {
      final sanusha = member(1, 'Sanusha', joinId: 4, leaveId: 4);
      final members = [sanusha];

      // Override: mark Sanusha as NOT participating in segment 4
      // (even though join/leave says she should)
      final overrides = [
        const MemberParticipation(
          memberId: 1,
          segmentId: 4,
          participating: false,
        ),
      ];

      final result = ParticipationCalculator.participatesInSegment(
        memberId: 1,
        segment: segments[3], // segment 4 (0-indexed: 3), id=4
        segmentOrder: 3,
        members: members,
        segments: segments,
        locations: locations,
        participations: overrides,
      );

      expect(result, isFalse);
    });

    test(
      'deriveForMember produces correct participation map for complex journey',
      () {
        final sanusha = member(1, 'Sanusha', joinId: 4, leaveId: 4);
        final derived = ParticipationCalculator.deriveForMember(
          member: sanusha,
          segments: segments,
          existing: const [],
        );

        // Segment IDs are 1..6
        expect(derived[1], isFalse, reason: 'Erode→Chennai');
        expect(derived[2], isFalse, reason: 'Chennai→Hyderabad');
        expect(derived[3], isFalse, reason: 'Hyderabad→Bengaluru');
        expect(derived[4], isTrue, reason: 'Bengaluru→Chennai');
        expect(derived[5], isTrue, reason: 'Chennai→Bengaluru');
        expect(derived[6], isFalse, reason: 'Bengaluru→Erode');
      },
    );

    test(
      'participatingMemberIds returns correct set for Bengaluru segment',
      () {
        final sanusha = member(1, 'Sanusha', joinId: 4, leaveId: 4);
        final fullMember = member(2, 'Full');
        final members = [sanusha, fullMember];

        final ids = ParticipationCalculator.participatingMemberIds(
          segment: segments[3], // Bengaluru→Chennai (id=4, sequence=3)
          segmentOrder: 3,
          members: members,
          segments: segments,
          locations: locations,
          participations: const [],
        );

        expect(ids, contains(1), reason: 'Sanusha should participate');
        expect(ids, contains(2), reason: 'Full member should participate');
      },
    );

    test('participatingMemberIds excludes Sanusha from Erode→Chennai', () {
      final sanusha = member(1, 'Sanusha', joinId: 4, leaveId: 4);
      final fullMember = member(2, 'Full');
      final members = [sanusha, fullMember];

      final ids = ParticipationCalculator.participatingMemberIds(
        segment: segments[0], // Erode→Chennai (id=1, sequence=0)
        segmentOrder: 0,
        members: members,
        segments: segments,
        locations: locations,
        participations: const [],
      );

      expect(ids, isNot(contains(1)), reason: 'Sanusha should NOT participate');
      expect(ids, contains(2), reason: 'Full member should participate');
    });
  });

  // ── Problem 9 continued: Full E2E settlement for complex journey ────

  group('Problem 9 — E2E settlement for complex journey', () {
    test('Sanusha only pays for segments she participated in', () {
      const splitter = EqualExpenseSplitter();

      // Members
      const sanushaId = 1;
      const fullId = 2;

      final sanusha = Member(
        id: sanushaId,
        tripId: 1,
        name: 'Sanusha',
        joinLocationId: 4,
        leaveLocationId: 4,
        createdAt: DateTime(2026, 9, 15),
      );
      final fullMember = Member(
        id: fullId,
        tripId: 1,
        name: 'Full',
        createdAt: DateTime(2026, 9, 15),
      );

      // Complex journey segments
      final segments = [
        const TravelSegment(
          id: 1,
          tripId: 1,
          sequence: 0,
          startLocationId: 1,
          endLocationId: 2,
        ),
        const TravelSegment(
          id: 2,
          tripId: 1,
          sequence: 1,
          startLocationId: 2,
          endLocationId: 3,
        ),
        const TravelSegment(
          id: 3,
          tripId: 1,
          sequence: 2,
          startLocationId: 3,
          endLocationId: 4,
        ),
        const TravelSegment(
          id: 4,
          tripId: 1,
          sequence: 3,
          startLocationId: 4,
          endLocationId: 2,
        ),
        const TravelSegment(
          id: 5,
          tripId: 1,
          sequence: 4,
          startLocationId: 2,
          endLocationId: 4,
        ),
        const TravelSegment(
          id: 6,
          tripId: 1,
          sequence: 5,
          startLocationId: 4,
          endLocationId: 1,
        ),
      ];

      // Derive participation
      final sanushaParticipation = ParticipationCalculator.deriveForMember(
        member: sanusha,
        segments: segments,
        existing: const [],
      );
      final fullParticipation = ParticipationCalculator.deriveForMember(
        member: fullMember,
        segments: segments,
        existing: const [],
      );

      // Expense: Bengaluru→Chennai (segment 4, sequence 3) — ₹600, Full pays
      // Sanusha participates (Bengaluru→Chennai is in her range)
      final segParticipants = <int>[];
      if (sanushaParticipation[4] == true) segParticipants.add(sanushaId);
      if (fullParticipation[4] == true) segParticipants.add(fullId);
      expect(segParticipants, [sanushaId, fullId]);

      final sharesSeg4 = splitter.split(
        totalMinor: 60000,
        memberIds: segParticipants,
      );
      expect(sharesSeg4.every((s) => s.amountMinor == 30000), isTrue);

      // Expense: Erode→Chennai (segment 1, sequence 0) — ₹400, Full pays
      // Sanusha does NOT participate
      final seg1Participants = <int>[];
      if (sanushaParticipation[1] == true) seg1Participants.add(sanushaId);
      if (fullParticipation[1] == true) seg1Participants.add(fullId);
      expect(seg1Participants, [fullId]);

      final sharesSeg1 = splitter.split(
        totalMinor: 40000,
        memberIds: seg1Participants,
      );
      expect(sharesSeg1, hasLength(1));
      expect(sharesSeg1.first.amountMinor, 40000);

      // Sanusha's total share: only segment 4
      final sanushaTotalShare = sharesSeg4
          .where((s) => s.memberId == sanushaId)
          .fold<int>(0, (sum, s) => sum + s.amountMinor);
      expect(sanushaTotalShare, 30000);

      // Full's total share: segment 1 + segment 4
      final fullTotalShare =
          sharesSeg1
              .where((s) => s.memberId == fullId)
              .fold<int>(0, (sum, s) => sum + s.amountMinor) +
          sharesSeg4
              .where((s) => s.memberId == fullId)
              .fold<int>(0, (sum, s) => sum + s.amountMinor);
      expect(fullTotalShare, 70000); // 40000 + 30000

      // Verify zero-sum
      final totalShares = sanushaTotalShare + fullTotalShare;
      expect(totalShares, 100000); // 60000 + 40000
    });
  });

  // ── Problem 10: Individual expenses ──────────────────────────────────

  group('Problem 10 — Individual expenses', () {
    final now = DateTime(2026, 9, 15);

    Expense makeExpense(
      int id,
      int payerId,
      int amount, {
      ExpenseScope scope = ExpenseScope.shared,
    }) => Expense(
      id: id,
      tripId: 1,
      payerMemberId: payerId,
      description: 'Expense $id',
      scope: scope,
      amountMinor: amount,
      externalAmountMinor: 0,
      createdAt: now,
      updatedAt: now,
    );

    test('individual expense: payer is only participant, no debt created', () {
      // Sheik pays ₹250 for his own food — individual expense
      final expense = makeExpense(1, 1, 25000, scope: ExpenseScope.individual);
      final shares = [
        const ExpenseShare(id: 1, expenseId: 1, memberId: 1, shareMinor: 25000),
      ];
      final payments = [
        const ExpensePayment(
          id: 1,
          expenseId: 1,
          memberId: 1,
          amountMinor: 25000,
        ),
      ];

      final result = BalanceCalculator.calculate(
        tripBudgetMinor: 0,
        contributions: const [],
        expenses: [expense],
        shares: shares,
        settlements: const [],
        payments: payments,
      );

      final sheik = result.members.firstWhere((m) => m.memberId == 1);
      expect(sheik.actualPaid, 25000);
      expect(sheik.expenseShare, 25000);
      expect(
        sheik.netPosition,
        0,
        reason: 'Individual expense creates no debt',
      );
      expect(result.outstandingMinor, 0);
    });

    test('individual expense in settlement produces no suggestions', () {
      final expense = makeExpense(1, 1, 25000, scope: ExpenseScope.individual);
      final shares = [
        const ExpenseShare(id: 1, expenseId: 1, memberId: 1, shareMinor: 25000),
      ];
      final payments = [
        const ExpensePayment(
          id: 1,
          expenseId: 1,
          memberId: 1,
          amountMinor: 25000,
        ),
      ];

      final result = SettlementCalculator.calculate(
        expenses: [expense],
        shares: shares,
        settlements: const [],
        payments: payments,
      );

      expect(result.suggestions, isEmpty);
      expect(result.totalOutstanding, 0);
    });

    test(
      'individual expense alongside shared expense does not corrupt shared balances',
      () {
        // Sheik: individual ₹250 (no debt)
        // Shared: ₹600 between A(1), B(2), C(3), paid by A
        final individualExpense = makeExpense(
          1,
          1,
          25000,
          scope: ExpenseScope.individual,
        );
        final sharedExpense = makeExpense(2, 1, 60000);
        final allExpenses = [individualExpense, sharedExpense];

        final allShares = [
          const ExpenseShare(
            id: 1,
            expenseId: 1,
            memberId: 1,
            shareMinor: 25000,
          ),
          const ExpenseShare(
            id: 2,
            expenseId: 2,
            memberId: 1,
            shareMinor: 20000,
          ),
          const ExpenseShare(
            id: 3,
            expenseId: 2,
            memberId: 2,
            shareMinor: 20000,
          ),
          const ExpenseShare(
            id: 4,
            expenseId: 2,
            memberId: 3,
            shareMinor: 20000,
          ),
        ];

        final allPayments = [
          const ExpensePayment(
            id: 1,
            expenseId: 1,
            memberId: 1,
            amountMinor: 25000,
          ),
          const ExpensePayment(
            id: 2,
            expenseId: 2,
            memberId: 1,
            amountMinor: 60000,
          ),
        ];

        final result = BalanceCalculator.calculate(
          tripBudgetMinor: 0,
          contributions: const [],
          expenses: allExpenses,
          shares: allShares,
          settlements: const [],
          payments: allPayments,
        );

        // Member 1: paid 85000 total, share = 25000 + 20000 = 45000
        // net = groupOutlay(85000) - share(45000) = +40000
        final m1 = result.members.firstWhere((m) => m.memberId == 1);
        expect(m1.actualPaid, 85000);
        expect(m1.expenseShare, 45000);
        expect(m1.netPosition, 40000);

        // Member 2: paid 0, share = 20000, net = -20000
        final m2 = result.members.firstWhere((m) => m.memberId == 2);
        expect(m2.netPosition, -20000);

        // Member 3: paid 0, share = 20000, net = -20000
        final m3 = result.members.firstWhere((m) => m.memberId == 3);
        expect(m3.netPosition, -20000);

        // Zero sum
        expect(m1.netPosition + m2.netPosition + m3.netPosition, 0);
      },
    );

    test('ExpenseScope.individual is a valid scope', () {
      expect(ExpenseScope.individual.apiValue, 'individual');
      expect(
        ExpenseScopeName.fromApiValue('individual'),
        ExpenseScope.individual,
      );
      expect(ExpenseScope.individual.label, 'Individual');
    });

    test(
      'multiple individual expenses by different members create no cross-debt',
      () {
        final exp1 = makeExpense(1, 1, 10000, scope: ExpenseScope.individual);
        final exp2 = makeExpense(2, 2, 20000, scope: ExpenseScope.individual);
        final allExpenses = [exp1, exp2];

        final allShares = [
          const ExpenseShare(
            id: 1,
            expenseId: 1,
            memberId: 1,
            shareMinor: 10000,
          ),
          const ExpenseShare(
            id: 2,
            expenseId: 2,
            memberId: 2,
            shareMinor: 20000,
          ),
        ];

        final allPayments = [
          const ExpensePayment(
            id: 1,
            expenseId: 1,
            memberId: 1,
            amountMinor: 10000,
          ),
          const ExpensePayment(
            id: 2,
            expenseId: 2,
            memberId: 2,
            amountMinor: 20000,
          ),
        ];

        final result = BalanceCalculator.calculate(
          tripBudgetMinor: 0,
          contributions: const [],
          expenses: allExpenses,
          shares: allShares,
          settlements: const [],
          payments: allPayments,
        );

        for (final member in result.members) {
          expect(
            member.netPosition,
            0,
            reason: 'Member ${member.memberId} should be balanced',
          );
        }
        expect(result.outstandingMinor, 0);

        final plan = SettlementCalculator.calculate(
          expenses: allExpenses,
          shares: allShares,
          settlements: const [],
          payments: allPayments,
        );
        expect(plan.suggestions, isEmpty);
      },
    );
  });
}
