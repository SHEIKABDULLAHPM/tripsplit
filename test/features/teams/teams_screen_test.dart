import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/expenses/data/expense_repository_impl.dart';
import 'package:tripsplit/features/expenses/domain/expense_payment.dart';
import 'package:tripsplit/features/expenses/domain/expense_scope.dart';
import 'package:tripsplit/features/teams/data/team_repository_impl.dart';
import 'package:tripsplit/features/teams/presentation/teams_screen.dart';
import 'package:tripsplit/injection/database_providers.dart';

/// Guards the per-team financial breakdown on the Teams screen.
///
/// A member's payment for a multi-team expense must only ever be attributed to
/// their own team's card — never shown as if the payer belongs to every linked
/// team.
void main() {
  testWidgets('multi-team payers appear only on their own team card', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.closeDatabase);

    final tripId = await db.tripDao.insert(TripsCompanion.insert(name: 'Goa'));
    final members = <String, int>{};
    for (final name in ['Sheik', 'Ben', 'Dhar', 'Di']) {
      members[name] = await db.memberDao.insert(
        MembersCompanion.insert(tripId: tripId, name: name),
      );
    }
    final teamRepo = TeamRepositoryImpl(db);
    final team1 = (await teamRepo.createTeam(tripId, 'Sheik Team')).id;
    final team2 = (await teamRepo.createTeam(tripId, 'Dhar Team')).id;
    await teamRepo.addMember(teamId: team1, memberId: members['Sheik']!);
    await teamRepo.addMember(teamId: team1, memberId: members['Ben']!);
    await teamRepo.addMember(teamId: team2, memberId: members['Dhar']!);
    await teamRepo.addMember(teamId: team2, memberId: members['Di']!);

    // One ₹3,288.60 expense across both teams: Sheik fronts ₹1,827 for his
    // team, Dhar fronts ₹1,461.60 for his own team.
    await ExpenseRepositoryImpl(db).createExpense(
      tripId: tripId,
      description: 'Shared',
      amountMinor: 3288_60,
      scope: ExpenseScope.team,
      payerMemberId: members['Sheik']!,
      payerTeamId: team1,
      teamIds: [team1, team2],
      participantMemberIds: members.values.toList(),
      otherPayers: [
        ExpensePayment(
          id: 0,
          expenseId: 0,
          memberId: members['Dhar']!,
          amountMinor: 1461_60,
          teamId: team2,
        ),
      ],
    );

    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: TeamsScreen(tripId: tripId)),
      ),
    );
    await tester.pumpAndSettle();

    Card cardOf(String teamName) => tester.widget<Card>(
      find.ancestor(of: find.text(teamName), matching: find.byType(Card)).first,
    );

    final sheikCard = cardOf('Sheik Team');
    final dharCard = cardOf('Dhar Team');

    Finder inCard(Card card, String text) =>
        find.descendant(of: find.byWidget(card), matching: find.text(text));

    // Each team's own members (paying or with a share) are listed.
    expect(inCard(sheikCard, 'Sheik'), findsWidgets);
    expect(inCard(sheikCard, 'Ben'), findsWidgets);
    expect(inCard(dharCard, 'Dhar'), findsWidgets);
    expect(inCard(dharCard, 'Di'), findsWidgets);

    // Nobody from the other team shows up on the breakdown.
    expect(inCard(sheikCard, 'Dhar'), findsNothing);
    expect(inCard(sheikCard, 'Di'), findsNothing);
    expect(inCard(dharCard, 'Sheik'), findsNothing);
    expect(inCard(dharCard, 'Ben'), findsNothing);
  });
}
