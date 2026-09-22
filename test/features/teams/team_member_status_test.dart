import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/money.dart';
import 'package:tripsplit/core/widgets/money_text.dart';
import 'package:tripsplit/core/widgets/status_chip.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/expenses/data/expense_repository_impl.dart';
import 'package:tripsplit/features/expenses/domain/expense_scope.dart';
import 'package:tripsplit/features/settlements/data/settlement_repository_impl.dart';
import 'package:tripsplit/features/teams/data/team_repository_impl.dart';
import 'package:tripsplit/features/teams/presentation/team_settlement_screen.dart';
import 'package:tripsplit/features/teams/presentation/teams_screen.dart';
import 'package:tripsplit/injection/database_providers.dart';

/// Guards the per-member settlement status on the Teams screen and the Team
/// settlement screen.
///
/// Both chips must read the settlement-aware net (the same authoritative
/// source as the Balances screen), so a fully paid debt flips "Owes" to
/// "Balanced" and shows a 0.00 net. The Share/Paid columns stay tied to
/// expense records: a settlement is a transfer, never an expense.
void main() {
  /// One team: Ana fronts a 40.00 team expense, Ben owes his 20.00 share.
  Future<(AppDatabase db, int tripId, int teamId, int anaId, int benId)>
  setUpTeam() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.closeDatabase);

    final tripId = await db.tripDao.insert(TripsCompanion.insert(name: 'Goa'));
    final anaId = await db.memberDao.insert(
      MembersCompanion.insert(tripId: tripId, name: 'Ana'),
    );
    final benId = await db.memberDao.insert(
      MembersCompanion.insert(tripId: tripId, name: 'Ben'),
    );
    final teamRepo = TeamRepositoryImpl(db);
    final teamId = (await teamRepo.createTeam(tripId, 'Goa Crew')).id;
    await teamRepo.addMember(teamId: teamId, memberId: anaId);
    await teamRepo.addMember(teamId: teamId, memberId: benId);

    await ExpenseRepositoryImpl(db).createExpense(
      tripId: tripId,
      description: 'Team dinner',
      amountMinor: 40_00,
      scope: ExpenseScope.team,
      payerMemberId: anaId,
      teamIds: [teamId],
      participantMemberIds: [anaId, benId],
    );

    return (db, tripId, teamId, anaId, benId);
  }

  /// Ben repays his full 20.00 share to Ana.
  Future<void> settleFully(AppDatabase db, int tripId, int benId, int anaId) =>
      SettlementRepositoryImpl(db).recordPayment(
        tripId: tripId,
        fromMemberId: benId,
        toMemberId: anaId,
        amountMinor: 20_00,
        paidMinor: 20_00,
      );

  testWidgets('team member chip flips Owes → Balanced after full settlement', (
    tester,
  ) async {
    final (db, tripId, _, anaId, benId) = await setUpTeam();

    await tester.binding.setSurfaceSize(const Size(600, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: TeamsScreen(tripId: tripId)),
      ),
    );
    await tester.pumpAndSettle();

    /// The member's status chip, located through the row holding their name.
    StatusChip chipFor(String name) {
      final row = find
          .ancestor(of: find.text(name), matching: find.byType(Row))
          .first;
      return tester.widget<StatusChip>(
        find.descendant(of: row, matching: find.byType(StatusChip)).first,
      );
    }

    /// Formatted money values (share, paid) rendered in the member's row.
    List<String> moneyIn(String name) {
      final row = find
          .ancestor(of: find.text(name), matching: find.byType(Row))
          .first;
      return find
          .descendant(of: row, matching: find.byType(MoneyText))
          .evaluate()
          .map((e) => MoneyCalculator.format((e.widget as MoneyText).minor))
          .toList();
    }

    // Before settlement Ben owes 20.00 → Owes; Ana is owed → Receives.
    expect(chipFor('Ben').label, 'Owes');
    expect(chipFor('Ben').tone, StatusTone.warning);
    expect(chipFor('Ana').label, 'Receives');
    expect(chipFor('Ana').tone, StatusTone.success);

    await settleFully(db, tripId, benId, anaId);
    await tester.pumpAndSettle();

    // Nothing outstanding: Owes is gone, both read Balanced.
    expect(chipFor('Ben').label, 'Balanced');
    expect(chipFor('Ben').tone, StatusTone.neutral);
    expect(chipFor('Ana').label, 'Balanced');
    expect(chipFor('Ana').tone, StatusTone.neutral);
    expect(find.text('OWES'), findsNothing);

    // Expense truth untouched: Ben's share stays 20.00 and his paid stays
    // 0.00 — a settlement transfer must never be booked as an expense
    // payment, and the team expense total never grows.
    expect(moneyIn('Ben'), ['₹20.00', '₹0.00']);
    expect(find.text('₹40.00'), findsWidgets);
  });

  testWidgets('team settlement per-member card clears Owes and nets to 0.00', (
    tester,
  ) async {
    final (db, tripId, teamId, anaId, benId) = await setUpTeam();

    await tester.binding.setSurfaceSize(const Size(600, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: TeamSettlementScreen(
            tripId: tripId,
            teamId: teamId,
            teamName: 'Goa Crew',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    /// The member card located through the name in its header row. The
    /// descendant scan must skip the summary/expense-breakdown cards (which
    /// also contain the name but have no status chip) and pick the card that
    /// actually renders the per-member settlement status.
    Finder cardFor(String name) {
      final cards = find
          .ancestor(of: find.text(name), matching: find.byType(Card))
          .evaluate();
      final candidates = cards
          .where(
            (e) => find
                .descendant(
                  of: find.byWidget(e.widget),
                  matching: find.byType(StatusChip),
                )
                .evaluate()
                .isNotEmpty,
          )
          .toList();
      expect(candidates, isNotEmpty, reason: 'No member card for "$name"');
      return find.byWidget(candidates.first.widget);
    }

    /// Formatted value of a labelled stat row inside the member's card.
    /// The row must be found inside the card itself: the label (e.g. "Net")
    /// appears once per member card, so a global ancestor lookup would pick
    /// whichever member's row was rendered first.
    String statIn(Finder card, String label) {
      final rows = find
          .descendant(
            of: card,
            matching: find.ancestor(
              of: find.text(label),
              matching: find.byType(Row),
            ),
          )
          .evaluate();
      expect(rows, isNotEmpty, reason: 'No "$label" row in the card');
      final money = find
          .descendant(
            of: find.byWidget(rows.first.widget),
            matching: find.byType(MoneyText),
          )
          .evaluate();
      expect(money, isNotEmpty, reason: 'No amount in "$label" row');
      return MoneyCalculator.format((money.first.widget as MoneyText).minor);
    }

    StatusChip chipIn(Finder card) => tester.widget<StatusChip>(
      find.descendant(of: card, matching: find.byType(StatusChip)).first,
    );

    // Before settlement: Owes 20.00 on the emphasized net row.
    expect(chipIn(cardFor('Ben')).label, 'Owes');
    expect(chipIn(cardFor('Ben')).tone, StatusTone.warning);
    expect(statIn(cardFor('Ben'), 'Net'), '₹20.00');

    await settleFully(db, tripId, benId, anaId);
    await tester.pumpAndSettle();

    // Fully paid: Owes disappears, net reads exactly 0.00.
    expect(chipIn(cardFor('Ben')).label, 'Balanced');
    expect(chipIn(cardFor('Ben')).tone, StatusTone.neutral);
    expect(statIn(cardFor('Ben'), 'Net'), '₹0.00');
    expect(find.text('OWES'), findsNothing);

    // Expense columns unchanged by the transfer.
    expect(statIn(cardFor('Ben'), 'Paid'), '₹0.00');
    expect(statIn(cardFor('Ben'), 'Share'), '₹20.00');
    expect(statIn(cardFor('Ana'), 'Paid'), '₹40.00');
    expect(statIn(cardFor('Ana'), 'Share'), '₹20.00');
  });
}
