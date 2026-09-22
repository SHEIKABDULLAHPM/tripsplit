import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/expenses/data/expense_repository_impl.dart';
import 'package:tripsplit/features/expenses/domain/expense_payment.dart';
import 'package:tripsplit/features/expenses/domain/expense_scope.dart';
import 'package:tripsplit/features/teams/data/team_repository_impl.dart';
import 'package:tripsplit/features/teams/presentation/team_settlement_screen.dart';
import 'package:tripsplit/injection/database_providers.dart';

/// Guards the per-member breakdown on the team settlement screen.
///
/// A payer from another team who fronted part of a shared multi-team expense
/// must never leak into this team's "Per member" list (cross-team member
/// matching). Only real team members belong on the breakdown.
void main() {
  testWidgets('per-member breakdown shows only this team\'s members', (
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

    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: TeamSettlementScreen(
            tripId: tripId,
            teamId: team1,
            teamName: 'Sheik Team',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Card cardWith(String text) => tester.widget<Card>(
      find.ancestor(of: find.text(text), matching: find.byType(Card)).first,
    );
    Finder inCard(Card card, String text) =>
        find.descendant(of: find.byWidget(card), matching: find.text(text));

    // Sheik team's own members appear in the per-member breakdown.
    expect(inCard(cardWith('Sheik'), 'Sheik'), findsWidgets);
    expect(inCard(cardWith('Ben'), 'Ben'), findsWidgets);

    // The payer from Team Dhar must not show up on Sheik Team's breakdown.
    expect(
      find.descendant(of: find.byType(Card), matching: find.text('Dhar')),
      findsNothing,
    );
    expect(
      find.descendant(of: find.byType(Card), matching: find.text('Di')),
      findsNothing,
    );
  });
}
