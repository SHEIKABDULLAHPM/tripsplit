import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tripsplit/core/calculations/money.dart';
import 'package:tripsplit/core/widgets/money_text.dart';
import 'package:tripsplit/core/widgets/status_chip.dart';
import 'package:tripsplit/database/app_database.dart';
import 'package:tripsplit/features/expenses/data/expense_repository_impl.dart';
import 'package:tripsplit/features/members/presentation/member_detail_screen.dart';
import 'package:tripsplit/features/settlements/data/settlement_repository_impl.dart';
import 'package:tripsplit/injection/database_providers.dart';

/// Guards the settlement status rendering on the member detail screen.
///
/// The header chip and the emphasized "Net position" row must use the
/// settlement-aware net (the same source as the Balances and Settlement
/// screens), so a fully paid debt reads "Balanced / 0.00" and never keeps
/// showing "Owes". Expense columns (Actual paid, Expense share) must stay
/// tied to expense records: a settlement is a transfer, so it may not
/// inflate paid cash or shrink a share.
void main() {
  testWidgets('status clears Owes and nets to 0.00 once fully settled', (
    tester,
  ) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.closeDatabase);

    final tripId = await db.tripDao.insert(TripsCompanion.insert(name: 'Goa'));
    final anaId = await db.memberDao.insert(
      MembersCompanion.insert(tripId: tripId, name: 'Ana'),
    );
    final benId = await db.memberDao.insert(
      MembersCompanion.insert(tripId: tripId, name: 'Ben'),
    );

    // Ana fronts the whole 40.00 taxi; Ben owes his 20.00 share.
    await ExpenseRepositoryImpl(db).createExpense(
      tripId: tripId,
      description: 'Taxi',
      amountMinor: 40_00,
      payerMemberId: anaId,
      participantMemberIds: [anaId, benId],
    );

    await tester.binding.setSurfaceSize(const Size(600, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: MemberDetailScreen(tripId: tripId, memberId: benId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    StatusChip chip() =>
        tester.widget<StatusChip>(find.byType(StatusChip).first);

    /// The MoneyText value shown in the `_DetailStatRow` labelled [label].
    String statValue(String label) {
      final row = find
          .ancestor(of: find.text(label), matching: find.byType(Row))
          .first;
      final money = tester.widget<MoneyText>(
        find.descendant(of: row, matching: find.byType(MoneyText)).first,
      );
      return MoneyCalculator.format(money.minor);
    }

    // Ben owes 20.00: warning-tone Owes chip, net row shows the debt.
    expect(chip().label, 'Owes');
    expect(chip().tone, StatusTone.warning);
    expect(find.text('Owes '), findsOneWidget);
    expect(find.text('₹20.00'), findsWidgets);

    // Partial payment: only the true remaining outstanding is displayed.
    await SettlementRepositoryImpl(db).recordPayment(
      tripId: tripId,
      fromMemberId: benId,
      toMemberId: anaId,
      amountMinor: 20_00,
      paidMinor: 8_00,
    );
    await tester.pumpAndSettle();

    expect(chip().label, 'Owes');
    expect(chip().tone, StatusTone.warning);
    expect(find.text('Owes '), findsOneWidget);
    expect(statValue('Net position'), '₹12.00');

    // Settle the rest: Owes disappears, net row reads exactly 0.00.
    await SettlementRepositoryImpl(db).recordPayment(
      tripId: tripId,
      fromMemberId: benId,
      toMemberId: anaId,
      amountMinor: 12_00,
      paidMinor: 12_00,
    );
    await tester.pumpAndSettle();

    expect(chip().label, 'Balanced');
    expect(chip().tone, StatusTone.neutral);
    expect(find.text('OWES'), findsNothing);
    expect(find.text('Balanced '), findsOneWidget);
    expect(statValue('Net position'), '₹0.00');

    // Expense truth is untouched by the transfers: Ben still paid nothing
    // to the merchant and his expense share is still the full 20.00.
    expect(statValue('Actual paid'), '₹0.00');
    expect(statValue('Expense share'), '₹20.00');
  });
}
