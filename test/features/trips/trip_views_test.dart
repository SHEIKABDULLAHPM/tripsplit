import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/contributions/data/contribution_repository_impl.dart';
import 'package:tripsplit/features/contributions/domain/contribution.dart';
import 'package:tripsplit/features/expenses/data/expense_repository_impl.dart';
import 'package:tripsplit/features/expenses/domain/expense_payment.dart';
import 'package:tripsplit/features/expenses/domain/expense_scope.dart';
import 'package:tripsplit/features/settlements/data/settlement_repository_impl.dart';
import 'package:tripsplit/features/trips/data/trip_views.dart';
import 'package:tripsplit/injection/database_providers.dart';

void main() {
  group('trip view providers', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);
    });

    tearDown(() async {
      await db.closeDatabase();
    });

    Future<void> waitFor(bool Function() condition) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Timed out waiting for a provider emission.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    List<TripCardData> homeCards() =>
        container.read(homeViewProvider).requireValue;

    TripView? tripView(int tripId) =>
        container.read(tripViewProvider(tripId)).requireValue;

    test('homeViewProvider summarizes trips from the latest data', () async {
      final tripId = await db.tripDao.insert(
        TripsCompanion.insert(name: 'Goa'),
      );
      final anaId = await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: 'Ana'),
      );
      await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: 'Ben'),
      );
      await ContributionRepositoryImpl(db).save(
        Contribution(
          id: 0,
          tripId: tripId,
          memberId: anaId,
          amountMinor: 100_00,
          note: 'budget',
          createdAt: DateTime(2026, 9, 12),
        ),
      );
      await ExpenseRepositoryImpl(db).createExpense(
        tripId: tripId,
        description: 'Dinner',
        amountMinor: 50_00,
        payerMemberId: anaId,
        participantMemberIds: [anaId],
      );

      final homeSub = container.listen(homeViewProvider, (_, __) {});
      addTearDown(homeSub.close);
      await waitFor(() => container.read(homeViewProvider).hasValue);
      final cards = homeCards();
      expect(cards, hasLength(1));
      final card = cards.single;
      expect(card.trip.name, 'Goa');
      expect(card.memberCount, 2);
      expect(card.expenseCount, 1);
      expect(card.contributionTotalMinor, 100_00);
      expect(card.spentMinor, 50_00);
    });

    test('homeViewProvider reacts to a new expense', () async {
      final tripId = await db.tripDao.insert(
        TripsCompanion.insert(name: 'Goa'),
      );
      final anaId = await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: 'Ana'),
      );
      final homeSub = container.listen(homeViewProvider, (_, __) {});
      addTearDown(homeSub.close);
      await waitFor(() => container.read(homeViewProvider).hasValue);

      await ExpenseRepositoryImpl(db).createExpense(
        tripId: tripId,
        description: 'Dinner',
        amountMinor: 10_00,
        payerMemberId: anaId,
        participantMemberIds: [anaId],
      );

      await waitFor(() => homeCards().single.expenseCount == 1);
      expect(homeCards().single.spentMinor, 10_00);
    });

    test('tripViewProvider resolves expense shares and balances', () async {
      final tripId = await db.tripDao.insert(
        TripsCompanion.insert(name: 'Goa'),
      );
      final anaId = await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: 'Ana'),
      );
      final benId = await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: 'Ben'),
      );
      await ExpenseRepositoryImpl(db).createExpense(
        tripId: tripId,
        description: 'Taxi',
        amountMinor: 40_00,
        payerMemberId: anaId,
        participantMemberIds: [anaId, benId],
      );
      final expenseId = (await db.expenseDao.getByTrip(tripId)).single.id;

      final sub = container.listen(tripViewProvider(tripId), (_, __) {});
      addTearDown(sub.close);
      await waitFor(() => container.read(tripViewProvider(tripId)).hasValue);
      final view = tripView(tripId)!;
      expect(view.members, hasLength(2));
      expect(view.expenses, hasLength(1));
      expect(view.expenses.single.expense.id, expenseId);
      expect(view.expenses.single.shares, hasLength(2));
      // Ben owes Ana the 20.00 share of the taxi.
      expect(view.settlementPlan.totalOutstanding, 20_00);
    });

    test('tripViewProvider yields null for an unknown trip', () async {
      final sub = container.listen(tripViewProvider(999), (_, __) {});
      addTearDown(sub.close);
      await waitFor(() => container.read(tripViewProvider(999)).hasValue);
      expect(tripView(999), isNull);
    });

    test('tripViewProvider reacts to a recorded payment', () async {
      final tripId = await db.tripDao.insert(
        TripsCompanion.insert(name: 'Goa'),
      );
      final anaId = await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: 'Ana'),
      );
      final benId = await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: 'Ben'),
      );
      await ExpenseRepositoryImpl(db).createExpense(
        tripId: tripId,
        description: 'Taxi',
        amountMinor: 40_00,
        payerMemberId: anaId,
        participantMemberIds: [anaId, benId],
      );
      final sub = container.listen(tripViewProvider(tripId), (_, __) {});
      addTearDown(sub.close);
      await waitFor(() => container.read(tripViewProvider(tripId)).hasValue);

      // Ben repays Ana the full 20.00 he owed.
      await SettlementRepositoryImpl(db).recordPayment(
        tripId: tripId,
        fromMemberId: benId,
        toMemberId: anaId,
        amountMinor: 20_00,
        paidMinor: 20_00,
        note: 'Taxi',
      );

      await waitFor(
        () => tripView(tripId)!.settlementPlan.totalOutstanding == 0,
      );
      final latest = tripView(tripId)!;
      expect(latest.payments, hasLength(1));
      expect(latest.settlements, hasLength(1));
      expect(latest.settlementObligationBetween(benId, anaId), 20_00);
    });

    test(
      'multi-team common expense resolves on real team membership: each '
      'non-payer member only owes their own team payer, payers balance',
      () async {
        final tripId = await db.tripDao.insert(
          TripsCompanion.insert(name: 'Goa'),
        );
        final ids = <int>[];
        for (final name in ['A', 'B', 'C', 'D']) {
          ids.add(
            await db.memberDao
                .insert(MembersCompanion.insert(tripId: tripId, name: name)),
          );
        }
        final team10 = await db.journeyDao.insertTeam(
          TeamsCompanion.insert(tripId: tripId, name: 'Team 10'),
        );
        final team20 = await db.journeyDao.insertTeam(
          TeamsCompanion.insert(tripId: tripId, name: 'Team 20'),
        );
        for (final memberId in [ids[0], ids[1]]) {
          await db.journeyDao.addTeamMember(team10, memberId);
        }
        for (final memberId in [ids[2], ids[3]]) {
          await db.journeyDao.addTeamMember(team20, memberId);
        }

        // One ₹4000 common expense across both teams. A (Team 10) pays ₹2500,
        // C (Team 20) pays ₹1500; all four share equally.
        await ExpenseRepositoryImpl(db).createExpense(
          tripId: tripId,
          description: 'Common room',
          amountMinor: 4000_00,
          payerMemberId: ids[0],
          scope: ExpenseScope.team,
          teamIds: [team10, team20],
          payerTeamId: team10,
          participantMemberIds: ids,
          otherPayers: [
            ExpensePayment(
              id: 0,
              expenseId: 0,
              memberId: ids[2],
              amountMinor: 1500_00,
              teamId: team20,
            ),
          ],
        );

        final sub = container.listen(tripViewProvider(tripId), (_, __) {});
        addTearDown(sub.close);
        await waitFor(() => container.read(tripViewProvider(tripId)).hasValue);

        final plan = tripView(tripId)!.settlementPlan;
        final edges = plan.suggestions
            .map((s) => '${s.fromMemberId}->${s.toMemberId}:${s.minor}')
            .toSet();
        // B owes only A (his team payer); D owes only C; the ~₹500 imbalance
        // between the payers closes as a C→A edge. No cross-team 4->1 leak.
        expect(
          edges,
          {
            '${ids[1]}->${ids[0]}:100000',
            '${ids[3]}->${ids[2]}:100000',
            '${ids[2]}->${ids[0]}:50000',
          },
        );
        expect(plan.totalOutstanding, 2500_00);
      },
    );
  });
}
